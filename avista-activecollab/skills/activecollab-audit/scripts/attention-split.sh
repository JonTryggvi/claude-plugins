#!/usr/bin/env bash
#
# attention-split.sh — the honest arithmetic on top of session-time.sh.
#
#   attention-split.sh --from 2026-08-24 --to 2026-08-24
#   attention-split.sh --from … --to … --map ~/.claude/activecollab-project-map.json
#
# session-time.sh reports per-directory totals. Those OVERLAP — two projects
# open in the same stretch each claim that hour — so they must never be added.
# This script does the two things that make them safe to quote:
#
#   UNION       per date and overall, the wall clock that actually passed.
#               The headline. Never larger than 24h in a day.
#   FAIR-SHARE  each instant divided evenly among the directories open at that
#               moment. The only per-project column that sums back to the union,
#               so it is the one to propose records from.
#
# It also folds by PROJECT ID rather than by map slug, which per-directory
# output cannot do: project 479 is reached by four map entries and 412 by two,
# and counting per-slug is what produced a "204.0h measured / 83.45h missing"
# headline against an authoritative 71.45h logged and a real gap of 16.58h.
#
# Private map entries (personal work) are excluded from the work totals and
# reported separately — never silently dropped, because "where did the other
# hour go" is the first question anyone asks.
#
# Read-only. Reads the session store and the project map; writes nothing.
#
set -uo pipefail
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAP="${AC_PROJECT_MAP:-$HOME/.claude/activecollab-project-map.json}"
FROM=""; TO=""; STORE_ARG=(); SESSIONS_JSON=""

usage() {
  echo "usage: attention-split.sh --from D --to D [--map FILE] [--store DIR] [--sessions FILE]" >&2
  exit 64
}
while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM="${2:?}"; shift 2 ;;
    --to)   TO="${2:?}"; shift 2 ;;
    --map)  MAP="${2:?}"; shift 2 ;;
    --store) STORE_ARG=(--store "${2:?}"); shift 2 ;;
    --sessions) SESSIONS_JSON="${2:?}"; shift 2 ;;   # skip session-time.sh, reuse its output
    -h|--help) usage ;;
    *) echo "attention-split.sh: unknown argument '$1'" >&2; usage ;;
  esac
done
[ -n "$FROM" ] && [ -n "$TO" ] || usage

command -v jq >/dev/null 2>&1 || { echo "attention-split.sh: jq is not installed" >&2; exit 69; }

TMP=$(mktemp -d) || exit 70; trap 'rm -rf "$TMP"' EXIT

# --- get the blocks ----------------------------------------------------------
if [ -n "$SESSIONS_JSON" ]; then
  cp "$SESSIONS_JSON" "$TMP/sessions.json"
else
  ST="$HERE/../../activecollab-reconcile-period/scripts/session-time.sh"
  [ -f "$ST" ] || ST="$HERE/session-time.sh"
  [ -f "$ST" ] || { echo "attention-split.sh: cannot find session-time.sh next to this skill" >&2; exit 69; }
  bash "$ST" --from "$FROM" --to "$TO" --map "$MAP" "${STORE_ARG[@]}" > "$TMP/sessions.json" 2>"$TMP/st.err" || {
    echo "attention-split.sh: session-time.sh failed:" >&2; tail -5 "$TMP/st.err" >&2; exit 65; }
fi

if ! jq -e '.projects | length > 0' < "$TMP/sessions.json" >/dev/null 2>&1; then
  echo "attention-split.sh: the session store yielded NO blocks for $FROM..$TO." >&2
  echo "  An empty store and a genuinely idle window both read as 0.00h — say which this is." >&2
  echo "  Check CLAUDE_SESSION_STORE (default ~/.claude/projects). The Claude desktop app writes" >&2
  echo "  its transcripts there too, so an empty store usually means the window really is idle." >&2
  jq -n --arg f "$FROM" --arg t "$TO" '{window:{from:$f,to:$t},empty_store:true,dates:[],projects:[],totals:{}}'
  exit 0
fi

python3 - "$TMP/sessions.json" "$MAP" "$FROM" "$TO" <<'PY'
import json, sys, os, datetime, collections

HOME = os.path.expanduser("~")
ses  = json.load(open(sys.argv[1]))
try:
    amap = json.load(open(sys.argv[2]))
except Exception:
    amap = {"entries": []}
FROM, TO = sys.argv[3], sys.argv[4]

# slug -> entry, for privacy and project-id folding
by_slug = {e.get("slug"): e for e in amap.get("entries", []) if e.get("slug")}

def parse(t): return datetime.datetime.fromisoformat(t)

def union_hours(ivs):
    if not ivs: return 0.0
    ivs = sorted(ivs); tot = 0.0; cs, ce = ivs[0]
    for s, e in ivs[1:]:
        if s <= ce: ce = max(ce, e)
        else: tot += (ce - cs).total_seconds(); cs, ce = s, e
    return (tot + (ce - cs).total_seconds()) / 3600.0

# ---- collect blocks, tagged with the identity we will fold on ---------------
# Fold key is the PROJECT ID where one exists, so several map entries pointing
# at one project collapse into that project instead of multiplying it.
blocks = []          # (start, end, key, label, is_private, project_id)
private_keys = set()
for p in ses.get("projects", []):
    slug = p.get("slug")
    entry = by_slug.get(slug, {}) if slug else {}
    is_private = bool(entry.get("private"))
    pid = p.get("project_id") or entry.get("project_id")
    if is_private:
        key = f"private:{slug or p['cwd']}"; private_keys.add(key)
    elif pid:
        key = f"pid:{pid}"
    else:
        key = f"unmapped:{p['cwd']}"
    label = slug or p["cwd"].replace(str(HOME), "~")
    for b in p.get("blocks", []):
        blocks.append((parse(b["start"]), parse(b["end"]), key, label, is_private,
                       pid, b.get("date"), bool(b.get("over_max_block")), b.get("events", 0)))

names = {}
for s, e, key, label, priv, pid, d, om, ev in blocks:
    names.setdefault(key, {"label": label, "project_id": pid, "private": priv, "cwds": set()})
    names[key]["cwds"].add(label)

# ---- per date: union (all / work-only) and fair-share per key ---------------
by_date = collections.defaultdict(list)
for b in blocks: by_date[b[6]].append(b)

dates_out = []
share_tot = collections.defaultdict(float)
union_tot = collections.defaultdict(float)
grand_all = grand_work = 0.0

for d in sorted(by_date):
    L = by_date[d]
    pts = sorted({t for b in L for t in (b[0], b[1])})
    share = collections.defaultdict(float)
    union = collections.defaultdict(float)
    day_all = day_work = 0.0
    for a, bnd in zip(pts, pts[1:]):
        live = [b for b in L if b[0] < bnd and b[1] > a]
        if not live: continue
        dur = (bnd - a).total_seconds() / 3600.0
        day_all += dur
        work_live = [b for b in live if not b[4]]
        if work_live: day_work += dur
        for b in {b[2] for b in live}: union[b] += dur
        for b in live: share[b[2]] += dur / len(live)
    for k, v in share.items(): share_tot[k] += v
    for k, v in union.items(): union_tot[k] += v
    grand_all += day_all; grand_work += day_work
    dates_out.append({
        "date": d,
        "union_hours": round(day_all, 2),
        "union_work_hours": round(day_work, 2),
        "union_private_hours": round(day_all - day_work, 2),
        "by_key": {k: {"union": round(union[k], 2), "fair_share": round(share[k], 2),
                       "label": names[k]["label"], "project_id": names[k]["project_id"],
                       "private": names[k]["private"]}
                   for k in sorted(share, key=lambda x: -share[x])},
    })

projects_out = []
for k in sorted(share_tot, key=lambda x: -share_tot[x]):
    n = names[k]
    projects_out.append({
        "key": k, "label": n["label"], "project_id": n["project_id"],
        "private": n["private"], "mapped": k.startswith("pid:"),
        "union_hours": round(union_tot[k], 2),
        "fair_share_hours": round(share_tot[k], 2),
        "cwds": sorted(n["cwds"]),
    })

work = [p for p in projects_out if not p["private"]]
priv = [p for p in projects_out if p["private"]]
unmapped = [p for p in work if not p["mapped"]]
flagged = [{"date": b[6], "label": b[3], "events": b[8]} for b in blocks if b[7]]

warnings = []
warnings.append(
    "UNION is the headline; FAIR_SHARE is the only per-project column that sums back to it. "
    "Per-directory totals from session-time.sh overlap and must never be added — on one real month "
    "they came to 147.0h against 69.82h of wall clock.")
if len(work) != len({p['project_id'] for p in work if p['project_id']}) + len(unmapped):
    warnings.append("several map entries fold onto one project id; that folding is applied here.")
if unmapped:
    warnings.append(
        "%d working director(ies) have no project mapping (%s h fair-share). They are absent from any "
        "reconciliation with no warning — map them or record them private." %
        (len(unmapped), round(sum(p["fair_share_hours"] for p in unmapped), 2)))
if priv:
    warnings.append(
        "%s h of fair-share is private/personal work, excluded from the work totals and listed separately."
        % round(sum(p["fair_share_hours"] for p in priv), 2))
if flagged:
    warnings.append(
        "%d block(s) exceed the max-block guard — a long background command reads as attention but is not "
        "work. Check them before proposing anything." % len(flagged))
warnings.append(
    "This measures ATTENTION inside Claude Code only. Browser, WP admin, DK, phone and meetings leave no "
    "events, so every figure here is a LOWER BOUND and must never be presented as the window's total.")

print(json.dumps({
    "window": {"from": FROM, "to": TO},
    "totals": {
        "union_hours": round(grand_all, 2),
        "union_work_hours": round(grand_work, 2),
        "union_private_hours": round(grand_all - grand_work, 2),
        "fair_share_work_hours": round(sum(p["fair_share_hours"] for p in work), 2),
        "fair_share_private_hours": round(sum(p["fair_share_hours"] for p in priv), 2),
        "days": len(dates_out),
        "unmapped_directories": len(unmapped),
    },
    "projects": work, "private": priv, "unmapped": unmapped,
    "over_max_blocks": flagged,
    "dates": dates_out,
    "warnings": warnings,
}, ensure_ascii=False, indent=1))
PY
