#!/usr/bin/env bash
#
# trashed-records.sh — find time records that were DELETED, and which date they
# were on, so a reconciliation does not re-propose work somebody deliberately
# removed.
#
#   trashed-records.sh --projects 489,487,154
#   trashed-records.sh --projects 489 --from 2026-08-01 --to 2026-08-31
#   trashed-records.sh --map ~/.claude/activecollab-project-map.json
#
# Emits JSON on stdout, a summary on stderr. READ-ONLY.
#
# WHY THIS EXISTS
#
# A reconciliation calls a date "unlogged" when it holds no active record. But a
# date whose duplicate was deliberately trashed also holds no active record, so
# it reads as unlogged and gets proposed again — and the deleted duplicate comes
# back. Demonstrated on a real month-end: 0.75h (16179) and 1.25h (16180) were
# posted to Fraktlausnir.is on 2026-08-12, recognised as already covered by the
# 3.50h record 16112 of 2026-08-13 which itemises the same work, and trashed. A
# fresh reconciliation proposes that same 2.00h straight back.
#
# HOW TRASHED RECORDS ARE ACTUALLY REACHABLE
#
# Not the way you would expect, so this is worth stating precisely — all of it
# verified against the live instance:
#
#   - `/time-records?from&to` CARRIES an `is_trashed` key but returns **zero**
#     trashed records. The server filters them out. So a client-side
#     `select(.is_trashed != true)` on that endpoint is dead code, and reading
#     that endpoint can never tell you a date had something deleted from it.
#     `/projects/<id>/time-records` and `/users/<id>/time-records` behave the
#     same way.
#   - `GET /trash` returns an object keyed by type — `TimeRecord`, `Task`,
#     `TaskList`, `RecurringTask`. Its `TimeRecord` value is a map of
#     **id -> summary string**. That gives you the ids and nothing else: no
#     date, no value, no project.
#   - A trashed record IS fetchable in full at
#     `/projects/<project-id>/time-records/<id>` — `record_date`, `value`,
#     `is_trashed: true`, the lot. But you need the right project id: a wrong
#     one 404s.
#
# So the ids come from /trash and the fields come from a per-project probe. That
# is why this script needs a candidate project list, and why it reports ids it
# could not place rather than pretending they do not exist.
#
set -uo pipefail
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

AC="${AC_BIN:-$HOME/.claude/bin/ac}"
FROM=""; TO=""; PROJECTS=""; MAP=""; QUIET=0

usage() {
  cat >&2 <<'EOT'
usage: trashed-records.sh (--projects ID[,ID…] | --map FILE) [--from DATE --to DATE] [--quiet]

  --projects  candidate project ids to probe each trashed id against
  --map       take the candidate ids from a project map instead
  --from/--to restrict the report to trashed records inside this window
EOT
  exit 64
}

while [ $# -gt 0 ]; do
  case "$1" in
    --projects) PROJECTS="${2:-}"; shift 2 ;;
    --map)      MAP="${2:-}"; shift 2 ;;
    --from)     FROM="${2:-}"; shift 2 ;;
    --to)       TO="${2:-}"; shift 2 ;;
    --quiet)    QUIET=1; shift ;;
    -h|--help)  usage ;;
    *) echo "trashed-records.sh: unknown argument '$1'" >&2; usage ;;
  esac
done

[ -x "$AC" ] || { echo "trashed-records.sh: no ac client at $AC — run activecollab-setup" >&2; exit 69; }
command -v jq >/dev/null 2>&1 || { echo "trashed-records.sh: jq is not installed" >&2; exit 69; }

TMP=$(mktemp -d) || exit 70
trap 'rm -rf "$TMP"' EXIT

# Candidate projects: explicit list, or every non-private entry in the map.
: > "$TMP/pids.txt"
if [ -n "$PROJECTS" ]; then
  printf '%s\n' "$PROJECTS" | tr ',' '\n' | tr -d ' ' | grep -E '^[0-9]+$' >> "$TMP/pids.txt" || true
fi
if [ -n "$MAP" ] && [ -f "$MAP" ]; then
  jq -r '.entries[]? | select((.private // false) | not) | .project_id // empty' < "$MAP" >> "$TMP/pids.txt"
  jq -r '.entries[]? | (.also_logged_under // [])[]' < "$MAP" >> "$TMP/pids.txt" 2>/dev/null || true
fi
sort -un "$TMP/pids.txt" -o "$TMP/pids.txt"
[ -s "$TMP/pids.txt" ] || { echo "trashed-records.sh: no candidate project ids — pass --projects or a --map with entries" >&2; exit 64; }

"$AC" GET /trash > "$TMP/trash.json" 2>"$TMP/trash.err" || {
  echo "trashed-records.sh: could not read /trash" >&2; head -c 200 "$TMP/trash.err" >&2; echo >&2; exit 65; }
jq -e 'type=="object"' < "$TMP/trash.json" >/dev/null 2>&1 || echo '{}' > "$TMP/trash.json"

# /trash's TimeRecord node is id -> summary. Take the ids.
jq -r '(.TimeRecord // {}) | keys[]' < "$TMP/trash.json" > "$TMP/ids.txt" 2>/dev/null || : > "$TMP/ids.txt"

: > "$TMP/found.ndjson"
: > "$TMP/unresolved.txt"
probes=0
while IFS= read -r id; do
  [ -n "$id" ] || continue
  hit=0
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    probes=$((probes + 1))
    if "$AC" GET "/projects/$pid/time-records/$id" > "$TMP/r.json" 2>/dev/null; then
      if jq -e '(.single // .) | has("record_date")' < "$TMP/r.json" >/dev/null 2>&1; then
        jq -c --slurpfile t "$TMP/trash.json" --arg id "$id" '
          (.single // .) as $r
          | {
              id: ($id|tonumber),
              project_id: $r.project_id,
              record_date: ($r.record_date | if type=="number" then (.|todate[:10]) else (.|tostring[:10]) end),
              value: $r.value,
              user_id: $r.user_id,
              billable_status: $r.billable_status,
              invoiced: (($r.invoice_item_id // 0) != 0),
              is_trashed: ($r.is_trashed // true),
              summary: ((($t[0].TimeRecord // {})[$id]) // $r.summary // "")
            }' < "$TMP/r.json" >> "$TMP/found.ndjson"
        hit=1
        break
      fi
    fi
  done < "$TMP/pids.txt"
  [ "$hit" = "1" ] || printf '%s\n' "$id" >> "$TMP/unresolved.txt"
done < "$TMP/ids.txt"

jq -s --slurpfile t "$TMP/trash.json" \
      --arg from "$FROM" --arg to "$TO" --argjson probes "$probes" \
      --rawfile unresolved "$TMP/unresolved.txt" '
  . as $found
  | ($found | map(select(
        ($from == "" or .record_date >= $from) and ($to == "" or .record_date <= $to)
      ))) as $win
  | {
      window: {from: (if $from=="" then null else $from end), to: (if $to=="" then null else $to end)},
      source: "ids from GET /trash (.TimeRecord is an id->summary map); fields from GET /projects/<id>/time-records/<id>, which serves trashed records in full. The date-windowed /time-records endpoint returns NO trashed records at all, so it cannot be used for this.",
      totals: {
        trashed_in_trash: (($t[0].TimeRecord // {}) | length),
        resolved: ($found | length),
        in_window: ($win | length),
        hours_in_window: ((($win | map(.value) | add // 0) * 100 | round) / 100),
        project_probes: $probes
      },
      trashed: ($win | sort_by(.record_date, .id)),
      all_resolved: ($found | sort_by(.record_date, .id)),
      unresolved_ids: ($unresolved | split("\n") | map(select(. != "")) | map(tonumber)),
      by_project_date: ($win | group_by([.project_id, .record_date])
        | map({project_id: .[0].project_id, record_date: .[0].record_date,
               records: length,
               hours: (((map(.value)|add // 0)*100|round)/100),
               ids: map(.id), values: map(.value)})),
      warnings: ([]
        + (if ($unresolved | split("\n") | map(select(. != "")) | length) > 0
           then ["\($unresolved | split("\n") | map(select(. != "")) | length) trashed record id(s) could not be placed against any candidate project, so their date and value are unknown. Widen the candidate list before concluding a date is clean — a trashed record you cannot see is exactly the one that comes back."]
           else [] end)
        + (if ($win | length) > 0
           then ["\($win|length) trashed record(s) fall in this window. A trashed record is USUALLY deliberate — a duplicate someone removed on purpose — so re-proposing its date pays twice. But a record trashed by accident is real missing time. Confirm each with the user rather than deciding either way."]
           else [] end))
    }' < "$TMP/found.ndjson" > "$TMP/out.json"

cat "$TMP/out.json"
[ "$QUIET" = "1" ] && exit 0
{
  jq -r '"trashed records" + (if .window.from then "  \(.window.from) .. \(.window.to)" else "  (all dates)" end)'  < "$TMP/out.json"
  jq -r '.totals | "  /trash holds \(.trashed_in_trash) time record(s); resolved \(.resolved), \(.in_window) in window (\(.hours_in_window)h), \(.project_probes) project probe(s)"' < "$TMP/out.json"
  jq -r '.by_project_date[] | "  ! project \(.project_id) \(.record_date): \(.hours)h trashed across \(.records) record(s) — ids \(.ids|map(tostring)|join(", ")) (\(.values|map(tostring)|join("h, "))h)"' < "$TMP/out.json"
  jq -r '.unresolved_ids[]? | "  ? id \(.) is trashed but could not be placed against a candidate project"' < "$TMP/out.json"
  jq -r '.warnings[] | "  ! \(.)"' < "$TMP/out.json"
} >&2
