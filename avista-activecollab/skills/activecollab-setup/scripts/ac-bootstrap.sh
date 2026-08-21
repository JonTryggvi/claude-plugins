#!/usr/bin/env bash
#
# ac-bootstrap.sh — one-time ActiveCollab API token bootstrap.
#
#   bash ac-bootstrap.sh "op://Employee/<login-item-id>" [https://active.avista.is]
#
# Exchanges the ActiveCollab login stored in 1Password for a long-lived API
# token, stores that token back into 1Password, and records the non-secret
# config in ~/.claude/.env.
#
# The password goes 1Password -> stdin -> HTTPS inside a single pipeline. It is
# never written to disk, never echoed, and never passed as a process argument.
#
set -uo pipefail

OP_LOGIN="${1:?usage: ac-bootstrap.sh <op://vault/login-item> [activecollab-url]}"
AC_URL="${2:-https://active.avista.is}"
AC_URL="${AC_URL%/}"

CLIENT_NAME="${AC_CLIENT_NAME:-Avista Claude Code}"
CLIENT_VENDOR="${AC_CLIENT_VENDOR:-Avista}"
ENV_FILE="${CLAUDE_ENV_FILE:-$HOME/.claude/.env}"

# ActiveCollab keys an API subscription on client_name + client_vendor, so
# re-running this updates the existing subscription instead of piling up tokens.
# The previously issued token stops working when that happens — expected.

die() { echo "FAIL: $*" >&2; exit 1; }

command -v op   >/dev/null 2>&1 || die "1Password CLI (op) is not installed."
command -v jq   >/dev/null 2>&1 || die "jq is not installed (brew install jq)."
command -v curl >/dev/null 2>&1 || die "curl is not installed."

# The vault is the first path segment of the login reference; the token item
# goes into the same vault.
OP_VAULT="${OP_LOGIN#op://}"; OP_VAULT="${OP_VAULT%%/*}"
[ -n "$OP_VAULT" ] || die "could not parse a vault out of '$OP_LOGIN'."

echo "ActiveCollab : $AC_URL"
echo "1Password    : $OP_LOGIN  (vault: $OP_VAULT)"

# --- 0. Is the instance reachable, and is it really ActiveCollab? -------------
info=$(curl -sS -m 15 "$AC_URL/api/v1/info" </dev/null 2>&1) \
  || die "could not reach $AC_URL — check the URL and your network/VPN."
app=$(printf '%s' "$info" | jq -r 'try .application catch ""')
[ "$app" = "ActiveCollab" ] \
  || die "$AC_URL/api/v1/info did not look like ActiveCollab (got: ${info:0:120})"
echo "Version      : $(printf '%s' "$info" | jq -r '.version // "?"')"

# --- 1. Read the username (safe to display) ----------------------------------
username=$(op read "$OP_LOGIN/username" </dev/null) \
  || die "could not read the username from 1Password. Is the item a Login, and is 1Password unlocked?"
echo "Authenticating as: $username"

# --- 2. Exchange password for a token ----------------------------------------
# jq -Rn + `input` pulls the password off stdin, keeping it out of argv.
resp=$(op read "$OP_LOGIN/password" </dev/null \
  | jq -Rn --arg u "$username" --arg cn "$CLIENT_NAME" --arg cv "$CLIENT_VENDOR" \
      '{username:$u, password:input, client_name:$cn, client_vendor:$cv}' \
  | curl -sS -m 30 -X POST "$AC_URL/api/v1/issue-token" \
      -H 'Content-Type: application/json' -d @- 2>&1)

if [ "$(printf '%s' "$resp" | jq -r 'try .is_ok catch false')" != "true" ]; then
  echo "FAIL: ActiveCollab did not issue a token." >&2
  # Only the error type/message — never the raw body.
  printf '%s' "$resp" \
    | jq -r 'try ("  type   : " + (.type//"?") + "\n  message: " + (.message//"?")) catch "  (non-JSON response)"' >&2
  cat >&2 <<'EOT'

  Common causes:
    - the 1Password item holds an out-of-date password
    - the account has two-factor auth enabled (issue-token cannot satisfy 2FA)
    - the user is not permitted to issue API tokens (ask an ActiveCollab owner)
EOT
  exit 1
fi

token=$(printf '%s' "$resp" | jq -r .token)
[ -n "$token" ] && [ "$token" != "null" ] || die "response claimed success but carried no token."
echo "Token issued OK (${#token} chars)"

# --- 3. Record the config ----------------------------------------------------
mkdir -p "$(dirname "$ENV_FILE")"
touch "$ENV_FILE"; chmod 600 "$ENV_FILE"

set_env() { # key [value] — update in place, append if absent, remove if value omitted
  local k="$1" v="${2-}" tmp
  tmp=$(mktemp)
  grep -v -E "^${k}=" "$ENV_FILE" > "$tmp" 2>/dev/null || true
  [ -n "$v" ] && printf '%s=%s\n' "$k" "$v" >> "$tmp"
  cat "$tmp" > "$ENV_FILE"   # rewrite in place, preserving the inode and 0600
  rm -f "$tmp"
}

set_env ACTIVECOLLAB_URL "$AC_URL"

if [ "${AC_STORE_OP:-0}" = "1" ]; then
  # 1Password-backed: the token stays off disk, at the cost of an unlock prompt
  # per call. An op:// reference cannot contain parentheses, so keep the title
  # plain and address the item by its ID.
  TOKEN_TITLE="${AC_TOKEN_TITLE:-ActiveCollab API Token - Claude Code}"

  # Re-running must not litter the vault with duplicates. `op item edit` can only
  # take a new value as an argument (exposing it in `ps`), so archive the old
  # item and write a fresh one. Archiving is reversible from the 1Password UI,
  # and the old token is already dead — ActiveCollab reissued the subscription.
  prior=$(op item list --vault="$OP_VAULT" --format=json </dev/null 2>/dev/null \
    | jq -r --arg t "$TOKEN_TITLE" 'try (.[] | select(.title==$t) | .id) catch empty' | head -1)
  if [ -n "$prior" ]; then
    op item delete "$prior" --archive </dev/null >/dev/null 2>&1 \
      && echo "Archived the previous token item ($prior)"
  fi

  # Template arrives via process substitution (never on disk); the token reaches
  # jq through the environment, so it stays out of argv.
  item_id=$(op item create --vault="$OP_VAULT" --format=json </dev/null \
    --template=<(AC_TOKEN="$token" jq -n --arg t "$TOKEN_TITLE" --arg url "$AC_URL" '{
        title: $t, category: "API_CREDENTIAL",
        fields: [
          {id:"credential", type:"CONCEALED", label:"credential", value:env.AC_TOKEN},
          {id:"hostname",   type:"STRING",    label:"hostname",   value:$url}
        ]
      }') | jq -r .id) \
    || die "could not write the token to 1Password."

  set_env ACTIVECOLLAB_OP_REF "op://$OP_VAULT/$item_id/credential"
  set_env ACTIVECOLLAB_TOKEN            # remove any stale plaintext token
  echo "Stored the token in 1Password: $OP_VAULT / $TOKEN_TITLE"
  echo "Wrote ACTIVECOLLAB_URL + ACTIVECOLLAB_OP_REF to $ENV_FILE (no secrets on disk)"
else
  # Default: token lives in ~/.claude/.env alongside the other Avista tokens.
  # No unlock prompts. The file is 0600; treat it as a credential store.
  set_env ACTIVECOLLAB_TOKEN "$token"
  set_env ACTIVECOLLAB_OP_REF           # remove any stale reference
  echo "Wrote ACTIVECOLLAB_URL + ACTIVECOLLAB_TOKEN to $ENV_FILE (mode 0600)"
fi

# --- 5. Install the client and prove the whole chain works -------------------
mkdir -p "$HOME/.claude/bin"
cp "$(dirname "${BASH_SOURCE[0]}")/ac" "$HOME/.claude/bin/ac"
chmod +x "$HOME/.claude/bin/ac"
echo "Installed client: ~/.claude/bin/ac"

echo
echo "Verifying..."
me=$("$HOME/.claude/bin/ac" GET /users 2>&1 \
  | jq -r --arg e "$username" 'try (.[] | select(.email==$e) | "\(.id)\t\(.display_name)") catch empty')
[ -n "$me" ] || die "the token was stored but a test call failed. Check $AC_URL is up and try again."
echo "  authenticated as user_id $me"

# --- 6. Is a bare `ac` safe to type on this machine? -------------------------
#
# macOS ships /usr/sbin/ac, a login-accounting tool, and ~/.claude/bin is not on
# PATH by default. A bare `ac GET /users` therefore runs Apple's binary, prints
# `total 0.00`, and EXITS 0 — a wrong answer that looks like an empty result and
# raises no error anywhere. Every skill writes the full path for this reason, but
# people type the short form, so say plainly what `ac` resolves to here.
echo
resolved=$(command -v ac 2>/dev/null || true)
ALIAS_LINE='alias ac="$HOME/.claude/bin/ac"'
case "${SHELL:-}" in
  */zsh) RC="$HOME/.zshrc" ;;
  */bash) RC="$HOME/.bashrc" ;;
  *) RC="$HOME/.zshrc" ;;
esac

if [ "$resolved" = "$HOME/.claude/bin/ac" ]; then
  echo "Bare \`ac\` resolves to our client. Nothing to do."
elif [ -z "$resolved" ]; then
  echo "Bare \`ac\` is not on PATH — the full path always works:"
  echo "    ~/.claude/bin/ac GET /users"
  echo "  To make the short form work, add this to $RC:"
  echo "    $ALIAS_LINE"
else
  echo "WARNING: bare \`ac\` resolves to $resolved, NOT our client."
  if [ "$resolved" = "/usr/sbin/ac" ]; then
    echo "  That is macOS login accounting. \`ac GET /users\` prints \"total 0.00\" and exits 0,"
    echo "  so a wrong answer reaches you with no error attached. Always call the full path:"
  else
    echo "  Something else owns that name. Always call the full path:"
  fi
  echo "    ~/.claude/bin/ac GET /users"
  echo "  Or shadow it deliberately by adding this to $RC:"
  echo "    $ALIAS_LINE"
fi

# Only write to a shell rc when explicitly asked. That file is the user's, and a
# skill should not quietly edit persistent shell config on their behalf.
if [ "${AC_INSTALL_ALIAS:-0}" = "1" ]; then
  if [ -f "$RC" ] && grep -qF "$ALIAS_LINE" "$RC"; then
    echo "  alias already present in $RC — left alone"
  else
    printf '\n# ActiveCollab API client (avista-activecollab plugin)\n%s\n' "$ALIAS_LINE" >> "$RC"
    echo "  appended the alias to $RC — open a new shell, then: ac GET /users"
  fi
fi

echo
echo "Setup complete."
