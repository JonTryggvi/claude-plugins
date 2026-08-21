#!/usr/bin/env bash
#
# project-map.sh — persist and query the repo -> ActiveCollab project mapping.
#
#   project-map.sh scan ~/dev ~/flywheel      # discover clone groups, show what is unmapped
#   project-map.sh scan --since 2026-07-21 ~/dev   # ...ranked by commits in the window
#   project-map.sh list                       # what is mapped
#   project-map.sh resolve <repo-path>        # which project does this repo belong to
#   project-map.sh tasks <project-id>         # OPEN + ARCHIVED tasks, one list
#   project-map.sh projects [pattern]         # every project (GETALL — all 213, not the first 100)
#   project-map.sh put <json-file>            # add/replace one entry (validated)
#   project-map.sh decide --slug S --date D --action never_propose --reason R
#                                             # record a judgement call, structured
#   project-map.sh validate                   # do the stored ids and paths still exist
#
# The map lives at ~/.claude/activecollab-project-map.json (override with
# AC_PROJECT_MAP). It is a cache of decisions a human made, not a source of
# truth about ActiveCollab — `validate` is what keeps it honest.
#
# WHY THIS EXISTS
#
# Resolving "which ActiveCollab project do these commits belong to" costs a
# handful of API calls, some judgement, and a question to the user. Doing it
# again every month is the expensive part of a reconciliation, and doing it
# from memory is how hours land on the wrong client. So it gets written down
# once, including the answers that are "there is no project" — a personal
# project asked about a second time is a small tax on every future run.
#
# ENTRY SHAPE
#
#   {
#     "slug": "myaccount",                  # short handle, unique
#     "repos": ["/abs/path", "/abs/path2"], # a clone group: same commits, several paths
#     "project_id": 388,
#     "project_name": "Idnu",
#     "default_task_id": 12088,             # optional; where hours usually land
#     "default_task_name": "ACF Fields...",
#     "default_job_type_id": 1,
#     "default_job_type": "Programming",
#     "budget_type": "pay_as_you_go",       # from the API; not_billable coerces billable_status to 0
#     "private": false,                     # true = deliberately has NO project
#     "also_logged_under": [487],            # other projects whose records can cover this one's dates
#     "decisions": [                         # judgement calls that must survive to next month
#       {"date":"2026-08-12","action":"never_propose",
#        "reason":"already inside record 16112 of 2026-08-13, which itemises it",
#        "decided":"2026-08-21"}
#     ],
#     "note": "why, if it needs saying"
#   }
#
# DECISIONS ARE WHAT MAKES A RECONCILIATION IDEMPOTENT
#
# A month-end run makes judgement calls: this date is already covered by a
# record that over-covers its own date; this date is deliberately logged short
# and was reviewed. Left in prose, those decisions only work if the next agent
# reads the note carefully and agrees with itself. Left nowhere, every month
# re-litigates last month from memory — and re-proposes work somebody already
# decided against.
#
#   never_propose  this date is settled; drop or flag any proposal on it
#   capped_at      this date is deliberately logged short of measured, reviewed
#                  and left that way (record `hours` = what was logged)
#
# Every decision carries a `reason` and a `decided` date, because a decision
# whose reasoning is lost is indistinguishable from a mistake and will be
# reversed by the next person who looks at the numbers.
#
# A private entry needs `slug`, `repos`, `private: true` and a `note`. It must
# NOT carry a project_id — the whole point is recording that there isn't one.
#
set -uo pipefail

AC="${AC_BIN:-$HOME/.claude/bin/ac}"
MAP="${AC_PROJECT_MAP:-$HOME/.claude/activecollab-project-map.json}"

need_ac() {
  [ -x "$AC" ] || { echo "project-map.sh: no ac client at $AC — run the activecollab-setup skill" >&2; exit 69; }
}
command -v jq >/dev/null 2>&1 || { echo "project-map.sh: jq is not installed" >&2; exit 69; }

ensure_map() {
  [ -f "$MAP" ] && return 0
  mkdir -p "$(dirname "$MAP")"
  jq -n '{version:1, updated:null, entries:[]}' > "$MAP"
  chmod 600 "$MAP"
  echo "project-map.sh: created $MAP" >&2
}

today() { date +%Y-%m-%d; }

usage() { sed -n '3,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 64; }

CMD="${1:-}"; shift 2>/dev/null || true

case "$CMD" in

# ---------------------------------------------------------------- scan -------
# Group every git repo under the given roots by remote origin URL. Repos sharing
# an origin are the same code in several places — a clone group — and must be
# measured as one unit, deduplicated by SHA, or the same work counts many times.
scan)
  SINCE=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --since) SINCE="${2:?--since needs YYYY-MM-DD}"; shift 2 ;;
      --since=*) SINCE="${1#*=}"; shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || { echo "project-map.sh scan: give one or more directories to search" >&2; exit 64; }
  ensure_map
  TMP=$(mktemp -d) || exit 70; trap 'rm -rf "$TMP"' EXIT
  : > "$TMP/repos.tsv"
  : > "$TMP/act.tsv"
  for root in "$@"; do
    [ -d "$root" ] || { echo "project-map.sh: no such directory: $root" >&2; continue; }
    find "$root" -maxdepth 8 -type d -name .git 2>/dev/null | sed 's|/\.git$||' | while read -r r; do
      o=$(git -C "$r" config --get remote.origin.url 2>/dev/null)
      [ -n "$o" ] || o="(no-origin):$r"
      printf '%s\t%s\n' "$o" "$r" >> "$TMP/repos.tsv"
    done
  done
  sort -u "$TMP/repos.tsv" -o "$TMP/repos.tsv"

  # An unmapped group is silently absent from every reconciliation, so this list
  # is where real misses hide — and a flat wall of 42 paths trains people to skim
  # it. With --since, each group is reported with its commit count and last
  # commit date in that window, active ones first, so "3 of 42 have commits since
  # 2026-07-21" replaces "42 alphabetical paths". SHAs are unioned across a
  # group's clones, because the same commit readable from three checkouts is one
  # commit, not three.
  if [ -n "$SINCE" ]; then
    while IFS=$'\t' read -r origin repo; do
      [ -n "${repo:-}" ] || continue
      git -C "$repo" log --no-merges "--since=$SINCE" --pretty=format:"%H%x09%ct" 2>/dev/null \
        | awk -F'\t' -v o="$origin" 'NF>=2 { print o "\t" $1 "\t" $2 }' >> "$TMP/act.tsv"
    done < "$TMP/repos.tsv"
  fi

  jq -R -s --slurpfile map "$MAP" \
     --arg since "$SINCE" \
     --rawfile act "$TMP/act.tsv" '
    [ split("\n")[] | select(length>0) | split("\t") | {origin:.[0], repo:.[1]} ]
    | group_by(.origin)
    | map({
        origin: .[0].origin,
        clones: (map(.repo) | sort),
        clone_count: length
      })
    | . as $groups
    | ($map[0].entries // []) as $entries
    | ( $act | split("\n") | map(select(. != "") | split("\t"))
        | group_by(.[0])
        | map({ key: .[0][0],
                value: ( (map(.[1]) | unique | length) as $n
                         | { commits: $n,
                             last_commit: ((map(.[2] | tonumber) | max) // null) } ) })
        | from_entries ) as $activity
    | {
        groups: [ $groups[] | . as $g
          | ([$entries[] | select((.repos // []) | any(. as $r | $g.clones | index($r)))] | first) as $hit
          | $g + {
              mapped: ($hit != null),
              slug: ($hit.slug // null),
              project_id: ($hit.project_id // null),
              private: ($hit.private // false),
              paths_not_in_map: (if $hit == null then $g.clones
                                 else [$g.clones[] | select(($hit.repos // []) | index(.) | not)] end),
              commits_since: (if $since == "" then null else (($activity[$g.origin].commits) // 0) end),
              last_commit: (if $since == "" then null
                            else (($activity[$g.origin].last_commit) | if . then (. | todate[:10]) else null end) end),
              active: (if $since == "" then null else ((($activity[$g.origin].commits) // 0) > 0) end)
            } ],
        window: (if $since == "" then null else {since: $since} end),
        summary: {
          groups_found: ($groups | length),
          clone_groups: ([$groups[] | select(.clone_count > 1)] | length),
          repos_total: ([$groups[] | .clone_count] | add // 0)
        }
      }
    | .summary += {
        mapped: ([.groups[] | select(.mapped and (.private|not))] | length),
        private: ([.groups[] | select(.private)] | length),
        unmapped: ([.groups[] | select(.mapped|not)] | length),
        unmapped_active: (if $since == "" then null
                          else ([.groups[] | select((.mapped|not) and .active)] | length) end),
        unmapped_quiet: (if $since == "" then null
                         else ([.groups[] | select((.mapped|not) and (.active|not))] | length) end)
      }
    | .groups = (.groups | sort_by([(if .active == true then 0 else 1 end), (-(.commits_since // 0)), .origin]))' < "$TMP/repos.tsv" > "$TMP/out.json"

  cat "$TMP/out.json"
  {
    jq -r '"scan: \(.summary.repos_total) repo(s) in \(.summary.groups_found) group(s) — \(.summary.clone_groups) of them cloned more than once"' < "$TMP/out.json"
    jq -r '"  mapped \(.summary.mapped)   private \(.summary.private)   UNMAPPED \(.summary.unmapped)"' < "$TMP/out.json"
    jq -r 'if .window then "  window: commits since \(.window.since) — \(.summary.unmapped_active) of \(.summary.unmapped) unmapped group(s) have commits in it" else empty end' < "$TMP/out.json"
    echo "  --- unmapped (each needs a project id, or an explicit private:true) ---"
    jq -r '.groups[] | select((.mapped|not) and (.active == true))
           | "  ACTIVE  \(.commits_since) commit(s), last \(.last_commit)   \(.clones|length)x  \(.clones[0])"
             + (if (.clones|length)>1 then "\n" + ([.clones[1:][] | "              + " + .] | join("\n")) else "" end)' < "$TMP/out.json"
    jq -r 'if .window and (.summary.unmapped_quiet > 0) then "  --- \(.summary.unmapped_quiet) unmapped group(s) with NO commits since \(.window.since) (listed, not ranked — nothing to reconcile there yet) ---" else empty end' < "$TMP/out.json"
    jq -r '.groups[] | select((.mapped|not) and (.active != true))
           | "  quiet   \(.clones|length)x  \(.clones[0])"
             + (if (.clones|length)>1 then "\n" + ([.clones[1:][] | "              + " + .] | join("\n")) else "" end)' < "$TMP/out.json"
    jq -r '.groups[] | select(.mapped and ((.paths_not_in_map|length) > 0)) | "  ! \(.slug): clone group has path(s) missing from the map — \(.paths_not_in_map|join(", "))"' < "$TMP/out.json"
  } >&2
  ;;

# ---------------------------------------------------------------- list -------
list)
  ensure_map
  cat "$MAP"
  {
    jq -r '"map: \(.entries|length) entr(y/ies), updated \(.updated // "never")"' < "$MAP"
    jq -r '.entries[] | select(.private|not) | "  \(.slug)\tproject \(.project_id) \(.project_name // "")\ttask \(.default_task_id // "-")\tjob \(.default_job_type // "-")\t\(.budget_type // "?")\t\(.repos|length) path(s)\t\((.decisions // [])|length) decision(s)\t\(if ((.also_logged_under // [])|length) > 0 then "also: " + ((.also_logged_under|map(tostring))|join(",")) else "" end)"' < "$MAP"
    jq -r '.entries[] | .slug as $s | (.decisions // [])[] | "    decision \($s) \(.date) \(.action)\(if .hours then " @\(.hours)h" else "" end) — \(.reason) [decided \(.decided)]"' < "$MAP"
    jq -r '.entries[] | select(.private) | "  \(.slug)\tPRIVATE — no ActiveCollab project (\(.note // "no reason recorded"))"' < "$MAP"
  } >&2
  ;;

# -------------------------------------------------------------- resolve -----
resolve)
  ensure_map
  target="${1:?usage: project-map.sh resolve <repo-path>}"
  top=$(git -C "$target" rev-parse --show-toplevel 2>/dev/null) || top="$target"
  jq --arg p "$top" '
    (.entries // []) as $e
    | ([$e[] | select((.repos // []) | index($p))] | first) as $hit
    | if $hit == null then {found:false, path:$p,
        hint:"not in the map — run `project-map.sh scan` on its parent directory, then decide a project or mark it private"}
      else {found:true, path:$p, entry:$hit} end' < "$MAP"
  ;;

# ---------------------------------------------------------------- tasks -----
# Open AND archived, merged. The open list gives completed tasks as bare ids in
# .completed_task_ids with no names, so a project can show 2 open tasks while
# holding 27 finished ones you cannot see. Completed tasks still accept time
# records, and for work that is already done the honest match is usually one of
# them — so proposing a match from the open list alone hides the right answer.
tasks)
  need_ac
  pid="${1:?usage: project-map.sh tasks <project-id>}"
  TMP=$(mktemp -d) || exit 70; trap 'rm -rf "$TMP"' EXIT
  "$AC" GET "/projects/$pid/tasks"         > "$TMP/open.json" 2>/dev/null || echo '{}' > "$TMP/open.json"
  "$AC" GET "/projects/$pid/tasks/archive" > "$TMP/arch.json" 2>/dev/null || echo '[]' > "$TMP/arch.json"
  jq -e 'type=="array"' < "$TMP/arch.json" >/dev/null 2>&1 || echo '[]' > "$TMP/arch.json"

  jq -n --slurpfile o "$TMP/open.json" --slurpfile a "$TMP/arch.json" --arg pid "$pid" '
    ($o[0] // {}) as $open | ($a[0] // []) as $arch
    | {
        project_id: ($pid|tonumber),
        task_lists: [($open.task_lists // [])[] | {id, name}],
        open: [($open.tasks // [])[] | {id, task_number, name, assignee_id, is_completed:false, source:"open"}],
        archived: [$arch[] | {id, task_number, name, assignee_id, is_completed:(.is_completed // true), source:"archive"}],
        counts: {
          open: (($open.tasks // []) | length),
          completed_ids_in_open_list: (($open.completed_task_ids // []) | length),
          archived_with_names: ($arch | length)
        }
      }
    | .all = (.open + .archived | sort_by(-.id))
    | .warning = (if .counts.completed_ids_in_open_list > .counts.open
        then "this project has more finished tasks (\(.counts.completed_ids_in_open_list)) than open ones (\(.counts.open)) — matching against the open list alone would miss most of it"
        else null end)' > "$TMP/out.json"

  cat "$TMP/out.json"
  {
    jq -r '"project \(.project_id): \(.counts.open) open, \(.counts.archived_with_names) archived"' < "$TMP/out.json"
    jq -r '.all[] | "  \(.id)\t#\(.task_number)\t[\(.source)]\t\(.name)"' < "$TMP/out.json"
    jq -r 'if .warning then "  ! \(.warning)" else empty end' < "$TMP/out.json"
  } >&2
  ;;

# ------------------------------------------------------------- projects -----
projects)
  need_ac
  pat="${1:-}"
  TMP=$(mktemp -d) || exit 70; trap 'rm -rf "$TMP"' EXIT
  # GETALL, not GET: /projects caps at 100 per page and this instance has 213.
  # A plain GET hides half the list and makes real projects look missing.
  "$AC" GETALL /projects > "$TMP/p.json" 2>/dev/null || { echo "project-map.sh: could not read /projects" >&2; exit 65; }
  jq -e 'type=="array"' < "$TMP/p.json" >/dev/null 2>&1 || { echo "project-map.sh: /projects did not return an array" >&2; exit 65; }
  jq --arg pat "$pat" '
    map({id, name, budget_type, is_tracking_enabled, company_id, is_completed})
    | (if $pat == "" then . else map(select(.name | test($pat; "i"))) end)
    | sort_by(.name)' < "$TMP/p.json" > "$TMP/out.json"
  cat "$TMP/out.json"
  {
    jq -r --slurpfile all "$TMP/p.json" '"projects: \(length) shown of \($all[0]|length) total (GETALL — a plain GET would have returned 100)"' < "$TMP/out.json"
    jq -r '.[] | "  \(.id)\t\(.name)\t\(.budget_type)"' < "$TMP/out.json"
    jq -r '[.[] | select(.budget_type=="not_billable")] | if length>0 then "  ! not_billable (these coerce billable_status to 0): " + (map(.id|tostring)|join(", ")) else empty end' < "$TMP/out.json"
  } >&2
  ;;

# ------------------------------------------------------------------ put -----
put)
  ensure_map
  f="${1:?usage: project-map.sh put <entry.json>}"
  [ -f "$f" ] || { echo "project-map.sh: no such file: $f" >&2; exit 66; }
  jq -e '.' < "$f" >/dev/null 2>&1 || { echo "project-map.sh: $f is not valid JSON" >&2; exit 65; }

  err=$(jq -r '
    [ (if (.slug // "") == "" then "slug is required" else empty end),
      (if ((.repos // []) | length) == 0 then "repos must hold at least one path" else empty end),
      (if (.private // false) then
         ((if .project_id then "a private entry must not carry a project_id — private means there is no project" else empty end),
          (if (.note // "") == "" then "a private entry needs a note saying why, so nobody re-litigates it next month" else empty end))
       else
         (if (.project_id | type) != "number" then "project_id is required (or set private:true)" else empty end)
       end),
      (if (.also_logged_under // []) | type != "array" then "also_logged_under must be an array of project ids"
       elif ((.also_logged_under // []) | map(select(type != "number")) | length) > 0 then "also_logged_under must hold numbers, not strings"
       else empty end),
      (if (.decisions // []) | type != "array" then "decisions must be an array" else empty end),
      ((.decisions // [])[] |
        (if (.date // "") | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") | not
           then "each decision needs a date as YYYY-MM-DD" else empty end),
        (if ((.action // "") | IN("never_propose","capped_at")) | not
           then "decision action must be never_propose or capped_at (got \"\(.action // "")\")" else empty end),
        (if (.reason // "") == ""
           then "decision for \(.date // "?") needs a reason — a decision whose reasoning is lost gets reversed next month" else empty end),
        (if (.decided // "") | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") | not
           then "decision for \(.date // "?") needs a `decided` date, so a stale call can be spotted" else empty end),
        (if (.action == "capped_at") and ((.hours // null) | type != "number")
           then "a capped_at decision for \(.date // "?") needs `hours` — the figure that was deliberately logged" else empty end)
      ) ] | join("; ")' < "$f")
  [ -z "$err" ] || { echo "project-map.sh: $err" >&2; exit 65; }

  TMP=$(mktemp) || exit 70
  jq --slurpfile new "$f" --arg d "$(today)" '
    ($new[0]) as $n
    | .entries = ([ (.entries // [])[] | select(.slug != $n.slug) ] + [$n] | sort_by(.slug))
    | .updated = $d' < "$MAP" > "$TMP" && cat "$TMP" > "$MAP" && rm -f "$TMP"
  chmod 600 "$MAP"
  jq -r --arg s "$(jq -r .slug < "$f")" '"stored: \($s) — map now holds \(.entries|length) entr(y/ies)"' < "$MAP" >&2
  ;;

# ---------------------------------------------------------------- decide -----
# Record a judgement call so next month does not re-litigate it. This is the
# ergonomic front door to the `decisions` array — hand-editing JSON to add one
# is how decisions end up unrecorded.
decide)
  ensure_map
  D_SLUG=""; D_DATE=""; D_ACTION=""; D_REASON=""; D_HOURS=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --slug)   D_SLUG="${2:-}"; shift 2 ;;
      --date)   D_DATE="${2:-}"; shift 2 ;;
      --action) D_ACTION="${2:-}"; shift 2 ;;
      --reason) D_REASON="${2:-}"; shift 2 ;;
      --hours)  D_HOURS="${2:-}"; shift 2 ;;
      *) echo "project-map.sh decide: unknown argument '$1'" >&2; exit 64 ;;
    esac
  done
  [ -n "$D_SLUG" ] && [ -n "$D_DATE" ] && [ -n "$D_ACTION" ] && [ -n "$D_REASON" ] || {
    cat >&2 <<'EOT'
usage: project-map.sh decide --slug SLUG --date YYYY-MM-DD
                             --action never_propose|capped_at
                             --reason "why, in a sentence"
                             [--hours N]     (required for capped_at)

  never_propose  this date is settled — do not propose it again
  capped_at      this date is deliberately logged short of measured, reviewed
                 and left; --hours is what was actually logged

The reason is not optional. A decision whose reasoning is lost is
indistinguishable from a mistake, and the next person to look at the numbers
will reverse it.
EOT
    exit 64; }
  case "$D_ACTION" in
    never_propose) : ;;
    capped_at) [ -n "$D_HOURS" ] || { echo "project-map.sh decide: capped_at needs --hours (what was deliberately logged)" >&2; exit 64; } ;;
    *) echo "project-map.sh decide: --action must be never_propose or capped_at" >&2; exit 64 ;;
  esac
  case "$D_DATE" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
    *) echo "project-map.sh decide: --date must be YYYY-MM-DD" >&2; exit 64 ;;
  esac
  jq -e --arg s "$D_SLUG" '[.entries[]? | select(.slug == $s)] | length > 0' < "$MAP" >/dev/null 2>&1 || {
    echo "project-map.sh decide: no entry with slug '$D_SLUG' — add it with \`put\` first" >&2
    jq -r '"  known slugs: " + ([.entries[]?.slug] | join(", "))' < "$MAP" >&2
    exit 66; }

  TMP=$(mktemp) || exit 70
  jq --arg s "$D_SLUG" --arg dt "$D_DATE" --arg a "$D_ACTION" --arg r "$D_REASON" \
     --arg h "$D_HOURS" --arg today "$(today)" '
    ({date:$dt, action:$a, reason:$r, decided:$today}
      + (if $h == "" then {} else {hours: ($h|tonumber)} end)) as $new
    | .entries = [ .entries[] |
        if .slug == $s then
          .decisions = ([ (.decisions // [])[]
                          | select((.date != $dt) or (.action != $a)) ] + [$new]
                        | sort_by(.date, .action))
        else . end ]
    | .updated = $today' < "$MAP" > "$TMP" && cat "$TMP" > "$MAP" && rm -f "$TMP"
  chmod 600 "$MAP"
  jq -r --arg s "$D_SLUG" --arg dt "$D_DATE" '.entries[] | select(.slug==$s) | (.decisions // [])[] | select(.date==$dt) |
    "recorded: \($s) \(.date) \(.action)\(if .hours then " @\(.hours)h" else "" end) — \(.reason) [decided \(.decided)]"' < "$MAP" >&2
  ;;

# ------------------------------------------------------------- validate -----
validate)
  ensure_map; need_ac
  TMP=$(mktemp -d) || exit 70; trap 'rm -rf "$TMP"' EXIT
  "$AC" GETALL /projects > "$TMP/p.json" 2>/dev/null || echo '[]' > "$TMP/p.json"
  jq -e 'type=="array"' < "$TMP/p.json" >/dev/null 2>&1 || echo '[]' > "$TMP/p.json"

  : > "$TMP/paths.tsv"
  jq -r '.entries[]? | .slug as $s | (.repos // [])[] | "\($s)\t\(.)"' < "$MAP" | while IFS=$'\t' read -r slug path; do
    if git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then printf '%s\t%s\tok\n' "$slug" "$path" >> "$TMP/paths.tsv"
    else printf '%s\t%s\tmissing\n' "$slug" "$path" >> "$TMP/paths.tsv"; fi
  done

  jq -R -s --slurpfile map "$MAP" --slurpfile proj "$TMP/p.json" '
    [ split("\n")[] | select(length>0) | split("\t") | {slug:.[0], path:.[1], state:.[2]} ] as $paths
    | ($map[0].entries // []) as $e
    | ($proj[0] | map({key:(.id|tostring), value:.}) | from_entries) as $pmap
    | {
        entries: [ $e[] | . as $x | {
            slug: $x.slug,
            private: ($x.private // false),
            project_id: $x.project_id,
            project_ok: (if ($x.private // false) then null else ($pmap[($x.project_id|tostring)] != null) end),
            project_name_now: ($pmap[(($x.project_id // 0)|tostring)].name // null),
            project_name_stored: $x.project_name,
            name_drifted: (($x.project_name != null) and ($pmap[(($x.project_id // 0)|tostring)].name != null)
                           and ($x.project_name != $pmap[(($x.project_id // 0)|tostring)].name)),
            budget_type_now: ($pmap[(($x.project_id // 0)|tostring)].budget_type // null),
            budget_type_stored: $x.budget_type,
            missing_paths: [ $paths[] | select(.slug == $x.slug and .state == "missing") | .path ]
          } ]
      }
    | .problems = [ .entries[] | select((.project_ok == false) or .name_drifted
                    or ((.missing_paths|length) > 0)
                    or ((.budget_type_stored != null) and (.budget_type_now != null) and (.budget_type_stored != .budget_type_now))) ]
    | .ok = ((.problems|length) == 0)' < "$TMP/paths.tsv" > "$TMP/out.json"

  cat "$TMP/out.json"
  {
    jq -r 'if .ok then "validate: map is consistent with the live instance" else "validate: \(.problems|length) entr(y/ies) need attention" end' < "$TMP/out.json"
    jq -r '.problems[] | select(.project_ok == false) | "  ! \(.slug): project \(.project_id) is not in GETALL /projects — archived, deleted, or not readable by this token"' < "$TMP/out.json"
    jq -r '.problems[] | select(.name_drifted) | "  ! \(.slug): project renamed \"\(.project_name_stored)\" -> \"\(.project_name_now)\""' < "$TMP/out.json"
    jq -r '.problems[] | select((.budget_type_stored != null) and (.budget_type_now != null) and (.budget_type_stored != .budget_type_now)) | "  ! \(.slug): budget_type changed \(.budget_type_stored) -> \(.budget_type_now) — billable behaviour has changed"' < "$TMP/out.json"
    jq -r '.problems[] | select((.missing_paths|length) > 0) | "  ! \(.slug): path(s) gone — \(.missing_paths|join(", "))"' < "$TMP/out.json"
  } >&2
  ;;

*) usage ;;
esac
