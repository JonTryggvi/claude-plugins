# avista-mail

Email for Claude in Avista's Gmail, with links that stay real.

## Skills

| Skill | Purpose |
|---|---|
| `avista-mail-overview` | What the plugin does, setup, how to make it the default. |
| `gmail-draft` | Create, update and reply-to Gmail drafts through the Gmail API instead of the connector. |

## Why

Measured 2026-11-04: the Gmail connector's `create_draft` rewrites every URL in a draft — plain-text body and HTML `href` alike, including encoded and uppercase variants — into `https://www.google.com/url?q=REAL_URL&source=gmail&ust=<timestamp>&sa=E`. Protocol-relative links become `javascript:void(0)`. The draft is stored that way and sent that way. The Gmail API stores the MIME message as given.

Reading through the connector is unaffected.

## Scripts

Both in `skills/gmail-draft/scripts/`, Python standard library only.

- `gmail_draft.py` — `auth` (one-time browser sign-in, PKCE, refresh token into `~/.claude/.env`), `create`, `update`, `check`. Builds a multipart plain + HTML message with real anchors, threads replies (`In-Reply-To`, `References`, `threadId`), appends the primary Gmail signature on request, and reads the stored draft back to count wrapped links. No send command.
- `unwrap.py` — turns `google.<tld>/url?q=` links in text or HTML back into the real URL.

## Setup

See the `gmail-draft` skill. In short: Google Cloud project with the Gmail API enabled, Internal consent screen, OAuth client of type Desktop app; `GMAIL_CLIENT_ID` and `GMAIL_CLIENT_SECRET` in `~/.claude/.env`; then `python3 -I gmail_draft.py auth` in your own terminal.

Scopes: `gmail.compose` (drafts; Google bundles send into it, the script never sends) and `gmail.readonly` (reply headers, signature).
