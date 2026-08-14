---
name: activecollab-log-time
description: Log tracked hours against an ActiveCollab task or project — resolves the project, task, job type and person from names to IDs, then posts the time record only after showing exactly what will be written. Use when the user says "log time in ActiveCollab", "log 2 hours on that task", "track my time", "book hours to <project>", "add a time record", "I spent 3 hours on X", "put that on the timesheet", or asks what has already been logged. Time records feed reporting and invoicing, so this never posts without explicit approval and never invents a duration the user did not state.
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
`ac POST <path> "$(cat payload.json)"`.

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

## Step 2 — Resolve the job type

```bash
ac GET /job-types | jq -r '.[] | "\(.id)\t\(.name)\tdefault=\(.is_default)"'
```

**More than one job type can be flagged `is_default`** — on this instance both `Design` and `Programming`
are. There is no single "the default": never auto-pick. Ask which rate applies, or infer from the project
and confirm out loud.

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
| `billable_status` | integer | no | `1` billable, `0` not. Defaults to billable when a task is attached, non-billable otherwise. |

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

## Reading time back

Both of these return an **object** with a `.time_records` key — not an array:

```bash
# everything on a task
ac GET /projects/479/tasks/13375/time-records \
  | jq -r '.time_records[] | "\(.record_date|todate[:10])\t\(.value)h\t\(.summary)"'
# one person across all projects
ac GET /users/6/time-records \
  | jq -r '.time_records[] | "\(.record_date|todate[:10])\t\(.value)h\t\(.summary)"'
```

Dates are written as `YYYY-MM-DD` but come back as UNIX timestamps — hence `todate`.

A task's total shows up on the task itself as `tracked_time` (top level, not under `single`).

## Correcting a record

```bash
ac PUT    /projects/479/time-records/<id> "$(cat payload.json)"
ac DELETE /projects/479/time-records/<id> | jq -r '.single.is_trashed'
```

`DELETE` is a **soft delete** — the record is trashed and recoverable from the UI, not purged. Even so it
disappears from reports immediately, and it may already have been invoiced. **Always confirm before
deleting**, and prefer correcting the value over delete-and-re-add.

## Failure modes

| Symptom | Cause |
|---|---|
| `character not in range`, then a stray record appears | Multibyte characters inline. Use a payload file. |
| `jq` returns null for `.id` | Response is wrapped — read `.single.id`. |
| `.[]` fails on a time-records read | Those endpoints return an object — use `.time_records[]`. |
| Validation error on `job_type_id` | ID does not exist, or is not enabled for that project. |
| Validation error on `user_id` | That person is not a project member (`ac GET /projects/<id>/members` returns bare user IDs). |
| Time landed on the wrong task | `task_number` passed where `task_id` was wanted (step 1). |
| Record is non-billable unexpectedly | `billable_status` omitted on a project-level record, where it defaults to `0`. |
