#!/usr/bin/env bash
#
# run-log.sh — remember that a reconciliation already ran, and what it posted.
#
#   run-log.sh check  --from 2026-07-01 --to 2026-07-31 --user 6
#   run-log.sh append --from 2026-07-01 --to 2026-07-31 --user 6 \
#                     --records 16301,16302,16303 --decisions 2 --note "month-end"
#   run-log.sh show [--limit 10]
#
# Log lives at ~/.claude/activecollab-runs.jsonl (override AC_RUN_LOG), 0600,
# append-only, one JSON object per line.
#
# WHAT THIS IS FOR, AND WHAT IT DELIBERATELY IS NOT
#
# ActiveCollab is the authority on how many hours are logged. This log is not a
# second copy of that and must never be used to answer "how much is on the
# timesheet" — reading it instead of the API is how two sources of truth drift
# apart.
#
# It answers the two questions the API cannot:
#
#   1. "Did a run already cover this window?" A reconciliation that is re-run
#      after posting sees its own records as logged and proposes nothing, which
#      is fine — until a decision or a mapping changes and it proposes a subset
#      again. Knowing a run posted 84 records for this window on 2026-08-21 is
#      what turns "here are 6 proposals" into "here are 6 proposals, and note a
#      run already posted 84 records for this window three weeks ago".
#
#   2. "Which records did this tool create?" If a posting run fails halfway,
#      the ids that made it are the difference between resuming and
#      double-posting. The API cannot tell you which records came from here.
#
# Judgement calls do NOT belong here. A decision that a date is settled is
# durable, reviewed, and belongs in the project map's `decisions` array where it
# is versioned alongside the mapping and read on every run. This log is a
# receipt; the map is the memory.
#
set -uo pipefail
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

LOG="${AC_RUN_LOG:-$HOME/.claude/activecollab-runs.jsonl}"
CMD="${1:-}"; shift 2>/dev/null || true
FROM=""; TO=""; USER_ID=""; RECORDS=""; DECISIONS=""; NOTE=""; LIMIT=10

usage() {
  echo "usage: run-log.sh check|append|show [--from D --to D --user ID] [--records id,id] [--decisions N] [--note T] [--limit N]" >&2
  exit 64
}

while [ $# -gt 0 ]; do
  case "$1" in
    --from)      FROM="${2:-}"; shift 2 ;;
    --to)        TO="${2:-}"; shift 2 ;;
    --user)      USER_ID="${2:-}"; shift 2 ;;
    --records)   RECORDS="${2:-}"; shift 2 ;;
    --decisions) DECISIONS="${2:-}"; shift 2 ;;
    --note)      NOTE="${2:-}"; shift 2 ;;
    --limit)     LIMIT="${2:-10}"; shift 2 ;;
    -h|--help)   usage ;;
    *) echo "run-log.sh: unknown argument '$1'" >&2; usage ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "run-log.sh: jq is not installed" >&2; exit 69; }
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
[ -f "$LOG" ] || { : > "$LOG"; chmod 600 "$LOG" 2>/dev/null || true; }

case "$CMD" in

append)
  [ -n "$FROM" ] && [ -n "$TO" ] && [ -n "$USER_ID" ] || { echo "run-log.sh append: --from, --to and --user are required" >&2; exit 64; }
  TMP=$(mktemp) || exit 70
  jq -nc --arg from "$FROM" --arg to "$TO" --arg u "$USER_ID" \
        --arg recs "$RECORDS" --arg dec "$DECISIONS" --arg note "$NOTE" \
        --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg host "$(hostname -s 2>/dev/null || echo unknown)" '
    ($recs | split(",") | map(select(. != "") | gsub("^\\s+|\\s+$";"") ) | map(select(test("^[0-9]+$")) | tonumber)) as $ids
    | {
        at: $at,
        host: $host,
        window: {from: $from, to: $to},
        user_id: ($u|tonumber),
        records_posted: ($ids|length),
        record_ids: $ids,
        decisions_applied: (if $dec == "" then null else ($dec|tonumber) end),
        note: (if $note == "" then null else $note end)
      }' > "$TMP" || { rm -f "$TMP"; echo "run-log.sh: could not build the entry" >&2; exit 65; }
  cat "$TMP" >> "$LOG"; rm -f "$TMP"
  chmod 600 "$LOG" 2>/dev/null || true
  tail -1 "$LOG" | jq -r '"logged run: \(.window.from)..\(.window.to) user \(.user_id) — \(.records_posted) record(s) posted"' >&2
  ;;

check)
  [ -n "$FROM" ] && [ -n "$TO" ] || { echo "run-log.sh check: --from and --to are required" >&2; exit 64; }
  jq -s --arg from "$FROM" --arg to "$TO" --arg u "$USER_ID" '
    map(select(. != null))
    | (if $u == "" then . else map(select(.user_id == ($u|tonumber))) end) as $mine
    | ($mine | map(select(.window.from <= $to and .window.to >= $from))) as $ov
    | {
        window: {from: $from, to: $to},
        prior_runs: ($ov | sort_by(.at) | reverse),
        totals: {
          runs_overlapping: ($ov | length),
          records_posted: ($ov | map(.records_posted) | add // 0),
          last_run_at: ($ov | map(.at) | max // null)
        },
        warnings: (if ($ov|length) > 0
          then ["\($ov|length) prior run(s) already covered part or all of this window, posting \($ov | map(.records_posted) | add // 0) record(s) in total; most recent \($ov | map(.at) | max). Those hours are already on the timesheet and will read as logged — so anything proposed now is either genuinely new, or something a mapping or decision change has resurfaced. Say which before posting."]
          else [] end)
      }' < "$LOG"
  ;;

show)
  jq -s --argjson n "$LIMIT" 'map(select(. != null)) | sort_by(.at) | reverse | .[0:$n]' < "$LOG" > /tmp/.rl.$$ && cat /tmp/.rl.$$ && rm -f /tmp/.rl.$$
  jq -s --argjson n "$LIMIT" -r 'map(select(. != null)) | sort_by(.at) | reverse | .[0:$n][]
    | "  \(.at)  \(.window.from)..\(.window.to)  user \(.user_id)  \(.records_posted) record(s)\(if .note then "  — \(.note)" else "" end)"' < "$LOG" >&2
  ;;

*) usage ;;
esac
