---
name: avista-activecollab-overview
description: Overview of the avista-activecollab plugin — what it bundles, what each skill does, the order to use them in, and how authentication works. Use when the user asks "what does avista-activecollab do", "what's in this plugin", "how do I get started with ActiveCollab", "which ActiveCollab skill do I run first", "how do I create a task from Claude", "how do I read logged time", or right after installing the plugin.
---

# avista-activecollab — overview

Talks to Avista's ActiveCollab (`https://active.avista.is`, self-hosted 8.x) from Claude Code: create
tasks, assign them to colleagues, set estimates, log tracked hours, and read those hours back to check
they match the work.

Present this overview, then point the user at the right skill.

## What's in the box

| Skill | What it does | When to use it |
|---|---|---|
| `activecollab-setup` | Installs the 1Password CLI, exchanges the user's ActiveCollab login for an API token, writes it to `~/.claude/.env`, installs the `ac` client, and verifies with a live call. | **Once per machine**, before anything else. |
| `activecollab-create-task` | Creates a task — resolves project, assignee and task list from names to IDs, writes the description to match what the task is *for* (see below), sets estimate/due date/labels, posts on approval. Also updates existing tasks. | Turning work into a ticket, before or after it happens. |
| `activecollab-start-task` | Pulls a task and reads its description back out as a working brief, then starts once you confirm. | Picking up a ticket someone wrote for you. |
| `activecollab-log-time` | Logs a time record against a task or project — resolves job type and person, posts on approval. | Recording hours actually worked. |
| `activecollab-suggest-time` | Measures working time from the git log (commits grouped into sittings), finds candidate tasks — creating one when none exists — and proposes one entry per sitting. Refuses to guess when commits are a poor signal. | After finishing a feature, when you need to know what to log and against what. |
| `activecollab-time-audit` | Reads logged time back — per task, project, person, or company over a date window — and compares it against git-measured hours to spot systematic under-logging. Read-only. | "How much is logged on this?" / "Are we under-logging?" |

```
1. activecollab-setup          ← once per machine

   activecollab-create-task    ← work needs a ticket (brief or record)
   activecollab-start-task     ← picking one up: reads the prompt back out
   activecollab-suggest-time   ← it landed: what to log, against which task
   activecollab-log-time       ← writes it
   activecollab-time-audit     ← reads it back: does logged match worked?
```

The middle four are a loop; the last one closes it from the other end.

## A task is either a brief or a record

The single most useful distinction in this plugin, and the thing `create-task` settles before it writes
anything:

|  | **Brief** — work that has not happened | **Record** — work that is already done |
|---|---|---|
| Why it exists | Someone has to pick it up and do it | Hours need something to attach to |
| Description | A **runnable prompt** — goal, files, a reproduction step, what is out of scope — in ActiveCollab's magic callout with a code block inside, so it copies out verbatim | **Two or three lines of past tense**: what changed and where |
| `estimate` | Set it. It is the plan. | Omitted. There was never a plan — the hours live on the time record. |
| After posting | Stays open | Completed |
| Read back by | `activecollab-start-task` | `activecollab-time-audit` |

A brief's description is a handoff: the person who picks it up should not have to reconstruct the context
from the title. A record's description is a receipt: enough that the line item still makes sense when it
turns up on an invoice six months later.

Getting this backwards is the expensive mistake in one direction only. A prompt written into a record task
lands on someone's board as live work, and `start-task` will hand it out as a brief for something that
shipped last month.

## Estimates are not logged time

The other common mix-up. A task's `estimate` is a **plan**; a time record is **hours actually worked**.
Different endpoints, different reports, and only time records reach invoicing. When a user says "set the
time to 3 hours", find out which they mean before writing anything.

It is also the quickest way to settle brief-vs-record: if the number in play is an estimate, it is a
brief. If it is hours already spent, it is a record, and the number does not belong on the task at all.

## Reading time back is full of traps

ActiveCollab's time endpoints **accept filters they silently ignore** — a filtered call returns HTTP 200
with the unfiltered set. `/time-records?from=&to=` is the only date-windowed source and it discards
`user_id`, `billable_status` and `page`. `/reports/run?type=TrackingFilter` discards `from`/`to`, mixes in
`Expense` records whose `value` is ISK rather than hours, and omits every project the token cannot read.

`activecollab-time-audit` documents all of it and ships a script that reads through the one honest path and
filters locally. Do not hand-roll a time report from `ac GET` calls without reading that skill first — the
wrong endpoint gives a confident wrong number.

## How auth works

ActiveCollab 8 removed the API-token page from user profiles, so `POST /api/v1/issue-token` with the
account password is the only way to get a token. `activecollab-setup` does that exchange once — reading
the password straight out of 1Password into the request, never storing or echoing it — and keeps only the
resulting token.

The token lands in `~/.claude/.env` (mode `0600`) as `ACTIVECOLLAB_TOKEN`, next to the team's other
tokens. A 1Password-backed variant exists (`AC_STORE_OP=1`) that keeps the token off disk entirely, at the
cost of an unlock prompt on every API call — Claude Code starts a fresh shell per command, so those
prompts do not batch.

Tokens are revocable from ActiveCollab without touching the password. Re-running setup invalidates the
previous token, because ActiveCollab keys one subscription per `client_name` + `client_vendor`.

## The `ac` client

Setup installs `~/.claude/bin/ac`, a thin wrapper the skills call:

```bash
ac GET    /users
ac GETALL /projects                  # follows pagination
ac POST   /projects/428/tasks '{"name":"Fix it","assignee_id":6}'
ac PUT    /projects/428/tasks/91 '{"estimate":2.5}'
ac DELETE /users/6/api-subscriptions/511
```

**Use `GETALL` for collections.** `/projects` is capped at 100 per page; Avista has 213. A plain `GET`
returns the first page with no indication anything is missing, which quietly produces wrong answers.
`GETALL` reads the `X-Angie-Pagination*` headers, walks every page, and warns if the merged count does not
match the advertised total. Endpoints that ignore paging (`/users`, `/job-types`, `/labels`) pass through
unchanged, and object endpoints (like `/projects/:id/tasks`) are refused with a clear message.

**Never capture a response in `$(...)`.** The shell runs under `LC_CTYPE="C"`, so Icelandic characters in
a task name or time-record summary throw `character not in range` the moment the JSON passes through
command substitution. Redirect to a file — on the way in *and* on the way out.

## Safety posture

Everything that writes here goes into a system the whole company and, on client projects, clients
themselves can see. The write skills resolve names to IDs first, echo the resolved values back in plain
language, and post **only after explicit approval**. Assignments and reassignments notify people; time
records feed invoicing. Deleting a time record destroys billable history — correct the value instead where
possible, and check `invoice_item_id` first, because a non-zero value means a client has already been
billed against it.

`activecollab-time-audit` is read-only by design, and its logged-vs-measured ratio is a measure of
**logging discipline on commit-producing work** — never a person's productivity, and never multiplied by
an hourly rate to produce a lost-revenue figure.

## More detail

See the plugin [README](../../README.md) for the API notes worth knowing before extending this —
pagination behaviour, the `id` vs `task_number` trap, the multiple-defaults quirk in job types, and which
time endpoints lie about filtering.
