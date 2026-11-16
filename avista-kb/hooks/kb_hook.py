#!/usr/bin/env python3
"""Hooks for avista-kb. They give Claude facts and never show anything to the user themselves.

  session-start  In an Avista git repo: is it tracked in the knowledge base, and is the handoff behind?
  post-bash      First SSH/scp/rsync to a <site>.tempurl.host in a session: is that site tracked?

Prints a hookSpecificOutput JSON with additionalContext, or nothing. Always exits 0: a broken
hook must never get in the way of the developer's work.
"""
import importlib.machinery
import importlib.util
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATE = Path.home() / ".claude" / "avista-kb" / "seen"
TAG = "[avista-kb]"


def load_kb():
  path = ROOT / "skills" / "kb-pickup" / "scripts" / "kb"
  loader = importlib.machinery.SourceFileLoader("kb_helper", str(path))
  spec = importlib.util.spec_from_loader("kb_helper", loader)
  mod = importlib.util.module_from_spec(spec)
  loader.exec_module(mod)
  return mod


def emit(event: str, text: str) -> None:
  print(json.dumps({"hookSpecificOutput": {"hookEventName": event, "additionalContext": f"{TAG} {text}"}}))


def git(cwd: str, *a: str) -> str:
  r = subprocess.run(["git", "-C", cwd, *a], capture_output=True, text=True, timeout=5)
  return r.stdout.strip() if r.returncode == 0 else ""


def find_kb(kb):
  saved, sys.stderr = sys.stderr, open(os.devnull, "w")
  try:
    return kb.kb_dir()
  except SystemExit:
    return None
  finally:
    sys.stderr.close()
    sys.stderr = saved


def features_for(kb, kbdir: Path, *, domain=None, repo=None) -> list:
  """[(slug, status, overview_dict)] for features linked to a domain or an owner/repo."""
  out = []
  for ov in sorted((kbdir / "features").glob("*/overview.md")):
    d = kb.parse(ov)
    sites = {kb.norm_domain(str(x)) for x in kb.as_list(d.get("sites"))}
    repos = {str(x).lower() for x in kb.as_list(d.get("repos"))}
    if (domain and domain in sites) or (repo and repo in repos):
      out.append((ov.parent.name, d.get("status") or "?", d))
  return out


def handoff_info(kb, kbdir: Path, slug: str):
  ho = kbdir / "features" / slug / "handoff.md"
  if not ho.is_file():
    return None, None
  d = kb.parse(ho)
  return d.get("updated"), d.get("by")


def repo_kind(top: str) -> str:
  p = Path(top)
  if (p / ".claude-plugin" / "plugin.json").is_file() or (p / ".claude-plugin" / "marketplace.json").is_file():
    return "a Claude plugin repo"
  style = p / "style.css"
  if style.is_file() and "Theme Name:" in style.read_text(errors="ignore")[:4000]:
    return "a WordPress theme"
  for php in p.glob("*.php"):
    if "Plugin Name:" in php.read_text(errors="ignore")[:4000]:
      return "a WordPress plugin"
  if (p / "wp-content").is_dir():
    return "a WordPress site repo"
  return "a git repo"


# --- session start ---------------------------------------------------------

def setup_pending(kb) -> bool:
  conf = kb.read_config()
  if conf.get("setup") == "done":
    return False
  snooze = conf.get("snooze", "")
  return not (snooze and snooze >= time.strftime("%Y-%m-%d"))


def session_start(data: dict) -> None:
  kb = load_kb()
  if setup_pending(kb):
    emit("SessionStart",
         "The avista-kb plugin is installed but not set up on this machine. At the first natural pause, never "
         "on the first message and never mid-task, ask once with AskUserQuestion (header 'Setup'): "
         "question 'The Avista knowledge base plugin is installed but not set up yet. It keeps track of where "
         "each feature's code lives so colleagues can pick up each other's work. Setup takes about a minute and "
         "I do the work: clone it, configure it, check it. Set it up now?', options 'Set it up now (Recommended)', "
         "'Remind me in a week', 'Not on this machine'. On the first, run the kb-setup skill. On the second, run "
         "`kb config snooze <date 7 days from today>`; on the third, `kb config snooze 2099-12-31` "
         "(kb is the kb-pickup skill's scripts/kb). Then carry on with what the user asked.")
    return
  cwd = data.get("cwd") or os.getcwd()
  top = git(cwd, "rev-parse", "--show-toplevel")
  if not top:
    return
  kbdir = find_kb(kb)
  remote = git(top, "remote", "get-url", "origin")
  slug = kb.repo_slug(remote) if remote else None
  if not slug or not slug.startswith("avista/"):
    return  # only Avista org repos; personal, client-org and third-party clones stay quiet
  if kbdir is None:
    emit("SessionStart", "Tracking in the Avista knowledge base is off on this machine: it isn't cloned "
         "(gh repo clone Avista/avista-knowledge-base). Mention this once only if the user asks to track or hand off work.")
    return
  if Path(top).resolve() == kbdir.resolve() or slug.endswith("/avista-knowledge-base"):
    return
  hits = features_for(kb, kbdir, repo=slug)
  if hits:
    lines = []
    for name, status, d in hits:
      updated, by = handoff_info(kb, kbdir, name)
      behind = ""
      if updated:
        n = git(top, "rev-list", "--count", f"--since={updated} 23:59", "HEAD")
        if n and n != "0":
          behind = f" {n} commit(s) in this repo since then, so the handoff is behind."
      lines.append(f"'{name}' ({status}), handoff updated {updated or 'never'} by {by or '?'}.{behind}")
    emit("SessionStart",
         f"This repo ({slug}) is tracked in the Avista knowledge base as " + " ".join(lines) +
         " Before changing code, read the handoff (`kb feature <slug>` via the kb-pickup skill) unless the user "
         "only asked a quick question. At the end of the session, update it with the kb-handoff skill without asking "
         "(Session end). If the handoff is behind, catch it up at the first pause.")
    return
  emit("SessionStart",
       f"This repo ({slug}, {repo_kind(top)}) is not tracked in the Avista knowledge base. If the user starts "
       "real work here (edits, commits, a fix that takes more than a few minutes), follow the kb-handoff skill's "
       "Start step: offer the 'Track work' picker once, at the first natural pause after that work begins. "
       "Never offer it on the first message, for questions or lookups, or in the middle of a multi-step task.")


# --- first ssh to a site ---------------------------------------------------

HOST_RE = re.compile(r"\b(?:ssh|scp|rsync|sftp)\b[^|;&]*?\b(?:[\w.-]+@)?([a-z0-9-]+\.tempurl\.host)\b", re.I)


def seen(session: str, key: str) -> bool:
  STATE.mkdir(parents=True, exist_ok=True)
  cutoff = time.time() - 7 * 86400
  for f in STATE.glob("*.txt"):
    if f.stat().st_mtime < cutoff:
      f.unlink(missing_ok=True)
  f = STATE / f"{re.sub(r'[^A-Za-z0-9_-]', '_', session or 'none')}.txt"
  done = set(f.read_text().split()) if f.is_file() else set()
  if key in done:
    return True
  with f.open("a") as fh:
    fh.write(key + "\n")
  return False


def post_bash(data: dict) -> None:
  if data.get("tool_name") != "Bash":
    return
  cmd = (data.get("tool_input") or {}).get("command") or ""
  m = HOST_RE.search(cmd)
  if not m:
    return
  host = m.group(1).lower()
  if seen(data.get("session_id", ""), host):
    return
  kb = load_kb()
  kbdir = find_kb(kb)
  if kbdir is None:
    return
  site, domain = None, None
  for sp in (kbdir / "sites").glob("*.md"):
    d = kb.parse(sp)
    if str(d.get("ssh_host") or "").lower() == host:
      site, domain = sp, kb.norm_domain(str(d.get("domain")))
      break
  if not site:
    emit("PostToolUse",
         f"{host} has no site page in the Avista knowledge base, so its domain isn't recorded. If code is changed "
         "on this server, follow the kb-handoff skill's Start step (Track work picker, once, at the next pause); "
         "it will create the site page.")
    return
  hits = features_for(kb, kbdir, domain=domain)
  if hits:
    names = ", ".join(f"'{n}' ({s})" for n, s, _ in hits)
    emit("PostToolUse",
         f"{host} is {domain}. The Avista knowledge base tracks these features on it: {names}. If this work "
         "belongs to one of them, read its handoff before changing code (kb-pickup) and update it at session end "
         "(kb-handoff, without asking). If it is new work that qualifies, offer the Track work picker once at the next pause.")
    return
  emit("PostToolUse",
       f"{host} is {domain}. No feature in the Avista knowledge base tracks this site. If code is changed here "
       "(not just inspected), follow the kb-handoff skill's Start step: offer the Track work picker once, at "
       "the next natural pause, never mid-task.")


MODES = {"session-start": session_start, "post-bash": post_bash}

def stamp(mode: str) -> None:
  """Record that a hook ran, so kb-setup can prove hooks load in real sessions."""
  STATE.parent.mkdir(parents=True, exist_ok=True)
  (STATE.parent / "hook-last-run").write_text(f"{mode} {time.strftime('%Y-%m-%dT%H:%M:%S')}\n")


if __name__ == "__main__":
  try:
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    stamp(mode)
    raw = sys.stdin.read() if not sys.stdin.isatty() else ""
    payload = json.loads(raw) if raw.strip() else {}
    handler = MODES.get(mode)
    if handler:
      handler(payload)
  except Exception as e:  # never block the session
    if os.environ.get("AVISTA_KB_HOOK_DEBUG"):
      print(f"avista-kb hook error: {e!r}", file=sys.stderr)
  sys.exit(0)
