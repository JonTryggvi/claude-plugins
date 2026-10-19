#!/usr/bin/env bash
#
# report.sh — summarise inventory.json: our plugins and where they run.
#
#   bash report.sh                       # plugins whose name or file matches "avista"
#   bash report.sh 'avista|regluvordur'  # any extended regex, case-insensitive
#   bash report.sh --plugin avista-core  # one plugin: every site and version
#
# Reads ~/.claude/avista-wp-fleet/inventory.json and sites.json (for customer
# names). Writes ~/.claude/avista-wp-fleet/inventory-report.md and prints it.
# Read-only; no network.
#
set -uo pipefail

D="${AVISTA_FLEET_DIR:-$HOME/.claude/avista-wp-fleet}"
[ -s "$D/inventory.json" ] || { echo "report: $D/inventory.json missing — run inventory.sh" >&2; exit 3; }
[ -s "$D/sites.json" ] || echo '[]' > "$D/sites.json"

if [ "${1:-}" = "--plugin" ]; then
  slug="${2:?usage: report.sh --plugin <folder-or-name>}"
  jq -r --arg p "$slug" --slurpfile s "$D/sites.json" '
    ($s[0] | map({key: (.hub_id|tostring), value: ([.customers[].name | gsub("&#0?38;"; "&")] | join(", "))}) | from_entries) as $cust
    | [ .sites[] | select(.ok) | . as $site
        | .plugins[] | select((.file | tostring | split("/")[0] | ascii_downcase) == ($p|ascii_downcase) or (.name|ascii_downcase) == ($p|ascii_downcase))
        | {domain: $site.domain, version, active, has_update, customer: ($cust[($site.hub_id|tostring)] // "")} ]
    | sort_by((.version // "" | [scan("[0-9]+") | tonumber]), .domain)
    | "| Site | Version | Active | Update available | Customer |", "|---|---|---|---|---|",
      (.[] | "| \(.domain) | \(.version) | \(.active) | \(.has_update) | \(.customer) |"),
      "", "\(length) installs"
  ' "$D/inventory.json"
  exit 0
fi

PATTERN="${1:-avista}"
OUT="$D/inventory-report.md"

jq -r --arg re "$PATTERN" '
  .read_at as $at
  | [.sites[] | select(.ok)] as $ok
  | [.sites[] | select(.ok | not)] as $bad
  | [ $ok[] | . as $site | .plugins[]
      | select(((.name // "") + " " + (.file // "" | tostring)) | test($re; "i"))
      | {folder: (.file | tostring | split("/")[0]), name, version, active, domain: $site.domain} ] as $ours
  | "# Fleet inventory",
    "",
    "Read \($at) from the WPMU DEV Hub API. \($ok|length) sites read, \($bad|length) failed.",
    "",
    "## Fleet",
    "",
    "| | Sites |",
    "|---|---|",
    "| Dashboard plugin active (data is current) | \($ok | map(select(.has_active_dash)) | length) |",
    "| No active Dashboard (plugin data may be stale or empty) | \($ok | map(select(.has_active_dash | not)) | length) |",
    "| Hosted on WPMU DEV | \($ok | map(select(.is_hosted)) | length) |",
    "| WordPress behind latest | \($ok | map(select(.wp_version != null and .wp_version != .wp_latest)) | length) |",
    "",
    "## Our plugins (name or file matching `\($re)`)",
    "",
    "| Plugin | Installs | Active | Versions in use |",
    "|---|---|---|---|",
    ( $ours | group_by(.folder)[]
      | "| \(.[0].name) (`\(.[0].folder)`) | \(length) | \(map(select(.active)) | length) | \(group_by(.version) | sort_by(.[0].version // "" | [scan("[0-9]+") | tonumber]) | map("\(.[0].version) ×\(length)") | join(", ")) |" ),
    "",
    "## Sites that failed to read",
    "",
    ( if ($bad|length) == 0 then "None." else ($bad[] | "- \(.domain) (hub \(.hub_id)): HTTP \(.http) \(.error)") end )
' "$D/inventory.json" > "$OUT"
chmod 600 "$OUT"
cat "$OUT"
