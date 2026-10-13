#!/usr/bin/env bash
#
# build-site-map.sh — join the three sources into one site map.
#
#   bash build-site-map.sh
#
# Inputs (all in ~/.claude/avista-wp-fleet/, written by the other scripts):
#   hub-sites.json       Hub site id, domain, home_url        (hub-probe.sh)
#   crm-customers.json   customer -> Hub site ids             (crm-site-map.sh)
#   ssh-hosts.json       ssh host -> domain it serves         (ssh-host-map.sh)
#
# Output: sites.json — one row per Hub site:
#   {hub_id, domain, home_url, customers:[{customer_id,name,activecollab_id}], ssh_host}
#
# Domains are compared without a leading "www." because the Hub and WordPress
# disagree about it often enough to matter.
#
set -uo pipefail

D="${AVISTA_FLEET_DIR:-$HOME/.claude/avista-wp-fleet}"
for f in hub-sites.json crm-customers.json; do
  [ -f "$D/$f" ] || { echo "build-site-map: $D/$f missing — run the earlier steps first" >&2; exit 3; }
done
[ -f "$D/ssh-hosts.json" ] || echo '[]' > "$D/ssh-hosts.json"

jq -n \
  --slurpfile hub "$D/hub-sites.json" \
  --slurpfile crm "$D/crm-customers.json" \
  --slurpfile ssh "$D/ssh-hosts.json" '
  def norm: (. // "") | ascii_downcase | sub("^www\\."; "");
  ($ssh[0] | map(select(.reachable)) | map({key: (.domain|norm), value: .ssh_host}) | from_entries) as $byDomain
  | ($crm[0] | [ .[] as $c | $c.site_ids[] | {key: tostring, value: {customer_id: $c.customer_id, name: $c.name, activecollab_id: $c.activecollab_id}} ]
      | group_by(.key) | map({key: .[0].key, value: map(.value)}) | from_entries) as $byHub
  | $hub[0] | map({
      hub_id: .id,
      domain: .domain,
      home_url: .home_url,
      customers: ($byHub[(.id|tostring)] // []),
      ssh_host: ($byDomain[(.domain|norm)] // null)
    })
' > "$D/sites.json"
chmod 600 "$D/sites.json"

jq -r '
  "sites: \(length)",
  "  linked to a CRM customer: \(map(select(.customers|length>0))|length)",
  "  reachable over SSH:       \(map(select(.ssh_host))|length)",
  "  linked to 2+ customers:   \(map(select(.customers|length>1))|length)"
' "$D/sites.json"

# CRM links that point at a site the Hub no longer lists — stale or deleted sites.
jq -r --slurpfile hub "$D/hub-sites.json" '
  ($hub[0] | map(.id)) as $ids
  | [ .[] | .site_ids[] as $s | select(($ids | index($s)) | not) | "\(.name) -> \($s)" ]
  | if length > 0 then "CRM links to sites the Hub does not list (\(length), first 20 shown):", .[:20][] else empty end
' "$D/crm-customers.json"
echo "wrote $D/sites.json"
