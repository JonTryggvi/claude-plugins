#!/usr/bin/env bash
#
# session-time.sh — measure ATTENTION time from Claude Code's own session logs.
#
#   session-time.sh --from 2026-07-01 --to 2026-07-31
#   session-time.sh --from … --to … --repo ~/dev/myplugin --repo ~/dev/other
#   session-time.sh --from … --to … --map ~/.claude/activecollab-project-map.json
#
# Emits JSON on stdout, a summary on stderr. READ-ONLY — it reads timestamps
# out of session logs and nothing else.
#
# WHY THIS EXISTS
#
# git measures commits, and commits are a weak proxy for time. Measured on a
# real three-week window in this repo:
#
#     git commit sittings   1.75h   (signal_quality: poor)
#     Claude session blocks 7.75h
#     actually logged      20.55h
#
# Sessions were 4.4x closer to the truth than commits. The reason is structural:
# a sitting whose commits cluster at the end measures almost nothing, and a
# single-commit sitting measures only the lead-in allowance — 0.25h for what was
# often an hour or more. The session log knows how long that hour actually was,
# because it recorded an event every time something happened.
#
# So this is a THIRD measurement source, and its job is to replace floors with
# spans. It is not an authority and must not be presented as one:
#
#   - It measures ATTENTION, not billable time. Work done in an editor, a
#     browser, WP admin, a meeting or on the phone produces no session events,
#     which is why 7.75h still fell well short of the 20.55h really logged.
#   - Two projects worked in the same hour both claim that hour. Cross-project
#     overlap is detected and reported rather than silently double-counted.
#   - A session left running does NOT inflate the figure: events only fire when
#     something happens, so an idle stretch over GAP_MIN closes the block by
#     itself. Long single blocks are still flagged, because a background command
#     that ran for hours looks like attention and was not.
#
# WHAT IT READS, AND WHAT IT DELIBERATELY DOES NOT
#
# Source: ~/.claude/projects/<mangled-cwd>/*.jsonl — one directory per working
# directory, written by both the CLI and desktop sessions that operate on a real
# local folder. Grouping is done on the `cwd` FIELD INSIDE the file, never on the
# directory name: the mangling replaces `/`, `.` and spaces all with `-`, so it
# cannot be reversed unambiguously ("claude-smalls/Avista Plugins" and
# "claude-smalls-Avista-Plugins" mangle identically).
#
# Not read: ~/Library/Application Support/Claude/local-agent-mode-sessions.
# Those sandboxed sessions carry a `cwd` of /sessions/<name> or their own outputs
# folder — no repo to attribute to, so including them would invent attribution.
#
# ONLY the `timestamp` and `cwd` fields are read. Session transcripts contain
# every prompt, file and credential ever discussed; message content is never
# parsed, never emitted, and must never reach a timesheet summary.
#
set -uo pipefail
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

FROM=""; TO=""; QUIET=0; MAP=""
REPOS=()
STORE="${CLAUDE_SESSION_STORE:-$HOME/.claude/projects}"
GAP_MIN="${GAP_MIN:-45}"
LEADIN_MIN="${LEADIN_MIN:-15}"
ROUND="${ROUND:-0.25}"
MAX_BLOCK_HOURS="${MAX_BLOCK_HOURS:-8}"

usage() {
  cat >&2 <<'EOT'
usage: session-time.sh --from YYYY-MM-DD --to YYYY-MM-DD
                       [--repo PATH …] [--map FILE] [--store DIR] [--quiet]

  --repo  restrict to these working directories (repeatable). Omit for all.
  --map   an activecollab-project-map.json; attributes each cwd to its project
          and its clone group, so sessions in a site clone count once.

env: GAP_MIN=45  LEADIN_MIN=15  ROUND=0.25  MAX_BLOCK_HOURS=8
EOT
  exit 64
}

while [ $# -gt 0 ]; do
  case "$1" in
    --from)  FROM="${2:-}"; shift 2 ;;
    --to)    TO="${2:-}"; shift 2 ;;
    --repo)  REPOS+=("${2:?--repo needs a path}"); shift 2 ;;
    --repo=*) REPOS+=("${1#*=}"); shift ;;
    --map)   MAP="${2:-}"; shift 2 ;;
    --store) STORE="${2:-}"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) usage ;;
    *) echo "session-time.sh: unknown argument '$1'" >&2; usage ;;
  esac
done

[ -n "$FROM" ] && [ -n "$TO" ] || usage
for d in "$FROM" "$TO"; do
  case "$d" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
    *) echo "session-time.sh: dates must be YYYY-MM-DD (got '$d')" >&2; exit 64 ;;
  esac
done
[ -d "$STORE" ] || { echo "session-time.sh: no session store at $STORE — nothing to measure" >&2; exit 66; }

TMP=$(mktemp -d) || exit 70
trap 'rm -rf "$TMP"' EXIT

# Resolve requested repos to their git toplevel, so a path inside a repo still
# matches the cwd a session recorded.
: > "$TMP/repos.txt"
for r in "${REPOS[@]:-}"; do
  [ -n "$r" ] || continue
  top=$(git -C "$r" rev-parse --show-toplevel 2>/dev/null) || top="$r"
  printf '%s\n' "$top" >> "$TMP/repos.txt"
done
[ -n "${MAP:-}" ] && [ -f "$MAP" ] && cp "$MAP" "$TMP/map.json"

python3 - "$STORE" "$FROM" "$TO" "$TMP" "$GAP_MIN" "$LEADIN_MIN" "$ROUND" "$MAX_BLOCK_HOURS" \
  > "$TMP/out.json" <<'PY'
import json, sys, io, os, glob, datetime, collections, subprocess

STORE, FROM, TO, TMP = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
GAP   = datetime.timedelta(minutes=float(sys.argv[5]))
LEAD  = float(sys.argv[6]) / 60.0
ROUND = float(sys.argv[7])
MAXB  = float(sys.argv[8])

d_from = datetime.date.fromisoformat(FROM)
d_to   = datetime.date.fromisoformat(TO)
t_from = datetime.datetime.combine(d_from, datetime.time.min, datetime.timezone.utc)
t_to   = datetime.datetime.combine(d_to + datetime.timedelta(days=1), datetime.time.min, datetime.timezone.utc)

def rnd(h):
    v = round(h / ROUND) * ROUND
    return round(max(v, ROUND), 2)

wanted = []
p = os.path.join(TMP, 'repos.txt')
if os.path.exists(p):
    with io.open(p, encoding='utf-8') as fh:
        wanted = [l.strip() for l in fh if l.strip()]

# The map lets a clone group collapse to one entry, so a session opened in a
# site clone lands on the same project as one opened in the standalone checkout.
clone_of, slug_of, pid_of = {}, {}, {}
mp = os.path.join(TMP, 'map.json')
if os.path.exists(mp):
    with io.open(mp, encoding='utf-8') as fh:
        try: mapdoc = json.load(fh)
        except Exception: mapdoc = {}
    for e in (mapdoc.get('entries') or []):
        repos = e.get('repos') or []
        canon = repos[0] if repos else None
        for r in repos:
            clone_of[r] = canon
            slug_of[r]  = e.get('slug')
            pid_of[r]   = e.get('project_id')

events = collections.defaultdict(list)   # key -> [datetime]
sessions = collections.defaultdict(set)
files_read = files_skipped = lines_bad = 0

for f in glob.glob(os.path.join(STORE, '*', '*.jsonl')):
    # A file's mtime is at least as late as its last event, so anything last
    # touched before the window opened cannot hold an event inside it.
    try:
        if datetime.datetime.fromtimestamp(os.path.getmtime(f), datetime.timezone.utc) < t_from:
            files_skipped += 1
            continue
    except OSError:
        continue
    files_read += 1
    sid = os.path.splitext(os.path.basename(f))[0]
    try:
        fh = io.open(f, encoding='utf-8', errors='replace')
    except OSError:
        continue
    with fh:
        cwd = None
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                o = json.loads(line)
            except Exception:
                lines_bad += 1
                continue
            if not isinstance(o, dict):
                continue
            # cwd is recorded on message lines; hold the last one seen.
            c = o.get('cwd')
            if isinstance(c, str) and c:
                cwd = c
            ts = o.get('timestamp')
            if not (isinstance(ts, str) and cwd):
                continue
            try:
                t = datetime.datetime.fromisoformat(ts.replace('Z', '+00:00'))
            except Exception:
                continue
            if t.tzinfo is None:
                t = t.replace(tzinfo=datetime.timezone.utc)
            if not (t_from <= t < t_to):
                continue
            if wanted and cwd not in wanted:
                continue
            events[cwd].append(t)
            sessions[cwd].add(sid)

# Collapse each cwd to the repository it belongs to BEFORE grouping. A session
# opened in skills/foo/scripts is the same project as one opened in the repo
# root; counted separately they fragment one project into dozens of entries and
# then "overlap" with each other for the same wall clock, which is nonsense.
#
# --git-common-dir is the right canonicaliser rather than --show-toplevel,
# because in a worktree --show-toplevel returns the worktree path while
# --git-common-dir returns the MAIN repo's .git — so worktree sessions fold back
# onto the project they branched from instead of looking like separate work.
_resolved = {}
def repo_root(path):
    if path in _resolved:
        return _resolved[path]
    root, kind = path, 'not-a-repo'
    try:
        out = subprocess.run(['git', '-C', path, 'rev-parse', '--path-format=absolute',
                              '--git-common-dir'],
                             capture_output=True, text=True, timeout=10)
        if out.returncode == 0:
            g = out.stdout.strip()
            if g:
                root = os.path.dirname(g) if os.path.basename(g) == '.git' else g
                kind = 'repo'
    except Exception:
        pass
    _resolved[path] = (root, kind)
    return _resolved[path]

merged_ev = collections.defaultdict(list)
merged_se = collections.defaultdict(set)
fragments = collections.defaultdict(set)
non_repo = set()
for cwd, ts in events.items():
    root, kind = repo_root(cwd)
    if kind == 'not-a-repo':
        non_repo.add(root)
    key = clone_of.get(root, root)
    merged_ev[key].extend(ts)
    merged_se[key] |= sessions[cwd]
    if cwd != key:
        fragments[key].add(cwd)
events, sessions = merged_ev, merged_se

projects = []
all_blocks = []
for key, ts in events.items():
    ts.sort()
    blocks = [[ts[0], ts[0], 1]]
    for t in ts[1:]:
        if t - blocks[-1][1] > GAP:
            blocks.append([t, t, 1])
        else:
            blocks[-1][1] = t
            blocks[-1][2] += 1
    byday = collections.defaultdict(float)
    out_blocks = []
    total = 0.0
    for a, b, n in blocks:
        raw = (b - a).total_seconds() / 3600.0
        h = rnd(raw + LEAD)
        capped = raw > MAXB
        total += h
        byday[a.date().isoformat()] += h
        out_blocks.append({
            'start': a.isoformat(), 'end': b.isoformat(),
            'date': a.date().isoformat(),
            'events': n,
            'span_hours': round(raw, 4),
            'hours': h,
            'over_max_block': capped,
        })
        all_blocks.append((a, b, key))
    projects.append({
        'cwd': key,
        'slug': slug_of.get(key),
        'project_id': pid_of.get(key),
        'sessions': len(sessions[key]),
        'subdirectories_folded_in': len(fragments.get(key, ())),
        'blocks': out_blocks,
        'total_hours': round(total, 2),
        'days': [{'date': d, 'hours': round(v, 2)} for d, v in sorted(byday.items())],
        'day_count': len(byday),
    })

projects.sort(key=lambda x: -x['total_hours'])

# Cross-project overlap: the same wall-clock hour claimed by two working
# directories. Real (you switch between projects), and it means the per-project
# totals cannot simply be added.
overlap_pairs = collections.defaultdict(float)
ab = sorted(all_blocks, key=lambda x: x[0])
for i in range(len(ab)):
    a1, b1, k1 = ab[i]
    for j in range(i + 1, len(ab)):
        a2, b2, k2 = ab[j]
        if a2 >= b1:
            break
        if k1 == k2:
            continue
        ov = (min(b1, b2) - a2).total_seconds() / 3600.0
        if ov > 0:
            overlap_pairs[tuple(sorted((k1, k2)))] += ov

total_hours = round(sum(p['total_hours'] for p in projects), 2)
overlap_total = round(sum(overlap_pairs.values()), 2)

# The union of every block across every project: actual wall clock spent at the
# keyboard. Per-project hours SUM to more than this whenever two projects were
# open in the same stretch, so this is the only figure that cannot exceed
# reality and the only honest headline.
_iv = sorted(((a, b) for a, b, _ in all_blocks))
_merged = []
for a, b in _iv:
    if _merged and a <= _merged[-1][1]:
        if b > _merged[-1][1]:
            _merged[-1][1] = b
    else:
        _merged.append([a, b])
wall_clock = round(sum((b - a).total_seconds() / 3600.0 for a, b in _merged), 2)

warnings = []
if not projects:
    warnings.append("no session events in this window — either nothing was worked in Claude Code, or the "
                    "store lives somewhere else (set CLAUDE_SESSION_STORE)")
if total_hours - wall_clock > 0.01:
    warnings.append("per-project hours sum to %.2fh but only %.2fh of wall clock passed — the difference is "
                    "stretches where more than one project was open. Use wall_clock_hours as the headline "
                    "and treat the per-project split as an attribution question, not arithmetic."
                    % (total_hours, wall_clock))
warnings.append("this measures ATTENTION inside Claude Code, not billable time. Work in an editor, a "
                "browser, WP admin, a meeting or on the phone leaves no session events, so this is a "
                "LOWER bound on real time and must never be presented as the total.")
if overlap_total > 0.01:
    warnings.append("%.2fh of wall clock is claimed by more than one working directory (%s). Per-project "
                    "totals therefore cannot be added — the same hour appears in two of them. Attribute "
                    "overlapping stretches deliberately rather than summing."
                    % (overlap_total, '; '.join('%s <-> %s' % (os.path.basename(a), os.path.basename(b))
                                                for a, b in list(overlap_pairs)[:4])))
big = [b for p in projects for b in p['blocks'] if b['over_max_block']]
if big:
    warnings.append("%d block(s) span more than %gh of continuous events. A long background command or a "
                    "monitor loop looks like attention and is not — check these before trusting them: %s"
                    % (len(big), MAXB, ', '.join('%s (%.2fh)' % (b['date'], b['span_hours']) for b in big[:5])))
folded = sum(p['subdirectories_folded_in'] for p in projects)
if folded:
    warnings.append("%d session working director(ies) were subdirectories or worktrees of a project and "
                    "were folded into their repository root — counting them separately would fragment one "
                    "project into many and double-count the same wall clock." % folded)
if non_repo:
    warnings.append("%d session location(s) are not inside a git repository, so they cannot be attributed "
                    "to a project: %s" % (len(non_repo), ', '.join(sorted(non_repo)[:5])))
unmapped = [p['cwd'] for p in projects if p['slug'] is None]
if unmapped and os.path.exists(mp):
    warnings.append("%d working director(ies) have session time but no project-map entry, so they cannot be "
                    "attributed to an ActiveCollab project: %s"
                    % (len(unmapped), ', '.join(os.path.basename(x) for x in unmapped[:6])))

out = {
    'window': {'from': FROM, 'to': TO},
    'source': {
        'store': STORE,
        'files_read': files_read,
        'files_skipped_by_mtime': files_skipped,
        'unparseable_lines': lines_bad,
        'note': 'grouped on the cwd field inside each file, never on the directory name (the mangling maps '
                '/, . and spaces all to -, so it is not reversible). Sandboxed local-agent-mode-sessions '
                'are excluded: their cwd is a session sandbox, not a repo. Only timestamp and cwd are read '
                '— message content is never parsed.',
    },
    'basis': 'attention blocks from Claude Code session event timestamps, %g-minute gap starts a new block, '
             '+%g-minute lead-in per block, rounded to %gh — the same house rule applied to commits, on a '
             'denser signal. A LOWER bound on real working time.'
             % (GAP.total_seconds() / 60, LEAD * 60, ROUND),
    'totals': {
        'wall_clock_hours': wall_clock,
        'attention_hours': total_hours,
        'projects': len(projects),
        'blocks': sum(len(p['blocks']) for p in projects),
        'days': len({d['date'] for p in projects for d in p['days']}),
        'cross_project_overlap_hours': overlap_total,
        'subdirectories_folded_in': sum(p['subdirectories_folded_in'] for p in projects),
    },
    'projects': projects,
    'warnings': warnings,
}
sys.stdout.write(json.dumps(out, ensure_ascii=False, indent=1))
PY

cat "$TMP/out.json"
[ "$QUIET" = "1" ] && exit 0
{
  jq -r '"session attention  \(.window.from) .. \(.window.to)"' < "$TMP/out.json"
  jq -r '.totals | "  \(.wall_clock_hours)h wall clock across \(.days) day(s); \(.attention_hours)h summed per project over \(.projects) director(ies) (\(.blocks) blocks)"' < "$TMP/out.json"
  jq -r '.source | "  read \(.files_read) session file(s), skipped \(.files_skipped_by_mtime) as older than the window"' < "$TMP/out.json"
  echo "  --- per working directory ---"
  jq -r '.projects[] | "  \(.total_hours)h\t\(.day_count)d\t\(.slug // "unmapped")\t\(.cwd)"' < "$TMP/out.json" \
    | awk -F'\t' '{printf "  %8s %4s  %-18s %s\n", $1,$2,$3,$4}'
  jq -r 'if .totals.cross_project_overlap_hours > 0.01 then "  ! \(.totals.cross_project_overlap_hours)h of wall clock is claimed by two directories — do not add the per-project totals" else empty end' < "$TMP/out.json"
  jq -r '.warnings[] | "  ! \(.)"' < "$TMP/out.json"
} >&2
