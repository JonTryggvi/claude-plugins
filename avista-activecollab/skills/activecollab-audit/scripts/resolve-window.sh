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
# WHY `period` IS NOT PURE ARITHMETIC
#
# The billing period ends on the 20th (override with AC_PERIOD_DAY) and the
# next one starts the day after. Two things bend that:
#
# - A weekend 20th may be cut on the Monday instead. So the END is a
#   PROPOSAL: the 20th recommended, the Monday offered beside it.
# - When a cut did slip past the 20th, the next period starts the day after
#   that cut rather than on the 21st, or the slipped days get proposed twice.
#   The run log is the only record of where the last cut actually landed.
#
# The START never moves EARLIER than the 21st, though. It used to be "the day
# after the last period run" in both directions, and that drifted: the
# 2026-09-01..09-13 patch run left 2026-08-22..08-31 covered by no period at
# all, and the next resolve proposed a start of 2026-09-14, burying the hole.
# A previous period that stopped short of the 20th now yields a GAP note.
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
NOMINAL_DAY="${AC_PERIOD_DAY:-20}"

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
    # ---- START: the day after last month's NOMINAL_DAY, or after a cut that slipped past it
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

    # The period ends on the NOMINAL_DAY, so it starts the day after last
    # month's. The run log can move that LATER (the last cut slipped past the
    # boundary, so those days are already posted) but never EARLIER (a short
    # previous period is a GAP to report, not a new boundary to follow).
    cur_month=${TODAY%-*}
    prev_month=$(d_add "${cur_month}-01" -1); prev_month=${prev_month%-*}
    FROM=$(d_add "${prev_month}-$(printf '%02d' "$NOMINAL_DAY")" 1)
    START_SRC="calendar"

    if [ -n "$PREV_END" ] && d_valid "$PREV_END"; then
      expected=$(d_add "$PREV_END" 1)
      if [ "$(d_epoch "$expected")" -lt "$(d_epoch "$FROM")" ]; then
        NOTES+=("GAP: the last period run ended $PREV_END (logged $PREV_AT), so $expected..$(d_add "$FROM" -1) is covered by NO period run. Audit that stretch separately or move the start back.")
      elif [ "$(d_epoch "$expected")" -gt "$(d_epoch "$FROM")" ]; then
        NOTES+=("start moved from $FROM to $expected: the last period run ended $PREV_END (logged $PREV_AT), past the ${NOMINAL_DAY}th, so the days up to it are already posted.")
        [ "$(d_epoch "$expected")" -gt "$(d_epoch "$(d_add "$FROM" 3)")" ] &&
          NOTES+=("CHECK: that is more than a weekend shift past the ${NOMINAL_DAY}th — confirm the previous period really ran to $PREV_END.")
        FROM="$expected"; START_SRC="run-log"
      fi
    else
      NOTES+=("no prior period run in the log; start is the day after last month's ${NOMINAL_DAY}th, with nothing to check it against")
    fi

    # ---- END: the NOMINAL_DAY. A weekend NOMINAL_DAY may be cut on the Monday instead — offer it beside.
    m=${TODAY%-*}
    nominal="${m}-$(printf '%02d' "$NOMINAL_DAY")"
    TO="$nominal"; END_SRC="proposed"
    dayname=$(date -j -f '%Y-%m-%d' "$nominal" '+%A' 2>/dev/null)
    case "$(d_dow "$nominal")" in
      Sat) monday=$(d_add "$nominal" 2) ;;
      Sun) monday=$(d_add "$nominal" 1) ;;
      *)   monday="" ;;
    esac
    ALTS=$(jq -n --arg a "$nominal" --arg b "$monday" --arg dn "$dayname" --arg day "$NOMINAL_DAY" '
      [ {date: $a, label: "recommended", why: ("the period ends on the " + $day + "th (a " + $dn + ")")} ]
      + (if $b == "" then [] else
          [ {date: $b, label: "weekend-shift",
             why: ("the " + $day + "th is a " + $dn + "; if the cut is made on Monday, end there — the next period then starts the day after")} ]
        end)')
    NOTES+=("the END is a PROPOSAL: the ${NOMINAL_DAY}th by default; a weekend ${NOMINAL_DAY}th may be cut on the Monday instead. Offer the alternatives and let a human pick.")
    [ "$(d_epoch "$FROM")" -gt "$(d_epoch "$TO")" ] &&
      NOTES+=("ALREADY COVERED: the last period run ended $PREV_END, after this period's proposed end — there is nothing new to resolve yet.")
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
