#!/usr/bin/env bash
#
# git-sittings.sh — group commits into working sittings and measure time.
#
#   git-sittings.sh                                   # last 14 days, current repo
#   git-sittings.sh --since=3.days
#   git-sittings.sh main..HEAD                        # a feature branch
#   AUTHOR=jon@avista.is git-sittings.sh              # one identity
#   git-sittings.sh --author jon@avista.is --author 'Jón Tryggvi' --author jontryggvi
#   git-sittings.sh --repo ~/dev/a --repo ~/dev/b --since=30.days
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
# MANY IDENTITIES, MANY CLONES
#
# Two facts about real repos make a single-author single-repo measurement wrong
# in ways that do not announce themselves:
#
#   1. People commit under several identities. A work email, a personal email,
#      a bare username, a GitHub noreply address — four is normal. A single
#      --author substring silently measures a fraction of someone's work and
#      reports the rest as somebody else's. Pass every identity you know of;
#      they OR together.
#
#   2. Shared code is cloned into every project that uses it. A plugin repo
#      lives once in its own checkout and again inside each Flywheel site, so
#      the same commit is readable from several paths. Measuring each clone
#      and adding the totals counts one afternoon of work three times.
#      --repo may be repeated, and commits are deduplicated by full SHA
#      across every path given, so a clone group measures as the UNION of its
#      copies rather than as any one nominated "canonical" repo — which
#      matters because the standalone checkout is often the one that is
#      BEHIND the site clones, not ahead of them.
#
# `commit_rows` vs `unique_commits` in the output is the honest record of how
# much duplication was removed. Report both; a large gap between them means
# whoever assembled the repo list was measuring the same work several times.
#
# COMMITTER DATE vs AUTHOR DATE
#
# git's --since/--until filter COMMITTER date, which is what you want for
# "when was this work done" — a rebase moves it, and a rebase is work. But a
# cherry-pick or a late-landed branch carries an author date from weeks
# earlier, and that work belongs to whichever period it was originally done
# in. --author-date-floor DATE drops commits authored before DATE while still
# grouping sittings on committer time, which keeps last month's work off this
# month's invoice.
#
set -uo pipefail

GAP_MIN="${GAP_MIN:-45}"        # minutes; gap above this starts a new sitting
LEADIN_MIN="${LEADIN_MIN:-15}"  # minutes of investigation credited before each sitting's first commit
ROUND="${ROUND:-0.25}"          # round each sitting to this fraction of an hour
FLOOR=""                        # --author-date-floor YYYY-MM-DD

# AUTHOR stays supported for compatibility, and accepts a comma-separated list.
AUTHORS=()
if [ -n "${AUTHOR:-}" ]; then
  IFS=',' read -r -a _a <<< "$AUTHOR"
  for x in "${_a[@]}"; do x="${x#"${x%%[![:space:]]*}"}"; x="${x%"${x##*[![:space:]]}"}"
    [ -n "$x" ] && AUTHORS+=("$x"); done
fi

REPOS=()
GITARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)               REPOS+=("${2:?--repo needs a path}"); shift 2 ;;
    --repo=*)             REPOS+=("${1#*=}"); shift ;;
    --author)             AUTHORS+=("${2:?--author needs a value}"); shift 2 ;;
    --author=*)           AUTHORS+=("${1#*=}"); shift ;;
    --author-date-floor)  FLOOR="${2:?--author-date-floor needs YYYY-MM-DD}"; shift 2 ;;
    --author-date-floor=*) FLOOR="${1#*=}"; shift ;;
    *)                    GITARGS+=("$1"); shift ;;
  esac
done

[ ${#GITARGS[@]} -eq 0 ] && GITARGS=(--since=14.days)

if [ -n "$FLOOR" ]; then
  case "$FLOOR" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
    *) echo "git-sittings.sh: --author-date-floor must be YYYY-MM-DD (got '$FLOOR')" >&2; exit 64 ;;
  esac
  if   FLOOR_TS=$(date -u -j -f "%Y-%m-%d %H:%M:%S" "$FLOOR 00:00:00" +%s 2>/dev/null); then :
  elif FLOOR_TS=$(date -u -d "$FLOOR 00:00:00" +%s 2>/dev/null); then :
  else echo "git-sittings.sh: could not parse '$FLOOR' as a date" >&2; exit 65; fi
else
  FLOOR_TS=0
fi

# Default to the repo we are standing in.
if [ ${#REPOS[@]} -eq 0 ]; then
  git rev-parse --git-dir >/dev/null 2>&1 || {
    echo '{"error":"not a git repository, and no --repo was given"}'; exit 1; }
  REPOS+=("$(git rev-parse --show-toplevel)")
fi

command -v jq >/dev/null 2>&1 || { echo '{"error":"jq is not installed"}' ; exit 69; }

TMP=$(mktemp -d) || exit 70
trap 'rm -rf "$TMP"' EXIT

# Never capture git output in $(...): subjects are full of Icelandic characters
# and the shell runs under LC_CTYPE="C", where command substitution throws
# `character not in range` mid-pipeline. File in, file out.
: > "$TMP/rows.tsv"
: > "$TMP/repos.ndjson"

authorargs=()
for a in "${AUTHORS[@]:-}"; do [ -n "$a" ] && authorargs+=("--author=$a"); done

dirty_total=0
last_commit=0
for repo in "${REPOS[@]}"; do
  if [ ! -d "$repo/.git" ] && ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    jq -n --arg p "$repo" '{path:$p, rows:0, error:"not a git repository"}' >> "$TMP/repos.ndjson"
    continue
  fi
  top=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || top="$repo"
  # Two path components, so two clones of the same project stay distinguishable.
  label=$(printf '%s' "$top" | awk -F/ '{ if (NF>1) printf "%s/%s", $(NF-1), $NF; else printf "%s", $NF }')

  : > "$TMP/one.tsv"
  git -C "$top" log --no-merges --date-order \
      --pretty=format:"%ct%x09%at%x09%H%x09${label}%x09%aE%x09%s" \
      "${authorargs[@]}" "${GITARGS[@]}" > "$TMP/one.tsv" 2>/dev/null
  [ -s "$TMP/one.tsv" ] && printf '\n' >> "$TMP/one.tsv"
  rows=$(awk "END{print NR+0}" < "$TMP/one.tsv")
  cat "$TMP/one.tsv" >> "$TMP/rows.tsv"

  d=$(git -C "$top" status --porcelain 2>/dev/null | awk "END{print NR+0}")
  dirty_total=$(( dirty_total + d ))
  lc=$(git -C "$top" log -1 --pretty=format:%ct "${authorargs[@]}" "${GITARGS[@]}" 2>/dev/null | head -1)
  case "${lc:-}" in ''|*[!0-9]*) lc=0 ;; esac
  [ "$lc" -gt "$last_commit" ] && last_commit="$lc"

  jq -n --arg p "$top" --arg l "$label" --argjson r "${rows:-0}" --argjson d "${d:-0}" \
    '{path:$p, label:$l, rows:$r, uncommitted_files:$d}' >> "$TMP/repos.ndjson"
done

rows_total=$(awk "END{print NR+0}" < "$TMP/rows.tsv")

if [ "${rows_total:-0}" -eq 0 ]; then
  jq -n --slurpfile repos "$TMP/repos.ndjson" \
        --argjson authors "$(printf '%s\n' "${AUTHORS[@]:-}" | jq -R . | jq -sc 'map(select(. != ""))')" \
    '{sittings:[], total_hours:0, multi_commit_hours:0, single_commit_hours:0,
      single_commit_sittings:0, commit_rows:0, unique_commits:0, duplicate_rows:0,
      excluded_backdated:0, repos:$repos, uncommitted_files:0,
      signal_quality:"none", warnings:[],
      note:("no commits matched" + (if ($authors|length)>0 then " for author(s) " + ($authors|join(", ")) else "" end))}'
  exit 0
fi

# Dedupe by full SHA across every clone, keep committer-time order, then group.
sort -n -k1,1 "$TMP/rows.tsv" | grep . > "$TMP/sorted.tsv"

raw_file="$TMP/raw.json"
awk -F'\t' -v gap="$GAP_MIN" -v leadin="$LEADIN_MIN" -v round="$ROUND" -v floor="$FLOOR_TS" '
function jstr(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/\r/, "", s); return s }
function flush(   span, hours, i, rl) {
  if (n == 0) return
  span  = (last - first) / 3600.0
  hours = span + (leadin / 60.0)
  hours = int(hours / round + 0.5) * round
  if (hours < round) hours = round
  idx++
  rl = ""
  for (i in rseen) rl = rl (rl == "" ? "" : ",") "\"" jstr(i) "\""
  printf "%s{\"sitting\":%d,\"start\":%d,\"end\":%d,\"commits\":%d,\"span_hours\":%.4f,\"hours\":%.2f,\"single_commit\":%s,\"repos\":[%s],\"subjects\":[%s]}",
         (idx > 1 ? "," : ""), idx, first, last, n, span, hours, (n == 1 ? "true" : "false"), rl, subs
  total += hours
  if (n == 1) { singles++; single_hours += hours } else { multi_hours += hours }
  delete rseen
}
BEGIN { printf "{\"sittings\":[" }
{
  ct = $1 + 0; at = $2 + 0; sha = $3; repo = $4; subj = $6
  for (i = 7; i <= NF; i++) subj = subj FS $i     # a subject may contain tabs
  if (sha in seen) { dupes++; next }
  seen[sha] = 1
  if (floor > 0 && at < floor) { backdated++; next }
  uniq++
  if (n > 0 && (ct - last) > gap * 60) { flush(); n = 0; subs = "" }
  if (n == 0) first = ct
  last = ct
  n++
  rseen[repo] = 1
  subs = subs (subs == "" ? "" : ",") "\"" jstr(subj) "\""
}
END {
  flush()
  printf "],\"total_hours\":%.2f,\"multi_commit_hours\":%.2f,\"single_commit_hours\":%.2f,\"single_commit_sittings\":%d,\"unique_commits\":%d,\"duplicate_rows\":%d,\"excluded_backdated\":%d}",
         total, multi_hours, single_hours, singles, uniq, dupes, backdated
}' "$TMP/sorted.tsv" > "$raw_file"

jq -n \
  --slurpfile raw "$raw_file" \
  --slurpfile repos "$TMP/repos.ndjson" \
  --argjson rowstotal "${rows_total:-0}" \
  --argjson dirty "${dirty_total:-0}" \
  --argjson last "${last_commit:-0}" \
  --argjson authors "$(printf '%s\n' "${AUTHORS[@]:-}" | jq -R . | jq -sc 'map(select(. != ""))')" \
  --arg gap "$GAP_MIN" --arg leadin "$LEADIN_MIN" --arg round "$ROUND" --arg floor "$FLOOR" \
  '($raw[0]) as $g
   | ($repos | map(select(.rows > 0))) as $live
   | {
     sittings: [$g.sittings[] | . + {
       start_iso: (.start | todate),
       end_iso:   (.end   | todate),
       date:      (.start | todate[:10])
     }],
     total_hours: $g.total_hours,
     multi_commit_hours: $g.multi_commit_hours,
     single_commit_hours: $g.single_commit_hours,
     single_commit_sittings: $g.single_commit_sittings,
     commit_rows: $rowstotal,
     unique_commits: $g.unique_commits,
     duplicate_rows: $g.duplicate_rows,
     excluded_backdated: $g.excluded_backdated,
     commit_count: $g.unique_commits,
     repos: $repos,
     uncommitted_files: $dirty,
     last_commit_iso: (if $last > 0 then ($last | todate) else null end),
     basis: {
       method: "commit-to-commit spans grouped into sittings, SHA-deduplicated across every repo given",
       gap_minutes: ($gap | tonumber),
       leadin_minutes_per_sitting: ($leadin | tonumber),
       rounding_hours: ($round | tonumber),
       author_filters: $authors,
       author_date_floor: (if $floor == "" then null else $floor end),
       repos_read: ($repos | length),
       window_basis: "committer date (git --since/--until); author date only used by --author-date-floor"
     },
     warnings: (
       []
       + (if ($authors|length) == 0 and ($live|length) > 0
          then ["no author filter — this measures EVERY committer in these repos, not one person. On any shared repo that credits colleagues hours to whoever asked."] else [] end)
       + (if $g.duplicate_rows > 0
          then ["read \($rowstotal) commit rows across \($repos|length) repo(s), \($g.unique_commits) unique after SHA dedupe — \($g.duplicate_rows) row(s) were the same commits seen in more than one clone. Summing per-clone totals instead would have multiplied this work."] else [] end)
       + (if ($live | map(.rows) | unique | length) > 1
          then ["clone group is uneven: " + ($live | map("\(.label)=\(.rows)") | join(", ")) + " rows. The lower counts are copies that are BEHIND, not extra work — this is why the union of the group is measured rather than a nominated canonical repo."] else [] end)
       + (if $g.excluded_backdated > 0
          then ["\($g.excluded_backdated) commit(s) landed in this window but were authored before \($floor) — cherry-picked or late-landed older work, excluded so it stays on the period it was actually done in"] else [] end)
       + (if $dirty > 0 then ["\($dirty) uncommitted file(s) — tail work is not measured here and must be added by hand"] else [] end)
       + (if $g.unique_commits == 1 then ["only one commit matched — commit spans cannot be measured, the figure is the lead-in allowance alone"] else [] end)
       + (if $g.single_commit_sittings > 0
          then ["\($g.single_commit_sittings) of \($g.sittings|length) sitting(s) hold a single commit, credited \($g.single_commit_hours)h in total — that is the lead-in allowance alone and is a FLOOR, not a measurement. Report it separately and let the user raise it; never present it as measured time."] else [] end)
       + (if ([$g.sittings[] | select(.span_hours < 0.5 and .commits > 1)] | length) > 0 then ["\([$g.sittings[] | select(.span_hours < 0.5 and .commits > 1)] | length) sitting(s) span under 30 minutes of commit time — commits clustered at the end of a long session look like this. If the real work took longer, the commit log is a POOR SIGNAL and you should measure from something else rather than trust this figure"] else [] end)
     ),
     signal_quality: (
       if   ($g.unique_commits == 0) then "none"
       elif ($g.unique_commits == 1) then "poor"
       elif ([$g.sittings[] | select(.span_hours < 0.5)] | length) == ($g.sittings | length) then "poor"
       elif ($g.total_hours < 1) then "weak"
       else "usable" end
     )
   }'
