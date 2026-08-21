---
name: activecollab-log-time
description: Log tracked hours against an ActiveCollab task or project — resolves the project, task, job type and person from names to IDs, then posts the time record only after showing exactly what will be written. Use when the user says "log time in ActiveCollab", "log 2 hours on that task", "track my time", "book hours to <project>", "add a time record", "I spent 3 hours on X", "put that on the timesheet", or wants to correct or delete a record they already logged. Time records feed reporting and invoicing, so this never posts without explicit approval and never invents a duration the user did not state. For reading hours back — per task, project, person or company over a date window — use activecollab-time-audit.
---

# Log time to ActiveCollab

Writes a **time record** — actual tracked hours. Not the same as a task's `estimate`, which is a plan (see
`activecollab-create-task`). Only time records reach reports and invoicing.

Requires `activecollab-setup`. If `ac` reports *not configured*, stop and point the user there.

**Never invent a duration.** If the user has not said how long something took, ask. Do not derive hours
from commit timestamps, session length, or your own sense of how long the work "should" take unless the
user explicitly asks you to estimate from a named source — and then say plainly that it is an estimate.

**Write the JSON payload to a file, never inline.** The shell here runs under `LC_CTYPE="C"`, so multibyte
characters in an inline argument throw `character not in range` — and a mangled call can still reach the
API and write a partial record before the error surfaces. Use the Write tool, then
`ac POST <path> "$(cat payload.json)"`. The same trap bites when *reading*: never capture a response in
`$(...)`, because record summaries are full of Icelandic characters. Redirect to a file.

## Step 1 — Resolve the project (and task, if any)

```bash
ac GETALL /projects | jq -r '.[] | "\(.id)\t\(.name)"' | sort -k2
```

Use `GETALL`. `/projects` caps at 100 per page and Avista has 213, so a plain `GET` hides most of the list.

For a task-level record, find the task. This endpoint returns an **object**, not an array:

```bash
ac GET /projects/<project-id>/tasks | jq -r '.tasks[] | "\(.id)\t#\(.task_number)\t\(.name)"'
```

Use the task's `id` (global) for `task_id`, **not** `task_number` (the small per-project number in the web
URL). They are different numbers, and confusing them files hours against an unrelated task silently.

Completed tasks still accept time records, so finished work is not a blocker.

## Step 2 — Resolve the job type

```bash
ac GET /job-types | jq -r '.[] | "\(.id)\t\(.name)\tdefault=\(.is_default)"'
```

**More than one job type can be flagged `is_default`** — on this instance both `Design` and `Programming`
are. There is no single "the default": never auto-pick. Ask which rate applies, or infer from the project
and confirm out loud.

Job types also carry `default_hourly_rate`. It is there if you need to explain which rate a record will be
billed at — not for turning hours into a revenue figure unasked.

## Step 3 — Resolve the person

```bash
ac GET /users | jq -r '.[] | select(.is_archived != true) | "\(.id)\t\(.display_name)\t\(.email)"'
```

Default to the user's own `user_id` from setup. Logging time **on behalf of someone else** puts hours in
that person's name on a real timesheet — only with an explicit instruction, and confirm the name first.

## Step 4 — Build the payload and get approval

`POST /projects/<project-id>/time-records`

| Field | Type | Required | Notes |
|---|---|---|---|
| `value` | decimal or string | **yes** | Hours. `1.5` or `"1:30"`. |
| `record_date` | date | **yes** | `YYYY-MM-DD`. Only default to today if the user said "today". |
| `user_id` | integer | **yes** | Whose timesheet this lands on. |
| `job_type_id` | integer | **yes** | Step 2. |
| `task_id` | integer | no | Attaches to a task; the record comes back as `parent_type: "Task"`. Omit for project-level. |
| `summary` | string | no | Worth filling in — it is what shows on reports. |
| `billable_status` | integer | no | See below. Defaults to billable when a task is attached, non-billable otherwise. |

### `billable_status` has four values, not two

| Value | Meaning | `invoice_item_id` |
|---|---|---|
| `0` | not billable | `0` |
| `1` | billable, not yet invoiced | `0` |
| `2` | billable, on an invoice | set |
| `3` | billable, on an invoice | set |

Only ever **write** `0` or `1`. `2` and `3` are states the invoicing side puts records into — verified on
this instance, where every `2` and `3` record carried a non-zero `invoice_item_id` and every `0` and `1`
carried zero.

Show the resolved values in plain language, and **call out `billable_status` explicitly** — it is the
field with money attached and its default flips depending on whether a task is set:

```
Project  : Avista Core - Plugin Development Overview (479)
Task     : #23 Fix the checkout total rounding (id 13375)
Person   : Jón Tryggvi Unnarsson (6)
Job type : Programming (1)
Date     : 2026-08-14
Value    : 2.5h   BILLABLE
Summary  : Rounding fix + regression test
```

After approval — note the response is wrapped in `single`:

```bash
ac POST /projects/479/time-records "$(cat payload.json)" \
  | jq -r '"logged \(.single.value)h (record \(.single.id)) on \(.single.parent_type) \(.single.parent_id)"'
```

Log each sitting under its **own** `record_date`. Collapsing four days into one entry is wrong on a
timesheet even when the total matches.

## Reading a record back

Enough to confirm what you just wrote, or to find the record you need to correct. For anything wider — a
date window, a whole project, a person, the company — use `activecollab-time-audit`; **none of the
endpoints below accept a date window**, and the one that does ignores every other filter you give it.

```bash
# everything on a task
ac GET /projects/479/tasks/13375/time-records \
  | jq -r '.time_records[] | "\(.record_date|todate[:10])\t\(.value)h\t\(.user_name)\t\(.summary)"'
# a whole project
ac GET /projects/479/time-records | jq -r '.time_records[] | "\(.record_date|todate[:10])\t\(.value)h"'
# one person across all projects
ac GET /users/6/time-records | jq -r '.time_records[] | "\(.record_date|todate[:10])\t\(.value)h"'
```

All three return an **object** with `.time_records` — not an array — plus a `.related` map keyed by id
carrying the full `Project` and `Task` objects those records point at, so you can print a task name
without a second lookup.

Dates are written as `YYYY-MM-DD` but come back as UNIX timestamps — hence `todate`.

A task's total shows up on the task itself as `tracked_time`, and **only on a direct task fetch** — it is
absent from the `/projects/<id>/tasks` list and from `.related.Task`:

```bash
ac GET /projects/479/tasks/13375 | jq -r '"\(.tracked_time)h tracked, estimate \(.estimate)h"'
```

There is no project-level equivalent. `/projects/<id>` carries `budget` and `is_tracking_enabled` but no
tracked total — a project's hours have to be summed client-side.

## Correcting a record

```bash
ac PUT    /projects/479/time-records/<id> "$(cat payload.json)"
ac DELETE /projects/479/time-records/<id> | jq -r '.single.is_trashed'
```

**Check `invoice_item_id` first.** A non-zero value means the record is already on an invoice, and editing
its hours changes history a client has been billed against:

```bash
ac GET /projects/479/time-records \
  | jq -r '.time_records[] | select(.id==16128) | "invoiced=\(.invoice_item_id != 0) status=\(.billable_status)"'
```

`DELETE` is a **soft delete** — the record is trashed and recoverable from the UI, not purged. Even so it
disappears from reports immediately. **Always confirm before deleting**, and prefer correcting the value
over delete-and-re-add.

## Failure modes

| Symptom | Cause |
|---|---|
| `character not in range`, then a stray record appears | Multibyte characters inline. Use a payload file. |
| `character not in range` while reading | A response was captured in `$(...)`. Redirect to a file. |
| `jq` returns null for `.id` | Response is wrapped — read `.single.id`. |
| `.[]` fails on a time-records read | Those endpoints return an object — use `.time_records[]`. |
| Validation error on `job_type_id` | ID does not exist, or is not enabled for that project. |
| Validation error on `user_id` | That person is not a project member (`ac GET /projects/<id>/members` returns bare user IDs). |
| Time landed on the wrong task | `task_number` passed where `task_id` was wanted (step 1). |
| Record is non-billable unexpectedly | `billable_status` omitted on a project-level record, where it defaults to `0`. |
| A record refuses to look edited | It may be invoiced (`invoice_item_id != 0`) — check before assuming the write failed. |
| A read "for one person" returns everyone | `user_id` was passed to `/time-records?from&to`, which ignores it. See `activecollab-time-audit`. |
