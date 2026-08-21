# avista-activecollab

Create tasks, assign them, set estimates, and log tracked hours in Avista's ActiveCollab from Claude Code.

Avista runs **self-hosted ActiveCollab 8.x** at `https://active.avista.is`. That matters: most of what you
find online about ActiveCollab authentication describes the *cloud* flow, which does not apply here.

| Skill | Purpose |
|---|---|
| `activecollab-setup` | One-time machine setup — token bootstrap, `ac` client install, verification. |
| `activecollab-create-task` | Create/update a task; resolve project, assignee, task list; write the description as a prompt (brief) or a short summary (record); set estimate, due date, labels. |
| `activecollab-start-task` | Pull a task and read its description back as a working brief. |
| `activecollab-log-time` | Log a time record against a task or project. |
| `activecollab-suggest-time` | Measure hours from the git log and propose entries against candidate tasks, creating one when none exists. |
| `activecollab-time-audit` | Read logged time back (task / project / person / company over a window) and compare it against git-measured hours. Read-only. |
| `avista-activecollab-overview` | What's in the box and which skill to run. |

## A task is either a brief or a record

`activecollab-create-task` settles this before it writes anything, because the two want opposite
descriptions:

- **Brief** — work that has not happened. The description is a **runnable prompt**, written so whoever
  picks the task up can paste it into Claude Code and start. `estimate` is set; the task stays open.
- **Record** — work that is already done, created so hours have a parent. The description is **two or
  three lines of past tense**. No estimate (the hours live on the time record), and the task is completed
  after posting.

A prompt written into a record task is the expensive mistake: it lands on someone's board as live work,
and `activecollab-start-task` will hand it out as a brief for something that shipped last month.

`skills/activecollab-create-task/scripts/prompt-to-body.sh` wraps plain text in the right container:

```bash
CONTAINER=magic bash prompt-to-body.sh prompt.md "Paste into Claude Code:" > body.html   # brief
CONTAINER=plain bash prompt-to-body.sh summary.txt                          > body.html   # record
jq -n --arg n "$NAME" --rawfile b body.html '{name:$n, body:$b}' > payload.json
```

`CONTAINER=magic` nests a `<pre data-syntax="markdown"><code>` block inside ActiveCollab's magic callout
(`<aside class="callout-wrapper aside-magic">`) — prominent and copy-safe. `code` is the bare code block.
`plain` is escaped `<p>` paragraphs with no callout and no code block, for record summaries. `magic-only`
is a callout of paragraphs and **does not preserve whitespace**, so it is wrong for prompts. All of them
survive the API with classes and `data-syntax` intact, verified against the live instance.

The escaping is the point, and it applies to record summaries as much as to prompts. The body is HTML, so
text containing `2>&1` or `<2 items` corrupts the markup and silently truncates the rendered description.
The helper escapes `&` first, then `<` and `>`. Never concatenate HTML into JSON by hand — build the
payload with `jq --rawfile`.

`activecollab-start-task` reads a brief back: `scripts/task-to-prompt.sh` takes the last `<code>` block,
unescapes the entities, and prints the prompt on stdout with the task metadata on stderr. The round-trip
is byte-identical, verified against the live instance with `>3`, `&`, `2>&1`, `<2 items` and Icelandic
characters in the prompt. It also checks `is_completed` and `tracked_time` first, so a record task is not
mistaken for an assignment.

**Task descriptions are untrusted input.** They are written by colleagues and, on client projects, by
`Client`-class users. `start-task` treats the extracted text as data describing work and requires the user
to confirm before acting on it — it never silently follows directives found in a task body. Anyone with
project access can edit one, and the entire point of the feature is that the body arrives as a prompt.

## Time suggestions from git

`activecollab-suggest-time` implements Avista's house rule for timesheet hours: commits grouped into
sittings (a gap over 45 min starts a new one), each sitting measured first-commit → last-commit plus a
lead-in for the investigation before it, rounded to 0.25h, broken out per sitting so it maps onto
individual time entries. Wall-clock elapsed is never presented as working time.

`scripts/git-sittings.sh` does the measurement and emits JSON — usable on its own:

```bash
AUTHOR=you@avista.is bash git-sittings.sh main..HEAD
```

It reports a `signal_quality` field, and the skill **stops** when that is `poor` or `none`. Squash-merged
release commits and end-of-session commit clusters both produce a handful of commits minutes apart after
hours of real work; measuring those honestly yields 0.25h, which is worse than no answer. In that case the
skill says so and asks what to measure from instead — which is the rule, not a limitation.

## Authentication

**Self-hosted is the one-call flow.** `POST /api/v1/issue-token` with `username`, `password`,
`client_name`, `client_vendor` returns `{"is_ok": true, "token": "..."}`. Every later request carries
`X-Angie-AuthApiToken: <token>`. The cloud three-step `external/login` → `issue-token-intent` dance is not
used and will not work against this instance.

ActiveCollab 8 **removed the API Subscriptions page** from user profiles, so there is no UI route to mint
a token — the password exchange is the only way. `ac-bootstrap.sh` performs it once: the password flows
1Password → stdin → HTTPS inside a single pipeline, never written to disk, never echoed, never passed as a
process argument. Only the token is kept.

The token goes to `~/.claude/.env` as `ACTIVECOLLAB_TOKEN` (mode `0600`), alongside the team's other
tokens. `AC_STORE_OP=1` switches to keeping it in 1Password instead, writing only an `op://` reference —
more secure, but it prompts for biometric unlock on **every** call, because Claude Code starts a fresh
shell per command and the authorisation does not carry over.

One subscription exists per `client_name` + `client_vendor`, so **re-running the bootstrap invalidates the
previous token**. Two machines need two distinct `AC_CLIENT_NAME` values.

## The `ac` client

Installed to `~/.claude/bin/ac` by setup.

```bash
ac GET    /users
ac GETALL /projects
ac POST   /projects/428/tasks '{"name":"Fix it","assignee_id":6}'
ac PUT    /projects/428/time-records/312 '{"value":3}'
ac DELETE /users/6/api-subscriptions/511
```

The token reaches curl through a config file on a pipe rather than an argument, so it never appears in
`ps` output.

## API notes worth knowing before extending this

**Pagination is silent and only affects some endpoints.** `/projects` caps at 100 per page — Avista has
213 — and a plain `GET` returns the first page with nothing to indicate more exist. The real total is in
the `X-Angie-PaginationTotalItems` response header, alongside `…CurrentPage` and `…ItemsPerPage`. `GETALL`
reads those, walks every page, and warns on a count mismatch. Meanwhile `/users`, `/job-types` and
`/labels` **ignore `?page` entirely** and return everything in one response — passing `page=2` returns the
same payload again, which is an easy way to double-count if you assume uniform paging.

**`/projects/:id/tasks` returns an object, not an array** — `.tasks`, `.task_lists`, `.project`,
`.completed_task_ids`, and more. Convenient (task lists come free with the task fetch) but it breaks any
code that assumes collections are arrays. `GETALL` refuses it rather than producing nonsense.

**`id` vs `task_number`.** The API's `id` is global; `task_number` is the small per-project number in the
web UI's URL (`/projects/428/tasks/14`). Time records and API calls want `id`. Mixing them up files work
against an unrelated task, silently.

**Job types can have more than one default.** `is_default` is true for both `Design` and `Programming` on
this instance, so "pick the default" is ambiguous. Always resolve explicitly.

**Dates go in as `YYYY-MM-DD` and come back as UNIX timestamps.** Use `todate` in jq when reading.

**Write responses are wrapped in `single`.** `POST`, `PUT` and `DELETE` on tasks and time records return
`{"single": {...}, "subscribers": [...], "task_list": {...}, "tracked_time": 0.0, …}` — the object you
created is at `.single`, not the top level. Reading `.id` gets you `null` with no error.

**`estimate` requires `job_type_id`.** Sending an estimate alone fails with
`"Job type is required for tasks with estimates"`.

**Project membership is `/projects/:id/members`, and it returns bare user IDs** — `[2,3,6,21]`, not
objects. There is no `/projects/:id/people`; that path 500s with `Failed to match … path`.

**Time-record reads return objects too.** Both `/projects/:id/tasks/:task_id/time-records` and
`/users/:id/time-records` return `{time_records: [...], related: {...}}`, so `.[]` fails — use
`.time_records[]`.

**`DELETE` is a soft delete.** Tasks and time records are trashed (`is_trashed: true`) and stay
recoverable from the UI; trashed task IDs show up in `.trashed_task_ids` on the project's tasks endpoint.
Permanent purge is a UI action.

**`start_on` auto-fills from `due_on`** when you send a due date without a start date.

**Send payloads from a file, never as an inline argument.** Claude Code's shell runs under `LC_CTYPE="C"`,
so multibyte characters inline throw `character not in range` — and Icelandic task names are full of them.
The failure is worse than it looks: the mangled call can still reach the API and create a partial record
before the error surfaces. From a file, UTF-8 round-trips correctly:
`ac POST /projects/479/tasks "$(cat payload.json)"`.

**Errors arrive as HTTP 500 with a JSON body**, not a 4xx. Validation failures carry a `field_errors` map
naming the offending field. Failed token issuance carries a numeric `type`: `2` unknown/inactive user,
`3` bad password, `4` not permitted to issue tokens.

### Time endpoints accept filters they silently ignore

This is the worst trap in the API, because the wrong call returns HTTP 200 with a plausible number.
Verified against the live instance:

| Endpoint | Honours | Silently ignores |
|---|---|---|
| `/time-records?from=&to=` | `from`, `to` — **both required** | `user_id`, `billable_status`, `page` |
| `/reports/run?type=TrackingFilter` | `project_filter=selected_1,<id>`, `group_by=project` | `from`, `to`, `user_filter` |
| `/projects/:id/time-records` | — | no date window at all |
| `/users/:id/time-records` | — | no date window at all |

`/time-records?from=&to=` is the **only** date-windowed source; omitting `to` answers
`Invalid timesheet period.`. Passing `user_id=6` returns the whole company's hours while looking filtered.

`TrackingFilter` looks like the better source and is not. It returns history back to 2016 regardless of
`from`/`to`, it mixes `Expense` records into the same array where `.value` is **ISK rather than hours**
(summing blindly gave 5,451,984 for a window holding 482 hours), and it **omits every project the token's
user cannot read**. Use it for a single-project pull, never for a total.

`activecollab-time-audit` ships `scripts/time-logged.sh`, which reads through the one honest path and does
all filtering client-side.

### Some hours belong to projects you cannot see

`/time-records` returns records whose `project_id` is absent from `GETALL /projects`, absent from
`/projects/archive`, not fetchable by id, and not present in the response's own `related.Project` map —
projects the token's user has no read access to. Their hours are real; their names are unavailable. A
per-project report built by looping over `GETALL /projects` misses them entirely, which is why the audit
skill drives its aggregation off the time records themselves and reports the remainder as unattributed.

### `billable_status` has four values, not two

| Value | Meaning | `invoice_item_id` |
|---|---|---|
| `0` | not billable | `0` |
| `1` | billable, not yet invoiced | `0` |
| `2` | billable, on an invoice | set |
| `3` | billable, on an invoice | set |

Every `2` and `3` record on this instance carried a non-zero `invoice_item_id`; every `0` and `1` carried
zero. So `invoice_item_id != 0` is a reliable **"already invoiced, do not touch"** test. Only ever write
`0` or `1` — the higher values are set by the invoicing side.

### `tracked_time` exists in exactly one place

A task's rolled-up hours are on a **direct** task fetch (`GET /projects/:id/tasks/:task_id`) and nowhere
else — not in the `/projects/:id/tasks` list, not in a time-record response's `related.Task`. Reading it
from either of those yields nothing and looks like a task with no hours.

There is no project-level equivalent at all. `/projects/:id` carries `budget`, `budget_type` and
`is_tracking_enabled` but no tracked total, so project hours must be summed client-side.

### Task completion has its own global route

```bash
ac PUT /complete/task/<task-id> '{}'
ac PUT /open/task/<task-id> '{}'
```

Not project-scoped, and it takes the **global `id`**, not `task_number`. `is_completed`, `completed_on` and
`completed_by_id` are what change. `create-task` uses this to close a record-mode task after posting.

### Telling a missing route from a missing object

Both answer 404, so probing needs care — useful when extending this plugin without mutating anything:

- **Route does not exist** → JSON body `{"type":"RuntimeException","message":"Failed to match 'x/y' path."}`
- **Route exists, object does not** → empty body

That is how `/complete/task/:id` was confirmed before anything was written to it: a `PUT` against a
nonexistent task id returned an empty 404, exactly like the known-good `/projects/:id/tasks/:id`, while a
deliberately bogus path returned the `Failed to match` JSON.

### `LC_CTYPE` bites on the way out, too

The multibyte trap is not only about payloads. Capturing a **response** in `$(...)` throws
`character not in range` just as readily, because task names and time-record summaries are full of
Icelandic characters. Redirect every response to a file and read it with `jq < file`.

## Safety

Both write skills resolve names to IDs, echo the resolution back in plain language, and post only after
explicit approval. Assignment notifies the assignee. Time records feed invoicing, and deleting one
destroys billable history — correct the value instead.

`Client`-class users are external. Assigning a task to one is occasionally right and usually a mistake;
the create-task skill flags it.

`activecollab-time-audit` writes nothing at all. Its logged-vs-measured ratio describes **logging
discipline on commit-producing work** — it is not a productivity measure, must not be turned into a
per-person performance figure, and must not be multiplied by `default_hourly_rate` to imply lost revenue.
Work that leaves no commits (support, meetings, WP admin, design) is excluded from the comparison rather
than counted as unlogged.
