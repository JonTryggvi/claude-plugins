#!/usr/bin/env bash
#
# hub-probe.sh — read-only capability test of the WPMU DEV Hub API.
#
#   bash hub-probe.sh
#
# Reads the WPMU DEV Hub API key and runs a fixed set of GET requests to find
# out what this key can actually see. Key resolution, first hit wins:
#
#   1. WPMUDEV_API_KEY in ~/.claude/.env   (no unlock prompt; key on disk)
#   2. WPMUDEV_OP_REF  in ~/.claude/.env   (a 1Password reference)
#   3. op://Shared/WPMU DEV API Key/credential   (Avista's shared item)
#
# 1Password is the default: the key stays off disk and each run is approved in
# the 1Password app. Writes:
#
#   ~/.claude/avista-wp-fleet/capabilities.json   one row per probe
#   ~/.claude/avista-wp-fleet/hub-sites.json      the site list, if any probe returned one
#
# GET only. Nothing is created, changed or deleted on WPMU DEV.
#
# The key goes .env or `op read` stdout -> shell variable -> printf (a builtin)
# -> curl stdin. It is
# never echoed, never written anywhere else, and never passed as a process
# argument, so it cannot be read out of `ps`.
#
# Why these probes: the CRM (crm.avista.is) found that GET /sites returns 502
# with a site's Dashboard key and lists sites through GET /team instead. Whether
# an account key gets past that 502 decides whether rollouts can go through the
# API or must go over SSH. This script answers that question; it does not assume.
#
set -uo pipefail

ENV_FILE="${CLAUDE_ENV_FILE:-$HOME/.claude/.env}"
OUT_DIR="${AVISTA_FLEET_DIR:-$HOME/.claude/avista-wp-fleet}"
BASE="https://wpmudev.com/api/hub/v1"

command -v jq >/dev/null || { echo "hub-probe: jq is required (brew install jq)" >&2; exit 2; }

env_value() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | sed -e 's/^["'\'']//' -e 's/["'\'']$//'; }

KEY_SOURCE=".env WPMUDEV_API_KEY"
WPMUDEV_API_KEY="$(env_value WPMUDEV_API_KEY)"
if [ -z "$WPMUDEV_API_KEY" ]; then
  OP_REF="$(env_value WPMUDEV_OP_REF)"
  OP_REF="${OP_REF:-op://Shared/WPMU DEV API Key/credential}"
  KEY_SOURCE="1Password ($OP_REF)"
  command -v op >/dev/null || { echo "hub-probe: no WPMUDEV_API_KEY in $ENV_FILE and the 1Password CLI (op) is not installed" >&2; exit 3; }
  WPMUDEV_API_KEY="$(op read "$OP_REF" </dev/null 2>/dev/null)"
  if [ -z "$WPMUDEV_API_KEY" ]; then
    echo "hub-probe: could not read the key from $KEY_SOURCE — 1Password locked, the request declined, or no access to that item" >&2
    exit 3
  fi
fi
echo "key source: $KEY_SOURCE"

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ROWS="$TMP/rows.jsonl"
: > "$ROWS"

# hub_get <path> -> prints HTTP status; body in $TMP/body, headers in $TMP/headers
hub_get() {
  printf 'Authorization: %s\nAccept: application/json\n' "$WPMUDEV_API_KEY" |
    curl -sS -o "$TMP/body" -D "$TMP/headers" -w '%{http_code}' --max-time 40 -H @- "$BASE$1" 2>"$TMP/curl_err" || true
}

header() { grep -i "^$1:" "$TMP/headers" 2>/dev/null | tail -1 | cut -d: -f2- | tr -d ' \r'; }

record() { # name path status note
  jq -nc --arg name "$1" --arg path "$2" --arg status "$3" --arg note "$4" \
    '{probe:$name, path:$path, status:($status|tonumber? // 0), note:$note}' >> "$ROWS"
  printf '%-16s %-48s %s  %s\n' "$1" "$2" "$3" "$4"
}

printf '%-16s %-48s %s  %s\n' PROBE PATH HTTP NOTE

# 1. /team — the route the CRM relies on today.
s=$(hub_get "/team")
note=""
if [ "$s" = 200 ]; then
  n=$(jq '(.sites // []) | length' "$TMP/body" 2>/dev/null || echo "?")
  note="sites in payload: $n"
  [ "$n" != "0" ] && [ "$n" != "?" ] && jq '[.sites[] | {id, domain, home_url}]' "$TMP/body" > "$TMP/team-sites.json"
else
  note="$(jq -r '.message // .code // empty' "$TMP/body" 2>/dev/null | head -c 120)"
fi
record team "/team" "$s" "$note"

# 2. /sites — the documented list. 502 here means the key behaves like a site key.
s=$(hub_get "/sites?per_page=100&page=1")
note=""
SITE_ID=""
if [ "$s" = 200 ]; then
  total=$(header x-wp-total); pages=$(header x-wp-totalpages)
  note="X-WP-Total=${total:-?} X-WP-TotalPages=${pages:-?}"
  cp "$TMP/body" "$TMP/sites-p1.json"
  SITE_ID=$(jq -r 'if type=="array" then .[0].id else (.data // .sites // [])[0].id end // empty' "$TMP/body")
  # Follow every page so the list is complete, never just page 1.
  p=2
  while [ -n "$pages" ] && [ "$p" -le "$pages" ]; do
    s2=$(hub_get "/sites?per_page=100&page=$p")
    [ "$s2" = 200 ] || { note="$note; page $p returned $s2"; break; }
    cp "$TMP/body" "$TMP/sites-p$p.json"
    p=$((p + 1))
  done
  jq -s '[.[] | (if type=="array" then . else (.data // .sites // []) end)[] | {id, domain, home_url, is_hosted, hosting_site_id, wp_version}]' "$TMP"/sites-p*.json > "$TMP/sites-all.json"
  note="$note; fetched $(jq length "$TMP/sites-all.json")"
else
  note="$(jq -r '.message // .code // empty' "$TMP/body" 2>/dev/null | head -c 120)"
fi
record sites "/sites?per_page=100" "$s" "$note"

# Fall back to a site id from /team for the per-site probes.
[ -z "$SITE_ID" ] && [ -f "$TMP/team-sites.json" ] && SITE_ID=$(jq -r '.[0].id // empty' "$TMP/team-sites.json")

if [ -n "$SITE_ID" ]; then
  # 3. Hosting module — does it expose SSH accounts, domains and the connect port?
  s=$(hub_get "/sites/$SITE_ID/modules/hosting")
  note=""
  if [ "$s" = 200 ]; then
    # Field names only, never values: accounts[] holds SSH usernames.
    note="fields present: $(jq -r '(if has("data") then .data else . end) as $h | ["accounts","domains","cname","connect_port","php","staging","backup"] | map(select(. as $f | $h | has($f))) | join(",")' "$TMP/body" 2>/dev/null)"
  else
    note="$(jq -r '.message // .code // empty' "$TMP/body" 2>/dev/null | head -c 120)"
  fi
  record hosting "/sites/{id}/modules/hosting" "$s" "$note"

  # 4. Per-site plugin list — the read half of an API-driven rollout.
  s=$(hub_get "/sites/$SITE_ID/plugins")
  note=""
  if [ "$s" = 200 ]; then
    note="plugins listed: $(jq 'if type=="array" then length else ((.data // .plugins // []) | length) end' "$TMP/body" 2>/dev/null)"
  else
    note="$(jq -r '.message // .code // empty' "$TMP/body" 2>/dev/null | head -c 120)"
  fi
  record plugins "/sites/{id}/plugins" "$s" "$note"
else
  record hosting "/sites/{id}/modules/hosting" 0 "skipped: no site id from /team or /sites"
  record plugins "/sites/{id}/plugins" 0 "skipped: no site id from /team or /sites"
fi

# Keep the most complete non-empty site list we got. An empty list is not a
# site list: it means the key belongs to an account whose team has no sites.
[ -f "$TMP/sites-all.json" ] && [ "$(jq length "$TMP/sites-all.json")" = 0 ] && rm -f "$TMP/sites-all.json"
if [ -f "$TMP/sites-all.json" ]; then
  cp "$TMP/sites-all.json" "$OUT_DIR/hub-sites.json"; SRC="/sites"
elif [ -f "$TMP/team-sites.json" ]; then
  cp "$TMP/team-sites.json" "$OUT_DIR/hub-sites.json"; SRC="/team"
else
  SRC=""
fi

jq -s --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg src "$SRC" \
  '{probed_at:$at, site_list_source:$src, probes:.}' "$ROWS" > "$OUT_DIR/capabilities.json"
chmod 600 "$OUT_DIR/capabilities.json" 2>/dev/null
[ -f "$OUT_DIR/hub-sites.json" ] && chmod 600 "$OUT_DIR/hub-sites.json"

# Whose team is this? Name only — enough to tell a personal account from the agency's.
TEAM_NAME=""
if [ "$(hub_get "/team")" = 200 ]; then
  TEAM_NAME=$(jq -r '"\(.name) (id \(.id))"' "$TMP/body" 2>/dev/null)
fi
jq --arg t "$TEAM_NAME" '. + {team:$t}' "$OUT_DIR/capabilities.json" > "$TMP/cap" && mv "$TMP/cap" "$OUT_DIR/capabilities.json"
chmod 600 "$OUT_DIR/capabilities.json"

echo
[ -n "$TEAM_NAME" ] && echo "key's team: $TEAM_NAME"
if [ -z "$SRC" ]; then
  echo "NO SITES: the key authenticates but its team lists no sites. It is probably a personal"
  echo "account's key, not the key of the account that owns the agency's sites. hub-sites.json not written."
fi
echo "wrote $OUT_DIR/capabilities.json${SRC:+ and hub-sites.json (from $SRC)}"
