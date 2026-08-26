#!/usr/bin/env bash
#
# resolve-window.sh — turn "yesterday" / "week" / "period" into a dated window,
# and say where every date came from.
#
#   resolve-window.sh yesterday
#   resolve-window.sh week [--trailing]
#   resolve-window.sh period
#   resolve-window.sh --from 2026-08-01 --to 2026-08-31
#
# JSON on stdout, a human summary on stderr. Reads nothing but the run log and
# the calendar; writes nothing.
#
# WHY `period` IS NOT ARITHMETIC
#
# The nominal billing boundary is the 19th, moved to the next working day when
# it lands on a weekend. That rule does NOT reproduce the periods actually
# worked: 2026-07-21..2026-08-21 ran 21st-to-21st even though 19 Jul was a
# Sunday (rule says the 20th) and 19 Aug was a Wednesday (rule says the 19th).
# The boundary slips because the period is cut when someone gets to it.
#
# So the END is only ever a PROPOSAL — three candidates, for a human to pick.
# The START is not a proposal: it is the day after the previous period ended,
# read from the run log, because that is the only thing that guarantees
# consecutive periods neither overlap nor leave a gap.
#
# WHICH RUNS COUNT AS PERIODS
#
# run-log.sh entries carry no `kind` field, so "the most recent run" is
# ambiguous — a one-day audit logged today has a LATER window end than a period
# audit appended eight minutes after it. Resolving a period start from the wrong
# one silently drops days at the boundary. Verified 2026-08-25: the log held a
# 2026-08-24..2026-08-24 day audit and a 2026-07-21..2026-08-21 period run;
# naive max-by-window-end would have started the next period on 2026-08-25 and
# lost 22-23 August.
#
# So a run counts as a period only if it says so (`kind: "period"`, which this
# skill writes) or, for entries predating that field, if its window spans
# MIN_PERIOD_DAYS or more.
#
set -uo pipefail
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

RUN_LOG="${AC_RUN_LOG:-$HOME/.claude/activecollab-runs.jsonl}"
MIN_PERIOD_DAYS="${AC_MIN_PERIOD_DAYS:-21}"
NOMINAL_DAY="${AC_PERIOD_DAY:-19}"
LATEST_DAY="${AC_PERIOD_LATEST_DAY:-21}"

MODE=""; FROM=""; TO=""; TRAILING=0; TODAY_OVERRIDE=""

usage() {
  echo "usage: resolve-window.sh yesterday|week|period [--trailing] [--from D --to D] [--today D]" >&2
  exit 64
}

while [ $# -gt 0 ]; do
  case "$1" in
    yesterday|week|period) MODE="$1"; shift ;;
    --trailing) TRAILING=1; shift ;;
    --from) FROM="${2:?--from needs a date}"; shift 2 ;;
    --to)   TO="${2:?--to needs a date}"; shift 2 ;;
    --today) TODAY_OVERRIDE="${2:?--today needs a date}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "resolve-window.sh: unknown argument '$1'" >&2; usage ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "resolve-window.sh: jq is not installed" >&2; exit 69; }

if [ -n "$FROM" ] && [ -n "$TO" ]; then MODE="explicit"; fi
[ -n "$MODE" ] || usage

TODAY="${TODAY_OVERRIDE:-$(date '+%Y-%m-%d')}"

# --- date helpers (BSD date; these Macs are the only target) ------------------
#
# NOTE the sign normalisation. BSD `date -v` needs an explicit + on forward
# offsets: `-v2d` does NOT mean "add two days", it means "set day-of-month to 2",
# silently and with exit 0. That turned a proposed 2026-09-21 boundary into
# 2026-09-02 and a 2026-08-22 period start into 2026-08-01 — both plausible
# dates, neither flagged. Always pass the sign.
d_add() {
  local off="$2"
  case "$off" in +*|-*) ;; *) off="+$off" ;; esac
  date -j -v"${off}d" -f '%Y-%m-%d' "$1" '+%Y-%m-%d' 2>/dev/null
}
d_dow() { date -j -f '%Y-%m-%d' "$1" '+%a' 2>/dev/null; }
d_epoch() { date -j -f '%Y-%m-%d' "$1" '+%s' 2>/dev/null; }
d_span() {  # inclusive day count between two dates
  local a b; a=$(d_epoch "$1"); b=$(d_epoch "$2")
  [ -n "$a" ] && [ -n "$b" ] || { echo 0; return; }
  echo $(( (b - a) / 86400 + 1 ))
}
d_valid() { date -j -f '%Y-%m-%d' "$1" '+%Y-%m-%d' >/dev/null 2>&1; }

for d in "$TODAY" ${FROM:+$FROM} ${TO:+$TO}; do
  d_valid "$d" || { echo "resolve-window.sh: '$d' is not a YYYY-MM-DD date" >&2; exit 64; }
done

NOTES=(); ALTS='[]'

# --- resolve ------------------------------------------------------------------
case "$MODE" in
  explicit)
    [ "$(d_epoch "$FROM")" -le "$(d_epoch "$TO")" ] || {
      echo "resolve-window.sh: --from is after --to" >&2; exit 64; }
    START_SRC="explicit"; END_SRC="explicit"
    ;;

  yesterday)
    FROM=$(d_add "$TODAY" -1); TO="$FROM"
    START_SRC="calendar"; END_SRC="calendar"
    ;;

  week)
    if [ "$TRAILING" = "1" ]; then
      TO=$(d_add "$TODAY" -1); FROM=$(d_add "$TO" -6)
      START_SRC="trailing-7"; END_SRC="trailing-7"
      NOTES+=("trailing 7 days ending yesterday, not a calendar week")
    else
      # previous complete Mon-Sun
      back=1
      while [ "$(d_dow "$(d_add "$TODAY" -$back)")" != "Sun" ]; do
        back=$((back+1))
        [ "$back" -gt 14 ] && break
      done
      TO=$(d_add "$TODAY" -$back); FROM=$(d_add "$TO" -6)
      START_SRC="iso-week"; END_SRC="iso-week"
      NOTES+=("previous complete Mon-Sun week; pass --trailing for the last 7 days instead")
    fi
    ;;

  period)
    # ---- START: the day after the last PERIOD run, never computed if one exists
    PREV_END=""; PREV_AT=""
    if [ -s "$RUN_LOG" ]; then
      PREV=$(jq -rs --argjson min "$MIN_PERIOD_DAYS" '
        [ .[]
          | select(.window.from and .window.to)
          | . + {span: (((.window.to | strptime("%Y-%m-%d") | mktime)
                        - (.window.from | strptime("%Y-%m-%d") | mktime)) / 86400 + 1)}
          | select((.kind == "period") or ((.kind == null) and (.span >= $min)))
        ]
        | sort_by(.window.to)
        | last
        | if . == null then "" else "\(.window.to)\t\(.at // "")" end
      ' < "$RUN_LOG" 2>/dev/null)
      PREV_END=$(printf '%s' "$PREV" | cut -f1)
      PREV_AT=$(printf '%s' "$PREV" | cut -f2)
    fi

    if [ -n "$PREV_END" ] && d_valid "$PREV_END"; then
      FROM=$(d_add "$PREV_END" 1)
      START_SRC="run-log"
      NOTES+=("start continues the period run that ended $PREV_END (logged $PREV_AT)")
    else
      # no prior period run: fall back one nominal boundary, and SAY it is inferred
      cur_month=${TODAY%-*}
      prev_month=$(d_add "${cur_month}-01" -1); prev_month=${prev_month%-*}
      FROM=$(d_add "${prev_month}-$(printf '%02d' "$NOMINAL_DAY")" 1)
      START_SRC="inferred"
      NOTES+=("NO PRIOR PERIOD RUN IN THE LOG — the start is INFERRED from the ${NOMINAL_DAY}th boundary, not known. Confirm it before trusting any total.")
    fi

    # ---- END: propose the nominal boundary, weekend-shifted, capped
    m=${TODAY%-*}
    nominal="${m}-$(printf '%02d' "$NOMINAL_DAY")"
    case "$(d_dow "$nominal")" in
      Sat) shifted=$(d_add "$nominal" 2); why="19th is a Saturday; cut moves to Monday" ;;
      Sun) shifted=$(d_add "$nominal" 1); why="19th is a Sunday; cut moves to Monday" ;;
      *)   shifted="$nominal";            why="19th is a $(d_dow "$nominal"); no weekend shift" ;;
    esac
    cap="${m}-$(printf '%02d' "$LATEST_DAY")"
    [ "$(d_epoch "$shifted")" -gt "$(d_epoch "$cap")" ] && shifted="$cap"

    TO="$shifted"; END_SRC="proposed"

    ALTS=$(jq -n --arg a "$shifted" --arg b "$nominal" --arg c "$cap" --arg why "$why" '
      [ {date: $a, label: "recommended", why: $why},
        {date: $b, label: "nominal",     why: "the 19th itself, ignoring any weekend shift"},
        {date: $c, label: "latest",      why: "the 21st — where the last two periods actually landed, because the cut slips to when someone gets to it"} ]
      # dedupe, then put the recommended one back on top: the selection card
      # convention is recommended-first, and unique_by re-sorts by date.
      | unique_by(.date)
      | sort_by(.label != "recommended")')
    NOTES+=("the END is a PROPOSAL. The 19th-plus-weekend rule does not reproduce the periods actually worked (2026-07-21..2026-08-21 ran 21st-to-21st against a rule saying 20th and 19th). Offer the alternatives and let a human pick.")
    ;;
esac

SPAN=$(d_span "$FROM" "$TO")

# --- overlap check against every prior run -----------------------------------
OVERLAPS='[]'
if [ -s "$RUN_LOG" ]; then
  OVERLAPS=$(jq -rs --arg f "$FROM" --arg t "$TO" '
    [ .[] | select(.window.from and .window.to)
      | select((.window.from <= $t) and (.window.to >= $f))
      | {from: .window.from, to: .window.to, at: .at, kind: (.kind // "unlabelled"),
         records: (.records_posted // (.record_ids | length) // 0), note: (.note // "")} ]
  ' < "$RUN_LOG" 2>/dev/null || echo '[]')
fi

jq -n \
  --arg mode "$MODE" --arg from "$FROM" --arg to "$TO" --arg today "$TODAY" \
  --arg ss "$START_SRC" --arg es "$END_SRC" --argjson span "$SPAN" \
  --argjson alts "$ALTS" --argjson overlaps "$OVERLAPS" \
  --args '
  {mode: $mode,
   window: {from: $from, to: $to, days: $span},
   today: $today,
   provenance: {start: $ss, end: $es},
   end_alternatives: $alts,
   overlapping_runs: $overlaps,
   needs_confirmation: (($es == "proposed") or ($ss == "inferred") or (($overlaps | length) > 0)),
   notes: $ARGS.positional}' "${NOTES[@]}"

{
  echo "window  $FROM .. $TO  ($SPAN day(s), mode=$MODE)"
  echo "  start: $START_SRC     end: $END_SRC"
  for n in "${NOTES[@]}"; do echo "  - $n"; done
  n_over=$(printf '%s' "$OVERLAPS" | jq 'length')
  if [ "${n_over:-0}" -gt 0 ]; then
    echo "  ! this window OVERLAPS $n_over prior run(s):"
    printf '%s' "$OVERLAPS" | jq -r '.[] | "      \(.from)..\(.to)  \(.kind)  \(.records) record(s)  \(.note)"'
    echo "  ! a run already covered part of this window. Read what it posted before proposing anything."
  fi
} >&2
