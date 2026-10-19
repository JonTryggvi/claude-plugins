#!/usr/bin/env bash
#
# inventory.sh — read every Hub site's WordPress version, plugins and themes.
#
#   bash inventory.sh
#
# One GET /api/hub/v1/sites/{id} per site in ~/.claude/avista-wp-fleet/hub-sites.json.
# That response carries the same plugin list as /sites/{id}/plugins (verified
# 2026-10-19: identical 41 rows, one page), plus themes and the WP version, so
# it halves the calls. A plugin's id is its file path (avista-core/avista-core.php),
# except WPMU DEV's own plugins, which use a numeric project id (119 = Dashboard);
# both are stored as strings. Requests are sequential with a short gap because WPMU DEV
# documents no rate limit; a 429 or 5xx is retried once after a pause.
#
# Writes (mode 600) to ~/.claude/avista-wp-fleet/:
#   inventory.json   one row per site: versions, plugins, themes, or the error
#
# GET only. Key resolution and handling match fleet-setup's hub-probe.sh: the
# key goes from .env or `op read` into a variable, then through printf to curl's
# stdin. It is never echoed or passed as a process argument.
#
set -uo pipefail

ENV_FILE="${CLAUDE_ENV_FILE:-$HOME/.claude/.env}"
D="${AVISTA_FLEET_DIR:-$HOME/.claude/avista-wp-fleet}"
BASE="https://wpmudev.com/api/hub/v1"
GAP="${FLEET_REQUEST_GAP:-0.3}"

command -v jq >/dev/null || { echo "inventory: jq is required (brew install jq)" >&2; exit 2; }
[ -s "$D/hub-sites.json" ] || { echo "inventory: $D/hub-sites.json missing — run fleet-setup first" >&2; exit 3; }

env_value() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | sed -e 's/^["'\'']//' -e 's/["'\'']$//'; }
WPMUDEV_API_KEY="$(env_value WPMUDEV_API_KEY)"
if [ -z "$WPMUDEV_API_KEY" ]; then
  OP_REF="$(env_value WPMUDEV_OP_REF)"; OP_REF="${OP_REF:-op://Shared/WPMU DEV API Key/credential}"
  WPMUDEV_API_KEY="$(op read "$OP_REF" </dev/null 2>/dev/null)"
  [ -n "$WPMUDEV_API_KEY" ] || { echo "inventory: could not read the key from $OP_REF" >&2; exit 3; }
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ROWS="$TMP/rows.jsonl"; : > "$ROWS"

hub_get() {
  printf 'Authorization: %s\nAccept: application/json\n' "$WPMUDEV_API_KEY" |
    curl -sS -o "$TMP/body" -w '%{http_code}' --max-time 40 -H @- "$BASE$1" 2>/dev/null || echo 000
}

TOTAL=$(jq length "$D/hub-sites.json")
i=0; ok=0; failed=0
while IFS=$'\t' read -r id domain; do
  i=$((i + 1))
  s=$(hub_get "/sites/$id")
  if [ "$s" = 429 ] || [ "${s:0:1}" = 5 ] || [ "$s" = 000 ]; then
    sleep 5; s=$(hub_get "/sites/$id")
  fi
  if [ "$s" = 200 ] && jq -e 'type=="object"' "$TMP/body" >/dev/null 2>&1; then
    jq -c --arg d "$domain" '{
      hub_id: .id, domain: (.domain // $d), ok: true,
      has_active_dash: .has_active_dash, is_hosted: .is_hosted, hosting_variant: .hosting_variant,
      is_multisite: .is_multisite, labels: (.labels // []),
      wp_version: .wp_version.version, wp_latest: .wp_version.latest_version,
      num_updates: .num_updates,
      plugins: [ (.plugins // [])[] | {file: (.id | tostring), name, version, latest_version, active: .is_active, has_update} ],
      themes:  [ (.themes  // [])[] | {name, version, latest_version, active: .is_active, has_update} ]
    }' "$TMP/body" >> "$ROWS"
    ok=$((ok + 1))
  else
    msg=$(jq -r '.message // .code // empty' "$TMP/body" 2>/dev/null | head -c 120)
    jq -nc --argjson id "$id" --arg d "$domain" --arg s "$s" --arg m "$msg" \
      '{hub_id:$id, domain:$d, ok:false, http:($s|tonumber? // 0), error:$m}' >> "$ROWS"
    failed=$((failed + 1))
  fi
  [ $((i % 25)) = 0 ] && echo "  $i / $TOTAL"
  sleep "$GAP"
done < <(jq -r '.[] | [.id, .domain] | @tsv' "$D/hub-sites.json")

jq -s --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{read_at:$at, sites:.}' "$ROWS" > "$D/inventory.json"
chmod 600 "$D/inventory.json"
echo "sites read: $ok   failed: $failed   of $TOTAL"
echo "wrote $D/inventory.json"
