---
name: gmail-draft
description: Create, update and reply-to Gmail drafts through the Gmail API with the bundled script instead of the Gmail connector, because the connector's create_draft, update_draft, reply and forward rewrite every link into a google.com/url?q=… redirect. Use whenever drafting or replying to an email, writing a Gmail draft, updating a draft, or any email that contains a link or URL — even when the user only says "skrifaðu póst", "svaraðu þessu", "draft a reply", "reply to this". Also use when someone says links in Claude's emails are "wrapped in google.com", "go through google.com/url" or "have a google redirect", or asks to set up Gmail draft access.
---

# Gmail drafts with real links

## Why

Measured 2026-11-04: the Gmail connector's `create_draft` rewrites **every** URL before it stores the draft — in the plain-text body, in HTML `<a href>`, with entity-encoded, uppercase and spaced variants alike — into:

```
https://www.google.com/url?q=REAL_URL&source=gmail&ust=<timestamp>&sa=E
```

The recipient gets an expiring google.com link that looks like phishing. A protocol-relative `href="//…"` is replaced with `javascript:void(0)`. Nothing in the input survives it, so drafts go through the Gmail API directly, which stores the message as given.

Reading mail with the connector is fine — received links come back as they were sent.

## Rule

- **Every draft, reply or draft update goes through `scripts/gmail_draft.py`.** Do not call the connector's `create_draft`, `update_draft`, `reply` or `forward` to write mail.
- Use the connector only to read: find the thread, `get_thread`, get the message id to reply to.
- **Draft, don't send.** The script has no send command. The user sends from Gmail.
- If the script isn't set up (`GMAIL_CLIENT_ID` / `GMAIL_CLIENT_SECRET` missing from `~/.claude/.env`), don't block on it: write the draft with the connector as usual, and when the draft contains links, list the real URLs under the draft link so the user can fix them in Gmail before sending. Mention Setup once, only if the user asks how to make it permanent.

## When the token expires (self-healing)

Google refresh tokens die when access is revoked, the password changes, or they go unused for about six months. The script handles it itself:

- Any command whose refresh fails with `invalid_grant` (or finds no `GMAIL_REFRESH_TOKEN`) opens the Google sign-in in the browser, waits up to 180 s, saves the new token and then finishes the draft. Nothing for Claude to do but wait.
- **Run every `create` / `update` / `check` with a Bash timeout of at least 240000 ms**, so the wait isn't cut off.
- If stderr says `Opening Google sign-in to renew it`, tell the user in one line: "Gmail access expired — click Allow in the browser tab that just opened." Do not click Allow for them.
- **Exit code 3 / `GMAIL_REAUTH_NEEDED`** means the sign-in didn't complete. Don't retry in a loop. Write this draft with the connector (listing the real URLs under the draft link, as above), and offer to start `python3 -I "$S" auth` in the user's Terminal panel so they can finish the sign-in; the next draft then goes through the script again.
- `GMAIL_NO_REAUTH=1` skips the browser step and exits 3 at once — for unattended runs where nobody can click.

## Usage

Write the body to a file in the scratchpad (plain text; the script builds the HTML part with real `<a href>` anchors), then:

```bash
S="<this skill's base directory>/scripts/gmail_draft.py"
```

New draft:

```bash
python3 -I "$S" create --to david@avista.is --cc thorvaldur@avista.is --subject "Efni" --body-file body.txt --signature
```

Reply in a thread (message id from the connector's `get_thread`; subject defaults to `Re: <original>`):

```bash
python3 -I "$S" create --to client@example.is --reply-to 1a1a6f21a55294e2 --body-file body.txt --signature
```

Replace a draft's content:

```bash
python3 -I "$S" update r2387382296715847742 --to client@example.is --subject "Efni" --body-file body.txt --signature
```

Check a draft made elsewhere:

```bash
python3 -I "$S" check r2387382296715847742
```

- `--to`, `--cc`, `--bcc` repeat for several recipients.
- `--html-file` supplies a hand-written HTML body; otherwise HTML is generated from the text.
- `--signature` appends the user's primary Gmail signature, like the connector's `includeSignature`.
- Output is JSON with `draftId`, `threadId`, a Gmail link and `wrappedLinks`. The script reads the stored draft back and exits 1 if any `google.com/url?` link is in it. Treat a non-zero `wrappedLinks` as a failure and tell the user.
- A reply draft does not quote the earlier message. Gmail shows the thread above it.

## Setup (once per person)

Done by the user, not by Claude — Claude never handles the client secret or tokens.

1. In Google Cloud Console, signed in with the `@avista.is` account: create (or reuse) a project, enable the **Gmail API**, set the OAuth consent screen to **Internal**, then **Credentials → Create credentials → OAuth client ID → Desktop app**.
2. Add the two values to `~/.claude/.env` (owner-only file, `chmod 600`):
   ```
   GMAIL_CLIENT_ID=....apps.googleusercontent.com
   GMAIL_CLIENT_SECRET=...
   ```
   One client can be shared by the whole team; each person still signs in with their own account.
3. In the user's own terminal (it opens a browser for sign-in):
   ```bash
   python3 -I "<this skill's base directory>/scripts/gmail_draft.py" auth
   ```
   This stores `GMAIL_REFRESH_TOKEN` in `~/.claude/.env`. It is never printed. Claude may start this command in the user's Terminal panel; the user clicks Allow.

Scopes requested: `gmail.compose` (create and update drafts — Google bundles send into this scope, the script never uses it) and `gmail.readonly` (reply headers and the signature).

To check setup, look only at key names: `grep -oE '^GMAIL_[A-Z_]+=' ~/.claude/.env`.

## Cleaning up text that is already wrapped

`scripts/unwrap.py` turns `google.<tld>/url?q=…` links back into the real URL — for drafts the connector already wrapped, or pasted text:

```bash
pbpaste | python3 -I "<this skill's base directory>/scripts/unwrap.py"
```
