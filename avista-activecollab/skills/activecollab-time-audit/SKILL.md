---
name: activecollab-time-audit
description: Read logged time back out of ActiveCollab — for a task, a project, a person, or the whole company over a date window — and compare it against hours measured from the git log to see whether work is being under-logged. Use when the user says "how much time is logged on this project", "what's been logged on that task", "read the time records", "show me the timesheet", "are we under-logging", "compare logged time to actual time spent", "do our logged hours match the work", "time audit", "how many hours went to <project> last month", "who logged what", or wants to know whether hours actually worked are reaching the timesheet. Read-only — it never creates, edits or deletes a time record. The logged-vs-measured ratio describes logging discipline on commit-producing work, never a person's productivity.
---

# Audit logged time in ActiveCollab

Two jobs, in order: **read** what is on the timesheet, then optionally **compare** it against what the git
log says was actually worked, to spot systematic under-logging.

Requires `activecollab-setup`. Writing time is a different skill — `activecollab-log-time`. **This skill
writes nothing.** If the audit turns up a gap, the fix is a human deciding what to log, then that skill.


## Call the client by its full path

Every `ac` call in this skill is written `~/.claude/bin/ac`, and that is not
pedantry. macOS ships its own `/usr/sbin/ac` — a login-accounting tool — and
`~/.claude/bin` is **not** on `PATH`. So a bare `ac GET /users` runs Apple's
binary, prints `total 0.00`, and **exits 0**. Nothing fails, nothing warns; you
get a wrong answer shaped like an empty result, and every conclusion built on
top of it inherits the error.

Resolve it once at the top of any script:

```bash
AC="${AC_BIN:-$HOME/.claude/bin/ac}"
[ -x "$AC" ] || { echo "no ac client — run the activecollab-setup skill" >&2; exit 69; }
"$AC" GETALL /projects
```

If a call returns something suspiciously empty or a bare `total 0.00`, check
which binary ran before you believe the number.

## The one thing to get right before reading any numbers

ActiveCollab's time endpoints disagree with each other, and two of them **accept filters they silently
ignore**. A filtered call returns HTTP 200 with the unfiltered set. Every number below was checked against
the live instance:

| Endpoint | Honours | Silently ignores |
|---|---|---|
| `/time-records?from=&to=` | `from`, `to` — **both required** | `user_id`, `billable_status`, `page` |
| `/reports/run?type=TrackingFilter` | `project_filter=selected_1,<id>`, `group_by=project` | `from`, `to`, `user_filter` |
| `/projects/<id>/time-records` | — | no date window at all |
| `/users/<id>/time-records` | — | no date window at all |
| `/projects/<id>/tasks/<id>/time-records` | — | no date window at all |

So: **`/time-records?from=&to=` is the only date-windowed source, and all filtering on top of it must be
done client-side.** Omitting `to` answers `Invalid timesheet period.`; passing `user_id=6` returns
everybody's hours while looking like it worked.

`TrackingFilter` looks like the better source and is a trap three ways over: it returns history back to
2016 regardless of `from`/`to`, it mixes `Expense` records into the same array where `.value` is **ISK,
not hours** (summing blindly gave 5,451,984 for a window that holds 482 hours), and it **silently omits
every project the token's user cannot read**. Use it only for a single-project pull via `project_filter`,
never for a total.

**Never capture a response in `$(...)`.** The shell runs under `LC_CTYPE="C"`, and time-record summaries
are full of Icelandic characters, so command substitution throws `character not in range` mid-pipeline.
Redirect to a file. The scripts here already do.

## Step 1 — Read what is logged

```bash
bash "<this-skill-dir>/scripts/time-logged.sh" --from 2026-06-01 --to 2026-08-21
bash "<this-skill-dir>/scripts/time-logged.sh" --from 2026-06-01 --to 2026-08-21 --project 479
bash "<this-skill-dir>/scripts/time-logged.sh" --from 2026-06-01 --to 2026-08-21 --user 6 --quiet > logged.json
```

One API call for the window, then everything filtered and aggregated locally. JSON on stdout, a summary on
stderr. It returns totals plus `by_user`, `by_project`, `by_job_type`, and the split between billable,
non-billable and already-invoiced hours.

For a **single task**, the direct read is simpler and needs no window:

```bash
~/.claude/bin/ac GET /projects/479/tasks/13388/time-records \
  | jq -r '.time_records[] | "\(.record_date|todate[:10])\t\(.value)h\t\(.user_name)\t\(.summary[0:60])"'
```

Both of these return an **object** with `.time_records` — not an array — plus a `.related` map keyed by id
holding the full `Project` and `Task` objects the records point at. That is how you render
"3.5h on #25 Fix rounding (Avista Core)" from one call instead of three.

A task also carries its own rolled-up `tracked_time` — but **only on a direct task fetch**:

```bash
~/.claude/bin/ac GET /projects/479/tasks/13388 | jq -r '"\(.tracked_time)h tracked, estimate \(.estimate)h"'
```

`tracked_time` is **absent** from the `/projects/<id>/tasks` list and from `.related.Task`. Do not reach
for it there and conclude the task has no hours.

**There is no project-level equivalent.** `/projects/<id>` carries `budget`, `budget_type` and
`is_tracking_enabled` but no tracked total, so a project's hours must be summed client-side. `time-logged.sh`
does that.

### Hours you can see but cannot attribute

`/time-records` returns records for projects that are **not** in `GETALL /projects`, **not** in
`/projects/archive`, **not** fetchable by id, and **not** in `.related.Project` — projects this token's
user has no read access to. Their hours are real and belong in a company total; their names are not
available.

`time-logged.sh` counts them and lists them in `unresolvable_projects` with a warning. Report them as
unattributed rather than dropping them, and never guess which client they belong to. Building a per-project
report by looping over `GETALL /projects` misses them entirely — that is why the read is driven off the
time records, not the project list.

### `billable_status` has four values, not two

| Value | Meaning | `invoice_item_id` |
|---|---|---|
| `0` | not billable | `0` |
| `1` | billable, not yet invoiced | `0` |
| `2` | billable, on an invoice | set |
| `3` | billable, on an invoice | set |

Verified: every `2` and `3` record had a non-zero `invoice_item_id`; every `0` and `1` had zero. So
**`invoice_item_id != 0` is a reliable "already invoiced, do not touch" test** — worth checking before
anyone edits or deletes a record the audit turns up.

## Step 2 — Decide whether a comparison is even meaningful

Only bother comparing on projects where the work leaves commits in a repo you can reach. Before pairing
anything up, be honest about the denominator:

- **Repo-backed dev work** — comparison is meaningful.
- **Retainers, support, WP admin, Breakdance page building, meetings, client calls, design, QA** — no
  commits, so measured time is near zero and the ratio is noise. Excluded, not "under-logged".
- **Squash-merged or commit-at-the-end work** — commits exist but measure almost nothing.
  `git-sittings.sh` flags this as `signal_quality: poor`, and it is excluded from the headline.

If most of the work in question is not commit-producing, say so and stop. There is no number to give.

## Step 3 — Compare logged against measured

Write a pairs file — the repo (or **clone group**) and the project its hours land on, tab-separated. The
first field may be a comma-separated list of paths holding the same commits:

```
# repo(s)                                                        project-id
/Users/me/dev/regluvordur                                        412
/Users/me/dev/idnu,/Users/me/flywheel/idnu/…/wp-content/…/myaccount   388
```

```bash
bash "<this-skill-dir>/scripts/logging-gap.sh" \
  --from 2026-06-01 --to 2026-08-21 --pairs pairs.tsv \
  --user 6 --author jontryggvi@avista.is --author 'Jón Tryggvi' --author jontryggvi
```

### Both sides have to describe the same person, and the script now enforces it

An earlier version of this script took only `AUTHOR` — a git filter — and read the ActiveCollab side
**unfiltered**. On a solo project that looks fine. On any shared project it compares one person's commits
against the whole team's timesheet, so colleagues' logged hours land in that person's `logged` column and
the delta stops meaning anything. Run the wrong way round — a team's commits against one person's
timesheet — and it manufactures a large fake shortfall instead.

So the script refuses to guess:

| Invocation | What happens |
|---|---|
| `--user 6 --author <id> [--author …]` | Both sides filtered to one person. The useful case. |
| `--team` | Both sides unfiltered, deliberately. Whole-firm habits. |
| `--author` alone | **Refused** — logged side would be everybody. |
| `--user` alone | **Refused** — measured side would be every committer. |
| neither | **Refused** — says which flags to add. |

`--user` is an ActiveCollab user id; `--author` is a git name/email substring and is **repeatable**,
because people commit under several identities — work email, personal email, bare username, a GitHub
noreply address. Four is normal. Pass every one you know of; missing one moves those commits out of the
measured side without saying so. Get the identities from the repo itself rather than guessing:

```bash
git -C <repo> log --since=2026-06-01 --format='%aN <%aE>' | sort | uniq -c | sort -rn
```

It then does one ActiveCollab read for the window, runs `git-sittings.sh` once per clone group over the
same window, and prints a row per pair:

```
logging gap  2026-06-01 .. 2026-08-21
  scope: logged side filtered to ActiveCollab user 6; measured side filtered to git identities …
  repo                             measured    logged    delta   ratio  signal
  claude-plugins                       7.50       5.8     -1.7    0.77  usable
  ---
  counted 1 pair(s): measured 7.5h vs logged 5.8h  (ratio 0.77)
  logged well below measured on commit-backed work — likely under-logging
  ! 2.25h of the measured side is single-commit sittings — a floor, not a measurement
```

The measured side follows Avista's house rule: 45-minute gap starts a new sitting, each sitting measured
first-commit → last-commit plus a 15-minute lead-in, rounded to 0.25h. Wall-clock elapsed is never used.

Three things it now does that change the numbers, all of them reported in the output:

- **Clone groups are deduplicated by SHA.** Shared code cloned into several checkouts is one body of work,
  not several. Watch `commit_rows` vs `unique_commits`; a wide gap means the same afternoon was readable
  from several paths and would have been counted repeatedly.
- **Commits authored before `--from` are excluded** (pass `--allow-backdated` to keep them). A cherry-pick
  that landed this month was worked last month and belongs on that invoice.
- **Single-commit sittings are surfaced separately** as `floor_only_hours`. Those measure the lead-in
  allowance alone, which is a floor rather than a measurement — never fold them into a headline as though
  they were measured.

## Step 4 — Interpret it honestly

`ratio = logged / measured`.

| Ratio | Reading |
|---|---|
| below 0.8 | Hours worked that never reached a timesheet. The finding worth acting on. |
| 0.8 – 0.95 | Slightly light. Worth a look, inside the noise floor for a single project. |
| 0.95 – 1.5 | Consistent with honest logging plus the non-commit work around it. |
| above 1.5 | Expected wherever most of the work is not commit-producing. Not evidence of over-logging. |

What the number is: **a measure of logging discipline on commit-producing work.**

What it is not, and must not be presented as:

- **Not a productivity metric.** It says nothing about how much anyone got done. Do not rank people by it,
  and do not put a per-person ratio in front of anyone as a performance figure. If the user asks for the
  per-person split, give the logged hours per person — those are facts — and keep the ratio at the level
  it is valid for: the firm's habits across many projects.
- **Not a per-project verdict.** One project at 0.7 is a rounding artefact of how that week was committed.
  Ten projects clustered below 0.9 is a pattern, and the pattern is the answer to "are we under-logging in
  general".
- **Not money.** Do not multiply a gap by `default_hourly_rate` (which `~/.claude/bin/ac GET /job-types` does expose) to
  produce lost revenue. Measure, do not price — and unlogged hours are not automatically billable hours.

State the basis every time: which window, which repos, which author filter, how many pairs were excluded
and why. A ratio with no denominator described is not a finding.

## Step 5 — If there is a real gap

Hand the specifics to `activecollab-log-time` — the missing sittings, with dates, so they land on the right
days rather than as one lump. If the work has no task to attach to, `activecollab-create-task` in **record
mode** makes one first: a short past-tense description, no estimate, completed after posting.

Never log the gap automatically. A number this skill produced is a measurement, not an instruction, and
timesheets feed invoices.

## What this skill must never do

- Write, edit or delete a time record. Read-only, without exception.
- Sum `.value` across a `TrackingFilter` response — that adds ISK to hours.
- Report a company total built by looping over `GETALL /projects` — it silently misses the projects this
  token cannot read.
- Present a filtered-looking call as filtered. `user_id` and `billable_status` on `/time-records` do
  nothing.
- Present a logged-vs-measured ratio as a productivity or performance measure, or attach a currency figure
  to a gap.

## Failure modes

| Symptom | Cause |
|---|---|
| `Invalid timesheet period.` | `from` without `to` on `/time-records`, or a non-`YYYY-MM-DD` date. |
| `character not in range` while reading | A response went through `$(...)`. Redirect to a file. |
| A "one person's" total that matches the company total | `user_id` on `/time-records` was ignored. Filter client-side. |
| A total in the millions | `TrackingFilter` `Expense` records — `.value` in ISK — summed with hours. |
| A project's hours missing from a company report | Built from `GETALL /projects`; that project is not readable by this token. |
| Task shows no tracked time | `tracked_time` was read from the `/tasks` list or `.related.Task`, where it does not exist. Fetch the task directly. |
| Every ratio is absurdly high | The projects are not commit-producing. There is nothing to compare. |
| Headline ratio built on one pair | `signal_quality` excluded the rest. Say so; do not generalise from one. |
| `git-sittings.sh not found` | Run from the plugin tree, or set `GIT_SITTINGS` to its path in `activecollab-suggest-time`. |
| `refusing to run unfiltered by accident` | `logging-gap.sh` needs `--user` **and** `--author`, or an explicit `--team`. Working as intended. |
| One person's gap looks enormous on a shared repo | Their `--author` list is incomplete, or a colleague's commits are in the measured side. Check the identity list against `git log --format='%aE'`. |
| Measured hours far exceed anything anyone worked | A clone group was passed as separate pairs instead of one comma-separated group, so the same commits were counted per copy. |
