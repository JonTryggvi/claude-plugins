#!/usr/bin/env bash
#
# reconcile-period.sh — measure a date window against what is logged in
# ActiveCollab, per project AND per date, and propose the difference.
#
#   reconcile-period.sh --from 2026-07-01 --to 2026-07-31 \
#     --user 6 --author jontryggvi@avista.is --author 'Jón Tryggvi'
#
# Reads the repo->project mapping written by activecollab-project-map, measures
# each clone group with git-sittings.sh, reads logged time once with
# time-logged.sh, and emits a reconciliation on stdout with a summary on stderr.
#
# READ-ONLY. It proposes; it never posts. The calling skill must show every
# proposed record to the user and get approval before anything is written.
#
# THE FOUR WAYS A PERIOD TOTAL SILENTLY GOES WRONG
#
#  1. Clone duplication. Shared plugins are cloned into every site that uses
#     them, so the same commit is readable from several paths. git-sittings.sh
#     deduplicates by SHA across each group; `dedupe` in the output records how
#     much was removed. On a real month-end run this was 470 rows -> 323 unique
#     commits, and the undeduplicated read was ~92h against an honest 59h.
#
#  2. A stale clone treated as canonical. The standalone checkout is often
#     BEHIND the site clones, not ahead. Each group is measured as the UNION of
#     its paths, never as one nominated repo.
#
#  3. Cherry-picked older work. --since/--until filter COMMITTER date, which is
#     right for "when was this done". But a commit authored weeks earlier and
#     landed now belongs to the earlier invoice, so commits authored before
#     --from are excluded (--allow-backdated keeps them).
#
#  4. Subtracting project totals instead of reconciling per date. Some existing
#     records deliberately over-cover their date as an upward correction. If you
#     only compare project totals, the dates those records were meant to cover
#     still look empty, and posting them duplicates the correction. Every
#     project here is reconciled per date, and `overshoot_if_all_posted` says
#     how far above the measured floor the timesheet would end up if every
#     "missing" date were posted. Surface that number BEFORE asking for
#     approval.
#
set -uo pipefail
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

FROM=""; TO=""; USER_ID=""; QUIET=0; ALLOW_BACKDATED=0
AUTHORS=()
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SITTINGS="${GIT_SITTINGS:-$HERE/../../activecollab-suggest-time/scripts/git-sittings.sh}"
LOGGED="${TIME_LOGGED:-$HERE/../../activecollab-time-audit/scripts/time-logged.sh}"
MAP="${AC_PROJECT_MAP:-$HOME/.claude/activecollab-project-map.json}"

usage() {
  cat >&2 <<'EOT'
usage: reconcile-period.sh --from YYYY-MM-DD --to YYYY-MM-DD
                           --user AC_USER_ID --author GIT_IDENTITY [--author …]
                           [--map FILE] [--allow-backdated] [--quiet]

  --user   ActiveCollab user id — the logged side is filtered to this person
  --author git name/email substring — repeatable, because people commit under
           several identities; the measured side is filtered to these

Both are required. Filtering one side and not the other compares two different
populations, so the delta would report colleagues' hours as this person's.
EOT
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
    --allow-backdated) ALLOW_BACKDATED=1; shift ;;
    --quiet)  QUIET=1; shift ;;
    -h|--help) usage ;;
    *) echo "reconcile-period.sh: unknown argument '$1'" >&2; usage ;;
  esac
done

[ -n "$FROM" ] && [ -n "$TO" ] || usage
for d in "$FROM" "$TO"; do
  case "$d" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
    *) echo "reconcile-period.sh: dates must be YYYY-MM-DD (got '$d')" >&2; exit 64 ;;
  esac
done

# Same guard as logging-gap.sh, for the same reason: one filtered side and one
# open side is not a comparison, and on a shared project the difference reads as
# this person's missing hours when it is actually a colleague's logged time.
if [ -z "$USER_ID" ] || [ ${#AUTHORS[@]} -eq 0 ]; then
  echo "reconcile-period.sh: both --user and --author are required." >&2
  echo "  A reconciliation attributes hours to one person on a real timesheet, so both sides" >&2
  echo "  must describe that same person. Pass every git identity they commit under —" >&2
  echo "  --author is repeatable, and a missing identity moves real work out of the measured side." >&2
  echo "  Identities in a repo:  git -C <repo> log --format='%aN <%aE>' | sort -u" >&2
  exit 64
fi

[ -f "$MAP" ] || { echo "reconcile-period.sh: no project map at $MAP — run the activecollab-project-map skill first" >&2; exit 66; }
[ -f "$SITTINGS" ] || { echo "reconcile-period.sh: git-sittings.sh not found at $SITTINGS (set GIT_SITTINGS)" >&2; exit 69; }
[ -f "$LOGGED" ]   || { echo "reconcile-period.sh: time-logged.sh not found at $LOGGED (set TIME_LOGGED)" >&2; exit 69; }
command -v jq >/dev/null 2>&1 || { echo "reconcile-period.sh: jq is not installed" >&2; exit 69; }

if UNTIL=$(date -u -j -f "%Y-%m-%d" "$TO" -v+1d +%Y-%m-%d 2>/dev/null); then :
elif UNTIL=$(date -u -d "$TO + 1 day" +%Y-%m-%d 2>/dev/null); then :
else echo "reconcile-period.sh: could not add a day to '$TO'" >&2; exit 65; fi

TMP=$(mktemp -d) || exit 70
trap 'rm -rf "$TMP"' EXIT

# --- the logged side: one API read for the window, filtered to this person ---
bash "$LOGGED" --from "$FROM" --to "$TO" --user "$USER_ID" --quiet > "$TMP/logged.json" || {
  echo "reconcile-period.sh: the ActiveCollab read failed — see above" >&2; exit 65; }

# time-logged.sh aggregates; for per-DATE reconciliation we need the raw records
# it was built from, so pull them once more and filter client-side (the endpoint
# ignores user_id, which is exactly why this is done here and not in the query).
AC="${AC_BIN:-$HOME/.claude/bin/ac}"
[ -x "$AC" ] || { echo "reconcile-period.sh: no ac client at $AC — run activecollab-setup" >&2; exit 69; }
"$AC" GET "/time-records?from=${FROM}&to=${TO}" > "$TMP/records.json" 2>/dev/null || {
  echo "reconcile-period.sh: could not read /time-records" >&2; exit 65; }

# --- the measured side: one git-sittings run per mapped clone group ----------
sitargs=()
for a in "${AUTHORS[@]}"; do [ -n "$a" ] && sitargs+=(--author "$a"); done
[ "$ALLOW_BACKDATED" = "0" ] && sitargs+=(--author-date-floor "$FROM")

: > "$TMP/measured.ndjson"
jq -r '.entries[]? | select((.private // false) | not) | @base64' < "$MAP" | while read -r b64; do
  printf '%s' "$b64" | base64 --decode > "$TMP/entry.json" 2>/dev/null || continue
  repoargs=(); missing=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if git -C "$p" rev-parse --git-dir >/dev/null 2>&1; then repoargs+=(--repo "$p")
    else missing="${missing:+$missing, }$p"; fi
  done < <(jq -r '(.repos // [])[]' < "$TMP/entry.json")

  if [ ${#repoargs[@]} -eq 0 ]; then
    jq -c --arg m "$missing" '. + {measured:null, unreadable_paths:($m|split(", ")|map(select(.!="")))}' \
      < "$TMP/entry.json" >> "$TMP/measured.ndjson"
    continue
  fi

  bash "$SITTINGS" "${repoargs[@]}" "${sitargs[@]}" "--since=$FROM" "--until=$UNTIL" \
    > "$TMP/s.json" 2>/dev/null \
    || echo '{"total_hours":0,"signal_quality":"none","unique_commits":0,"sittings":[],"warnings":["git-sittings failed"]}' > "$TMP/s.json"

  jq -c --slurpfile s "$TMP/s.json" --arg m "$missing" \
    '. + {measured:$s[0], unreadable_paths:($m|split(", ")|map(select(.!="")))}' \
    < "$TMP/entry.json" >> "$TMP/measured.ndjson"
done

# --- reduce -----------------------------------------------------------------
python3 - "$TMP" "$FROM" "$TO" "$USER_ID" > "$TMP/out.json" <<'PY'
import json, sys, io, os

tmp, FROM, TO, USER_ID = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])

def load(name, default=None):
    p = os.path.join(tmp, name)
    if not os.path.exists(p):
        return default
    with io.open(p, encoding='utf-8') as fh:
        try:
            return json.load(fh)
        except Exception:
            return default

def r2(x):
    return round(float(x) + 0.0, 2)

logged_doc = load('logged.json', {}) or {}
records_doc = load('records.json', {}) or {}
raw = records_doc.get('time_records') or []
related_p = (records_doc.get('related') or {}).get('Project') or {}

# One person, non-trashed. The endpoint ignores user_id, so filter here.
recs = [x for x in raw if not x.get('is_trashed') and x.get('user_id') == USER_ID]

def rdate(x):
    d = x.get('record_date')
    if isinstance(d, (int, float)):
        import datetime
        return datetime.datetime.fromtimestamp(int(d), datetime.timezone.utc).strftime('%Y-%m-%d')
    return str(d)[:10]

logged_by_project = {}
for x in recs:
    pid = x.get('project_id')
    e = logged_by_project.setdefault(pid, {'hours': 0.0, 'dates': {}, 'records': []})
    v = float(x.get('value') or 0)
    e['hours'] += v
    d = rdate(x)
    dd = e['dates'].setdefault(d, {'hours': 0.0, 'records': []})
    dd['hours'] += v
    row = {'id': x.get('id'), 'date': d, 'value': v,
           'summary': (x.get('summary') or '')[:120],
           'task_id': x.get('parent_id') if x.get('parent_type') == 'Task' else None,
           'billable_status': x.get('billable_status'),
           'invoiced': bool(x.get('invoice_item_id')),
           'job_type_id': x.get('job_type_id')}
    dd['records'].append(row)
    e['records'].append(row)

entries = []
with io.open(os.path.join(tmp, 'measured.ndjson'), encoding='utf-8') as fh:
    for line in fh:
        line = line.strip()
        if line:
            entries.append(json.loads(line))

projects = []
tot_measured = tot_logged = tot_proposed = tot_floor = 0.0
rows = uniq = dupes = backdated = 0
mapped_pids = set()

for e in entries:
    pid = e.get('project_id')
    mapped_pids.add(pid)
    m = e.get('measured') or {}
    sittings = m.get('sittings') or []
    rows += int(m.get('commit_rows') or 0)
    uniq += int(m.get('unique_commits') or 0)
    dupes += int(m.get('duplicate_rows') or 0)
    backdated += int(m.get('excluded_backdated') or 0)

    lg = logged_by_project.get(pid, {'hours': 0.0, 'dates': {}, 'records': []})

    by_date = {}
    for i, s in enumerate(sittings):
        d = s.get('date')
        b = by_date.setdefault(d, {'measured': 0.0, 'sittings': [], 'floor': 0.0})
        b['measured'] += float(s.get('hours') or 0)
        if s.get('single_commit'):
            b['floor'] += float(s.get('hours') or 0)
        b['sittings'].append({
            'index': i + 1,
            'start': s.get('start_iso'), 'end': s.get('end_iso'),
            'commits': s.get('commits'), 'span_hours': s.get('span_hours'),
            'hours': s.get('hours'), 'single_commit': bool(s.get('single_commit')),
            'repos': s.get('repos') or [],
            'subjects': (s.get('subjects') or [])[:6],
        })

    dates = []
    proposed_here = 0.0
    for d in sorted(set(list(by_date.keys()) + list(lg['dates'].keys()))):
        meas = r2(by_date.get(d, {}).get('measured', 0.0))
        logd = r2(lg['dates'].get(d, {}).get('hours', 0.0))
        if meas > 0 and logd == 0:
            status = 'missing'
        elif meas == 0 and logd > 0:
            status = 'logged-only'          # non-commit work, or an over-covering correction
        elif logd + 1e-9 >= meas:
            status = 'covered'
        else:
            status = 'partial'
        row = {'date': d, 'measured_hours': meas, 'logged_hours': logd,
               'delta_hours': r2(logd - meas), 'status': status,
               'floor_only_hours': r2(by_date.get(d, {}).get('floor', 0.0)),
               'sittings': by_date.get(d, {}).get('sittings', []),
               'logged_records': lg['dates'].get(d, {}).get('records', [])}
        if status in ('missing', 'partial'):
            proposed_here += (meas - logd)
        dates.append(row)

    meas_tot = r2(sum(float(s.get('hours') or 0) for s in sittings))
    floor_tot = r2(m.get('single_commit_hours') or 0)
    log_tot = r2(lg['hours'])
    prop = r2(proposed_here)

    projects.append({
        'slug': e.get('slug'),
        'project_id': pid,
        'project_name': e.get('project_name') or (related_p.get(str(pid), {}) or {}).get('name'),
        'budget_type': e.get('budget_type'),
        'default_task_id': e.get('default_task_id'),
        'default_task_name': e.get('default_task_name'),
        'default_job_type_id': e.get('default_job_type_id'),
        'default_job_type': e.get('default_job_type'),
        'measured_hours': meas_tot,
        'measured_floor_only_hours': floor_tot,
        'measured_excluding_floor_hours': r2(meas_tot - floor_tot),
        'logged_hours': log_tot,
        'delta_hours': r2(log_tot - meas_tot),
        'proposed_hours': prop,
        'overshoot_if_all_posted': r2(log_tot + prop - meas_tot),
        # If the project's logged total already covers its measured total, then every
        # date that looks empty is already paid for by a record that over-covers its
        # own date. Posting those proposals duplicates an existing correction.
        'already_fully_covered': bool(log_tot + 1e-9 >= meas_tot),
        'duplicate_risk_hours': r2(prop) if log_tot + 1e-9 >= meas_tot else 0.0,
        'single_commit_sittings': int(m.get('single_commit_sittings') or 0),
        'commit_rows': int(m.get('commit_rows') or 0),
        'unique_commits': int(m.get('unique_commits') or 0),
        'duplicate_rows': int(m.get('duplicate_rows') or 0),
        'excluded_backdated': int(m.get('excluded_backdated') or 0),
        'signal_quality': m.get('signal_quality') or 'none',
        'repos_read': [r.get('label') for r in (m.get('repos') or []) if (r.get('rows') or 0) > 0],
        'repo_row_counts': {r.get('label'): r.get('rows') for r in (m.get('repos') or [])},
        'unreadable_paths': e.get('unreadable_paths') or [],
        'uncommitted_files': int(m.get('uncommitted_files') or 0),
        'dates': dates,
    })
    tot_measured += meas_tot
    tot_logged += log_tot
    tot_proposed += prop
    tot_floor += floor_tot

# Logged hours in projects the map does not cover: real time, not proposals.
unmapped = []
for pid, e in sorted(logged_by_project.items(), key=lambda kv: -kv[1]['hours']):
    if pid in mapped_pids:
        continue
    unmapped.append({'project_id': pid,
                     'project_name': (related_p.get(str(pid), {}) or {}).get('name'),
                     'logged_hours': r2(e['hours']),
                     'records': len(e['records'])})

# One proposal per sitting, under its own record_date. Collapsing a month into
# one entry is wrong on a timesheet even when the total matches.
proposals = []
for p in projects:
    for d in p['dates']:
        if d['status'] not in ('missing', 'partial'):
            continue
        for s in d['sittings']:
            proposals.append({
                'project_id': p['project_id'],
                'project_name': p['project_name'],
                'slug': p['slug'],
                'record_date': d['date'],
                'value': s['hours'],
                'task_id': p['default_task_id'],
                'job_type_id': p['default_job_type_id'],
                'billable_hint': ('will store non-billable — project budget_type is not_billable'
                                  if p['budget_type'] == 'not_billable' else 'billable as sent'),
                'single_commit_floor': s['single_commit'],
                'commits': s['commits'],
                'span_hours': s['span_hours'],
                'repos': s['repos'],
                'suggested_summary': '; '.join(s['subjects'][:3]) or None,
                'date_already_has_logged_hours': d['logged_hours'] > 0,
                'project_already_fully_covered': p['already_fully_covered'],
                'duplicate_risk': p['already_fully_covered'],
            })

warnings = []
if dupes > 0:
    warnings.append(
        "read %d commit rows across the mapped clone groups, %d unique after SHA dedupe (%d duplicates removed). "
        "Adding per-clone totals instead would have multiplied this work." % (rows, uniq, dupes))
if backdated > 0:
    warnings.append(
        "%d commit(s) landed in this window but were authored before %s — cherry-picked or late-landed "
        "older work, excluded so it stays on the period it was done in. Pass --allow-backdated to include them."
        % (backdated, FROM))
if tot_floor > 0:
    warnings.append(
        "%.2fh of the measured total comes from single-commit sittings across %d sitting(s). That is the "
        "lead-in allowance alone — a FLOOR, not a measurement. Report it separately and let the user raise "
        "the ones they remember; never inflate it silently."
        % (tot_floor, sum(p['single_commit_sittings'] for p in projects)))
overshoot = r2(tot_logged + tot_proposed - tot_measured)
dup_risk = r2(sum(p['duplicate_risk_hours'] for p in projects))
dup_projects = [p['slug'] for p in projects if p['duplicate_risk_hours'] > 0.01]
if dup_risk > 0.01:
    warnings.append(
        "DUPLICATE RISK: %.2fh of the %.2fh proposed falls on project(s) whose logged total ALREADY covers "
        "their measured total (%s). Those dates look empty per-date, but the hours are already on the "
        "timesheet in a record that over-covers its own date as an upward correction. Posting them pays "
        "twice. Walk the per-date table for those projects with the user before proposing anything there."
        % (dup_risk, tot_proposed, ', '.join(dup_projects)))
if overshoot > 0.01:
    warnings.append(
        "posting every proposed record would put this person's timesheet %.2fh above the measured total "
        "(%.2fh logged + %.2fh proposed vs %.2fh measured) across the mapped projects. Read this with care: "
        "logged legitimately exceeds measured wherever the work produced no commits — meetings, support, "
        "admin, page building. It is evidence of duplication only where the excess sits on a project that "
        "is already fully covered, which is what DUPLICATE RISK above measures. Quote the number, say which "
        "of the two it is, and let the user decide."
        % (overshoot, tot_logged, tot_proposed, tot_measured))
for p in projects:
    if p['unreadable_paths']:
        warnings.append("%s: unreadable path(s) %s — that part of the clone group was not measured"
                        % (p['slug'], ', '.join(p['unreadable_paths'])))
    counts = [v for v in (p['repo_row_counts'] or {}).values() if v is not None]
    if len(counts) > 1 and len(set(counts)) > 1:
        warnings.append("%s: clone group is uneven (%s) — the lower counts are copies that are BEHIND, "
                        "which is why the union is measured rather than a nominated canonical repo"
                        % (p['slug'], ', '.join('%s=%s' % (k, v) for k, v in p['repo_row_counts'].items())))
if unmapped:
    warnings.append("%d project(s) hold logged hours but are not in the project map (%.2fh total). Those "
                    "hours are real; the map just cannot attribute them to a repo. Add them with "
                    "activecollab-project-map, or accept them as non-commit work."
                    % (len(unmapped), r2(sum(u['logged_hours'] for u in unmapped))))

out = {
    'window': {'from': FROM, 'to': TO},
    'scope': {
        'activecollab_user_id': USER_ID,
        'note': 'measured and logged sides are both filtered to this one person, which is the only way '
                'the difference means anything',
    },
    'basis': 'measured = git commit sittings (45min gap, +15min lead-in, 0.25h rounding), SHA-deduplicated '
             'across each clone group, windowed on committer date with commits authored before --from '
             'excluded. logged = ActiveCollab time records in the window for this user. Reconciled per '
             'project AND per date. Measures; never prices.',
    'dedupe': {'commit_rows': rows, 'unique_commits': uniq, 'duplicate_rows': dupes,
               'excluded_backdated': backdated},
    'totals': {
        'measured_hours': r2(tot_measured),
        'measured_floor_only_hours': r2(tot_floor),
        'measured_excluding_floor_hours': r2(tot_measured - tot_floor),
        'logged_hours': r2(tot_logged),
        'delta_hours': r2(tot_logged - tot_measured),
        'proposed_hours': r2(tot_proposed),
        'overshoot_if_all_posted': overshoot,
        'duplicate_risk_hours': dup_risk,
        'proposals': len(proposals),
    },
    'projects': sorted(projects, key=lambda p: -p['measured_hours']),
    'proposals': sorted(proposals, key=lambda x: (x['record_date'], x['project_id'] or 0)),
    'unmapped_logged_projects': unmapped,
    'warnings': warnings,
}
sys.stdout.write(json.dumps(out, ensure_ascii=False, indent=1))
PY

cat "$TMP/out.json"

[ "$QUIET" = "1" ] && exit 0

{
  jq -r '"reconcile  \(.window.from) .. \(.window.to)   ActiveCollab user \(.scope.activecollab_user_id)"' < "$TMP/out.json"
  jq -r '.totals | "  measured \(.measured_hours)h   logged \(.logged_hours)h   delta \(.delta_hours)h   proposed \(.proposed_hours)h across \(.proposals) record(s)"' < "$TMP/out.json"
  jq -r '.dedupe | "  git: \(.commit_rows) rows -> \(.unique_commits) unique commits (\(.duplicate_rows) duplicates removed, \(.excluded_backdated) backdated excluded)"' < "$TMP/out.json"
  jq -r '.totals | if .measured_floor_only_hours > 0 then "  floor: \(.measured_floor_only_hours)h of the measured total is single-commit sittings — a floor, reported separately" else empty end' < "$TMP/out.json"
  jq -r '.totals | if .duplicate_risk_hours > 0.01 then "  ! DUPLICATE RISK: \(.duplicate_risk_hours)h of the \(.proposed_hours)h proposed is on project(s) already fully covered — walk those dates before proposing" else empty end' < "$TMP/out.json"
  jq -r '.totals | if .overshoot_if_all_posted > 0.01 then "  i posting everything proposed lands \(.overshoot_if_all_posted)h above measured — expected where work produced no commits; duplication only where flagged above" else empty end' < "$TMP/out.json"
  echo "  --- per project ---"
  printf '  %-22s %9s %9s %8s %9s  %s\n' project measured logged delta proposed signal
  jq -r '.projects[] | "  \((.slug // "?")|.[0:22])\t\(.measured_hours)\t\(.logged_hours)\t\(.delta_hours)\t\(.proposed_hours)\t\(.signal_quality)"' < "$TMP/out.json" \
    | awk -F'\t' '{printf "  %-22s %9s %9s %8s %9s  %s\n", $1,$2,$3,$4,$5,$6}'
  jq -r '.unmapped_logged_projects[] | "  i logged but unmapped: \(.logged_hours)h in project \(.project_id) \(.project_name // "(name not readable)")"' < "$TMP/out.json"
  jq -r '.warnings[] | "  ! \(.)"' < "$TMP/out.json"
} >&2
