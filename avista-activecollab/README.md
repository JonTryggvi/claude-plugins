# avista-activecollab

Create tasks, assign them, set estimates, and log tracked hours in Avista's ActiveCollab from Claude Code.

Avista runs **self-hosted ActiveCollab 8.x** at `https://active.avista.is`. That matters: most of what you
find online about ActiveCollab authentication describes the *cloud* flow, which does not apply here.

| Skill | Purpose |
|---|---|
| `activecollab-setup` | One-time machine setup — token bootstrap, `ac` client install, verification. |
| `activecollab-create-task` | Create/update a task; resolve project, assignee, task list; set estimate, due date, labels. |
| `activecollab-log-time` | Log a time record against a task or project. |
| `activecollab-suggest-time` | Measure hours from the git log and propose entries against candidate tasks. |
| `avista-activecollab-overview` | What's in the box and which skill to run. |

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

## Safety

Both write skills resolve names to IDs, echo the resolution back in plain language, and post only after
explicit approval. Assignment notifies the assignee. Time records feed invoicing, and deleting one
destroys billable history — correct the value instead.

`Client`-class users are external. Assigning a task to one is occasionally right and usually a mistake;
the create-task skill flags it.
