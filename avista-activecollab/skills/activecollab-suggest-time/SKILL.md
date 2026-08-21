---
name: activecollab-suggest-time
description: Suggest timesheet entries after finishing a feature — measures working time from the git log by grouping commits into sittings, finds candidate ActiveCollab tasks from the branch name, commit messages and repo, and proposes one time record per sitting for the user to confirm. Creates a record-mode task to hang the hours on when no existing task matches. Use when the user says "I finished this feature, log the time", "suggest time entries", "how long did this take", "what should I log for this", "find the task for this work", "estimate hours from git", or wraps up a piece of work and needs it on a timesheet. Measures rather than prices, states its basis, and refuses to guess when the commit history is a poor signal.
---

# Suggest time entries from git

After a feature lands, works out **what to log and against which task**. Produces a proposal; a human
confirms before anything is written.

Requires `activecollab-setup`. Logging itself follows `activecollab-log-time` — this skill decides the
numbers, that one writes them. For the reverse question — *what has already been logged, and does it match
the work?* — use `activecollab-time-audit`.

## The house rule this implements

Avista measures timesheet hours from the git log, not from wall clock and not from what the work "would
cost":

- A gap longer than **45 minutes** starts a new sitting.
- A sitting is measured **first commit → last commit**, then plus a **lead-in** for the investigation
  before its first commit.
- Uncommitted tail work is added by hand — it has no commits to measure.
- **Never** present elapsed wall-clock time as working time. Sessions span days with long gaps.
- Break the total down **per sitting**, so it maps onto individual time entries.
- If commits are a poor signal — squashed at the end, work done in a web UI, long investigation with no
  commits — **say so and ask what to measure from instead of guessing.**

That last rule is not optional. A confident wrong number on a timesheet becomes a wrong invoice.

## Step 1 — Measure

```bash
bash "<this-skill-dir>/scripts/git-sittings.sh" --since=7.days
bash "<this-skill-dir>/scripts/git-sittings.sh" main..HEAD          # a feature branch
AUTHOR=<their-email> bash "<this-skill-dir>/scripts/git-sittings.sh" --since=30.days
```

Filter by author whenever the repo has more than one committer — you are logging *their* time.

Tunables (env): `GAP_MIN` (45), `LEADIN_MIN` (15), `ROUND` (0.25h), `AUTHOR`.

The script emits JSON: `sittings[]` with date, start/end, commit count, measured span and suggested
`hours`; plus `total_hours`, `uncommitted_files`, `warnings[]`, `basis{}`, and `signal_quality`.

## Step 2 — Check the signal before going further

Read `signal_quality` and **stop if it is not `usable`**:

| Value | Meaning | What to do |
|---|---|---|
| `usable` | Commits are spread through the work | Proceed. |
| `weak` | Under an hour measured | Proceed, but show the warnings and invite a correction. |
| `poor` | Single commits, or every sitting under 30 min of commit span | **Do not propose a number.** Say the commit log is a poor signal here and ask what to measure from. |
| `none` | No commits matched | Ask for a different range, author, or basis. |

`poor` is common and not a failure of the tool. Squash-merged release commits, or a long session where
everything is committed at the end, both produce two commits six minutes apart after four hours of work.
Reporting 0.25h there would be worse than reporting nothing.

When the signal is poor, ask directly: *"The commits here are clustered at the end, so they measure 0.25h
for what was clearly a longer session. What should I measure from — do you remember roughly when you
started and stopped?"* Then log what the user states, marked as their figure rather than a measurement.

## Step 3 — Find candidate tasks

In priority order, stopping at the first that yields a confident hit:

1. **An explicit task number** in the branch name or commit subjects — `#25`, `task/25`, `ac-25`:
   ```bash
   git log --pretty=format:'%s %b' main..HEAD | grep -oE '#[0-9]+' | sort -u
   git rev-parse --abbrev-ref HEAD
   ```
   Resolve it as a `task_number` **within a project** — it is not globally unique, so you still need the
   project. Confirm the task name matches the work before trusting it.

2. **The repo name against project names:**
   ```bash
   basename "$(git rev-parse --show-toplevel)"
   ac GETALL /projects | jq -r '.[] | "\(.id)\t\(.name)"'
   ```
   Use `GETALL` — `/projects` pages at 100 and Avista has 213.

3. **Their open assigned tasks** in the matched project, most recently updated first:
   ```bash
   ac GET /projects/<id>/tasks \
     | jq -r '.tasks | sort_by(.updated_on) | reverse | .[] | select(.assignee_id==<uid>) | "\(.id)\t#\(.task_number)\t\(.name)"'
   ```
   Note this lists **open** tasks; completed ones come back from that call as bare ids in
   `.completed_task_ids`. Work that finished a while ago may well have a completed task already, and a
   completed task still accepts time records.

4. **Nothing matches — then create the task.** This is the common case for work that was never ticketed:
   a fix that came up mid-session, a piece of maintenance, anything started before anyone wrote it down.
   The hours still need a parent.

Then match against what the commits actually say. Show the top few candidates with their task numbers and
**let the user pick** — never auto-select. Getting the task wrong bills the right hours to the wrong
client.

### When no task exists

Hand off to `activecollab-create-task` in **record mode** — the branch built for exactly this. It writes a
short past-tense description of what was done, sets **no estimate** (there was never a plan; the hours go
on the time record), and completes the task after posting so finished work does not sit on the board.

Do **not** let it write a runnable prompt into the description. A prompt describing work that is already
merged reads as open work to everyone who sees the project, and `activecollab-start-task` will hand it out
as a live brief. Say "record mode" explicitly when you hand off, so step 0 of that skill does not have to
infer it.

Suggest the task name from the commit subjects, not from the branch name — `fix/rounding-2` is not a task
title. One task per coherent piece of work, even when it spans several sittings; the sittings become
separate time records against the same task.

## Step 4 — Propose, with the basis stated

One time record per sitting, because each sitting is a separate timesheet entry on its own date:

```
Task: #25 Rannsaka kaffivélina (id 13377) in Avista Core (479)
Basis: commit-to-commit spans, 45min gap, +15min lead-in per sitting, rounded to 0.25h
       (measured from git, author jontryggvi@avista.is)

  2026-08-12   09:14-11:40   6 commits   span 2.43h   ->  2.75h
  2026-08-13   14:02-15:10   3 commits   span 1.13h   ->  1.50h
                                                    TOTAL  4.25h

  ! 3 uncommitted files — tail work not measured, add by hand if it was significant
```

Always show: the per-sitting breakdown, the measured span *next to* the suggested hours (so the lead-in is
visible, not hidden), the basis line, and every warning. Never collapse it to a single number — the user
is confirming a measurement, and they can only do that if they can see it.

Then ask for confirmation, including whether it is billable and which job type.

If the task already has hours on it, show them — `ac GET /projects/<id>/tasks/<task-id>` carries
`tracked_time` (a direct task fetch only; it is absent from the task list). Proposing 4.25h against a task
that already holds 4h of the same work is how time gets double-logged.

## Step 5 — Log it

Hand off to `activecollab-log-time` for each confirmed sitting. In short: payload to a file (never inline
— the shell runs under `LC_CTYPE="C"` and Icelandic characters break as arguments), `job_type_id` is
required, and the response is wrapped in `single`.

```bash
ac POST /projects/479/time-records "$(cat sitting-1.json)" \
  | jq -r '"logged \(.single.value)h on \(.single.record_date|todate[:10])"'
```

Log each sitting under its **own** `record_date`. Collapsing four days into one entry is wrong on a
timesheet even when the total matches.

If a record-mode task was created in step 3, complete it once the hours are in — see step 6 of
`activecollab-create-task`. Completing it before the records are written means a failure mid-flow leaves a
closed task with no hours on it.

## What this skill must never do

- Present wall-clock session length as working time.
- Log without a human confirming the numbers.
- Produce a figure when `signal_quality` is `poor` or `none` — ask instead.
- Write a runnable prompt into a task created for work that is already done.
- Quote what the work "would cost" to build. That is a **quote**, a different question, and only when
  explicitly asked for one.
