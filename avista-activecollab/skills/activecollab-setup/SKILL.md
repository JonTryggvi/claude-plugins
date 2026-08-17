---
name: activecollab-setup
description: Set up ActiveCollab API access on an Avista machine — installs the 1Password CLI, walks the user through the desktop-app integration toggle, exchanges their ActiveCollab login for a long-lived API token, writes the token to ~/.claude/.env, and installs the `ac` client. Use when the user says "set up ActiveCollab", "connect me to ActiveCollab", "get an ActiveCollab token", "ActiveCollab isn't authenticated", "ac says not configured", "my ActiveCollab token stopped working", "401 from ActiveCollab", or before any other activecollab-* skill can run. Run this once per machine. The user's password is read directly from 1Password into the token request and is never stored, echoed, or passed as a process argument.
---

# ActiveCollab setup

Gets a machine from nothing to a working ActiveCollab API client. Run once per machine; re-run if the
token is revoked or the password changes.

Avista's instance is **self-hosted at `https://active.avista.is`** (ActiveCollab 8.x), so authentication
is the simple single-call `issue-token` flow — not the three-step cloud intent flow. Do not follow cloud
instructions found in ActiveCollab's docs; they do not apply here.

## Why a token and not the password

ActiveCollab 8 removed the *API Subscriptions* page from user profiles, so there is **no UI route to mint
a token** — `POST /api/v1/issue-token` with the account password is the only way to get one. That is a
one-time exchange: the password is used once, in-process, and only the resulting token is kept.

Never write the password into `~/.claude/.env`, a script, or a note. If someone asks you to, redirect
them to this flow — the token is revocable without a password change, the password is not.

## Where the token ends up

By default the token is written to `~/.claude/.env` as `ACTIVECOLLAB_TOKEN`, alongside Avista's other
tokens. The file is `0600`. This costs no unlock prompts, which matters because Claude Code starts a fresh
shell per command — a 1Password-backed token would prompt on **every** API call.

If a user prefers the token never touch disk, run the bootstrap with `AC_STORE_OP=1` and it stores the
token in 1Password instead, writing only a reference to `.env`. The `ac` client supports both and prefers
`ACTIVECOLLAB_TOKEN` when present. Offer this to anyone who asks; don't push it — the default matches how
the team already handles `FIGMA_TOKEN` and `AVISTA_GITHUB_TOKEN`.

## Step 1 — Check what's already there

```bash
command -v op && op --version; command -v jq || echo "jq MISSING"
grep -c ACTIVECOLLAB ~/.claude/.env 2>/dev/null || echo 0
[ -x ~/.claude/bin/ac ] && ~/.claude/bin/ac GET /users | jq -r '"already working: \(length) users"'
```

If that last line prints a user count, the machine is **already set up** — stop and say so. Reissuing a
token invalidates the existing one for no reason.

## Step 2 — Install the 1Password CLI

The password has to come from somewhere, and 1Password is where Avista keeps it.

```bash
brew install --cask 1password-cli
```

Then the part **only the user can do**, in the 1Password desktop app:
**Settings → Developer → Integrate with 1Password CLI**.

Ask them to flip it, then confirm:

```bash
op vault list </dev/null
```

Vaults listed means it works. Note that `op whoami` reports *"account is not signed in"* even when the
desktop integration is working — trust `op vault list`, not `op whoami`.

If it errors: the toggle is off, the desktop app is locked, or the user is signed into a different
1Password account than the one holding the ActiveCollab login.

## Step 3 — Find their ActiveCollab login item

```bash
op item list --format=json </dev/null \
  | jq -r '.[] | select((.title|ascii_downcase|test("active ?collab")) or ((.urls//[])[].href // "" | test("active\\.avista"))) | "\(.id)\t\(.title)\t[\(.vault.name)]"'
```

Show the matches and confirm which one to use. If nothing matches, the user must save their ActiveCollab
login to 1Password first — a **Login** item with `username` and `password` fields. Never read or print the
password field yourself; the script consumes it without exposing it.

## Step 4 — Bootstrap

```bash
bash "<this-skill-dir>/scripts/ac-bootstrap.sh" "op://<Vault>/<login-item-id>" "https://active.avista.is"
```

It verifies the host really is ActiveCollab, exchanges the password for a token, writes
`ACTIVECOLLAB_URL` + `ACTIVECOLLAB_TOKEN` to `~/.claude/.env` (mode `0600`), installs `~/.claude/bin/ac`,
and proves the whole chain with a real API call. It prints the user's `user_id` on success — note it, the
other skills need it.

Add `AC_STORE_OP=1` in front of the command for the 1Password-backed variant.

**Re-running invalidates the old token.** ActiveCollab keys the API subscription on
`client_name` + `client_vendor`, so a second run updates the one subscription rather than accumulating
tokens — but any other machine using that token stops working. If someone needs two machines live at
once, give the second a distinct `AC_CLIENT_NAME`.

## Step 5 — Confirm

```bash
ac GET    /users    | jq -r '"users: \(length)"'
ac GETALL /projects | jq -r '"projects: \(length)"'
```

`~/.claude/bin` may not be on the user's `PATH`. If `ac` is not found, call it as `~/.claude/bin/ac`, or
add the directory to their `~/.zshrc`.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `ac: not configured` | `~/.claude/.env` lacks `ACTIVECOLLAB_URL` plus a token or op ref — re-run step 4. |
| HTTP 401 on every call | Token revoked, or another machine re-ran the bootstrap under the same client name. Re-run step 4. |
| `type: 3 / Password is not valid` | The 1Password item holds a stale password. User updates 1Password, then re-run. |
| `type: 2 / User does not exist or not active` | Wrong email in the login item, or the account is suspended. |
| `type: 4` on issue-token | The account may not issue API tokens — an ActiveCollab owner has to grant it. |
| Token issue fails, account has 2FA | `issue-token` cannot satisfy 2FA. Use an account without it, or disable it for this one. |
| `could not read the API token from 1Password` | Only on the `AC_STORE_OP=1` path — 1Password is locked or the item was deleted. |

## Housekeeping worth raising

> **This endpoint returns every token in plaintext.** `/users/:id/api-subscriptions` includes a `token`
> field with the live credential in it. **Never** pipe it to `cat`, `head`, `tee`, a log, or a raw
> response dump — always project the safe fields with `jq` as below. A token printed to a terminal is a
> token in scrollback, in the session transcript, and in any agent's context; it has to be rotated.

API subscriptions never expire on their own. Once set up, show the user what is live on their account:

```bash
ac GET "/users/<their-user-id>/api-subscriptions" \
  | jq -r '.[] | "\(.id)\t\(.client_name) / \(.client_vendor)\tcreated=\(.created_on|todate)\trequests=\(.requests_count)"'
```

`requests_count` and `last_used_on` are the useful forensic fields: to test whether some other client is
using a given subscription, read the count, make the suspect client do one call, and read it again.

Note you can only read **your own** subscriptions — `/users/<someone-else>/api-subscriptions` returns 404
even for an Owner. A token belonging to another user can only be revoked from that user's account.

Anything unrecognised is a live full-access credential worth revoking
(`ac DELETE /users/<uid>/api-subscriptions/<id>`) — but **ask first**. A stale-looking entry may be a
mobile app they still use.
