#!/usr/bin/env bash
#
# post-and-verify.sh — pre-flight a time record against the project's billing
# settings, then (on --post) write it and diff what was SENT against what the
# platform actually STORED.
#
#   post-and-verify.sh --project 154 --payload rec.json            # pre-flight only
#   post-and-verify.sh --project 154 --payload rec.json --post     # write, then verify
#   post-and-verify.sh --project 154 --payload rec.json --map ~/.claude/activecollab-project-map.json
#
# Writing requires --post. Pre-flight is the default because this touches a real
# timesheet, and an accidental invocation should not be able to create a record.
#
# WHY A DIFF, AND NOT JUST A POST
#
# ActiveCollab silently overrides fields on write. A project whose `budget_type`
# is `not_billable` stores `billable_status: 0` no matter what you send: HTTP
# 200, no validation error, nothing in the response to say it happened.
# Confirmed on 9 records posted to Avista Connect (154), every one of which
# reads back as non-billable. The work was real and billable and it is now on a
# timesheet as neither.
#
# The trap is that `is_billable` is NOT the mechanism, so a guard written
# against it passes and proves nothing. Verified on the live instance:
#
#   project 154 Avista Connect    is_billable=false  budget_type=not_billable   -> stores 0 always
#   project 428 Avista Commerce   is_billable=false  budget_type=pay_as_you_go  -> stores 1 fine
#   project 489 Fraktlausnir.is   is_billable=true   budget_type=pay_as_you_go  -> stores 1 fine
#
# 428 has the same `is_billable` as 154 and behaves like 489. `budget_type` is
# what predicts the coercion.
#
# So: check budget_type BEFORE posting and say plainly what will happen, then
# re-read afterwards and diff. The only authority on what was written is what
# comes back — reporting the payload you sent as though it were the outcome is
# how a non-billable record gets described as billable to the person invoicing.
#
set -uo pipefail
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

AC="${AC_BIN:-$HOME/.claude/bin/ac}"
PROJECT=""; PAYLOAD=""; MAP="${AC_PROJECT_MAP:-$HOME/.claude/activecollab-project-map.json}"; DO_POST=0; QUIET=0

usage() {
  cat >&2 <<'EOT'
usage: post-and-verify.sh --project ID --payload FILE [--map FILE] [--post] [--quiet]

  (default)  pre-flight only: reports what the platform will override. Writes nothing.
  --post     actually create the record, then re-read it and diff sent vs stored.

The payload is a file, never an inline argument: summaries are full of Icelandic
characters and a mangled inline call can still reach the API and write a partial
record before the error surfaces.
EOT
  exit 64
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:-}"; shift 2 ;;
    --payload) PAYLOAD="${2:-}"; shift 2 ;;
    --map)     MAP="${2:-}"; shift 2 ;;
    --post)    DO_POST=1; shift ;;
    --quiet)   QUIET=1; shift ;;
    -h|--help) usage ;;
    *) echo "post-and-verify.sh: unknown argument '$1'" >&2; usage ;;
  esac
done

[ -n "$PROJECT" ] && [ -n "$PAYLOAD" ] || usage
[ -f "$PAYLOAD" ] || { echo "post-and-verify.sh: no such payload file: $PAYLOAD" >&2; exit 66; }
jq -e '.' < "$PAYLOAD" >/dev/null 2>&1 || { echo "post-and-verify.sh: $PAYLOAD is not valid JSON" >&2; exit 65; }
[ -x "$AC" ] || { echo "post-and-verify.sh: no ac client at $AC — run activecollab-setup" >&2; exit 69; }

TMP=$(mktemp -d) || exit 70
trap 'rm -rf "$TMP"' EXIT

# budget_type: prefer the map's cache (the write path already has the answer and
# historically did not use it), fall back to the API, and say which was used.
BT=""; BT_SRC="none"
if [ -f "$MAP" ]; then
  BT=$(jq -r --argjson p "$PROJECT" 'first(.entries[]? | select(.project_id == $p) | .budget_type // empty) // empty' < "$MAP" 2>/dev/null || true)
  [ -n "$BT" ] && BT_SRC="project-map cache"
fi
# Fetch the project when the cache misses, and also for its name, so the
# pre-flight can say "154 Avista Connect" rather than a bare id.
echo '{}' > "$TMP/proj.json"
if "$AC" GET "/projects/$PROJECT" > "$TMP/proj.json" 2>/dev/null; then :; else echo '{}' > "$TMP/proj.json"; fi
if [ -z "$BT" ]; then
  BT=$(jq -r '(.single // .) | .budget_type // empty' < "$TMP/proj.json" 2>/dev/null || true)
  [ -n "$BT" ] && BT_SRC="live GET /projects/$PROJECT"
fi
PNAME=$(jq -r '(.single // .) | .name // empty' < "$TMP/proj.json" 2>/dev/null || true)
# A cached budget_type that disagrees with the live one is worse than no cache:
# it predicts the wrong outcome confidently. Check, and prefer live.
if [ "$BT_SRC" = "project-map cache" ]; then
  LIVE_BT=$(jq -r '(.single // .) | .budget_type // empty' < "$TMP/proj.json" 2>/dev/null || true)
  if [ -n "$LIVE_BT" ] && [ "$LIVE_BT" != "$BT" ]; then
    echo "post-and-verify.sh: the project map says budget_type=$BT but the live project says $LIVE_BT — using live, and the map needs \`project-map.sh validate\`" >&2
    BT="$LIVE_BT"; BT_SRC="live GET /projects/$PROJECT (map cache was stale: was $BT)"
  fi
fi

jq -n --slurpfile pl "$PAYLOAD" --arg bt "$BT" --arg src "$BT_SRC" \
      --arg pid "$PROJECT" --arg pname "$PNAME" --argjson post "$DO_POST" '
  ($pl[0]) as $p
  | ($p.billable_status // null) as $bs
  | {
      project: {id: ($pid|tonumber), name: (if $pname == "" then null else $pname end),
                budget_type: (if $bt == "" then null else $bt end), budget_type_source: $src},
      sending: {value: $p.value, record_date: $p.record_date, user_id: $p.user_id,
                job_type_id: $p.job_type_id, task_id: $p.task_id,
                billable_status: $bs, summary: ($p.summary // null)},
      preflight: {
        will_coerce_billable: (($bt == "not_billable") and ($bs != null) and ($bs != 0)),
        billable_status_unknown: ($bs == null),
        budget_type_unknown: ($bt == ""),
        notes: ([]
          + (if ($bt == "not_billable") and ($bs != null) and ($bs != 0)
             then ["project \($pid)\(if $pname != "" then " " + $pname else "" end) is budget_type=not_billable: billable_status \($bs) WILL be stored as 0. The record still lands, the hours are still tracked, but it will not reach an invoice. Say this before posting, not after."]
             else [] end)
          + (if $bt == "not_billable" and $bs == 0
             then ["project is not_billable and billable_status 0 is being sent — consistent, nothing will be overridden"]
             else [] end)
          + (if $bs == null
             then ["no billable_status in the payload: the API defaults it to billable when task_id is set and non-billable otherwise, so the outcome depends on a field you did not state. Set it explicitly."]
             else [] end)
          + (if $bt == "" then ["budget_type could not be determined for project \($pid) — pre-flight cannot predict coercion, so the post-write diff is the only check left"] else [] end))
      },
      posted: (if $post == 1 then null else false end)
    }' > "$TMP/pre.json"

if [ "$DO_POST" != "1" ]; then
  cat "$TMP/pre.json"
  [ "$QUIET" = "1" ] && exit 0
  {
    jq -r '"pre-flight  project \(.project.id)\(if .project.name then " " + .project.name else "" end)  budget_type=\(.project.budget_type // "unknown") (\(.project.budget_type_source))"' < "$TMP/pre.json"
    jq -r '.sending | "  sending: \(.value)h on \(.record_date)  billable_status=\(.billable_status // "unset")  job_type=\(.job_type_id // "unset")  task=\(.task_id // "none")"' < "$TMP/pre.json"
    jq -r '.preflight.notes[] | "  ! \(.)"' < "$TMP/pre.json"
    echo "  nothing was written — re-run with --post once the user has approved"
  } >&2
  exit 0
fi

# --- write ------------------------------------------------------------------
"$AC" POST "/projects/$PROJECT/time-records" "$(cat "$PAYLOAD")" > "$TMP/resp.json" 2>"$TMP/resp.err" || {
  echo "post-and-verify.sh: the POST failed — nothing to verify" >&2
  head -c 400 "$TMP/resp.err" >&2; echo >&2
  head -c 400 "$TMP/resp.json" >&2; echo >&2
  exit 65; }
jq -e '(.single // .) | has("id")' < "$TMP/resp.json" >/dev/null 2>&1 || {
  echo "post-and-verify.sh: the POST returned no record id — check whether anything was created before retrying" >&2
  head -c 400 "$TMP/resp.json" >&2; echo >&2; exit 65; }

RID=$(jq -r '(.single // .) | .id' < "$TMP/resp.json")

# Re-read rather than trusting the POST echo. Both are checked: a field the POST
# response already disagrees with tells you the platform overrode it on write,
# and the fresh read confirms what is actually stored now.
"$AC" GET "/projects/$PROJECT/time-records/$RID" > "$TMP/read.json" 2>/dev/null || cp "$TMP/resp.json" "$TMP/read.json"

jq -n --slurpfile pre "$TMP/pre.json" --slurpfile resp "$TMP/resp.json" --slurpfile read "$TMP/read.json" \
      --arg rid "$RID" '
  ($pre[0]) as $P
  | (($read[0].single // $read[0])) as $r
  | (($resp[0].single // $resp[0])) as $w
  | ($P.sending) as $sent
  | ($r.record_date | if type=="number" then (.|todate[:10]) else (.|tostring[:10]) end) as $stored_date
  | (if $r.parent_type == "Task" then $r.parent_id else null end) as $stored_task
  | [
      {field:"value",           sent:$sent.value,           stored:$r.value},
      {field:"record_date",     sent:$sent.record_date,     stored:$stored_date},
      {field:"user_id",         sent:$sent.user_id,         stored:$r.user_id},
      {field:"job_type_id",     sent:$sent.job_type_id,     stored:$r.job_type_id},
      {field:"task_id",         sent:$sent.task_id,         stored:$stored_task},
      {field:"billable_status", sent:$sent.billable_status, stored:$r.billable_status},
      {field:"summary",         sent:$sent.summary,         stored:$r.summary}
    ] as $rows
  | ($rows | map(select(.sent != null and ((.sent|tostring) != (.stored|tostring))))) as $diff
  | {
      record: {id: ($rid|tonumber), project_id: $r.project_id,
               invoiced: (($r.invoice_item_id // 0) != 0), is_trashed: ($r.is_trashed // false)},
      project: $P.project,
      preflight: $P.preflight,
      posted: true,
      fields: $rows,
      overridden: $diff,
      verified: (($diff | length) == 0),
      warnings: ([]
        + (if ($diff | map(select(.field == "billable_status")) | length) > 0
           then ["billable_status was sent as \($sent.billable_status) and STORED as \($r.billable_status). \(if $P.project.budget_type == "not_billable" then "The project is budget_type=not_billable, which coerces it — this is an override, not an error." else "The project is not not_billable, so something else changed it; do not assume the value you sent." end) Report the stored value, never the sent one."]
           else [] end)
        + (if ($diff | map(select(.field == "record_date")) | length) > 0
           then ["record_date was sent as \($sent.record_date) and stored as \($stored_date) — a record on the wrong day is wrong on a timesheet even when the total matches"] else [] end)
        + (if ($diff | map(select(.field == "value")) | length) > 0
           then ["value was sent as \($sent.value) and stored as \($r.value)"] else [] end)
        + (if ($diff | map(select(.field == "task_id")) | length) > 0
           then ["task_id was sent as \($sent.task_id) and the record is attached to \($stored_task) — check task_id vs task_number"] else [] end)
        + (if ($diff | length) == 0 then ["every field stored as sent"] else [] end))
    }' > "$TMP/out.json"

cat "$TMP/out.json"
[ "$QUIET" = "1" ] && exit 0
{
  jq -r '"posted record \(.record.id) to project \(.project.id)\(if .project.name then " " + .project.name else "" end)  budget_type=\(.project.budget_type // "unknown")"' < "$TMP/out.json"
  jq -r '.fields[] | select(.sent != null) | "  \(.field): sent \(.sent|tostring) -> stored \(.stored|tostring)" + (if (.sent|tostring) != (.stored|tostring) then "   OVERRIDDEN" else "" end)' < "$TMP/out.json"
  jq -r '.warnings[] | "  ! \(.)"' < "$TMP/out.json"
} >&2
