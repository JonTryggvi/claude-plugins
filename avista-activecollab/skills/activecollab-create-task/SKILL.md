---
name: activecollab-create-task
description: Create a task in Avista's ActiveCollab and assign it to a colleague — resolves the project, assignee, and task list from names to IDs, sets an estimate, due date, and labels, then creates it only after showing the user exactly what will be posted. Use when the user says "create a task in ActiveCollab", "add a task for <person>", "assign this to <person> in ActiveCollab", "make an AC task", "add this to the <project> project", "log this as a task", "set an estimate on that task", or describes work that should become a ticket. Also handles updating an existing task's assignee, estimate, or due date. Writes into a shared system other people see, so it never posts without explicit approval.
---

# Create an ActiveCollab task

Turns a described piece of work into a task on `active.avista.is`, assigned to a real person.

Requires `activecollab-setup`. If `ac` reports *not configured*, stop and point the user at that skill.

**This writes into a project your colleagues — and on client projects, clients — can see.** Resolve
everything to IDs first, show the user the exact payload, and only then POST. Never guess an assignee.

## Two rules that will bite you

**1. Always write the JSON payload to a file. Never inline it.** The shell here runs under `LC_CTYPE="C"`,
so any multibyte character in an inline argument throws `character not in range` — and Icelandic task
names are full of them (`þ ý ð æ ö á í`). Worse, a mangled call can still reach the API and create a
partial task before the error surfaces. Use the Write tool to create the payload, then:

```bash
ac POST /projects/479/tasks "$(cat /path/to/payload.json)"
```

From a file, UTF-8 round-trips perfectly (`þýðingar` → `þýðingar` → `þýðingar`).

**2. `estimate` requires `job_type_id`.** Sending an estimate without one fails with
`"Job type is required for tasks with estimates"`. Get the job type in the same breath as the estimate —
`ac GET /job-types` lists them, and note that **more than one can be flagged `is_default`** (both `Design`
and `Programming` are), so never auto-pick.

## Step 1 — Resolve the project

```bash
ac GETALL /projects | jq -r '.[] | "\(.id)\t\(.name)"' | sort -k2
```

Use `GETALL`, not `GET`. ActiveCollab caps `/projects` at 100 per page and Avista has 213, so a plain
`GET` silently returns the first hundred — and the project you want is often not in it.

If two projects could plausibly match, **ask**. Posting into the wrong client's project is visible to that
client. If the user gave a numeric ID, trust it but echo the project name back so a typo is caught.

## Step 2 — Resolve the assignee

```bash
ac GET /users | jq -r '.[] | select(.is_archived != true) | "\(.id)\t\(.display_name)\t\(.email)\t[\(.class)]"'
```

- **`class` matters.** `Client` users are external. Assigning to a Client is occasionally correct and
  usually a mistake — if the resolved person is a Client, say so and confirm.
- **Match on the full `display_name`**, not a first-name substring; several people share first names.

The assignee must be a project member. The membership endpoint is `/members` (there is no `/people`), and
it returns an **array of bare user IDs** — not objects:

```bash
ids=$(ac GET /projects/479/members)          # e.g. [2,3,6,21]
ac GET /users | jq -r --argjson m "$ids" '.[] | select(.id as $i | $m | index($i)) | "\(.id)\t\(.display_name)"'
```

## Step 3 — Pick a task list (optional but usually wanted)

The project's tasks endpoint already carries its task lists, so one call covers both:

```bash
ac GET /projects/<project-id>/tasks | jq -r '.task_lists[] | "\(.id)\t\(.name)"'
```

This endpoint returns an **object** (`.tasks`, `.task_lists`, `.project`, …), not an array — `GETALL` will
refuse it and a bare `.[]` will not work. Task lists are per-project; a list ID from another project is
silently wrong.

Omitting `task_list_id` drops the task into the project's default list.

## Step 4 — Build the payload and get approval

`POST /projects/<project-id>/tasks`

| Field | Type | Notes |
|---|---|---|
| `name` | string | **Required.** |
| `body` | string | Description. HTML accepted. |
| `assignee_id` | integer | Step 2. Notifies that person. |
| `task_list_id` | integer | Step 3. |
| `estimate` | decimal | Hours, e.g. `2.5`. **Requires `job_type_id`.** A *plan*, not logged time. |
| `job_type_id` | integer | Which rate the estimate is against. |
| `due_on` | date | `YYYY-MM-DD`. Also sets `start_on` to the same date if you omit it. |
| `start_on` | date | `YYYY-MM-DD`. |
| `is_important` | boolean | |
| `labels` | array | Label **names**, e.g. `["NEW"]`. `ac GET /labels` lists them (they have `id` and `name` only — no `type` field on this instance). |

Show the resolved values in plain language before posting — names, not just IDs:

```
Project  : Avista Core - Plugin Development Overview (479)
Assignee : Daniella Casanas (21)  [Owner]
List     : Avista Core (1082)
Name     : Fix the checkout total rounding
Estimate : 2.5h  (job type: Programming)
Due      : 2026-08-22
```

Wait for explicit approval, then write the payload file and post. **The response is wrapped in
`single`** — the task is at `.single`, not the top level:

```bash
ac POST /projects/479/tasks "$(cat payload.json)" \
  | jq -r '"created #\(.single.task_number) (id \(.single.id)): \(.single.name)"'
```

## Step 5 — Confirm and hand back a link

```
https://active.avista.is/projects/<project-id>/tasks/<task-number>
```

The URL uses `task_number` (small, per-project); the API uses `id` (global). They are different numbers
and mixing them up sends the user to an unrelated task.

## Updating an existing task

Same field names, `PUT`, same `single` wrapper:

```bash
ac PUT /projects/479/tasks/13375 "$(cat payload.json)" | jq -r '.single.estimate'
```

Reassigning notifies the new assignee — confirm before doing it.

## Deleting

```bash
ac DELETE /projects/479/tasks/<id> | jq -r '.single.is_trashed'
```

This is a **soft delete** — the task moves to the project trash (it appears in `.trashed_task_ids`) and
stays recoverable from the UI. Purging permanently is a UI action.

## Estimates vs logged time

`estimate` is a plan. Actual hours are **time records**, a different endpoint — see
`activecollab-log-time`. If the user says "set the time to 3 hours", clarify which they mean; only time
records reach invoicing.

## Failure modes

| Symptom | Cause |
|---|---|
| `character not in range`, then a stray task appears | Multibyte characters inline. Use a payload file (top of this skill). |
| `Job type is required for tasks with estimates` | `estimate` sent without `job_type_id`. |
| HTTP 401 | Token dead — re-run `activecollab-setup`. |
| `Failed to match 'projects/N/people' path` | Wrong endpoint; membership is `/members`. |
| Validation error on `assignee_id` | Not a member of the project (step 2). |
| `jq` returns null for `.id` | The response is wrapped — read `.single.id`. |
