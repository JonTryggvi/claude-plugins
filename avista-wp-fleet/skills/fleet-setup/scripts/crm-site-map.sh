#!/usr/bin/env bash
#
# crm-site-map.sh — read the customer <-> WPMU DEV site links out of the Avista CRM.
#
#   bash crm-site-map.sh <ssh-target>        e.g. jontryggvi_ssh@ace-avista.tempurl.host
#
# Extra ssh options (for a host with no ~/.ssh/config entry) go in FLEET_SSH_OPTS:
#   FLEET_SSH_OPTS="-i ~/.ssh/jont -o IdentitiesOnly=yes" bash crm-site-map.sh ...
#
# The CRM (crm.avista.is, theme ace-zero) stores each customer's Hub site ids in
# the `wpmudev_site_ids` post meta on `ace_customer` posts, decoded by the theme's
# avista_crm_customer_wpmudev_site_ids(). This runs that same decoder over SSH
# with `wp eval-file -` and writes:
#
#   ~/.claude/avista-wp-fleet/crm-customers.json
#     [{customer_id, name, activecollab_id, site_ids:[...]}]
#
# Read-only: no option, post or meta is written on the CRM.
#
set -uo pipefail

TARGET="${1:?usage: crm-site-map.sh <user@host>}"
OUT_DIR="${AVISTA_FLEET_DIR:-$HOME/.claude/avista-wp-fleet}"
mkdir -p "$OUT_DIR"; chmod 700 "$OUT_DIR"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# shellcheck disable=SC2086
ssh -o BatchMode=yes -o ConnectTimeout=15 ${FLEET_SSH_OPTS:-} "$TARGET" \
  'W=$(dirname "$(find ~ -maxdepth 4 -name wp-config.php 2>/dev/null | head -1)"); cd "$W" && wp eval-file - 2>/dev/null' \
  > "$TMP" <<'PHP'
<?php
if (!function_exists('avista_crm_customer_wpmudev_site_ids')) {
  fwrite(STDERR, "decoder missing\n");
  echo json_encode(['error' => 'avista_crm_customer_wpmudev_site_ids() not found — the CRM theme changed']);
  return;
}
$out = [];
$ids = get_posts(['post_type' => 'ace_customer', 'post_status' => 'any', 'numberposts' => -1, 'fields' => 'ids']);
foreach ($ids as $id) {
  $sites = avista_crm_customer_wpmudev_site_ids((int) $id);
  if (!$sites) continue;
  $out[] = [
    'customer_id'     => (int) $id,
    'name'            => get_the_title($id),
    'activecollab_id' => (string) get_post_meta($id, 'activecollab_customer_id', true),
    'site_ids'        => array_values(array_map('intval', $sites)),
  ];
}
echo json_encode(['customers_total' => count($ids), 'linked' => $out]);
PHP

if ! jq -e . "$TMP" >/dev/null 2>&1; then
  echo "crm-site-map: no JSON came back from $TARGET (ssh or wp-cli failed)" >&2
  exit 4
fi
if jq -e '.error' "$TMP" >/dev/null; then
  jq -r '.error' "$TMP" >&2; exit 5
fi

jq '.linked' "$TMP" > "$OUT_DIR/crm-customers.json"
chmod 600 "$OUT_DIR/crm-customers.json"
jq -r '"customers: \(.customers_total)  linked to sites: \(.linked|length)  site links: \([.linked[].site_ids[]]|length)"' "$TMP"
echo "wrote $OUT_DIR/crm-customers.json"
