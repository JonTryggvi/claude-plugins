#!/usr/bin/env bash
#
# logging-gap.sh — compare hours LOGGED in ActiveCollab against hours MEASURED
# from the git log, over the same window, for a set of repo/project pairs.
#
#   logging-gap.sh --from 2026-06-01 --to 2026-08-21 --pairs pairs.tsv \
#                  --user 6 --author jontryggvi@avista.is --author 'Jón Tryggvi'
#
#   logging-gap.sh --from … --to … --pairs pairs.tsv --team    # whole team, both sides
#
# pairs.tsv — one pair per line, tab-separated, `#` comments and blanks ignored.
# The first field may be a COMMA-SEPARATED clone group; every path is read and
# commits are deduplicated by SHA across them:
#
#   /Users/me/dev/regluvordur                                        412
#   /Users/me/dev/idnu,/Users/me/dev/flywheel/idnu/…/myaccount       388
#
# Emits JSON on stdout, a table on stderr. Read-only.
#
# BOTH SIDES MUST DESCRIBE THE SAME PERSON
#
# This is the one thing that made an earlier version of this script produce
# confidently wrong answers, so it is now enforced rather than documented.
#
# The logged side comes from ActiveCollab and the measured side from git. If you
# filter one to a person and leave the other wide open, the delta is not a gap —
# it is the difference between two different populations. Reading one author's
# commits against a whole team's timesheet reports colleagues' logged hours as
# though that one person had logged them; reading a team's commits against one
# person's timesheet manufactures a huge fake shortfall. On a solo project both
# mistakes hide, which is what makes them survive.
#
# So: pass --user (ActiveCollab user id) together with at least one --author
# (git identity), or pass --team to compare everybody against everybody
# deliberately. Anything else exits with an error rather than a number.
#
# People commit under several identities — work email, personal email, bare
# username, a GitHub noreply address. Pass every one you know of; --author is
# repeatable and the identities OR together. Missing one silently moves those
# commits out of the measured side and into nobody's.
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

FROM=""; TO=""; PAIRS=""; QUIET=0; USER_ID=""; TEAM=0; ALLOW_BACKDATED=0
AUTHORS=()
if [ -n "${AUTHOR:-}" ]; then
  IFS=',' read -r -a _a <<< "$AUTHOR"
  for x in "${_a[@]}"; do x="${x#"${x%%[![:space:]]*}"}"; x="${x%"${x##*[![:space:]]}"}"
    [ -n "$x" ] && AUTHORS+=("$x"); done
fi

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SITTINGS="${GIT_SITTINGS:-$HERE/../../activecollab-suggest-time/scripts/git-sittings.sh}"
LOGGED="${TIME_LOGGED:-$HERE/time-logged.sh}"

usage() {
  cat >&2 <<'EOT'
usage: logging-gap.sh --from YYYY-MM-DD --to YYYY-MM-DD --pairs FILE
                      ( --user AC_USER_ID --author GIT_IDENTITY [--author …] | --team )
                      [--allow-backdated] [--quiet]

  --user   ActiveCollab user id — filters the LOGGED side to one person
  --author git name/email substring — filters the MEASURED side; repeatable,
           because people commit under several identities
  --team   compare the whole team on BOTH sides (no filtering anywhere)

Both sides must describe the same population or the delta is meaningless, so
--user and --author are required together unless --team is given.
EOT
  exit 64
}

while [ $# -gt 0 ]; do
  case "$1" in
    --from)   FROM="${2:-}"; shift 2 ;;
    --to)     TO="${2:-}"; shift 2 ;;
    --pairs)  PAIRS="${2:-}"; shift 2 ;;
    --user)   USER_ID="${2:-}"; shift 2 ;;
    --author) AUTHORS+=("${2:?--author needs a value}"); shift 2 ;;
    --author=*) AUTHORS+=("${1#*=}"); shift ;;
    --team)   TEAM=1; shift ;;
    --allow-backdated) ALLOW_BACKDATED=1; shift ;;
    --quiet)  QUIET=1; shift ;;
    -h|--help) usage ;;
    *) echo "logging-gap.sh: unknown argument '$1'" >&2; usage ;;
  esac
done

[ -n "$FROM" ] && [ -n "$TO" ] && [ -n "$PAIRS" ] || usage

# --- the guard that stops the two-populations bug ----------------------------
if [ "$TEAM" = "1" ]; then
  if [ -n "$USER_ID" ] || [ ${#AUTHORS[@]} -gt 0 ]; then
    echo "logging-gap.sh: --team means no filtering on either side — drop --user/--author, or drop --team." >&2
    exit 64
  fi
else
  if [ -z "$USER_ID" ] && [ ${#AUTHORS[@]} -eq 0 ]; then
    echo "logging-gap.sh: refusing to run unfiltered by accident." >&2
    echo "  Pass --user <ac-id> AND --author <git-identity> to compare one person," >&2
    echo "  or --team to deliberately compare the whole team on both sides." >&2
    exit 64
  fi
  if [ -z "$USER_ID" ]; then
    echo "logging-gap.sh: --author was given but --user was not." >&2
    echo "  The measured side would be one person's commits and the logged side the whole" >&2
    echo "  team's timesheet, so the delta would report colleagues' hours as theirs." >&2
    echo "  Add --user <activecollab-user-id>, or use --team." >&2
    exit 64
  fi
  if [ ${#AUTHORS[@]} -eq 0 ]; then
    echo "logging-gap.sh: --user was given but no --author." >&2
    echo "  The logged side would be one person and the measured side every committer in" >&2
    echo "  the repo, so any colleague's commits become that person's missing hours." >&2
    echo "  Add --author <name-or-email> (repeatable — pass every identity they use)," >&2
    echo "  or use --team." >&2
    exit 64
  fi
fi

[ -f "$PAIRS" ] || { echo "logging-gap.sh: no such pairs file: $PAIRS" >&2; exit 66; }
[ -f "$SITTINGS" ] || { echo "logging-gap.sh: git-sittings.sh not found at $SITTINGS (set GIT_SITTINGS)" >&2; exit 69; }
[ -f "$LOGGED" ]   || { echo "logging-gap.sh: time-logged.sh not found at $LOGGED (set TIME_LOGGED)" >&2; exit 69; }

# git --until is a timestamp, so bound it at the day AFTER --to to include all of it.
if UNTIL=$(date -u -j -f "%Y-%m-%d" "$TO" -v+1d +%Y-%m-%d 2>/dev/null); then :
elif UNTIL=$(date -u -d "$TO + 1 day" +%Y-%m-%d 2>/dev/null); then :
else echo "logging-gap.sh: could not add a day to '$TO'" >&2; exit 65; fi

TMP=$(mktemp -d) || exit 70
trap 'rm -rf "$TMP"' EXIT

# One ActiveCollab read for the whole window, filtered to the same person the
# git side is filtered to. `--user` here is applied CLIENT-SIDE by
# time-logged.sh, because /time-records silently ignores user_id.
logargs=(--from "$FROM" --to "$TO" --quiet)
[ -n "$USER_ID" ] && logargs+=(--user "$USER_ID")
bash "$LOGGED" "${logargs[@]}" > "$TMP/logged.json" || {
  echo "logging-gap.sh: the ActiveCollab read failed — see above" >&2; exit 65; }

sitargs=()
for a in "${AUTHORS[@]:-}"; do [ -n "$a" ] && sitargs+=(--author "$a"); done
[ "$ALLOW_BACKDATED" = "0" ] && sitargs+=(--author-date-floor "$FROM")

: > "$TMP/rows.ndjson"
while IFS=$'\t' read -r repofield project rest || [ -n "${repofield:-}" ]; do
  case "${repofield:-}" in ''|'#'*) continue ;; esac
  [ -n "${project:-}" ] || { echo "logging-gap.sh: skipping '$repofield' — no project id on that line" >&2; continue; }

  # A clone group: one project, several paths holding the same commits.
  IFS=',' read -r -a group <<< "$repofield"
  repoargs=(); missing=""
  for p in "${group[@]}"; do
    p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"
    [ -n "$p" ] || continue
    if git -C "$p" rev-parse --git-dir >/dev/null 2>&1; then repoargs+=(--repo "$p")
    else missing="${missing:+$missing, }$p"; fi
  done

  if [ ${#repoargs[@]} -eq 0 ]; then
    jq -n --arg r "$repofield" --arg p "$project" --arg m "$missing" \
      '{repo:$r, project_id:($p|tonumber), error:("no readable git repository: " + $m)}' >> "$TMP/rows.ndjson"
    continue
  fi

  bash "$SITTINGS" "${repoargs[@]}" "${sitargs[@]}" "--since=$FROM" "--until=$UNTIL" \
    > "$TMP/s.json" 2>/dev/null \
    || echo '{"total_hours":0,"signal_quality":"none","unique_commits":0,"warnings":["git-sittings failed"]}' > "$TMP/s.json"

  jq -n --slurpfile s "$TMP/s.json" --slurpfile l "$TMP/logged.json" \
        --arg r "$repofield" --arg p "$project" --arg m "$missing" '
    ($s[0]) as $g | ($l[0]) as $lg | ($p|tonumber) as $pid
    | ([$lg.by_project[] | select(.project_id == $pid)] | first) as $proj
    | ($g.total_hours // 0) as $measured
    | ($proj.hours // 0) as $logged
    | {
        repo: $r,
        repos_read: [($g.repos // [])[] | select(.rows > 0) | .label],
        project_id: $pid,
        project_name: ($proj.project_name // null),
        measured_hours: $measured,
        measured_floor_only_hours: ($g.single_commit_hours // 0),
        logged_hours: $logged,
        delta_hours: (((($logged - $measured)*100)|round)/100),
        ratio: (if $measured > 0 then (((($logged/$measured)*100)|round)/100) else null end),
        commits: ($g.unique_commits // $g.commit_count // 0),
        commit_rows: ($g.commit_rows // 0),
        duplicate_rows: ($g.duplicate_rows // 0),
        excluded_backdated: ($g.excluded_backdated // 0),
        signal_quality: ($g.signal_quality // "none"),
        uncommitted_files: ($g.uncommitted_files // 0),
        unreadable_paths: (if $m == "" then [] else ($m | split(", ")) end),
        counted_in_headline: (($g.signal_quality // "none") as $q | $q == "usable" or $q == "weak")
      }' >> "$TMP/rows.ndjson"
done < "$PAIRS"

jq -s --slurpfile lg "$TMP/logged.json" --arg from "$FROM" --arg to "$TO" \
      --arg user "$USER_ID" --argjson team "$TEAM" \
      --argjson authors "$(printf '%s\n' "${AUTHORS[@]:-}" | jq -R . | jq -sc 'map(select(. != ""))')" '
  . as $rows
  | ([$rows[] | select(.error == null and .counted_in_headline)]) as $ok
  | ($ok | map(.measured_hours) | add // 0) as $m
  | ($ok | map(.logged_hours)   | add // 0) as $l
  | {
      window: {from: $from, to: $to},
      scope: {
        activecollab_user_id: (if $user == "" then null else ($user|tonumber) end),
        git_author_filters: $authors,
        team_wide: ($team == 1),
        note: (if $team == 1
               then "both sides unfiltered — every committer against the whole team timesheet"
               else "logged side filtered to ActiveCollab user \($user); measured side filtered to git identities \($authors|join(", ")). Both sides describe the same person, which is the only way the delta means anything." end)
      },
      basis: "logged = ActiveCollab time records in the window; measured = git commit sittings (45min gap, +15min lead-in, 0.25h rounding), SHA-deduplicated across each clone group, over the same window. Ratio is logging discipline on commit-producing work only — never a productivity measure.",
      company_totals: $lg[0].totals,
      headline: {
        pairs_counted: ($ok|length),
        pairs_excluded: (($rows|length) - ($ok|length)),
        measured_hours: ((($m*100)|round)/100),
        logged_hours:   ((($l*100)|round)/100),
        delta_hours:    (((($l-$m)*100)|round)/100),
        ratio: (if $m > 0 then (((($l/$m)*100)|round)/100) else null end),
        floor_only_hours: (($ok | map(.measured_floor_only_hours) | add // 0 | .*100 | round) / 100),
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
  jq -r '"  scope: \(.scope.note)"' < "$TMP/out.json"
  printf '  %-34s %9s %9s %8s %7s  %s\n' repo measured logged delta ratio signal
  jq -r '.pairs[] | select(.error == null)
         | "  \(.repo|split(",")|first|split("/")|last|.[0:34])\t\(.measured_hours)\t\(.logged_hours)\t\(.delta_hours)\t\(.ratio // "-")\t\(.signal_quality)"' < "$TMP/out.json" \
    | awk -F'\t' '{printf "  %-34s %9s %9s %8s %7s  %s\n", $1,$2,$3,$4,$5,$6}'
  jq -r '"  ---\n  counted \(.headline.pairs_counted) pair(s): measured \(.headline.measured_hours)h vs logged \(.headline.logged_hours)h  (ratio \(.headline.ratio // "-"))\n  \(.headline.reading)"' < "$TMP/out.json"
  jq -r 'if .headline.floor_only_hours > 0 then "  ! \(.headline.floor_only_hours)h of the measured side is single-commit sittings — a floor (lead-in only), not a measurement" else empty end' < "$TMP/out.json"
  jq -r '.pairs[] | select(.duplicate_rows > 0) | "  i \(.repo|split(",")|first|split("/")|last): \(.commit_rows) rows -> \(.commits) unique after SHA dedupe across the clone group"' < "$TMP/out.json"
  jq -r '.window.from as $f | .pairs[] | select(.excluded_backdated > 0) | "  i \(.repo|split(",")|first|split("/")|last): \(.excluded_backdated) commit(s) authored before \($f) excluded — cherry-picked older work belongs to the previous period"' < "$TMP/out.json"
  jq -r '.pairs[] | select((.unreadable_paths|length) > 0) | "  ! \(.project_id): unreadable path(s) \(.unreadable_paths|join(", ")) — that part of the clone group was not measured"' < "$TMP/out.json"
  jq -r '.excluded[] | "  ! excluded \(.repo|split(",")|first|split("/")|last): \(.reason)"' < "$TMP/out.json"
  jq -r '.company_totals | "  in-scope totals for this window: \(.hours)h logged, \(.billable_hours)h billable"' < "$TMP/out.json"
} >&2
