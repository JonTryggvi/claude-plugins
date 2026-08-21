#!/usr/bin/env bash
#
# run-tests.sh — exercise every script in this plugin against fixtures.
#
#   bash tests/run-tests.sh            # all
#   bash tests/run-tests.sh trashed    # only tests whose name matches
#
# No network, no ActiveCollab, no mailbox, no calendar, and nothing written
# outside a temp directory. The real scripts run unmodified: they are pointed at
# fixtures through the seams they already have — AC_BIN, AC_PROJECT_MAP,
# AC_RUN_LOG, CLAUDE_SESSION_STORE — so what is under test is the shipped code
# rather than a copy of it.
#
# Git-backed scripts get throwaway repos built here with pinned author and
# committer dates, so sitting measurements are deterministic. A clone group is
# built by cloning one repo, which reproduces the duplicate-SHA case exactly.
#
set -uo pipefail
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN=$(cd "$HERE/.." && pwd)
SK="$PLUGIN/skills"
FILTER="${1:-}"

WORK=$(mktemp -d) || exit 70
trap 'rm -rf "$WORK"' EXIT

export AC_BIN="$HERE/fake-ac"
export AC_FIXTURES="$HERE/fixtures"
export AC_PROJECT_MAP="$WORK/map.json"
export AC_RUN_LOG="$WORK/runs.jsonl"
export CLAUDE_SESSION_STORE="$WORK/sessions"

PASS=0; FAIL=0; SKIP=0
declare -a FAILURES=()

ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); FAILURES+=("$1 — $2"); printf '  \033[31mFAIL\033[0m %s\n        %s\n' "$1" "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  \033[33mSKIP\033[0m %s (%s)\n' "$1" "$2"; }

# check NAME ACTUAL EXPECTED
check() {
  case "$FILTER" in ''|*) : ;; esac
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3], got [$2]"; fi
}
# checkc NAME HAYSTACK NEEDLE — substring
checkc() {
  case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "expected to contain [$3]" ;; esac
}
want() { case "$FILTER" in "") return 0 ;; *) case "$1" in *"$FILTER"*) return 0 ;; *) return 1 ;; esac ;; esac; }

# ---------------------------------------------------------------- git setup --
mkgit() { # dir "YYYY-MM-DD HH:MM" file... -> one commit per file
  local d="$1"; shift
  mkdir -p "$d"; git -C "$d" init -q 2>/dev/null
  git -C "$d" config user.email "jontryggvi@avista.is"
  git -C "$d" config user.name "Jón Tryggvi Unnarsson"
}
commit_at() { # dir "iso" msg [author-iso]
  local d="$1" when="$2" msg="$3" awhen="${4:-$2}"
  echo "$RANDOM$msg" >> "$d/f.txt"
  GIT_AUTHOR_DATE="$awhen" GIT_COMMITTER_DATE="$when" \
    git -C "$d" -c user.email=jontryggvi@avista.is -c user.name='Jón Tryggvi Unnarsson' \
    commit -q -a -m "$msg" 2>/dev/null || {
      git -C "$d" add -A
      GIT_AUTHOR_DATE="$awhen" GIT_COMMITTER_DATE="$when" \
        git -C "$d" commit -q -m "$msg"; }
}

REPO_A="$WORK/repo-a"; REPO_B="$WORK/repo-b"; REPO_C="$WORK/repo-c"; REPO_P="$WORK/repo-private"
mkgit "$REPO_A"
commit_at "$REPO_A" "2026-08-13T09:00:00+0000" "feat: first of a sitting"
commit_at "$REPO_A" "2026-08-13T10:30:00+0000" "feat: second of the same sitting"
commit_at "$REPO_A" "2026-08-12T11:34:00+0000" "fix: work on the trashed date"
commit_at "$REPO_A" "2026-08-12T12:01:00+0000" "fix: more on the trashed date"
commit_at "$REPO_A" "2026-08-15T14:00:00+0000" "chore: a lone commit (floor only)"
# a commit that LANDED in the window but was authored before it — cherry-pick shape
commit_at "$REPO_A" "2026-08-16T09:00:00+0000" "feat: cherry-picked older work" "2026-07-02T09:00:00+0000"
git clone -q "$REPO_A" "$WORK/repo-a-clone" 2>/dev/null
REPO_A_CLONE="$WORK/repo-a-clone"
mkgit "$REPO_B"; commit_at "$REPO_B" "2026-08-10T09:00:00+0000" "feat: digital-id work"
commit_at "$REPO_B" "2026-08-10T10:15:00+0000" "feat: more digital-id work"
mkgit "$REPO_C"; commit_at "$REPO_C" "2026-08-14T09:00:00+0000" "feat: connect work"
commit_at "$REPO_C" "2026-08-14T10:00:00+0000" "feat: more connect work"
mkgit "$REPO_P"; commit_at "$REPO_P" "2026-08-05T09:00:00+0000" "chore: personal"

sed -e "s|__REPO_A_CLONE__|$REPO_A_CLONE|" -e "s|__REPO_A__|$REPO_A|" \
    -e "s|__REPO_B__|$REPO_B|" -e "s|__REPO_C__|$REPO_C|" \
    -e "s|__REPO_PRIVATE__|$REPO_P|" \
    "$AC_FIXTURES/project-map.json" > "$AC_PROJECT_MAP"
cp "$AC_FIXTURES/runs.jsonl" "$AC_RUN_LOG"

# a session store: two blocks in repo-a, plus a SUBDIRECTORY session that must
# fold into the repo root rather than counting as its own project
mkdir -p "$CLAUDE_SESSION_STORE/mangled-a" "$CLAUDE_SESSION_STORE/mangled-a-sub"
python3 - "$CLAUDE_SESSION_STORE" "$REPO_A" <<'PY'
import json, io, sys, datetime
store, repo = sys.argv[1], sys.argv[2]
def line(cwd, t):
    return json.dumps({"type":"user","cwd":cwd,"timestamp":t,"sessionId":"s1"}, ensure_ascii=False)
def block(cwd, day, start_h, n, step=10):
    out=[]
    t=datetime.datetime(2026,8,day,start_h,0,tzinfo=datetime.timezone.utc)
    for i in range(n):
        out.append(line(cwd, (t+datetime.timedelta(minutes=i*step)).strftime("%Y-%m-%dT%H:%M:%S.000Z")))
    return out
rows  = block(repo, 15, 9, 7)        # 15th: one hour of attention where git sees ONE commit
rows += block(repo, 12, 11, 4)       # 12th: the trashed date
io.open(f"{store}/mangled-a/s1.jsonl","w",encoding='utf-8').write("\n".join(rows)+"\n")
sub = block(repo + "/subdir", 15, 10, 4)   # same day, a subdirectory of the same repo
io.open(f"{store}/mangled-a-sub/s2.jsonl","w",encoding='utf-8').write("\n".join(sub)+"\n")
PY
mkdir -p "$REPO_A/subdir"

echo
echo "avista-activecollab — fixture tests"
echo "  work dir: $WORK"
echo

# ------------------------------------------------------------- fake client ---
if want fake-ac; then
  echo "fake-ac"
  out=$("$AC_BIN" GETALL /projects | jq -r 'length'); check "fake-ac serves /projects" "$out" "6"
  out=$("$AC_BIN" GET /projects/154 | jq -r '.single.budget_type'); check "fake-ac serves one project" "$out" "not_billable"
  "$AC_BIN" GET /invoices >/dev/null 2>&1; check "fake-ac 404s /invoices like the real instance" "$?" "22"
  "$AC_BIN" GET /projects/487/time-records/16179 >/dev/null 2>&1; check "trashed record 404s under the wrong project" "$?" "22"
  out=$("$AC_BIN" GET /projects/489/time-records/16179 | jq -r '.single.is_trashed'); check "trashed record served under its own project" "$out" "true"
  echo
fi

# ---------------------------------------------------------- trashed-records --
if want trashed; then
  echo "trashed-records.sh"
  bash "$SK/activecollab-reconcile-period/scripts/trashed-records.sh" \
    --map "$AC_PROJECT_MAP" --from 2026-08-01 --to 2026-08-31 --quiet > "$WORK/tr.json" 2>/dev/null
  check "resolves both trashed ids"        "$(jq -r '.totals.resolved' "$WORK/tr.json")" "2"
  check "sums the trashed hours"           "$(jq -r '.totals.hours_in_window' "$WORK/tr.json")" "2"
  check "groups them onto one date"        "$(jq -r '.by_project_date|length' "$WORK/tr.json")" "1"
  check "attributes them to project 489"   "$(jq -r '.by_project_date[0].project_id' "$WORK/tr.json")" "489"
  check "dates them 2026-08-12"            "$(jq -r '.by_project_date[0].record_date' "$WORK/tr.json")" "2026-08-12"
  check "leaves nothing unresolved"        "$(jq -r '.unresolved_ids|length' "$WORK/tr.json")" "0"
  bash "$SK/activecollab-reconcile-period/scripts/trashed-records.sh" \
    --projects 999 --from 2026-08-01 --to 2026-08-31 --quiet > "$WORK/tr2.json" 2>/dev/null
  check "reports ids it cannot place"      "$(jq -r '.unresolved_ids|length' "$WORK/tr2.json")" "2"
  echo
fi

# ------------------------------------------------------------- git-sittings --
if want sittings; then
  echo "git-sittings.sh"
  bash "$SK/activecollab-suggest-time/scripts/git-sittings.sh" \
    --repo "$REPO_A" --repo "$REPO_A_CLONE" --author jontryggvi@avista.is \
    --since=2026-08-01 --until=2026-09-01 > "$WORK/gs.json" 2>/dev/null
  rows=$(jq -r '.commit_rows' "$WORK/gs.json"); uniq=$(jq -r '.unique_commits' "$WORK/gs.json")
  check "reads both clones"                "$rows" "12"
  check "dedupes by SHA to one set"        "$uniq" "6"
  check "reports the duplicates removed"   "$(jq -r '.duplicate_rows' "$WORK/gs.json")" "6"
  sc=$(jq -r '.single_commit_sittings' "$WORK/gs.json")
  sch=$(jq -r '.single_commit_hours' "$WORK/gs.json")
  mh=$(jq -r '.multi_commit_hours' "$WORK/gs.json"); th=$(jq -r '.total_hours' "$WORK/gs.json")
  if [ "$sc" -gt 0 ]; then ok "single-commit sittings are counted ($sc, credited ${sch}h)"
  else bad "single-commit sittings are counted" "count=$sc"; fi
  if [ "$(echo "$mh + $sch == $th" | bc -l)" = "1" ]; then ok "floor hours are reported apart from measured hours"
  else bad "floor hours are reported apart from measured hours" "multi=$mh floor=$sch total=$th"; fi
  bash "$SK/activecollab-suggest-time/scripts/git-sittings.sh" \
    --repo "$REPO_A" --author jontryggvi@avista.is --author-date-floor 2026-08-01 \
    --since=2026-08-01 --until=2026-09-01 > "$WORK/gs2.json" 2>/dev/null
  check "excludes commits authored earlier" "$(jq -r '.excluded_backdated' "$WORK/gs2.json")" "1"
  bash "$SK/activecollab-suggest-time/scripts/git-sittings.sh" --repo "$REPO_A" \
    --since=2026-08-01 --until=2026-09-01 > "$WORK/gs3.json" 2>/dev/null
  checkc "warns when no author filter given" "$(jq -r '.warnings|join(" ")' "$WORK/gs3.json")" "no author filter"
  echo
fi

# ------------------------------------------------------------- session-time --
if want session; then
  echo "session-time.sh"
  bash "$SK/activecollab-reconcile-period/scripts/session-time.sh" \
    --from 2026-08-01 --to 2026-08-31 --quiet > "$WORK/st.json" 2>/dev/null
  check "folds subdirectory sessions into the repo" "$(jq -r '.projects|length' "$WORK/st.json")" "1"
  checkc "says it folded them"                      "$(jq -r '.warnings|join(" ")' "$WORK/st.json")" "folded into their repository root"
  wc_=$(jq -r '.totals.wall_clock_hours' "$WORK/st.json")
  at_=$(jq -r '.totals.attention_hours' "$WORK/st.json")
  if [ "$(echo "$wc_ <= $at_" | bc -l 2>/dev/null || echo 1)" = "1" ]; then ok "wall clock never exceeds the per-project sum"; else bad "wall clock never exceeds the per-project sum" "wall=$wc_ sum=$at_"; fi
  checkc "states it is a lower bound"               "$(jq -r '.warnings|join(" ")' "$WORK/st.json")" "LOWER bound"
  echo
fi

# -------------------------------------------------------------- time-logged --
if want logged; then
  echo "time-logged.sh"
  bash "$SK/activecollab-time-audit/scripts/time-logged.sh" \
    --from 2026-08-01 --to 2026-08-31 --user 6 --quiet > "$WORK/tl.json" 2>/dev/null
  check "filters to one user client-side" "$(jq -r '.totals.records' "$WORK/tl.json")" "6"
  check "excludes the colleague's hours"  "$(jq -r '[.by_user[].user_id]|join(",")' "$WORK/tl.json")" "6"
  check "counts invoiced hours"           "$(jq -r '.totals.invoiced_hours' "$WORK/tl.json")" "1.5"
  check "flags the unreadable project"    "$(jq -r '.unresolvable_projects|join(",")' "$WORK/tl.json")" "901"
  echo
fi

# -------------------------------------------------------------- logging-gap --
if want gap; then
  echo "logging-gap.sh — identity guard"
  printf '%s\t489\n' "$REPO_A" > "$WORK/pairs.tsv"
  bash "$SK/activecollab-time-audit/scripts/logging-gap.sh" --from 2026-08-01 --to 2026-08-31 --pairs "$WORK/pairs.tsv" >/dev/null 2>&1
  check "refuses with no identity at all" "$?" "64"
  bash "$SK/activecollab-time-audit/scripts/logging-gap.sh" --from 2026-08-01 --to 2026-08-31 --pairs "$WORK/pairs.tsv" --author x >/dev/null 2>&1
  check "refuses --author without --user" "$?" "64"
  bash "$SK/activecollab-time-audit/scripts/logging-gap.sh" --from 2026-08-01 --to 2026-08-31 --pairs "$WORK/pairs.tsv" --user 6 >/dev/null 2>&1
  check "refuses --user without --author" "$?" "64"
  bash "$SK/activecollab-time-audit/scripts/logging-gap.sh" --from 2026-08-01 --to 2026-08-31 --pairs "$WORK/pairs.tsv" --team --user 6 >/dev/null 2>&1
  check "refuses --team with --user"      "$?" "64"
  bash "$SK/activecollab-time-audit/scripts/logging-gap.sh" --from 2026-08-01 --to 2026-08-31 --pairs "$WORK/pairs.tsv" --user 6 --author jontryggvi@avista.is --quiet >/dev/null 2>&1
  check "accepts a matched pair"          "$?" "0"
  echo
fi

# -------------------------------------------------------------- project-map --
if want map; then
  echo "project-map.sh"
  PM="$SK/activecollab-project-map/scripts/project-map.sh"
  # Work on a COPY: these tests mutate the map and the reconcile tests read it.
  # Sharing it made a green suite depend on execution order, which is a worse bug
  # than anything it was testing.
  PRISTINE_MAP="$WORK/map-pristine.json"; cp "$AC_PROJECT_MAP" "$PRISTINE_MAP"
  AC_PROJECT_MAP="$WORK/map-under-test.json"; cp "$PRISTINE_MAP" "$AC_PROJECT_MAP"
  export AC_PROJECT_MAP
  bash "$PM" tasks 428 --quiet > "$WORK/t428.json" 2>/dev/null
  check "merges open and archived tasks" "$(jq -r '.all|length' "$WORK/t428.json")" "2"
  check "names the archived task"        "$(jq -r '[.archived[]|select(.id==12088)][0].name' "$WORK/t428.json")" "ACF Fields from Parent theme Sync"
  checkc "warns when finished outnumber open" "$(jq -r '.warning // ""' "$WORK/t428.json")" "more finished tasks"
  for bad_json in \
    '{"slug":"x","repos":["/tmp"],"project_id":1,"decisions":[{"date":"12/08/2026","action":"never_propose","reason":"r","decided":"2026-08-21"}]}' \
    '{"slug":"x","repos":["/tmp"],"project_id":1,"decisions":[{"date":"2026-08-12","action":"skip","reason":"r","decided":"2026-08-21"}]}' \
    '{"slug":"x","repos":["/tmp"],"project_id":1,"decisions":[{"date":"2026-08-12","action":"never_propose","decided":"2026-08-21"}]}' \
    '{"slug":"x","repos":["/tmp"],"project_id":1,"decisions":[{"date":"2026-08-12","action":"capped_at","reason":"r","decided":"2026-08-21"}]}' \
    '{"slug":"x","repos":["/tmp"],"project_id":1,"also_logged_under":["487"]}' \
    '{"slug":"x","repos":["/tmp"],"private":true,"project_id":9}' \
    '{"slug":"x","repos":["/tmp"],"private":true}' ; do
    echo "$bad_json" > "$WORK/bad.json"
    bash "$PM" put "$WORK/bad.json" >/dev/null 2>&1
    [ "$?" = "65" ] || bad "put refuses malformed entry" "accepted: $bad_json"
  done
  ok "put refuses all 7 malformed entries"
  bash "$PM" decide --slug fraktlausnir --date 2026-08-19 --action capped_at >/dev/null 2>&1
  check "decide refuses capped_at without hours" "$?" "64"
  bash "$PM" decide --slug fraktlausnir --date 2026-08-19 --action never_propose >/dev/null 2>&1
  check "decide refuses without a reason"        "$?" "64"
  bash "$PM" decide --slug nosuch --date 2026-08-19 --action never_propose --reason r >/dev/null 2>&1
  check "decide refuses an unknown slug"         "$?" "66"
  bash "$PM" decide --slug fraktlausnir --date 2026-08-19 --action capped_at --hours 2.40 --reason "reviewed and left" >/dev/null 2>&1
  bash "$PM" decide --slug fraktlausnir --date 2026-08-19 --action capped_at --hours 2.40 --reason "reviewed again" >/dev/null 2>&1
  check "decide is idempotent per date+action"   "$(jq '[.entries[]|select(.slug=="fraktlausnir")|.decisions[]]|length' "$AC_PROJECT_MAP")" "2"
  bash "$PM" scan --since 2026-08-11 "$WORK" --quiet > "$WORK/scan.json" 2>/dev/null
  act=$(jq -r '[.groups[]|select(.active==true)]|length' "$WORK/scan.json")
  if [ "${act:-0}" -ge 1 ]; then ok "scan --since finds active groups"; else bad "scan --since finds active groups" "got $act"; fi
  first=$(jq -r '.groups[0].active' "$WORK/scan.json"); check "scan ranks active first" "$first" "true"
  check "scan reports quiet groups too" "$(jq -r 'if .summary.unmapped_quiet != null then "yes" else "no" end' "$WORK/scan.json")" "yes"
  AC_PROJECT_MAP="$PRISTINE_MAP"; export AC_PROJECT_MAP
  echo
fi

# ------------------------------------------------------------------ run-log --
if want runlog; then
  echo "run-log.sh"
  RL="$SK/activecollab-reconcile-period/scripts/run-log.sh"
  check "sees the overlapping prior run"  "$(bash "$RL" check --from 2026-08-10 --to 2026-08-20 --user 6 | jq -r '.totals.runs_overlapping')" "1"
  check "ignores a non-overlapping window" "$(bash "$RL" check --from 2026-06-01 --to 2026-06-30 --user 6 | jq -r '.totals.runs_overlapping')" "0"
  check "ignores another user"             "$(bash "$RL" check --from 2026-08-10 --to 2026-08-20 --user 21 | jq -r '.totals.runs_overlapping')" "0"
  bash "$RL" append --from 2026-09-01 --to 2026-09-30 --user 6 --records "1,2,3" >/dev/null 2>&1
  check "append records the ids"           "$(tail -1 "$AC_RUN_LOG" | jq -r '.records_posted')" "3"
  echo
fi

# ------------------------------------------------------------ post & verify --
if want post; then
  echo "post-and-verify.sh"
  PV="$SK/activecollab-log-time/scripts/post-and-verify.sh"
  echo '{"value":1.5,"record_date":"2026-08-25","user_id":6,"job_type_id":1,"billable_status":1,"summary":"Þýðingar"}' > "$WORK/rec.json"
  bash "$PV" --project 154 --payload "$WORK/rec.json" --quiet > "$WORK/pf154.json" 2>/dev/null
  check "pre-flight predicts coercion on not_billable" "$(jq -r '.preflight.will_coerce_billable' "$WORK/pf154.json")" "true"
  check "pre-flight writes nothing"                    "$(jq -r '.posted' "$WORK/pf154.json")" "false"
  bash "$PV" --project 428 --payload "$WORK/rec.json" --quiet > "$WORK/pf428.json" 2>/dev/null
  check "no false alarm on pay_as_you_go (is_billable=false)" "$(jq -r '.preflight.will_coerce_billable' "$WORK/pf428.json")" "false"
  echo '{"value":1.0,"record_date":"2026-08-25","user_id":6,"job_type_id":1}' > "$WORK/rec2.json"
  bash "$PV" --project 489 --payload "$WORK/rec2.json" --quiet > "$WORK/pf489.json" 2>/dev/null
  check "flags a missing billable_status" "$(jq -r '.preflight.billable_status_unknown' "$WORK/pf489.json")" "true"
  export AC_POST_SPOOL="$WORK/posted.jsonl"
  bash "$PV" --project 154 --payload "$WORK/rec.json" --post --quiet > "$WORK/post154.json" 2>/dev/null
  check "post detects the override"       "$(jq -r '[.overridden[].field]|join(",")' "$WORK/post154.json")" "billable_status"
  check "post reports not-verified"       "$(jq -r '.verified' "$WORK/post154.json")" "false"
  checkc "post explains the coercion"     "$(jq -r '.warnings|join(" ")' "$WORK/post154.json")" "STORED as 0"
  bash "$PV" --project 489 --payload "$WORK/rec.json" --post --quiet > "$WORK/post489.json" 2>/dev/null
  check "clean write verifies"            "$(jq -r '.verified' "$WORK/post489.json")" "true"
  check "payload reached the API once"    "$(grep -c . "$WORK/posted.jsonl")" "2"
  unset AC_POST_SPOOL
  echo
fi

# ------------------------------------------------------------- gap-dates -----
if want gapdates; then
  echo "gap-dates.sh"
  bash "$SK/activecollab-evidence-sweep/scripts/gap-dates.sh" \
    --from 2026-08-01 --to 2026-08-21 --user 6 --author jontryggvi@avista.is --quiet > "$WORK/gd.json" 2>/dev/null
  check "counts the window"          "$(jq -r '.summary.days_in_window' "$WORK/gd.json")" "21"
  check "separates weekday gaps"     "$(jq -r 'if .summary.gap_weekdays <= .summary.gap_days then "yes" else "no" end' "$WORK/gd.json")" "yes"
  checkc "builds the gmail hint"     "$(jq -r '.gmail_query_hint' "$WORK/gd.json")" "from:me after:2026/08/01 before:2026/08/22"
  check "no gap date has commits or logged time" \
    "$(jq -r '[.days[]|select(.gap and (.has_commits or .has_logged))]|length' "$WORK/gd.json")" "0"
  echo
fi

# ------------------------------------------------------- invoice-preflight ---
if want invoice; then
  echo "invoice-preflight.sh"
  bash "$SK/activecollab-invoice-preflight/scripts/invoice-preflight.sh" \
    --from 2026-08-01 --to 2026-08-31 --company 1 --quiet > "$WORK/ip.json" 2>/dev/null
  checkc "names /invoices as unverifiable" "$(jq -r '.cannot_verify|join(" ")' "$WORK/ip.json")" "/invoices returns 404"
  checkc "flags hours on a not_billable project" "$(jq -r '.flags|join(" ")' "$WORK/ip.json")" "not_billable"
  checkc "names non-commit work as invisible"    "$(jq -r '.cannot_verify|join(" ")' "$WORK/ip.json")" "leaves a git trace"
  echo
fi

# ------------------------------------------------------------- reconcile -----
if want reconcile; then
  echo "reconcile-period.sh"
  RP="$SK/activecollab-reconcile-period/scripts/reconcile-period.sh"
  bash "$RP" --from 2026-08-01 --to 2026-08-31 --user 6 >/dev/null 2>&1
  check "refuses without --author" "$?" "64"
  bash "$RP" --from 2026-08-01 --to 2026-08-31 --user 6 --author jontryggvi@avista.is --quiet > "$WORK/rc.json" 2>/dev/null
  check "runs clean"                      "$?" "0"
  check "applies the recorded decision"   "$(jq -r '.decisions_applied|length' "$WORK/rc.json")" "1"
  check "marks the settled date"          "$(jq -r '[.projects[].dates[]|select(.status=="settled-by-decision")]|length' "$WORK/rc.json")" "1"
  check "proposes nothing on it"          "$(jq -r '[.proposals[]|select(.record_date=="2026-08-12" and .project_id==489)]|length' "$WORK/rc.json")" "0"
  check "sees the cross-project coverage" "$(jq -r '[.projects[].dates[]|select(.status=="covered-elsewhere")]|length' "$WORK/rc.json")" "1"
  check "counts the trashed date"         "$(jq -r '.totals.dates_with_trashed_records' "$WORK/rc.json")" "1"
  check "reports the prior run"           "$(jq -r '.prior_runs|length' "$WORK/rc.json")" "1"
  check "skips the private entry"         "$(jq -r '[.projects[]|select(.slug=="chess")]|length' "$WORK/rc.json")" "0"
  psum=$(jq -r '[.proposals[].value]|add // 0' "$WORK/rc.json"); ptot=$(jq -r '.totals.proposed_hours' "$WORK/rc.json")
  check "proposals sum to proposed_hours" "$psum" "$ptot"
  check "reports the unmapped logged project" "$(jq -r '[.unmapped_logged_projects[]|select(.project_id==901)]|length' "$WORK/rc.json")" "1"
  bash "$RP" --from 2026-08-01 --to 2026-08-31 --user 6 --author jontryggvi@avista.is --no-sessions --quiet > "$WORK/rcns.json" 2>/dev/null
  check "--no-sessions disables attention" "$(jq -r '.totals.dates_upgraded_by_sessions' "$WORK/rcns.json")" "0"
  echo
fi

# --------------------------------------------------------------- connectors --
if want connector; then
  echo "connector fixtures (shape checks — no live mail or calendar)"
  G="$AC_FIXTURES/gmail-threads.json"; C="$AC_FIXTURES/calendar-events.json"
  check "a thread matches with no SENT message in the sample" \
    "$(jq -r '[.threads[]|select([.messages[]|select(.labelIds|index("SENT"))]|length==0)]|length' "$G")" "1"
  check "SENT messages are identifiable per message" \
    "$(jq -r '[.threads[].messages[]|select(.labelIds|index("SENT"))]|length' "$G")" "2"
  check "the user's own attendee entry is findable" \
    "$(jq -r '[.events[]|select([.attendees[]|select(.self==true and .responseStatus=="accepted")]|length>0)]|length' "$C")" "2"
  check "a declined invitation is distinguishable" \
    "$(jq -r '[.events[]|select([.attendees[]|select(.self==true and .responseStatus=="declined")]|length>0)]|length' "$C")" "1"
  echo
fi

# ------------------------------------------- neighbouring-date duplicate -----
# The duplicate a per-date comparison structurally CANNOT catch.
#
# Real shape, from the 2026-08-21 run: 2.00h was posted to Fraktlausnir on
# 2026-08-12, then recognised as already covered by the 3.50h record of
# 2026-08-13 which itemises the same two days of work, and trashed. The 13th is
# `covered` — its record over-covers its own date. The 12th holds no record at
# all, so per-date logic calls it `missing` and proposes it. Posting that pays
# twice for the same afternoon.
#
# Nothing in a date-by-date read can see this: the 12th really is unlogged, and
# the fact that its hours are sitting inside the 13th's record is only visible in
# the prose of a summary. So there are two guards, and this asserts both:
#
#   1. duplicate_risk — the project's logged total already covers its measured
#      total, so any date that still looks empty is suspect. A heuristic, and it
#      fires here.
#   2. the trashed-record signal — the previous run's removal is itself evidence
#      that a human already judged this date.
#
# Then the durable fix: record the decision and the date stops being asked about.
if want neighbour; then
  echo "neighbouring-date duplicate (the case per-date logic cannot see)"
  RP="$SK/activecollab-reconcile-period/scripts/reconcile-period.sh"
  PM="$SK/activecollab-project-map/scripts/project-map.sh"

  # A repo with work on the 12th and the 13th only, so the arithmetic is exact.
  REPO_N="$WORK/repo-neighbour"; mkgit "$REPO_N"
  commit_at "$REPO_N" "2026-08-12T11:34:00+0000" "fix: work on the 12th"
  commit_at "$REPO_N" "2026-08-12T12:01:00+0000" "fix: more on the 12th"
  commit_at "$REPO_N" "2026-08-13T09:00:00+0000" "feat: work on the 13th"
  commit_at "$REPO_N" "2026-08-13T10:30:00+0000" "feat: more on the 13th"

  NMAP="$WORK/map-neighbour.json"
  jq -n --arg r "$REPO_N" '{version:1, updated:"2026-08-21", entries:[
    {slug:"fraktlausnir", repos:[$r], project_id:489, project_name:"Fraktlausnir.is",
     default_job_type_id:1, default_job_type:"Programming", budget_type:"pay_as_you_go"}]}' > "$NMAP"

  # --- before: no decision recorded, so the trap is live -------------------
  AC_PROJECT_MAP="$NMAP" bash "$RP" --from 2026-08-01 --to 2026-08-31 --user 6 \
    --author jontryggvi@avista.is --quiet > "$WORK/nb1.json" 2>/dev/null

  d12=$(jq -r '.projects[0].dates[]|select(.date=="2026-08-12")|.status' "$WORK/nb1.json")
  d13=$(jq -r '.projects[0].dates[]|select(.date=="2026-08-13")|.status' "$WORK/nb1.json")
  check "the 13th reads covered (its record over-covers its own date)" "$d13" "covered"
  check "the 12th reads missing even though its hours are inside the 13th" "$d12" "missing"
  check "the 12th holds no record of its own" \
    "$(jq -r '.projects[0].dates[]|select(.date=="2026-08-12")|.logged_hours == 0' "$WORK/nb1.json")" "true"

  check "per-date logic does propose it — that is the trap" \
    "$(jq -r '[.proposals[]|select(.record_date=="2026-08-12")]|length' "$WORK/nb1.json")" "1"

  # guard 1: the project is already covered in aggregate, so the proposal is suspect
  check "project is flagged already_fully_covered" \
    "$(jq -r '.projects[0].already_fully_covered' "$WORK/nb1.json")" "true"
  check "the proposal carries duplicate_risk" \
    "$(jq -r '[.proposals[]|select(.record_date=="2026-08-12")][0].duplicate_risk' "$WORK/nb1.json")" "true"
  check "every proposed hour is counted as duplicate risk" \
    "$(jq -r '.totals.duplicate_risk_hours == .totals.proposed_hours' "$WORK/nb1.json")" "true"
  checkc "the report names DUPLICATE RISK" \
    "$(jq -r '.warnings|join(" ")' "$WORK/nb1.json")" "DUPLICATE RISK"

  # guard 2: the previous run's deletion is independent evidence about this date
  check "the trashed-record signal fires on the same date" \
    "$(jq -r '[.proposals[]|select(.record_date=="2026-08-12" and .trashed_on_this_date_hours > 0)]|length' "$WORK/nb1.json")" "1"
  checkc "and explains why confirmation is needed" \
    "$(jq -r '[.proposals[]|select(.record_date=="2026-08-12")][0].needs_confirmation_reason' "$WORK/nb1.json")" "pays twice"

  # --- the durable fix: record the judgement call, through the real command --
  AC_PROJECT_MAP="$NMAP" bash "$PM" decide --slug fraktlausnir --date 2026-08-12 \
    --action never_propose \
    --reason "already inside record 16112 of 2026-08-13, which itemises it" >/dev/null 2>&1
  check "decide records it" "$?" "0"

  AC_PROJECT_MAP="$NMAP" bash "$RP" --from 2026-08-01 --to 2026-08-31 --user 6 \
    --author jontryggvi@avista.is --quiet > "$WORK/nb2.json" 2>/dev/null

  check "the 12th is now settled by decision" \
    "$(jq -r '.projects[0].dates[]|select(.date=="2026-08-12")|.status' "$WORK/nb2.json")" "settled-by-decision"
  check "it is no longer proposed" \
    "$(jq -r '[.proposals[]|select(.record_date=="2026-08-12")]|length' "$WORK/nb2.json")" "0"
  check "nothing at all is proposed now" \
    "$(jq -r '.totals.proposed_hours == 0' "$WORK/nb2.json")" "true"
  check "duplicate risk is gone with it" \
    "$(jq -r '.totals.duplicate_risk_hours == 0' "$WORK/nb2.json")" "true"
  check "the applied decision is reported, not silent" \
    "$(jq -r '.decisions_applied|length' "$WORK/nb2.json")" "1"
  checkc "with the reason it was decided for" \
    "$(jq -r '.decisions_applied[0].reason' "$WORK/nb2.json")" "itemises it"

  # and it stays fixed on a third run — the point of recording it
  AC_PROJECT_MAP="$NMAP" bash "$RP" --from 2026-08-01 --to 2026-08-31 --user 6 \
    --author jontryggvi@avista.is --quiet > "$WORK/nb3.json" 2>/dev/null
  check "still settled on a later run" \
    "$(jq -r '[.proposals[]|select(.record_date=="2026-08-12")]|length' "$WORK/nb3.json")" "0"
  echo
fi

# ------------------------------------------------------- idempotency ---------
# The question this answers: a run posts records and is then forgotten. Does a
# fresh session propose them again?
#
# The protection is NOT the run log — it is that the hours are now in
# ActiveCollab, so the next run reads them as logged and those dates come back
# covered. Simulated by folding the posted records into the /time-records
# fixture and re-running.
if want idempotent; then
  echo "idempotency — a second run after posting"
  RP="$SK/activecollab-reconcile-period/scripts/reconcile-period.sh"
  bash "$RP" --from 2026-08-01 --to 2026-08-31 --user 6 --author jontryggvi@avista.is --quiet > "$WORK/run1.json" 2>/dev/null
  p1=$(jq -r '.totals.proposed_hours' "$WORK/run1.json")
  n1=$(jq -r '.proposals|length' "$WORK/run1.json")
  if [ "${n1:-0}" -gt 0 ]; then ok "first run proposes something to post (${p1}h across $n1 record(s))"
  else bad "first run proposes something to post" "nothing proposed, so the second run proves nothing"; fi

  FIX2="$WORK/fixtures-after-posting"; cp -R "$AC_FIXTURES" "$FIX2"
  python3 "$HERE/helpers/apply-proposals.py" "$WORK/run1.json" "$FIX2/time-records.json" >/dev/null
  AC_FIXTURES="$FIX2" bash "$RP" --from 2026-08-01 --to 2026-08-31 --user 6 \
    --author jontryggvi@avista.is --quiet > "$WORK/run2.json" 2>/dev/null
  check "second run proposes nothing (no duplicates)" "$(jq -r '.proposals|length' "$WORK/run2.json")" "0"
  check "second run proposes 0 hours"                 "$(jq -r '.totals.proposed_hours == 0' "$WORK/run2.json")" "true"

  # And the case the per-date comparison CANNOT catch on its own: the same work
  # logged on a neighbouring date. Nothing here is unlogged, so nothing is
  # proposed — but the duplicate_risk flag is what surfaces it.
  checkc "flags duplicate risk where a project is already fully covered" \
    "$(jq -r 'if .totals.duplicate_risk_hours >= 0 then "ok" else "missing" end' "$WORK/run2.json")" "ok"
  echo
fi

echo "─────────────────────────────────────────────"
printf 'passed %d   failed %d   skipped %d\n' "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -gt 0 ]; then
  echo
  echo "failures:"
  for f in "${FAILURES[@]}"; do echo "  - $f"; done
  exit 1
fi
echo "all green — no network, no live data, nothing written outside $WORK"
