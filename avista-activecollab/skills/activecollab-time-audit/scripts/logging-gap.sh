#!/usr/bin/env bash
#
# logging-gap.sh — compare hours LOGGED in ActiveCollab against hours MEASURED
# from the git log, over the same window, for a set of repo/project pairs.
#
#   logging-gap.sh --from 2026-06-01 --to 2026-08-21 --pairs pairs.tsv
#   AUTHOR=jontryggvi@avista.is logging-gap.sh --from … --to … --pairs pairs.tsv
#
# pairs.tsv — one pair per line, tab-separated, `#` comments and blanks ignored:
#
#   /Users/me/dev/regluvordur      412
#   /Users/me/dev/idnu             388
#
# Emits JSON on stdout, a table on stderr. Read-only.
#
# WHAT THE RATIO DOES AND DOES NOT MEAN
#
# `logged / measured` is a measure of LOGGING DISCIPLINE on commit-producing
# work, and nothing else. It is not a productivity metric and must never be
# presented as one.
#
#   - Only work that produces commits is measurable. Meetings, support, client
#     calls, design, QA, WP admin and anything done in a browser produce no
#     commits, so a project can be logged honestly and still show a ratio far
#     above 1.0. That is expected, not an error.
#   - A ratio below 1.0 on a repo-backed dev project is the signal worth
#     looking at: hours worked that never reached a timesheet.
#   - Pairs whose git signal is `poor` or `none` are EXCLUDED from the headline
#     ratio and reported separately. Squash-merged releases and
#     commit-everything-at-the-end sessions measure near zero and would
#     otherwise manufacture a huge fake gap.
#
set -uo pipefail

FROM=""; TO=""; PAIRS=""; QUIET=0
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SITTINGS="${GIT_SITTINGS:-$HERE/../../activecollab-suggest-time/scripts/git-sittings.sh}"
LOGGED="${TIME_LOGGED:-$HERE/time-logged.sh}"

usage() {
  echo "usage: logging-gap.sh --from YYYY-MM-DD --to YYYY-MM-DD --pairs FILE [--quiet]" >&2
  exit 64
}

while [ $# -gt 0 ]; do
  case "$1" in
    --from)  FROM="${2:-}"; shift 2 ;;
    --to)    TO="${2:-}"; shift 2 ;;
    --pairs) PAIRS="${2:-}"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) usage ;;
    *) echo "logging-gap.sh: unknown argument '$1'" >&2; usage ;;
  esac
done

[ -n "$FROM" ] && [ -n "$TO" ] && [ -n "$PAIRS" ] || usage
[ -f "$PAIRS" ] || { echo "logging-gap.sh: no such pairs file: $PAIRS" >&2; exit 66; }
[ -f "$SITTINGS" ] || { echo "logging-gap.sh: git-sittings.sh not found at $SITTINGS (set GIT_SITTINGS)" >&2; exit 69; }
[ -f "$LOGGED" ]   || { echo "logging-gap.sh: time-logged.sh not found at $LOGGED (set TIME_LOGGED)" >&2; exit 69; }

# git --until is a timestamp, so bound it at the day AFTER --to to include all of it.
if UNTIL=$(date -u -j -f "%Y-%m-%d" "$TO" -v+1d +%Y-%m-%d 2>/dev/null); then :
elif UNTIL=$(date -u -d "$TO + 1 day" +%Y-%m-%d 2>/dev/null); then :
else echo "logging-gap.sh: could not add a day to '$TO'" >&2; exit 65; fi

TMP=$(mktemp -d) || exit 70
trap 'rm -rf "$TMP"' EXIT

# One ActiveCollab read for the whole window; every project is filtered out of it.
bash "$LOGGED" --from "$FROM" --to "$TO" --quiet > "$TMP/logged.json" || {
  echo "logging-gap.sh: the ActiveCollab read failed — see above" >&2; exit 65; }

: > "$TMP/rows.ndjson"
while IFS=$'\t' read -r repo project rest || [ -n "${repo:-}" ]; do
  case "${repo:-}" in ''|'#'*) continue ;; esac
  [ -n "${project:-}" ] || { echo "logging-gap.sh: skipping '$repo' — no project id on that line" >&2; continue; }

  if [ ! -d "$repo/.git" ]; then
    jq -n --arg r "$repo" --arg p "$project" \
      '{repo:$r, project_id:($p|tonumber), error:"not a git repository"}' >> "$TMP/rows.ndjson"
    continue
  fi

  ( cd "$repo" && bash "$SITTINGS" "--since=$FROM" "--until=$UNTIL" ) > "$TMP/s.json" 2>/dev/null \
    || echo '{"total_hours":0,"signal_quality":"none","commit_count":0,"warnings":["git-sittings failed"]}' > "$TMP/s.json"

  jq -n --slurpfile s "$TMP/s.json" --slurpfile l "$TMP/logged.json" \
        --arg r "$repo" --arg p "$project" '
    ($s[0]) as $g | ($l[0]) as $lg | ($p|tonumber) as $pid
    | ([$lg.by_project[] | select(.project_id == $pid)] | first) as $proj
    | ($g.total_hours // 0) as $measured
    | ($proj.hours // 0) as $logged
    | {
        repo: $r,
        project_id: $pid,
        project_name: ($proj.project_name // null),
        measured_hours: $measured,
        logged_hours: $logged,
        delta_hours: (((($logged - $measured)*100)|round)/100),
        ratio: (if $measured > 0 then (((($logged/$measured)*100)|round)/100) else null end),
        commits: ($g.commit_count // 0),
        signal_quality: ($g.signal_quality // "none"),
        uncommitted_files: ($g.uncommitted_files // 0),
        counted_in_headline: (($g.signal_quality // "none") as $q | $q == "usable" or $q == "weak")
      }' >> "$TMP/rows.ndjson"
done < "$PAIRS"

jq -s --slurpfile lg "$TMP/logged.json" --arg from "$FROM" --arg to "$TO" '
  . as $rows
  | ([$rows[] | select(.error == null and .counted_in_headline)]) as $ok
  | ($ok | map(.measured_hours) | add // 0) as $m
  | ($ok | map(.logged_hours)   | add // 0) as $l
  | {
      window: {from: $from, to: $to},
      basis: "logged = ActiveCollab time records in the window; measured = git commit sittings (45min gap, +15min lead-in, 0.25h rounding) over the same window. Ratio is logging discipline on commit-producing work only — never a productivity measure.",
      company_totals: $lg[0].totals,
      headline: {
        pairs_counted: ($ok|length),
        pairs_excluded: (($rows|length) - ($ok|length)),
        measured_hours: ((($m*100)|round)/100),
        logged_hours:   ((($l*100)|round)/100),
        delta_hours:    (((($l-$m)*100)|round)/100),
        ratio: (if $m > 0 then (((($l/$m)*100)|round)/100) else null end),
        reading: (if $m <= 0 then "no measurable git time — nothing to compare"
                  elif ($l/$m) < 0.8 then "logged well below measured on commit-backed work — likely under-logging"
                  elif ($l/$m) < 0.95 then "logged slightly below measured — worth a look"
                  elif ($l/$m) <= 1.5 then "logged in line with or above measured — consistent with honest logging plus non-commit work"
                  else "logged far above measured — expected when most of the work is not commit-producing" end)
      },
      pairs: ($rows | sort_by(.ratio // 999)),
      excluded: [$rows[] | select(.error != null or (.counted_in_headline|not))
                 | {repo, project_id, reason: (.error // "git signal \(.signal_quality) — not measurable")}]
    }' < "$TMP/rows.ndjson" > "$TMP/out.json"

cat "$TMP/out.json"

[ "$QUIET" = "1" ] && exit 0

{
  jq -r '"logging gap  \(.window.from) .. \(.window.to)"' < "$TMP/out.json"
  printf '  %-34s %9s %9s %8s %7s  %s\n' repo measured logged delta ratio signal
  jq -r '.pairs[] | select(.error == null)
         | "  \(.repo|split("/")|last|.[0:34])\t\(.measured_hours)\t\(.logged_hours)\t\(.delta_hours)\t\(.ratio // "-")\t\(.signal_quality)"' < "$TMP/out.json" \
    | awk -F'\t' '{printf "  %-34s %9s %9s %8s %7s  %s\n", $1,$2,$3,$4,$5,$6}'
  jq -r '"  ---\n  counted \(.headline.pairs_counted) pair(s): measured \(.headline.measured_hours)h vs logged \(.headline.logged_hours)h  (ratio \(.headline.ratio // "-"))\n  \(.headline.reading)"' < "$TMP/out.json"
  jq -r '.excluded[] | "  ! excluded \(.repo|split("/")|last): \(.reason)"' < "$TMP/out.json"
  jq -r '.company_totals | "  company-wide in this window: \(.hours)h logged, \(.billable_hours)h billable"' < "$TMP/out.json"
} >&2
