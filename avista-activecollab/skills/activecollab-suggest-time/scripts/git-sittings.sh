#!/usr/bin/env bash
#
# git-sittings.sh — group commits into working sittings and measure time.
#
#   git-sittings.sh                          # last 14 days, current repo
#   git-sittings.sh --since=3.days
#   git-sittings.sh main..HEAD               # a feature branch
#   AUTHOR=jon@avista.is git-sittings.sh     # only my commits
#
# Implements Avista's house rule for timesheet estimates:
#   - a gap longer than GAP_MIN starts a new sitting
#   - a sitting measures first-commit -> last-commit, NOT wall clock
#   - LEADIN_MIN is added per sitting for the investigation before its first commit
#   - uncommitted work is reported separately, never silently folded in
#
# Emits JSON on stdout. Measures; never prices. The output is a SUGGESTION —
# the caller must have a human confirm before anything is logged.
#
set -uo pipefail

GAP_MIN="${GAP_MIN:-45}"        # minutes; gap above this starts a new sitting
LEADIN_MIN="${LEADIN_MIN:-15}"  # minutes of investigation credited before each sitting's first commit
ROUND="${ROUND:-0.25}"          # round each sitting to this fraction of an hour
AUTHOR="${AUTHOR:-}"            # optional author filter (substring of name or email)

git rev-parse --git-dir >/dev/null 2>&1 || {
  echo '{"error":"not a git repository"}'; exit 1; }

args=("$@")
[ ${#args[@]} -eq 0 ] && args=(--since=14.days)
[ -n "$AUTHOR" ] && args+=("--author=$AUTHOR")

log=$(git log --no-merges --date-order --pretty=format:'%ct%x09%h%x09%aE%x09%s' "${args[@]}" 2>/dev/null)

if [ -z "$log" ]; then
  jq -n --arg a "$AUTHOR" '{sittings:[], total_hours:0, commit_count:0,
    signal_quality:"none", warnings:[], uncommitted_files:0,
    note:("no commits matched" + (if $a != "" then " for author \($a)" else "" end))}'
  exit 0
fi

# Dirty working tree = tail work that exists but has no commit to measure from.
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
last_commit=$(git log -1 --pretty=format:%ct 2>/dev/null)

raw=$(printf '%s\n' "$log" | sort -n | awk -v gap="$GAP_MIN" -v leadin="$LEADIN_MIN" -v round="$ROUND" '
BEGIN { printf "{\"sittings\":[" }
function flush(   span, hours) {
  if (n == 0) return
  span  = (last - first) / 3600.0
  hours = span + (leadin / 60.0)
  hours = int(hours / round + 0.5) * round
  if (hours < round) hours = round
  idx++
  printf "%s{\"sitting\":%d,\"start\":%d,\"end\":%d,\"commits\":%d,\"span_hours\":%.4f,\"hours\":%.2f,\"subjects\":[%s]}",
         (idx > 1 ? "," : ""), idx, first, last, n, span, hours, subs
  total += hours
}
{
  ts = $1
  # rebuild the subject from field 4 onward
  sub(/^[0-9]+\t[0-9a-f]+\t[^\t]*\t/, "")
  s = $0
  gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
  if (n > 0 && (ts - last) > gap * 60) { flush(); n = 0; subs = "" }
  if (n == 0) first = ts
  last = ts
  n++
  subs = subs (subs == "" ? "" : ",") "\"" s "\""
}
END {
  flush()
  printf "],\"total_hours\":%.2f,\"commit_count\":%d}", total, NR
}')

jq -n \
  --argjson raw "$raw" \
  --argjson dirty "${dirty:-0}" \
  --argjson last "${last_commit:-0}" \
  --arg gap "$GAP_MIN" --arg leadin "$LEADIN_MIN" --arg round "$ROUND" --arg author "$AUTHOR" \
  '{
     sittings: [$raw.sittings[] | . + {
       start_iso: (.start | todate),
       end_iso:   (.end   | todate),
       date:      (.start | todate[:10])
     }],
     total_hours: $raw.total_hours,
     commit_count: $raw.commit_count,
     uncommitted_files: $dirty,
     last_commit_iso: (if $last > 0 then ($last | todate) else null end),
     basis: {
       method: "commit-to-commit spans grouped into sittings",
       gap_minutes: ($gap | tonumber),
       leadin_minutes_per_sitting: ($leadin | tonumber),
       rounding_hours: ($round | tonumber),
       author_filter: (if $author == "" then null else $author end)
     },
     warnings: (
       []
       + (if $dirty > 0 then ["\($dirty) uncommitted file(s) — tail work is not measured here and must be added by hand"] else [] end)
       + (if $raw.commit_count == 1 then ["only one commit matched — commit spans cannot be measured, the figure is the lead-in allowance alone"] else [] end)
       + (if ([$raw.sittings[] | select(.commits == 1)] | length) > 0 then ["\([$raw.sittings[] | select(.commits == 1)] | length) sitting(s) have a single commit — measured as lead-in only, likely an undercount"] else [] end)
       + (if ([$raw.sittings[] | select(.span_hours < 0.5 and .commits > 1)] | length) > 0 then ["\([$raw.sittings[] | select(.span_hours < 0.5 and .commits > 1)] | length) sitting(s) span under 30 minutes of commit time — commits clustered at the end of a long session look like this. If the real work took longer, the commit log is a POOR SIGNAL and you should measure from something else rather than trust this figure"] else [] end)
     ),
     signal_quality: (
       if   ($raw.commit_count == 0) then "none"
       elif ($raw.commit_count == 1) then "poor"
       elif ([$raw.sittings[] | select(.span_hours < 0.5)] | length) == ($raw.sittings | length) then "poor"
       elif ($raw.total_hours < 1) then "weak"
       else "usable" end
     )
   }'
