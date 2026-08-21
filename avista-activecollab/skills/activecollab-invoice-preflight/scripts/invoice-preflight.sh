#!/usr/bin/env bash
#
# invoice-preflight.sh — check one client's period before it is invoiced.
#
#   invoice-preflight.sh --company 202 --from 2026-07-01 --to 2026-07-31
#   invoice-preflight.sh --client 'Tækniskólinn' --from … --to … \
#       --author jontryggvi@avista.is        # also check for commits with no time
#
# Emits JSON on stdout, a report on stderr. READ-ONLY, always.
#
# WHAT IT ANSWERS
#
#   1. What is logged for this client in the period, split by whether it is
#      billable, already invoiced, or non-billable.
#   2. Which of those hours are billable but NOT yet on an invoice — the
#      hours this invoice is presumably for.
#   3. Which dates have commits in the client's mapped repos but no time
#      record — work that would be invoiced late or not at all.
#
# WHAT IT CANNOT ANSWER, AND SAYS SO
#
# `/invoices` returns 404 for a normal API token on this instance, so there is
# no way to read the invoice list, check an invoice's contents, or confirm that
# an invoice exists. The ONLY invoice signal available is `invoice_item_id` on
# each time record: non-zero means that record is already on some invoice.
# Everything this script says about invoicing rests on that one field, and the
# report states it rather than implying a completeness it cannot have.
#
# It also cannot see:
#   - non-commit work with no time record (meetings, support, phone fixes) —
#     that is activecollab-evidence-sweep's job
#   - projects this token cannot read, which 404 individually
#   - anything in projects with no repo in the project map, where "commits but
#     no time" is unanswerable rather than clean
#
# A preflight that hides its blind spots is worse than none, because the
# blind spots are where the missing money is.
#
set -uo pipefail
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

FROM=""; TO=""; COMPANY=""; CLIENT=""; USER_ID=""; QUIET=0
AUTHORS=()
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SITTINGS="${GIT_SITTINGS:-$HERE/../../activecollab-suggest-time/scripts/git-sittings.sh}"
MAP="${AC_PROJECT_MAP:-$HOME/.claude/activecollab-project-map.json}"
AC="${AC_BIN:-$HOME/.claude/bin/ac}"

usage() {
  cat >&2 <<'EOT'
usage: invoice-preflight.sh --from YYYY-MM-DD --to YYYY-MM-DD
                            (--company ID | --client NAME-PATTERN)
                            [--user AC_USER_ID] [--author GIT_ID …] [--quiet]

  --company / --client   which client to check (one of them)
  --user                 restrict the logged side to one person (default: everyone,
                         which is usually right for an invoice)
  --author               git identities, for the "commits but no time" check;
                         omit to skip that check rather than measure everybody
EOT
  exit 64
}

while [ $# -gt 0 ]; do
  case "$1" in
    --from)    FROM="${2:-}"; shift 2 ;;
    --to)      TO="${2:-}"; shift 2 ;;
    --company) COMPANY="${2:-}"; shift 2 ;;
    --client)  CLIENT="${2:-}"; shift 2 ;;
    --user)    USER_ID="${2:-}"; shift 2 ;;
    --author)  AUTHORS+=("${2:?--author needs a value}"); shift 2 ;;
    --author=*) AUTHORS+=("${1#*=}"); shift ;;
    --map)     MAP="${2:-}"; shift 2 ;;
    --quiet)   QUIET=1; shift ;;
    -h|--help) usage ;;
    *) echo "invoice-preflight.sh: unknown argument '$1'" >&2; usage ;;
  esac
done

[ -n "$FROM" ] && [ -n "$TO" ] || usage
[ -n "$COMPANY" ] || [ -n "$CLIENT" ] || { echo "invoice-preflight.sh: give --company ID or --client NAME" >&2; usage; }
[ -x "$AC" ] || { echo "invoice-preflight.sh: no ac client at $AC — run activecollab-setup" >&2; exit 69; }
command -v jq >/dev/null 2>&1 || { echo "invoice-preflight.sh: jq is not installed" >&2; exit 69; }

TMP=$(mktemp -d) || exit 70
trap 'rm -rf "$TMP"' EXIT

# /companies is not paginated on this instance (GET and GETALL both return 211),
# but /projects caps at 100 of 213 — so that one MUST be GETALL or most of the
# client's projects simply will not be there.
"$AC" GET    /companies > "$TMP/co.json" 2>/dev/null || echo '[]' > "$TMP/co.json"
"$AC" GETALL /projects  > "$TMP/pr.json" 2>/dev/null || echo '[]' > "$TMP/pr.json"
jq -e 'type=="array"' < "$TMP/co.json" >/dev/null 2>&1 || echo '[]' > "$TMP/co.json"
jq -e 'type=="array"' < "$TMP/pr.json" >/dev/null 2>&1 || { echo "invoice-preflight.sh: could not read /projects" >&2; exit 65; }

if [ -z "$COMPANY" ]; then
  jq -r --arg c "$CLIENT" '[.[] | select(.name | test($c; "i"))] | .[] | "\(.id)\t\(.name)"' < "$TMP/co.json" > "$TMP/match.tsv"
  n=$(awk 'END{print NR+0}' < "$TMP/match.tsv")
  if [ "$n" -eq 0 ]; then
    echo "invoice-preflight.sh: no company matching '$CLIENT'." >&2
    echo "  Company names are the client names; list them with: $AC GET /companies | jq -r '.[]|\"\\(.id)\\t\\(.name)\"'" >&2
    exit 66
  elif [ "$n" -gt 1 ]; then
    echo "invoice-preflight.sh: '$CLIENT' matches $n companies — pick one with --company:" >&2
    sed 's/^/    /' < "$TMP/match.tsv" >&2
    exit 65
  fi
  COMPANY=$(cut -f1 < "$TMP/match.tsv")
fi

"$AC" GET "/time-records?from=${FROM}&to=${TO}" > "$TMP/records.json" 2>/dev/null || {
  echo "invoice-preflight.sh: could not read /time-records" >&2; exit 65; }
"$AC" GET /job-types > "$TMP/jt.json" 2>/dev/null || echo '[]' > "$TMP/jt.json"
jq -e 'type=="array"' < "$TMP/jt.json" >/dev/null 2>&1 || echo '[]' > "$TMP/jt.json"

# Confirm the invoice list really is unreadable rather than assuming it.
inv_readable=false
if "$AC" GET /invoices > "$TMP/inv.json" 2>/dev/null && jq -e 'type' < "$TMP/inv.json" >/dev/null 2>&1; then
  inv_readable=true
fi

# --- commits with no time, for this client's mapped projects only ------------
: > "$TMP/git.ndjson"
if [ ${#AUTHORS[@]} -gt 0 ] && [ -f "$MAP" ]; then
  if UNTIL=$(date -u -j -f "%Y-%m-%d" "$TO" -v+1d +%Y-%m-%d 2>/dev/null); then :
  elif UNTIL=$(date -u -d "$TO + 1 day" +%Y-%m-%d 2>/dev/null); then :
  else UNTIL="$TO"; fi
  sitargs=(); for a in "${AUTHORS[@]}"; do [ -n "$a" ] && sitargs+=(--author "$a"); done
  sitargs+=(--author-date-floor "$FROM")

  jq -r --slurpfile pr "$TMP/pr.json" --arg co "$COMPANY" '
    ($pr[0] | map(select(.company_id == ($co|tonumber)) | .id)) as $ids
    | .entries[]? | select((.private // false) | not) | select(.project_id as $p | $ids | index($p))
    | @base64' < "$MAP" | while read -r b64; do
    printf '%s' "$b64" | base64 --decode > "$TMP/e.json" 2>/dev/null || continue
    repoargs=()
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      git -C "$p" rev-parse --git-dir >/dev/null 2>&1 && repoargs+=(--repo "$p")
    done < <(jq -r '(.repos // [])[]' < "$TMP/e.json")
    [ ${#repoargs[@]} -gt 0 ] || continue
    bash "$SITTINGS" "${repoargs[@]}" "${sitargs[@]}" "--since=$FROM" "--until=$UNTIL" \
      > "$TMP/s.json" 2>/dev/null || echo '{"sittings":[]}' > "$TMP/s.json"
    jq -c --slurpfile s "$TMP/s.json" '{project_id, slug, measured:$s[0]}' < "$TMP/e.json" >> "$TMP/git.ndjson"
  done
fi

python3 - "$TMP" "$FROM" "$TO" "$COMPANY" "${USER_ID:-}" "$inv_readable" "${#AUTHORS[@]}" <<'PY' > "$TMP/out.json"
import json, sys, io, os, datetime

tmp, FROM, TO, COMPANY = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
USER_ID = int(sys.argv[5]) if sys.argv[5] else None
INV_READABLE = sys.argv[6] == 'true'
N_AUTHORS = int(sys.argv[7])

def load(n, d=None):
    p = os.path.join(tmp, n)
    if not os.path.exists(p): return d
    with io.open(p, encoding='utf-8') as fh:
        try: return json.load(fh)
        except Exception: return d

def r2(x): return round(float(x) + 0.0, 2)

companies = load('co.json', []) or []
projects  = load('pr.json', []) or []
jobs = {str(j.get('id')): j.get('name') for j in (load('jt.json', []) or [])}
recs_doc  = load('records.json', {}) or {}
related_p = (recs_doc.get('related') or {}).get('Project') or {}

cname = next((c.get('name') for c in companies if c.get('id') == COMPANY), None)
client_projects = [p for p in projects if p.get('company_id') == COMPANY]
cp_ids = {p['id'] for p in client_projects}

recs = [x for x in (recs_doc.get('time_records') or [])
        if not x.get('is_trashed') and x.get('project_id') in cp_ids
        and (USER_ID is None or x.get('user_id') == USER_ID)]

def rdate(x):
    d = x.get('record_date')
    if isinstance(d, (int, float)):
        return datetime.datetime.fromtimestamp(int(d), datetime.timezone.utc).strftime('%Y-%m-%d')
    return str(d)[:10]

gitrows = []
p = os.path.join(tmp, 'git.ndjson')
if os.path.exists(p):
    with io.open(p, encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if line: gitrows.append(json.loads(line))
git_by_pid = {g['project_id']: g for g in gitrows}

per_project = []
for pr in sorted(client_projects, key=lambda x: x.get('name') or ''):
    pid = pr['id']
    rs = [x for x in recs if x.get('project_id') == pid]
    billable_uninvoiced = [x for x in rs if x.get('billable_status') == 1 and not x.get('invoice_item_id')]
    invoiced            = [x for x in rs if x.get('invoice_item_id')]
    nonbillable         = [x for x in rs if x.get('billable_status') == 0]
    logged_dates = {rdate(x) for x in rs}

    g = git_by_pid.get(pid)
    commit_dates, uncovered = [], []
    measured = 0.0
    if g and g.get('measured'):
        for s in (g['measured'].get('sittings') or []):
            commit_dates.append(s.get('date'))
            measured += float(s.get('hours') or 0)
        uncovered = sorted({d for d in commit_dates if d not in logged_dates})

    per_project.append({
        'project_id': pid,
        'project_name': pr.get('name'),
        'budget_type': pr.get('budget_type'),
        'tracking_enabled': pr.get('is_tracking_enabled'),
        'logged_hours': r2(sum(float(x.get('value') or 0) for x in rs)),
        'records': len(rs),
        'billable_uninvoiced_hours': r2(sum(float(x.get('value') or 0) for x in billable_uninvoiced)),
        'billable_uninvoiced_records': len(billable_uninvoiced),
        'already_invoiced_hours': r2(sum(float(x.get('value') or 0) for x in invoiced)),
        'non_billable_hours': r2(sum(float(x.get('value') or 0) for x in nonbillable)),
        'by_job_type': [{'job_type': jobs.get(str(j), 'unknown'),
                         'hours': r2(sum(float(x.get('value') or 0) for x in rs if x.get('job_type_id') == j))}
                        for j in sorted({x.get('job_type_id') for x in rs if x.get('job_type_id')})],
        'git_checked': g is not None,
        'measured_hours': r2(measured) if g else None,
        'dates_with_commits_no_time': uncovered,
        'unlogged_date_count': len(uncovered),
    })

tot_logged  = r2(sum(p['logged_hours'] for p in per_project))
tot_uninv   = r2(sum(p['billable_uninvoiced_hours'] for p in per_project))
tot_inv     = r2(sum(p['already_invoiced_hours'] for p in per_project))
tot_nonbill = r2(sum(p['non_billable_hours'] for p in per_project))

# Everything the check could not establish. This list is the point of the skill.
cannot_verify = []
if not INV_READABLE:
    cannot_verify.append(
        "whether an invoice already exists for this period, or what is on it — /invoices returns 404 for "
        "this API token. The only invoice signal available is invoice_item_id on each time record "
        "(non-zero = already on some invoice). 'not yet invoiced' below means exactly that field is zero, "
        "nothing more.")
if N_AUTHORS == 0:
    cannot_verify.append(
        "whether there is committed work with no time record — no --author was given, so the git check was "
        "skipped rather than run against every committer.")
unmapped = [p for p in per_project if not p['git_checked']]
if unmapped:
    cannot_verify.append(
        "'commits but no time' for %d of this client's %d project(s) — no repo for them in the project map, "
        "so the question is unanswered rather than clean: %s"
        % (len(unmapped), len(per_project), ', '.join('%s (%s)' % (p['project_name'], p['project_id']) for p in unmapped[:8])))
cannot_verify.append(
    "non-commit work with no time record — support handled by email, meetings, phone fixes. None of it "
    "leaves a git trace, so nothing here can find it. Run activecollab-evidence-sweep for that.")
unreadable = [p['project_id'] for p in per_project if p['tracking_enabled'] is None]
if unreadable:
    cannot_verify.append("project(s) %s did not return readable detail for this token"
                         % ', '.join(str(x) for x in unreadable))

flags = []
for p in per_project:
    if p['unlogged_date_count'] > 0:
        flags.append("%s (%s): %d date(s) with commits but no time record — %s"
                     % (p['project_name'], p['project_id'], p['unlogged_date_count'],
                        ', '.join(p['dates_with_commits_no_time'][:8])))
    if p['budget_type'] == 'not_billable' and p['logged_hours'] > 0:
        flags.append("%s (%s): %.2fh logged on a budget_type=not_billable project — those records store as "
                     "non-billable whatever was sent, so they will not reach an invoice"
                     % (p['project_name'], p['project_id'], p['logged_hours']))
    if p['tracking_enabled'] is False and p['logged_hours'] > 0:
        flags.append("%s (%s): time tracking is disabled but %.2fh is logged"
                     % (p['project_name'], p['project_id'], p['logged_hours']))

out = {
    'window': {'from': FROM, 'to': TO},
    'client': {'company_id': COMPANY, 'company_name': cname, 'projects': len(client_projects)},
    'scope': {'activecollab_user_id': USER_ID,
              'note': ('one person only' if USER_ID else 'every person — usually right for an invoice'),
              'git_author_filters': N_AUTHORS},
    'totals': {
        'logged_hours': tot_logged,
        'billable_not_yet_invoiced_hours': tot_uninv,
        'already_invoiced_hours': tot_inv,
        'non_billable_hours': tot_nonbill,
        'dates_with_commits_no_time': sum(p['unlogged_date_count'] for p in per_project),
    },
    'projects': [p for p in per_project if p['records'] > 0 or p['unlogged_date_count'] > 0],
    'quiet_projects': [{'project_id': p['project_id'], 'project_name': p['project_name']}
                       for p in per_project if p['records'] == 0 and p['unlogged_date_count'] == 0],
    'flags': flags,
    'cannot_verify': cannot_verify,
    'basis': 'logged from /time-records over the window, filtered client-side to this company\'s projects '
             '(the endpoint ignores every filter but from/to). Invoice state read from invoice_item_id '
             'only. Measured from git commit sittings where a repo is mapped. Read-only.',
}
sys.stdout.write(json.dumps(out, ensure_ascii=False, indent=1))
PY

cat "$TMP/out.json"
[ "$QUIET" = "1" ] && exit 0
{
  jq -r '"invoice preflight  \(.client.company_name // "company \(.client.company_id)") (\(.client.company_id))  \(.window.from) .. \(.window.to)"' < "$TMP/out.json"
  jq -r '.scope | "  scope: \(.note)"' < "$TMP/out.json"
  jq -r '.totals | "  logged \(.logged_hours)h   billable not yet invoiced \(.billable_not_yet_invoiced_hours)h   already invoiced \(.already_invoiced_hours)h   non-billable \(.non_billable_hours)h"' < "$TMP/out.json"
  echo "  --- per project ---"
  printf '  %-40s %8s %10s %9s  %s\n' project logged uninvoiced measured gaps
  jq -r '.projects[] | "  \((.project_name // "?")|.[0:40])\t\(.logged_hours)\t\(.billable_uninvoiced_hours)\t\(.measured_hours // "-")\t\(.unlogged_date_count)"' < "$TMP/out.json" \
    | awk -F'\t' '{printf "  %-40s %8s %10s %9s  %s\n", $1,$2,$3,$4,$5}'
  echo "  --- flags ---"
  jq -r 'if (.flags|length)==0 then "    none" else (.flags[] | "    ! \(.)") end' < "$TMP/out.json"
  echo "  --- could NOT verify ---"
  jq -r '.cannot_verify[] | "    ? \(.)"' < "$TMP/out.json"
} >&2
