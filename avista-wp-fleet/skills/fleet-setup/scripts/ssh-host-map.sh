#!/usr/bin/env bash
#
# ssh-host-map.sh — find out which site each configured SSH host actually serves.
#
#   bash ssh-host-map.sh
#
# For every `Host *.tempurl.host` block in ~/.ssh/config, connects read-only and
# asks WordPress for its home URL. The Hub knows sites by domain; ~/.ssh/config
# knows them by tempurl host. Asking the site is the only reliable join — the
# tempurl slug often differs from the domain (steindal-is vs steindal.is).
#
# Writes ~/.claude/avista-wp-fleet/ssh-hosts.json
#   [{ssh_host, home_url, domain, wp_root, reachable, error}]
#
# Read-only: runs `wp option get home` and nothing else.
#
set -uo pipefail

OUT_DIR="${AVISTA_FLEET_DIR:-$HOME/.claude/avista-wp-fleet}"
mkdir -p "$OUT_DIR"; chmod 700 "$OUT_DIR"
ROWS="$(mktemp)"; trap 'rm -f "$ROWS"' EXIT

hosts=$(awk 'tolower($1)=="host" { for (i=2;i<=NF;i++) if ($i ~ /tempurl\.host$/) print $i }' ~/.ssh/config 2>/dev/null | sort -u)
[ -z "$hosts" ] && { echo "ssh-host-map: no *.tempurl.host entries in ~/.ssh/config" >&2; exit 3; }

for h in $hosts; do
  res=$(ssh -n -o BatchMode=yes -o ConnectTimeout=12 "$h" \
    'W=$(dirname "$(find ~ -maxdepth 4 -name wp-config.php 2>/dev/null | head -1)"); cd "$W" 2>/dev/null && echo "ROOT=$W" && wp option get home 2>/dev/null' 2>&1 \
    | grep -v -i 'post-quantum\|store now\|pq.html')
  root=$(printf '%s\n' "$res" | sed -n 's/^ROOT=//p' | head -1)
  home=$(printf '%s\n' "$res" | grep -E '^ *https?://' | head -1 | tr -d ' ')
  if [ -n "$home" ]; then
    jq -nc --arg h "$h" --arg u "$home" --arg r "$root" \
      '{ssh_host:$h, home_url:$u, domain:($u|sub("^https?://";"")|sub("/.*$";"")), wp_root:$r, reachable:true, error:""}' >> "$ROWS"
    printf '%-36s %s\n' "$h" "$home"
  else
    err=$(printf '%s\n' "$res" | tail -1 | head -c 120)
    jq -nc --arg h "$h" --arg e "$err" '{ssh_host:$h, home_url:"", domain:"", wp_root:"", reachable:false, error:$e}' >> "$ROWS"
    printf '%-36s UNREACHABLE  %s\n' "$h" "$err"
  fi
done

jq -s . "$ROWS" > "$OUT_DIR/ssh-hosts.json"
chmod 600 "$OUT_DIR/ssh-hosts.json"
echo "wrote $OUT_DIR/ssh-hosts.json"
