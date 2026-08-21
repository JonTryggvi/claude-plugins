---
name: avista-activecollab-overview
description: Overview of the avista-activecollab plugin — what it bundles, what each skill does, the order to use them in, and how authentication works. Use when the user asks "what does avista-activecollab do", "what's in this plugin", "how do I get started with ActiveCollab", "which ActiveCollab skill do I run first", "how do I create a task from Claude", "how do I read logged time", "how do I reconcile a month", "which skill do I use for month-end", or right after installing the plugin.
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
| `activecollab-suggest-time` | Measures working time from the git log (commits grouped into sittings, SHA-deduplicated across clone groups, every identity a person commits under), finds candidate tasks — creating one when none exists — and proposes one entry per sitting. Refuses to guess when commits are a poor signal. | After finishing a feature, when you need to know what to log and against what. |
| `activecollab-time-audit` | Reads logged time back — per task, project, person, or company over a date window — and compares it against git-measured hours to spot systematic under-logging. Read-only. | "How much is logged on this?" / "Are we under-logging?" |
| `activecollab-project-map` | Persists the repo → project mapping: clone-group paths, project id, default task and job type, and an explicit `private` flag for repos that deliberately have no project. | **Once per repo**, then whenever `validate` reports drift. |
| `activecollab-reconcile-period` | The month-end job: measures a whole window against what is logged, per project **and per date**, from **two** sources — git commits and Claude Code session attention — and proposes the difference one record per sitting. | Closing out a month or a period. |
| `activecollab-evidence-sweep` | Finds billable work with no git trace — support email, meetings, phone fixes — via the Gmail and calendar connectors, and asks for the hours. | The measured total is obviously too low. |
| `activecollab-invoice-preflight` | Per client, before billing: what is logged, what is billable and not yet invoiced, which dates have commits but no time — and what it could not verify. | Billing day. |

```
0. activecollab-setup            ← once per machine
   activecollab-project-map      ← once per repo, and `validate` before any reconciliation

   PER PIECE OF WORK
     activecollab-create-task    ← work needs a ticket (brief or record)
     activecollab-start-task     ← picking one up: reads the prompt back out
     activecollab-suggest-time   ← it landed: what to log, against which task
     activecollab-log-time       ← writes it

   PER PERIOD (month-end)
     activecollab-reconcile-period  ← measure the window vs what is logged, per date
     activecollab-evidence-sweep    ← the work git cannot see; asks for hours
     activecollab-log-time          ← writes the approved records
     activecollab-invoice-preflight ← per client, before the invoice goes out

   ANY TIME
     activecollab-time-audit     ← read-only: does logged match worked?
```

The per-work loop and the per-period loop answer different questions. `suggest-time` is *"I just finished
this feature, what do I log?"*. `reconcile-period` is *"it is the 1st, what did the whole of last month
actually contain?"* — a different measurement, because a period contains clone duplication, cherry-picked
commits, dates already covered by an over-covering record, and whole categories of work that never touched
git. Reaching for `suggest-time` repeatedly to cover a month gets all four of those wrong.

Run them in this order at month-end, because each one narrows what the next has to look at:

1. **`project-map validate`** — a stale mapping produces confident wrong attribution.
2. **`reconcile-period`** — measures everything commit-backed and proposes per date.
3. **`evidence-sweep`** — takes the dates still blank on both sides and looks for email/calendar evidence.
4. **`log-time`** — writes what the user approved, and reads each record back.
5. **`invoice-preflight`** — per client, confirms there is nothing left and says what it could not check.


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
filters locally. Do not hand-roll a time report from `~/.claude/bin/ac GET` calls without reading that skill
first — the wrong endpoint gives a confident wrong number.

Four more traps, all verified against the live instance, that decide whether a period total is right:

| Trap | What actually happens |
|---|---|
| `GET /projects` | Caps at **100**; this instance has **213**. Use `GETALL` or half the projects are invisible and a real one looks missing. |
| Finished tasks | `/projects/<id>/tasks` returns them as **bare ids** in `.completed_task_ids`. Names and numbers only come from `/projects/<id>/tasks/archive` — an **array**, where the open list is an object. Project 154 shows 2 open tasks and holds 27 archived. |
| `billable_status` on write | Projects with `budget_type: not_billable` (7 of 213) store **`0`** whatever you send, silently. `is_billable` does not exist here — it reads `null`, so a check against it always passes. Read the record back. |
| `GET /invoices` | **404** for a normal API token. There is no way to read invoices; `invoice_item_id != 0` on a time record is the only invoice signal available. |

**There are three measurement sources, not one, and they are ranked.** Commits are a weak proxy for time:
measured over a real three-week window in one repo, commit sittings gave **1.75h** (`signal: poor`), Claude
Code's own session logs gave **7.75h**, and **20.55h** was really logged. So `reconcile-period` measures
commits *and* session attention, uses whichever is higher per date, and labels which — because they are
different kinds of evidence. Session attention needs no timer to remember (events only fire when work
happens, so an idle gap closes the block by itself), but it sees only what happened inside Claude Code, so
it too is a lower bound. Anything outside it — meetings, support mail, WP admin — is
`activecollab-evidence-sweep`'s job, and that one asks rather than measures.

Two more that bite the measuring side rather than the API: shared repos cloned into several sites make the
same commit readable from several paths (dedupe by SHA, and measure a clone group as the **union** — the
standalone checkout is often the copy that is *behind*), and `--since`/`--until` filter **committer** date,
so cherry-picked older work lands in the wrong period unless author date is checked too.

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

Setup installs `~/.claude/bin/ac`, a thin wrapper the skills call.

**Always the full path — never a bare `ac`.** macOS ships `/usr/sbin/ac`, a login-accounting tool, and
`~/.claude/bin` is **not** on `PATH`. So `ac GET /users` runs Apple's binary, prints `total 0.00`, and
**exits 0**. No error, no warning — a wrong answer wearing the costume of a successful call, and every
number built on top of it inherits the mistake. In a reconciliation it reads as "nothing is logged this
month", which is how a whole period gets double-posted. `activecollab-setup` step 6 reports what `ac`
resolves to on the machine and offers to install an alias.



```bash
~/.claude/bin/ac GET    /users
~/.claude/bin/ac GETALL /projects                  # follows pagination
~/.claude/bin/ac POST   /projects/428/tasks '{"name":"Fix it","assignee_id":6}'
~/.claude/bin/ac PUT    /projects/428/tasks/91 '{"estimate":2.5}'
~/.claude/bin/ac DELETE /users/6/api-subscriptions/511
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

`activecollab-time-audit`, `activecollab-invoice-preflight` and `activecollab-project-map` are read-only
against ActiveCollab by design (the last writes one local file). `activecollab-reconcile-period` and
`activecollab-evidence-sweep` propose records and post **only** what the user has seen and approved,
record by record — they derive numbers rather than being told them, which is exactly why the human has to
see each one before it reaches a timesheet.

The logged-vs-measured ratio is a measure of **logging discipline on commit-producing work** — never a
person's productivity, and never multiplied by an hourly rate to produce a lost-revenue figure.

Two habits the period skills enforce because getting them wrong is expensive and invisible:

- **Both sides of any comparison must describe the same person.** Filtering the git side to one author
  while reading the whole team's timesheet reports colleagues' hours as that person's shortfall.
  `logging-gap.sh` and `reconcile-period.sh` now refuse to run half-filtered rather than produce a number.
- **A floor is not a measurement.** A sitting with one commit gets the lead-in allowance alone (0.25h).
  Session attention replaces most of these with a real span; what remains a floor is reported separately. It never gets folded into a headline or quietly rounded up to something more
  plausible — a guessed number on a timesheet is worse than a visibly conservative one, because nobody
  knows to question it.

## More detail

See the plugin [README](../../README.md) for the API notes worth knowing before extending this —
pagination behaviour, the `id` vs `task_number` trap, the multiple-defaults quirk in job types, and which
time endpoints lie about filtering.
