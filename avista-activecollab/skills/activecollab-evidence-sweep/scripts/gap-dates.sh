#!/usr/bin/env bash
#
# gap-dates.sh — list the dates in a window that have NO git trace and NO
# logged time, so an evidence sweep knows where to look.
#
#   gap-dates.sh --from 2026-07-01 --to 2026-07-31 --user 6 \
#                --author jontryggvi@avista.is --author 'Jón Tryggvi'
#
# Emits JSON on stdout, a calendar-ish summary on stderr. READ-ONLY.
#
# WHY THIS IS THE INPUT TO AN EVIDENCE SWEEP
#
# git only sees work that produced commits. A password reset done from an email
# request, a two-hour client call, an afternoon in a WordPress admin — all
# measure 0.00h and leave no trace anywhere this plugin normally looks. The way
# to find them is not to search everything: it is to work out which days are
# blank on both the git side and the timesheet side, and look only there.
#
# A blank day is not automatically unlogged work. Most of them are days off,
# weekends, or days the person genuinely worked on something already logged
# elsewhere. The point is to narrow a month to a handful of days worth asking
# about, not to generate a list of accusations.
#
set -uo pipefail
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

FROM=""; TO=""; USER_ID=""; QUIET=0
AUTHORS=()
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SITTINGS="${GIT_SITTINGS:-$HERE/../../activecollab-suggest-time/scripts/git-sittings.sh}"
MAP="${AC_PROJECT_MAP:-$HOME/.claude/activecollab-project-map.json}"
AC="${AC_BIN:-$HOME/.claude/bin/ac}"

usage() {
  echo "usage: gap-dates.sh --from YYYY-MM-DD --to YYYY-MM-DD --user AC_USER_ID --author GIT_ID [--author …] [--map FILE] [--quiet]" >&2
  exit 64
}

while [ $# -gt 0 ]; do
  case "$1" in
    --from)   FROM="${2:-}"; shift 2 ;;
    --to)     TO="${2:-}"; shift 2 ;;
    --user)   USER_ID="${2:-}"; shift 2 ;;
    --author) AUTHORS+=("${2:?--author needs a value}"); shift 2 ;;
    --author=*) AUTHORS+=("${1#*=}"); shift ;;
    --map)    MAP="${2:-}"; shift 2 ;;
    --quiet)  QUIET=1; shift ;;
    -h|--help) usage ;;
    *) echo "gap-dates.sh: unknown argument '$1'" >&2; usage ;;
  esac
done

[ -n "$FROM" ] && [ -n "$TO" ] && [ -n "$USER_ID" ] || usage
[ ${#AUTHORS[@]} -gt 0 ] || { echo "gap-dates.sh: at least one --author is required, or every committer counts as this person" >&2; exit 64; }
[ -x "$AC" ] || { echo "gap-dates.sh: no ac client at $AC — run activecollab-setup" >&2; exit 69; }
command -v jq >/dev/null 2>&1 || { echo "gap-dates.sh: jq is not installed" >&2; exit 69; }

if UNTIL=$(date -u -j -f "%Y-%m-%d" "$TO" -v+1d +%Y-%m-%d 2>/dev/null); then :
elif UNTIL=$(date -u -d "$TO + 1 day" +%Y-%m-%d 2>/dev/null); then :
else echo "gap-dates.sh: could not add a day to '$TO'" >&2; exit 65; fi

TMP=$(mktemp -d) || exit 70
trap 'rm -rf "$TMP"' EXIT

"$AC" GET "/time-records?from=${FROM}&to=${TO}" > "$TMP/records.json" 2>/dev/null || {
  echo "gap-dates.sh: could not read /time-records" >&2; exit 65; }

# Every mapped repo at once — we only need to know whether ANY commit exists on a
# date, so attribution does not matter here and one pass is enough.
repoargs=()
if [ -f "$MAP" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    git -C "$p" rev-parse --git-dir >/dev/null 2>&1 && repoargs+=(--repo "$p")
  done < <(jq -r '.entries[]? | (.repos // [])[]' < "$MAP")
fi
sitargs=()
for a in "${AUTHORS[@]}"; do [ -n "$a" ] && sitargs+=(--author "$a"); done

if [ ${#repoargs[@]} -gt 0 ]; then
  bash "$SITTINGS" "${repoargs[@]}" "${sitargs[@]}" "--since=$FROM" "--until=$UNTIL" \
    > "$TMP/s.json" 2>/dev/null || echo '{"sittings":[]}' > "$TMP/s.json"
else
  echo '{"sittings":[]}' > "$TMP/s.json"
  echo "gap-dates.sh: no readable repos in $MAP — every date will look commit-free" >&2
fi

python3 - "$TMP" "$FROM" "$TO" "$USER_ID" <<'PY' > "$TMP/out.json"
import json, sys, io, os, datetime

tmp, FROM, TO, USER_ID = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])

def load(n, d=None):
    p = os.path.join(tmp, n)
    if not os.path.exists(p): return d
    with io.open(p, encoding='utf-8') as fh:
        try: return json.load(fh)
        except Exception: return d

recs_doc = load('records.json', {}) or {}
sit = load('s.json', {}) or {}

def rdate(x):
    d = x.get('record_date')
    if isinstance(d, (int, float)):
        return datetime.datetime.fromtimestamp(int(d), datetime.timezone.utc).strftime('%Y-%m-%d')
    return str(d)[:10]

logged = {}
for x in (recs_doc.get('time_records') or []):
    if x.get('is_trashed') or x.get('user_id') != USER_ID:
        continue
    d = rdate(x)
    logged[d] = logged.get(d, 0.0) + float(x.get('value') or 0)

commits = {}
for s in (sit.get('sittings') or []):
    d = s.get('date')
    commits[d] = commits.get(d, 0) + int(s.get('commits') or 0)

d0 = datetime.date.fromisoformat(FROM)
d1 = datetime.date.fromisoformat(TO)
days = []
cur = d0
while cur <= d1:
    iso = cur.isoformat()
    c = commits.get(iso, 0)
    lg = round(logged.get(iso, 0.0) + 0.0, 2)
    days.append({
        'date': iso,
        'weekday': cur.strftime('%a'),
        'is_weekend': cur.weekday() >= 5,
        'commit_count': c,
        'has_commits': c > 0,
        'logged_hours': lg,
        'has_logged': lg > 0,
        # A gap is a day with no evidence on either side we already look at.
        'gap': (c == 0 and lg == 0),
    })
    cur += datetime.timedelta(days=1)

gaps = [d for d in days if d['gap']]
weekday_gaps = [d for d in gaps if not d['is_weekend']]

out = {
    'window': {'from': FROM, 'to': TO},
    'user_id': USER_ID,
    'basis': 'a date is a gap when it holds no commits by the given git identities AND no time records '
             'for the given ActiveCollab user. A gap is a place to ASK, not evidence of unlogged work — '
             'most are days off.',
    'summary': {
        'days_in_window': len(days),
        'days_with_commits': sum(1 for d in days if d['has_commits']),
        'days_with_logged_time': sum(1 for d in days if d['has_logged']),
        'gap_days': len(gaps),
        'gap_weekdays': len(weekday_gaps),
        'logged_hours_total': round(sum(logged.values()) + 0.0, 2),
    },
    'days': days,
    'gaps': [d['date'] for d in gaps],
    'gap_weekdays': [d['date'] for d in weekday_gaps],
    # Gmail wants slash dates and an exclusive upper bound.
    'gmail_query_hint': 'from:me after:%s before:%s' % (
        FROM.replace('-', '/'),
        (d1 + datetime.timedelta(days=1)).isoformat().replace('-', '/')),
}
sys.stdout.write(json.dumps(out, ensure_ascii=False, indent=1))
PY

cat "$TMP/out.json"
[ "$QUIET" = "1" ] && exit 0
{
  jq -r '"gap dates  \(.window.from) .. \(.window.to)   ActiveCollab user \(.user_id)"' < "$TMP/out.json"
  jq -r '.summary | "  \(.days_in_window) days: \(.days_with_commits) with commits, \(.days_with_logged_time) with logged time, \(.gap_days) with neither (\(.gap_weekdays) of them weekdays)"' < "$TMP/out.json"
  echo "  --- gap weekdays: look for email/calendar evidence on these only ---"
  jq -r '.days[] | select(.gap and (.is_weekend|not)) | "    \(.date) \(.weekday)"' < "$TMP/out.json"
  jq -r '"  gmail: \(.gmail_query_hint)  (their REPLIES are the evidence of work, not mail received)"' < "$TMP/out.json"
  echo "  A gap is a question, not a finding. Most are days off."
} >&2
