---
name: activecollab-project-map
description: Persist the repo-to-ActiveCollab-project mapping so it is resolved once instead of rediscovered every month — records each clone group's paths, its project id, default task and job type, an explicit private flag for repos that deliberately have no project, structured decisions that keep last month's judgement calls from being re-litigated, and the other projects a group's hours can legitimately land on. Use when the user says "which ActiveCollab project does this repo belong to", "map this repo to a project", "remember that this repo has no project", "save the project mapping", "which of my repos aren't mapped yet", "which unmapped repos actually have commits", "record that this date is already covered", "don't propose that date again", "remember this decision for next month", "find the task for this work", "is that project still there", or before running activecollab-reconcile-period or activecollab-invoice-preflight, both of which need the mapping to exist. Resolves projects with GETALL (a plain GET hides half the list) and includes archived tasks when proposing a match, because completed tasks still accept time records and the honest match for finished work is usually archived. Writes only a local map file — never to ActiveCollab.
---

# Map repos to ActiveCollab projects, once

Answering *"which project do these commits belong to?"* costs a handful of API calls, some judgement, and
usually a question to the user. Doing it again every month is the slow part of a reconciliation, and doing
it from memory is how hours land on the wrong client.

So write it down. This skill maintains `~/.claude/activecollab-project-map.json` and is the thing
`activecollab-reconcile-period` and `activecollab-invoice-preflight` read before they measure anything.

**This skill never writes to ActiveCollab.** It reads the API and writes one local file.

## Call the client by its full path

Every `ac` call here is written `~/.claude/bin/ac`. macOS ships its own `/usr/sbin/ac` — login accounting —
and `~/.claude/bin` is **not** on `PATH`, so a bare `ac GETALL /projects` runs Apple's binary, prints
`total 0.00`, and **exits 0**. A project list that comes back empty because the wrong binary answered looks
exactly like a project list that is genuinely empty. `project-map.sh` resolves the path itself; when you
call the API directly, use the full path.

## What an entry holds

```json
{
  "slug": "myaccount",
  "repos": ["/Users/me/dev/myaccount",
            "/Users/me/flywheel/idnu/app/public/wp-content/plugins/myaccount"],
  "project_id": 388,
  "project_name": "Iðnú",
  "default_task_id": 12088,
  "default_task_name": "ACF Fields from Parent theme Sync",
  "default_job_type_id": 1,
  "default_job_type": "Programming",
  "budget_type": "pay_as_you_go",
  "private": false,
  "also_logged_under": [487],
  "decisions": [
    {"date": "2026-08-12", "action": "never_propose",
     "reason": "already inside record 16112 of 2026-08-13, which itemises it",
     "decided": "2026-08-21"}
  ],
  "note": ""
}
```

`repos` is a **clone group**, not one path — see below. `budget_type` is cached because `not_billable`
projects coerce `billable_status` to `0` on write, and knowing that before proposing a billable record
saves an invoice surprise (`activecollab-log-time` has the detail).

## Decisions: the part that makes a reconciliation idempotent

A month-end run makes judgement calls. *This date looks empty but is already covered by a record that
over-covers its own date. This date is logged short of measured on purpose, and it was reviewed.* Those
calls are the expensive part of the work — and if they live in a `note` as prose, they only survive if the
next agent reads the note carefully and happens to agree with itself. If they live nowhere, every month
re-litigates last month from memory and re-proposes work somebody already decided against.

So record them structurally:

```bash
bash "<this-skill-dir>/scripts/project-map.sh" decide \
  --slug fraktlausnir --date 2026-08-12 --action never_propose \
  --reason "already inside record 16112 of 2026-08-13, which itemises it"

bash "<this-skill-dir>/scripts/project-map.sh" decide \
  --slug fraktlausnir --date 2026-08-19 --action capped_at --hours 2.40 \
  --reason "logged 2.40h against 3.00h measured, reviewed and left"
```

| `action` | Means | Effect in `reconcile-period` |
|---|---|---|
| `never_propose` | This date is settled. | The date is dropped from proposals and reported as `settled-by-decision`. |
| `capped_at` | Deliberately logged short of measured, reviewed. `--hours` is what was logged. | Same — the shortfall is not a finding. |

`decide` replaces any existing decision for the same date **and** action, so re-running it updates rather
than duplicating. Use it rather than hand-editing the JSON: editing by hand is how decisions end up
unrecorded, which is the whole problem.

**The `reason` is required and the tool refuses without one.** A decision whose reasoning is lost is
indistinguishable from a mistake, and the next person to look at the numbers will reverse it — putting back
exactly what was removed. `decided` is stamped automatically so a stale call can be spotted later.

`reconcile-period` reports every decision it applied, with its reason and date, so a run is never quietly
shaped by a rule nobody can see. If an applied decision now looks wrong, change it in the map rather than
overriding it in the run — otherwise next month decides it again.

## `also_logged_under`: hours that land on another project

Work measured under one clone group is sometimes logged against a **different** project. On a real
month-end, Digital-Id work was covered by a 3.25h whole-security-sweep record on Reykvc.is (487). A
per-project, per-date comparison cannot see that, so those dates read as unlogged and get proposed again.

```json
"also_logged_under": [487]
```

`reconcile-period` then counts records on those projects when deciding whether a date is covered, and marks
such dates `covered-elsewhere` rather than `covered` — so the fact that the hours went somewhere else stays
visible instead of being smoothed away. Verified: the 2026-08-10 Digital-Id date measures 0.75h, has 0h of
its own, and reads `covered-elsewhere` from 3.25h on 487.

Use it for a genuine, deliberate arrangement. It is not a way to make an awkward date go quiet — if you are
unsure whether hours really cover the work, that is a question for the user, not a map entry.

## Step 1 — Find out what is not mapped yet

```bash
bash "<this-skill-dir>/scripts/project-map.sh" scan ~/dev ~/flywheel ~/Dropbox/dev
bash "<this-skill-dir>/scripts/project-map.sh" scan --since 2026-07-21 ~/dev ~/flywheel
```

`scan` walks the given roots for git repos, groups them by **remote origin URL**, and reports each group as
mapped, private, or unmapped.

### Use `--since`, because a flat list of unmapped groups gets skimmed

An unmapped group is silently absent from every reconciliation, so this list is exactly where real misses
hide. A real run returned **59 groups, 42 unmapped**, as an alphabetical wall — and none of the 42 had
commits in the window, but nothing said so, which had to be worked out by hand. Forty-two paths with no
signal trains people to skim the one list they cannot afford to skim.

`--since` reports each unmapped group with its commit count and last commit date in that window, active
ones first:

```
  window: commits since 2026-08-10 — 7 of 21 unmapped group(s) have commits in it
  ACTIVE  49 commit(s), last 2026-08-21   1x  …/claude-smalls/idnu-shell
  ACTIVE  27 commit(s), last 2026-08-20   1x  …/Avista Plugins/Avista-Core
  --- 14 unmapped group(s) with NO commits since 2026-08-10 ---
  quiet   1x  …/claude-smalls/HF
```

"7 of 21 have commits since 2026-08-10" is a thing someone can act on. SHAs are unioned across a group's
clones first, because the same commit readable from three checkouts is one commit.

Quiet groups are still listed — a group with no commits in the window may hold non-commit work, and it will
matter next month. They are just not ranked as though they were urgent. Grouping by origin is the point: repos sharing an origin are the same code in
several places, and the map has to hold them as one entry.

### Why clone groups, and not one repo per project

Shared plugins and themes get cloned into every site that uses them. The same commit is then readable from
several paths, so measuring each path and adding the totals counts one afternoon's work several times over
— on a real month-end run this read ~92h where the honest figure was 59h.

Recording the whole group in one entry is what lets the measuring side deduplicate by SHA. And the group
must be measured as a **union**, never as one nominated canonical repo, because the standalone checkout is
often the copy that is *behind* the site clones rather than ahead of them. A tidy-looking "canonical" repo
with 58 commits next to a site clone with 63 is not the authority; the union of both is.

If `scan` reports a group whose paths are only partly in the map, add the missing ones. A half-recorded
clone group is worse than an unrecorded one, because it measures without complaining.

## Step 2 — Resolve a project for each unmapped group

```bash
bash "<this-skill-dir>/scripts/project-map.sh" projects            # all of them
bash "<this-skill-dir>/scripts/project-map.sh" projects 'idnu|iðnú' # filtered
```

This uses `GETALL`, and that is not a detail. `/projects` caps at **100 per page** and this instance has
**213**. A plain `GET /projects` returns the first hundred with no indication anything is missing, so half
the list is invisible and a project that exists looks like it doesn't — at which point the natural next move
is to create a duplicate. Verified on the live instance: `GET` → 100, `GETALL` → 213.

Repo names and project names rarely match exactly. Show the user the plausible candidates with their ids
and **let them pick**. Never auto-select: a wrong mapping bills the right hours to the wrong client, and
because it is now written down, it keeps doing so every month until someone notices.

## Step 3 — Pick a default task, including the archived ones

```bash
bash "<this-skill-dir>/scripts/project-map.sh" tasks 428
```

This merges the **open** list with `/projects/<id>/tasks/archive` and labels each row with its source.

That second call is the one people skip, and it hides the right answer. `/projects/<id>/tasks` returns open
tasks in `.tasks` and finished ones as **bare ids** in `.completed_task_ids` — no names, no numbers, nothing
you can match against. The archive endpoint returns those same tasks as full objects. Verified live:

| Project | Open `.tasks` | `.completed_task_ids` | `/tasks/archive` |
|---|---|---|---|
| 428 Avista Commerce | 0 | 14 bare ids | 14 full objects |
| 154 Avista Connect | 2 | 27 bare ids | 27 full objects |

So project 154 looks like a two-task project from the open list and actually holds 29. **Completed tasks
still accept time records**, and for work that is already done the honest match is usually one of them —
id 12088 *"ACF Fields from Parent theme Sync"* is a real example, invisible unless you read the archive.

Note the shapes differ: the open list is an **object**, the archive is an **array**. And numbers people
quote from a reconciliation are usually global `id`s, not the small `task_number` from the web URL — 12088
is an id; its task_number is #12. Mixing them up files hours against an unrelated task.

A default task is optional. Leave it out when hours genuinely land on different tasks each month, rather
than nominating one and quietly mis-filing.

## Step 4 — Record private projects explicitly

Personal and internal projects usually have **no** ActiveCollab project, and that is a real answer worth
storing:

```bash
cat > /tmp/entry.json <<'J'
{"slug":"chess","repos":["/Users/me/dev/chess"],"private":true,
 "note":"personal project, no client, never billed — do not ask again"}
J
bash "<this-skill-dir>/scripts/project-map.sh" put /tmp/entry.json
```

Without this, every run surfaces the same repos as unmapped work and asks about them again. Asking twice is
a small tax; asking every month trains the user to skim the unmapped list, which is where the real misses
hide.

A private entry needs a `note` and must **not** carry a `project_id` — the script refuses both mistakes,
because "private" means there is no project, not "project unknown". If the user is unsure whether something
is billable, that is not private; leave it unmapped and ask.

## Step 5 — Store it, and show the user first

```bash
bash "<this-skill-dir>/scripts/project-map.sh" put /tmp/entry.json
bash "<this-skill-dir>/scripts/project-map.sh" list
```

`put` replaces any entry with the same `slug` and validates the shape. Show the resolved names in plain
language before storing — this file decides where hours go for months, so a typo here is expensive and
cheap to catch now:

```
slug        : myaccount
project     : Iðnú (388)          budget_type pay_as_you_go — billable records store as sent
default task: 12088 #12 ACF Fields from Parent theme Sync  [archived — still accepts time]
job type    : Programming (1)
repos       : 2 paths (clone group)
                /Users/me/dev/myaccount
                /Users/me/flywheel/idnu/…/plugins/myaccount
```

## Step 6 — Keep it honest

```bash
bash "<this-skill-dir>/scripts/project-map.sh" validate
```

A cached mapping decays. `validate` checks every stored entry against the live instance and reports:

- a `project_id` that is no longer in `GETALL /projects` — archived, deleted, or not readable by this token
- a project that has been **renamed** since it was recorded
- a `budget_type` that has **changed**, because that changes whether records store as billable
- repo paths that no longer exist

Run it at the start of any reconciliation. A stale map produces confident wrong attribution, which is
harder to spot than an error.

## What this skill must never do

- Auto-select a project because the name looked close. The map outlives the guess.
- Build the project list from a plain `GET /projects` — that is 100 of 213, and the missing half looks
  like it doesn't exist.
- Propose a task match from the open list alone. Most finished work is archived, and archived tasks are
  exactly what after-the-fact hours attach to.
- Store a `private` entry without a reason, or with a `project_id`.
- Nominate one clone as canonical and drop the others. Measure the union.
- Write anything to ActiveCollab. This skill reads the API and writes one local file.

## Failure modes

| Symptom | Cause |
|---|---|
| A project the user names is "not in ActiveCollab" | Built from `GET /projects` — 100 of 213. Use `GETALL`. |
| `total 0.00` from any call | That was `/usr/sbin/ac`, not our client. Use `~/.claude/bin/ac`. |
| A task the user remembers is missing | It is completed. Read `/projects/<id>/tasks/archive` too. |
| `.[]` fails on the open task list | It returns an object (`.tasks`); the archive returns an array. |
| Time filed against an unrelated task | A `task_number` was stored where the global `id` was wanted. |
| Measured hours far above anything worked | A clone group was recorded as separate entries, so its commits count once per copy. |
| The same repos come up as unmapped every month | They are personal — record them `private` with a note. |
| 42 unmapped groups with nothing to distinguish them | Pass `--since`; only the active ones need a decision now. |
| A date settled last month is proposed again | The decision was prose in a `note`, or was never recorded. Use `decide`. |
| `decide` refuses without a reason | Deliberate. An unexplained decision gets reversed by the next person. |
| A date is covered by another project and still proposed | Add that project to `also_logged_under`. |
| `validate` reports a project as unreadable | Some projects 404 for this token; their hours are real but unattributable. Do not guess a replacement. |
