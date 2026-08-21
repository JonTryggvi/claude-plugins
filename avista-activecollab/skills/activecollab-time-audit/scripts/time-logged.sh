#!/usr/bin/env bash
#
# time-logged.sh — read logged time out of ActiveCollab and aggregate it.
#
#   time-logged.sh --from 2026-06-01 --to 2026-08-21
#   time-logged.sh --from 2026-06-01 --to 2026-08-21 --project 479
#   time-logged.sh --from 2026-06-01 --to 2026-08-21 --user 6
#   time-logged.sh --from 2026-06-01 --to 2026-08-21 --quiet > logged.json
#
# Emits JSON on stdout; a human-readable summary on stderr (silence it with
# --quiet). Read-only: never writes, updates or deletes anything.
#
# Why this script exists rather than a couple of inline `ac` calls:
#
#   1. `/time-records?from=&to=` is the ONLY endpoint that honours a date
#      window, and it requires BOTH bounds — omit `to` and it answers
#      `Invalid timesheet period.`
#   2. That endpoint SILENTLY IGNORES `user_id`, `billable_status` and `page`.
#      Passing them returns the unfiltered set with a 200, so a filter that
#      looks applied is not. All filtering here is therefore client-side.
#   3. `/reports/run?type=TrackingFilter` looks like the better source and is
#      not: it ignores `from`/`to` (returns history back to 2016), mixes
#      `Expense` records — whose `value` is ISK, not hours — into the same
#      array, and silently omits every project the token's user cannot see.
#      Summing its `.value` yields a meaningless ISK+hours total.
#   4. Every response is redirected to a file, never captured in `$(...)`.
#      The shell runs under LC_CTYPE="C", so Icelandic characters in a summary
#      field throw `character not in range` the moment the JSON passes through
#      command substitution.
#
set -uo pipefail

FROM=""; TO=""; PROJECT=""; USER_ID=""; QUIET=0
AC="${AC_BIN:-$HOME/.claude/bin/ac}"

usage() {
  echo "usage: time-logged.sh --from YYYY-MM-DD --to YYYY-MM-DD [--project ID] [--user ID] [--quiet]" >&2
  exit 64
}

while [ $# -gt 0 ]; do
  case "$1" in
    --from)    FROM="${2:-}"; shift 2 ;;
    --to)      TO="${2:-}"; shift 2 ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    --user)    USER_ID="${2:-}"; shift 2 ;;
    --quiet)   QUIET=1; shift ;;
    -h|--help) usage ;;
    *) echo "time-logged.sh: unknown argument '$1'" >&2; usage ;;
  esac
done

[ -n "$FROM" ] && [ -n "$TO" ] || { echo "time-logged.sh: --from and --to are both required (the API rejects a half-open window)" >&2; usage; }
for d in "$FROM" "$TO"; do
  case "$d" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
    *) echo "time-logged.sh: dates must be YYYY-MM-DD (got '$d')" >&2; exit 64 ;;
  esac
done
[ -x "$AC" ] || { echo "time-logged.sh: no ac client at $AC — run the activecollab-setup skill" >&2; exit 69; }

TMP=$(mktemp -d) || exit 70
trap 'rm -rf "$TMP"' EXIT

"$AC" GET "/time-records?from=${FROM}&to=${TO}" > "$TMP/tr.json" 2>"$TMP/tr.err"
if [ ! -s "$TMP/tr.json" ]; then
  echo "time-logged.sh: no response from /time-records — see below" >&2
  cat "$TMP/tr.err" >&2
  exit 65
fi
if jq -e 'has("message") and (has("time_records")|not)' < "$TMP/tr.json" >/dev/null 2>&1; then
  jq -r '"time-logged.sh: ActiveCollab refused the read: \(.message)"' < "$TMP/tr.json" >&2
  exit 65
fi

"$AC" GET /job-types > "$TMP/jt.json" 2>/dev/null || true
jq -e 'type=="array"' < "$TMP/jt.json" >/dev/null 2>&1 || echo '[]' > "$TMP/jt.json"

jq -n \
  --slurpfile tr "$TMP/tr.json" \
  --slurpfile jt "$TMP/jt.json" \
  --arg from "$FROM" --arg to "$TO" \
  --arg project "$PROJECT" --arg user "$USER_ID" '
  ($tr[0]) as $doc
  | ($jt[0] | map({key:(.id|tostring), value:.name}) | from_entries) as $jobs
  | (($doc.related.Project // {}) | with_entries({key:.key, value:.value.name})) as $pnames
  | ($doc.time_records // []) as $all
  | ($all | map(select(.is_trashed == true))) as $trashed
  | ($all | map(select(.is_trashed != true))
      | (if $project != "" then map(select(.project_id == ($project|tonumber))) else . end)
      | (if $user    != "" then map(select(.user_id    == ($user|tonumber)))    else . end)
    ) as $rec
  | ($rec | map(.value) | add // 0) as $hours
  | {
      window: {from: $from, to: $to},
      source: "/time-records?from&to (the only date-windowed time endpoint; its user_id/billable_status/page params are ignored, so filtering here is client-side)",
      filters: {project: (if $project=="" then null else ($project|tonumber) end),
                user:    (if $user=="" then null else ($user|tonumber) end)},
      totals: {
        records: ($rec|length),
        hours: (($hours*100|round)/100),
        billable_hours:     ((($rec|map(select(.billable_status != 0))|map(.value)|add // 0)*100|round)/100),
        non_billable_hours: ((($rec|map(select(.billable_status == 0))|map(.value)|add // 0)*100|round)/100),
        invoiced_hours:     ((($rec|map(select(.invoice_item_id != 0))|map(.value)|add // 0)*100|round)/100)
      },
      by_user: ($rec | group_by(.user_id) | map({
        user_id: .[0].user_id, user_name: .[0].user_name,
        records: length, hours: ((((map(.value)|add)*100)|round)/100)
      }) | sort_by(-.hours)),
      by_project: ($rec | group_by(.project_id) | map({
        project_id: .[0].project_id,
        project_name: ($pnames[(.[0].project_id|tostring)] // null),
        resolvable: (($pnames[(.[0].project_id|tostring)] // null) != null),
        records: length, hours: ((((map(.value)|add)*100)|round)/100)
      }) | sort_by(-.hours)),
      by_job_type: ($rec | group_by(.job_type_id) | map({
        job_type_id: .[0].job_type_id,
        job_type: ($jobs[(.[0].job_type_id|tostring)] // "unknown"),
        records: length, hours: ((((map(.value)|add)*100)|round)/100)
      }) | sort_by(-.hours)),
      unresolvable_projects: ($rec | map(.project_id) | unique
        | map(select(($pnames[(.|tostring)] // null) == null))),
      warnings: ([]
        + (if ($rec|length) == 0 then ["no time records in this window after filtering"] else [] end)
        + (if ($trashed|length) > 0 then ["\($trashed|length) trashed record(s) excluded"] else [] end)
        + (($rec | map(.project_id) | unique | map(select(($pnames[(.|tostring)] // null) == null)) | length) as $u
           | if $u > 0 then ["\($u) project(s) could not be resolved to a name — this token cannot read them, so their hours are counted but unattributed"] else [] end)
      )
    }' > "$TMP/out.json"

cat "$TMP/out.json"

[ "$QUIET" = "1" ] && exit 0

{
  jq -r '"logged time  \(.window.from) .. \(.window.to)"' < "$TMP/out.json"
  jq -r '"  \(.totals.hours)h across \(.totals.records) records   billable \(.totals.billable_hours)h   already invoiced \(.totals.invoiced_hours)h"' < "$TMP/out.json"
  echo "  per person:"
  jq -r '.by_user[] | "    \(.hours)h\t\(.user_name)"' < "$TMP/out.json"
  echo "  top projects:"
  jq -r '.by_project[:10][] | "    \(.hours)h\t\(.project_name // "project \(.project_id) (name not readable)")"' < "$TMP/out.json"
  jq -r '.warnings[] | "  ! \(.)"' < "$TMP/out.json"
} >&2
