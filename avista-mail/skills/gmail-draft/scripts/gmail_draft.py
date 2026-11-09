#!/usr/bin/env python3
"""Create and update Gmail drafts through the Gmail API, so links stay real.

The Gmail connector's create_draft / update_draft / reply rewrite every URL into
https://www.google.com/url?q=...&source=gmail&ust=...&sa=E before storing the
draft. The Gmail API stores the MIME message as given, so drafts written here
keep their real links.

Standard library only. Credentials live in ~/.claude/.env (chmod 600):
  GMAIL_CLIENT_ID=...        OAuth client, type "Desktop app"
  GMAIL_CLIENT_SECRET=...
  GMAIL_REFRESH_TOKEN=...    written by `gmail_draft.py auth`, never printed

Self-healing: if the refresh token has expired or been revoked (invalid_grant)
or is missing, any command re-opens the Google sign-in, waits up to 180 s for
the user to click Allow, saves the new token and carries on. If that does not
complete it exits 3 and prints GMAIL_REAUTH_NEEDED. GMAIL_NO_REAUTH=1 skips the
browser step and exits 3 straight away.

Commands:
  auth                                   one-time browser sign-in
  create --to A [--cc B] [--bcc C] --subject S --body-file F [--html-file H]
         [--reply-to MESSAGE_ID] [--signature]
  update DRAFT_ID  (same options as create; replaces the draft's content)
  check DRAFT_ID                         exit 1 if any google.com/url? link is in it

Body text can also come from stdin with --body-file -.
Output is JSON: draft id, message id, thread id, Gmail URL, wrapped-link count.
"""
import argparse
import base64
import hashlib
import html
import http.server
import json
import os
import re
import secrets
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from email.message import EmailMessage
from email.policy import SMTP
from pathlib import Path

ENV_PATH = Path.home() / '.claude' / '.env'
SCOPES = [
  'https://www.googleapis.com/auth/gmail.compose',   # create/update drafts
  'https://www.googleapis.com/auth/gmail.readonly',  # reply headers + signature
]
AUTH_URL = 'https://accounts.google.com/o/oauth2/v2/auth'
TOKEN_URL = 'https://oauth2.googleapis.com/token'
API = 'https://gmail.googleapis.com/gmail/v1/users/me'
WRAPPED = re.compile(r'https?://(?:www\.)?google\.[a-z.]{2,6}/url\?', re.I)
URL_IN_TEXT = re.compile(r'(https?://[^\s<>"\']+[^\s<>"\'.,;:!?)\]])')


# ---------- ~/.claude/.env ----------

def read_env() -> dict:
  values = {}
  if ENV_PATH.exists():
    for line in ENV_PATH.read_text().splitlines():
      if '=' in line and not line.lstrip().startswith('#'):
        key, _, val = line.partition('=')
        values[key.strip()] = val.strip().strip('"').strip("'")
  return values


def write_env_key(key: str, value: str) -> None:
  lines = ENV_PATH.read_text().splitlines() if ENV_PATH.exists() else []
  lines = [l for l in lines if not l.startswith(f'{key}=')]
  lines.append(f'{key}={value}')
  ENV_PATH.parent.mkdir(parents=True, exist_ok=True)
  fd = os.open(ENV_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
  with os.fdopen(fd, 'w') as fh:
    fh.write('\n'.join(lines) + '\n')
  os.chmod(ENV_PATH, 0o600)


def client_creds() -> tuple:
  env = read_env()
  cid, csec = env.get('GMAIL_CLIENT_ID'), env.get('GMAIL_CLIENT_SECRET')
  if not cid or not csec:
    sys.exit(f'GMAIL_CLIENT_ID / GMAIL_CLIENT_SECRET missing from {ENV_PATH}. See the skill for setup.')
  return cid, csec


# ---------- OAuth ----------

REAUTH_EXIT = 3          # exit code: access is gone and the browser re-auth did not complete
REAUTH_TIMEOUT = 180     # seconds to wait for the user to click Allow


class ReauthNeeded(Exception):
  pass


def post_form(url: str, data: dict) -> dict:
  req = urllib.request.Request(url, data=urllib.parse.urlencode(data).encode(), method='POST')
  try:
    with urllib.request.urlopen(req) as resp:
      return json.load(resp)
  except urllib.error.HTTPError as err:
    body = err.read().decode(errors='replace')
    # invalid_grant = the refresh token expired or was revoked. Recoverable by signing in again.
    if data.get('grant_type') == 'refresh_token' and 'invalid_grant' in body:
      raise ReauthNeeded(body[:300])
    sys.exit(f'OAuth error {err.code}: {body[:300]}')


def cmd_auth(_args) -> None:
  if not run_auth_flow():
    sys.exit('Sign-in did not complete.')


def run_auth_flow(timeout: float = None) -> bool:
  """Browser sign-in; stores a new GMAIL_REFRESH_TOKEN. Returns False on timeout."""
  cid, csec = client_creds()
  verifier = secrets.token_urlsafe(64)
  challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b'=').decode()
  state = secrets.token_urlsafe(16)
  result = {}

  class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
      qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
      result.update({k: v[0] for k, v in qs.items()})
      self.send_response(200)
      self.send_header('Content-Type', 'text/html; charset=utf-8')
      self.end_headers()
      self.wfile.write('<p>Gmail draft access set up. You can close this tab.</p>'.encode())
      threading.Thread(target=self.server.shutdown, daemon=True).start()

    def log_message(self, *a):
      pass

  server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
  redirect = f'http://127.0.0.1:{server.server_port}'
  url = AUTH_URL + '?' + urllib.parse.urlencode({
    'client_id': cid, 'redirect_uri': redirect, 'response_type': 'code',
    'scope': ' '.join(SCOPES), 'access_type': 'offline', 'prompt': 'consent',
    'state': state, 'code_challenge': challenge, 'code_challenge_method': 'S256',
  })
  print('Opening the Google sign-in page. If it does not open, visit:\n' + url, file=sys.stderr)
  webbrowser.open(url)
  if timeout is None:
    server.serve_forever()
  else:
    timer = threading.Timer(timeout, server.shutdown)
    timer.daemon = True
    timer.start()
    server.serve_forever()
    timer.cancel()
  server.server_close()

  if not result:
    return False
  if result.get('state') != state or 'code' not in result:
    sys.exit(f"Sign-in failed: {result.get('error', 'state mismatch')}")
  tokens = post_form(TOKEN_URL, {
    'code': result['code'], 'client_id': cid, 'client_secret': csec,
    'redirect_uri': redirect, 'grant_type': 'authorization_code', 'code_verifier': verifier,
  })
  if 'refresh_token' not in tokens:
    sys.exit('Google returned no refresh token. Remove the app at myaccount.google.com/permissions and run auth again.')
  write_env_key('GMAIL_REFRESH_TOKEN', tokens['refresh_token'])
  print(f'Saved GMAIL_REFRESH_TOKEN to {ENV_PATH}.', file=sys.stderr)
  return True


def refresh_access_token() -> str:
  cid, csec = client_creds()
  refresh = read_env().get('GMAIL_REFRESH_TOKEN')
  if not refresh:
    raise ReauthNeeded('no refresh token')
  return post_form(TOKEN_URL, {
    'client_id': cid, 'client_secret': csec, 'refresh_token': refresh, 'grant_type': 'refresh_token',
  })['access_token']


def access_token() -> str:
  """Access token; if the refresh token has expired or been revoked, re-run the
  browser sign-in once, wait for the user to click Allow, and carry on.
  GMAIL_NO_REAUTH=1 turns the browser step off (exit REAUTH_EXIT instead)."""
  try:
    return refresh_access_token()
  except ReauthNeeded as why:
    reason = str(why)
  if os.environ.get('GMAIL_NO_REAUTH') == '1':
    print(f'GMAIL_REAUTH_NEEDED: {reason}', file=sys.stderr)
    sys.exit(REAUTH_EXIT)
  print('Gmail access has expired or was revoked. Opening Google sign-in to renew it - '
        f'click Allow in the browser (waiting up to {REAUTH_TIMEOUT}s).', file=sys.stderr)
  if not run_auth_flow(timeout=REAUTH_TIMEOUT):
    print('GMAIL_REAUTH_NEEDED: sign-in was not completed in time. Run: gmail_draft.py auth', file=sys.stderr)
    sys.exit(REAUTH_EXIT)
  try:
    return refresh_access_token()
  except ReauthNeeded as why:
    print(f'GMAIL_REAUTH_NEEDED: new token rejected too ({why})', file=sys.stderr)
    sys.exit(REAUTH_EXIT)


def api(method: str, path: str, token: str, body: dict = None) -> dict:
  data = json.dumps(body).encode() if body is not None else None
  req = urllib.request.Request(API + path, data=data, method=method, headers={
    'Authorization': f'Bearer {token}', 'Content-Type': 'application/json',
  })
  try:
    with urllib.request.urlopen(req) as resp:
      return json.load(resp)
  except urllib.error.HTTPError as err:
    sys.exit(f'Gmail API {method} {path} -> {err.code}: {err.read().decode(errors="replace")[:400]}')


# ---------- message building ----------

def text_to_html(text: str) -> str:
  escaped = html.escape(text)
  linked = URL_IN_TEXT.sub(lambda m: f'<a href="{m.group(1)}">{m.group(1)}</a>', escaped)
  return '<div dir="ltr">' + linked.replace('\n', '<br>\n') + '</div>'


def html_to_text(markup: str) -> str:
  markup = re.sub(r'(?i)<br\s*/?>|</div>|</p>', '\n', markup)
  markup = re.sub(r'(?is)<a [^>]*href="([^"]+)"[^>]*>(.*?)</a>',
                  lambda m: m.group(2) if m.group(2).strip() == m.group(1) else f'{m.group(2)} ({m.group(1)})', markup)
  return html.unescape(re.sub(r'<[^>]+>', '', markup)).strip()


def signature(token: str) -> str:
  for alias in api('GET', '/settings/sendAs', token).get('sendAs', []):
    if alias.get('isPrimary'):
      return alias.get('signature', '')
  return ''


def reply_context(token: str, message_id: str) -> dict:
  msg = api('GET', f'/messages/{message_id}?format=metadata'
            '&metadataHeaders=Message-ID&metadataHeaders=References&metadataHeaders=Subject', token)
  headers = {h['name'].lower(): h['value'] for h in msg['payload'].get('headers', [])}
  return {
    'threadId': msg['threadId'],
    'message_id': headers.get('message-id', ''),
    'references': headers.get('references', ''),
    'subject': headers.get('subject', ''),
  }


def build_raw(args, token: str) -> tuple:
  text = sys.stdin.read() if args.body_file == '-' else Path(args.body_file).read_text()
  markup = Path(args.html_file).read_text() if args.html_file else text_to_html(text)
  if args.signature:
    sig = signature(token)
    if sig:
      markup += f'<br><br>-- <br><div class="gmail_signature">{sig}</div>'
      text += '\n\n-- \n' + html_to_text(sig)

  msg = EmailMessage(policy=SMTP)
  msg['To'] = ', '.join(args.to)
  if args.cc:
    msg['Cc'] = ', '.join(args.cc)
  if args.bcc:
    msg['Bcc'] = ', '.join(args.bcc)

  thread_id = None
  subject = args.subject or ''
  if args.reply_to:
    ctx = reply_context(token, args.reply_to)
    thread_id = ctx['threadId']
    if not subject:
      subject = ctx['subject'] if ctx['subject'].lower().startswith('re:') else f"Re: {ctx['subject']}"
    if ctx['message_id']:
      msg['In-Reply-To'] = ctx['message_id']
      msg['References'] = f"{ctx['references']} {ctx['message_id']}".strip()
  msg['Subject'] = subject

  msg.set_content(text)
  msg.add_alternative(markup, subtype='html')
  raw = base64.urlsafe_b64encode(msg.as_bytes()).decode()
  return raw, thread_id


def count_wrapped(token: str, draft_id: str) -> int:
  draft = api('GET', f'/drafts/{draft_id}?format=raw', token)
  raw = base64.urlsafe_b64decode(draft['message']['raw'] + '==').decode('utf-8', errors='replace')
  raw = re.sub(r'=\r?\n', '', raw).replace('=3D', '=')  # undo quoted-printable soft breaks
  return len(WRAPPED.findall(raw))


def report(token: str, draft: dict) -> None:
  wrapped = count_wrapped(token, draft['id'])
  print(json.dumps({
    'draftId': draft['id'],
    'messageId': draft['message']['id'],
    'threadId': draft['message'].get('threadId'),
    'viewUrl': f"https://mail.google.com/mail/#drafts?compose={draft['message']['id']}",
    'wrappedLinks': wrapped,
  }, indent=2))
  if wrapped:
    sys.exit(1)


def cmd_create(args) -> None:
  token = access_token()
  raw, thread_id = build_raw(args, token)
  message = {'raw': raw}
  if thread_id:
    message['threadId'] = thread_id
  report(token, api('POST', '/drafts', token, {'message': message}))


def cmd_update(args) -> None:
  token = access_token()
  raw, thread_id = build_raw(args, token)
  message = {'raw': raw}
  if thread_id:
    message['threadId'] = thread_id
  report(token, api('PUT', f'/drafts/{args.draft_id}', token, {'id': args.draft_id, 'message': message}))


def cmd_check(args) -> None:
  token = access_token()
  wrapped = count_wrapped(token, args.draft_id)
  print(json.dumps({'draftId': args.draft_id, 'wrappedLinks': wrapped}))
  if wrapped:
    sys.exit(1)


def main() -> None:
  parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
  sub = parser.add_subparsers(dest='cmd', required=True)
  sub.add_parser('auth').set_defaults(func=cmd_auth)

  def compose_opts(p):
    p.add_argument('--to', action='append', required=True)
    p.add_argument('--cc', action='append')
    p.add_argument('--bcc', action='append')
    p.add_argument('--subject')
    p.add_argument('--body-file', required=True, help='plain-text body, or - for stdin')
    p.add_argument('--html-file', help='HTML body; generated from the text body when left out')
    p.add_argument('--reply-to', help='Gmail message id to thread the draft under')
    p.add_argument('--signature', action='store_true', help='append the primary Gmail signature')

  p_create = sub.add_parser('create')
  compose_opts(p_create)
  p_create.set_defaults(func=cmd_create)

  p_update = sub.add_parser('update')
  p_update.add_argument('draft_id')
  compose_opts(p_update)
  p_update.set_defaults(func=cmd_update)

  p_check = sub.add_parser('check')
  p_check.add_argument('draft_id')
  p_check.set_defaults(func=cmd_check)

  args = parser.parse_args()
  args.func(args)


if __name__ == '__main__':
  main()
