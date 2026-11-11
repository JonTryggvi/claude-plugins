# avista-mail

Email for Claude in Avista's Gmail: drafts with links that stay real, written in your own voice.

## Skills

| Skill | Purpose |
|---|---|
| `avista-mail-overview` | What the plugin does, setup, how to make it the default. |
| `gmail-draft` | Create, update and reply-to Gmail drafts through the Gmail API instead of the connector. |
| `voice-profile` | Build or refresh your personal voice profile (`~/.claude/voice/profile.md`) from a sample of your own sent mail. |
| `voice-write` | Draft and rewrite emails and messages in your voice from that profile; Gmail drafts go through `gmail-draft`. |

## Why

Measured 2026-11-04: the Gmail connector's `create_draft` rewrites every URL in a draft — plain-text body and HTML `href` alike, including encoded and uppercase variants — into `https://www.google.com/url?q=REAL_URL&source=gmail&ust=<timestamp>&sa=E`. Protocol-relative links become `javascript:void(0)`. The draft is stored that way and sent that way. The Gmail API stores the MIME message as given.

Reading through the connector is unaffected.

## Your own voice

`voice-profile` reads your sent mail, not anyone else's, and writes a profile only you use. The plugin ships no one's voice: every person builds their own.

- `scripts/sent_sample.py fetch` lists the newest 1,000 `SENT` message ids and takes 200 spread evenly across them, so the sample covers more than the last few days. It fetches them through the Gmail batch endpoint, 25 per request: 12 HTTP requests and about 1,000 quota units in all (`--plan-only` prints the count without calling Gmail). Batches are paced to about 940 units a minute, and rate-limit replies (429, or 403 `rateLimitExceeded`) are retried after a back-off. A project can have a per-user per-minute cap well below Google's documented default; we hit one on 2026-11-11 with 50-message batches.
- Quoted replies, forwarded blocks, the Gmail signature and "Sent from my iPhone" lines are stripped. Messages sent by a delegate, calendar replies and chats are dropped. Recipient addresses aren't kept, only internal/external.
- Samples go in a private temp dir (700/600) and `sent_sample.py clean <dir>` deletes it after the profile is written. Bodies are never printed to stdout.
- The profile is `~/.claude/voice/profile.md` (dir 700, file 600). It's never committed or uploaded. A `## My own notes` section survives refreshes.
- `voice-write` defers to a hand-written personal voice skill if the user has one.

## Scripts

Python standard library only. `gmail_draft.py` and `unwrap.py` are in `skills/gmail-draft/scripts/`, and `sent_sample.py` is in `skills/voice-profile/scripts/`.

- `gmail_draft.py` — `auth` (one-time browser sign-in, PKCE, refresh token into `~/.claude/.env`), `create`, `update`, `check`. Builds a multipart plain + HTML message with real anchors, threads replies (`In-Reply-To`, `References`, `threadId`), appends the primary Gmail signature on request, and reads the stored draft back to count wrapped links. No send command.
- `unwrap.py` — turns `google.<tld>/url?q=` links in text or HTML back into the real URL.
- `sent_sample.py` — `fetch` (read-only, batched sample of your own sent mail into a private temp dir; reuses `gmail_draft.py`'s sign-in) and `clean` (deletes only a directory it created).

## Setup

See the `gmail-draft` skill. In short: Google Cloud project with the Gmail API enabled, Internal consent screen, OAuth client of type Desktop app; `GMAIL_CLIENT_ID` and `GMAIL_CLIENT_SECRET` in `~/.claude/.env`; then `python3 -I gmail_draft.py auth` in your own terminal.

Scopes: `gmail.compose` (drafts; Google bundles send into it, the script never sends) and `gmail.readonly` (reply headers, signature, and the sent-mail sample for `voice-profile`).
