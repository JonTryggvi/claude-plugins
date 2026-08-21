---
name: activecollab-reconcile-period
description: Reconcile a whole date window against ActiveCollab — measures every mapped repo over the period, reads back what is already logged, compares per project AND per date, and proposes one time record per sitting for the difference. Use when the user says "reconcile last month", "month-end reconciliation", "what did I not log in July", "close out the period", "catch up my timesheet for the month", "reconcile the period before invoicing", "I need to log a month of work", "find everything I worked on but never logged", or has a window of hours to settle rather than one feature. Deduplicates shared repos cloned into several sites by SHA, excludes cherry-picked older work, reports single-commit sittings separately as a floor, and refuses to propose a record on a date whose hours are already covered by an over-covering correction. Never posts without showing the user every record first. For a single feature use activecollab-suggest-time; for a read-only look at logged hours use activecollab-time-audit.
---

# Reconcile a period

The month-end job, end to end: **measure a window, read what is logged, propose the difference.**

Three skills sit near this one and none of them do this:

| Skill | Scope | Writes? |
|---|---|---|
| `activecollab-suggest-time` | one feature that just landed | proposes |
| `activecollab-time-audit` | is logging discipline slipping? | never |
| **this skill** | a whole window, per project and per date | proposes, posts on approval |
| `activecollab-invoice-preflight` | is one client ready to invoice? | never |

Requires `activecollab-setup` and, before anything else, `activecollab-project-map` — the mapping is what
tells this skill which repos belong to which project, and reconciliation without it is guesswork with a
confident total attached.

## Call the client by its full path

Every `ac` call is `~/.claude/bin/ac`. macOS ships `/usr/sbin/ac` (login accounting) and `~/.claude/bin`
is not on `PATH`, so a bare `ac GET /time-records` prints `total 0.00` and **exits 0**. In a reconciliation
that reads as "nothing is logged this month", and the proposal that follows would double-post the entire
period. The scripts resolve the path themselves; do the same in any call you make by hand.

## Step 0 — Both sides must describe the same person

A reconciliation attributes hours to one person on a real timesheet, so:

```bash
bash "<this-skill-dir>/scripts/reconcile-period.sh" \
  --from 2026-07-01 --to 2026-07-31 \
  --user 6 \
  --author jontryggvi@avista.is --author 'Jón Tryggvi' --author jontryggvi
```

`--user` is the ActiveCollab user id; `--author` is a git identity and is **repeatable**. Both are
required — the script exits rather than guess, because filtering one side and not the other compares two
different populations and reports colleagues' logged hours as this person's missing time.

**Get the identities from the repos, not from memory.** Four per person is ordinary: work email, personal
email, bare username, a GitHub noreply address. A missing one moves real work out of the measured side
without any warning.

```bash
git -C <repo> log --since=2026-07-01 --until=2026-08-01 --format='%aN <%aE>' | sort | uniq -c | sort -rn
```

Show that list and have the user confirm which rows are theirs.

## Step 1 — Validate the map before measuring

```bash
bash "../activecollab-project-map/scripts/project-map.sh" validate
bash "../activecollab-project-map/scripts/project-map.sh" scan ~/dev ~/flywheel
```

A stale map produces confident wrong attribution, which is harder to catch than an error. `validate`
reports dead project ids, renamed projects, changed `budget_type`, and vanished paths; `scan` reports repo
groups that are not in the map at all. Settle both before you measure — an unmapped clone group is simply
absent from the reconciliation, and nothing downstream says so.

## Step 2 — Run the reconciliation

```bash
bash "<this-skill-dir>/scripts/reconcile-period.sh" --from … --to … --user … --author … > recon.json
```

One ActiveCollab read for the window, one `git-sittings.sh` run per mapped clone group. JSON on stdout, a
summary on stderr. **Read-only** — it proposes, it never posts.

## Step 3 — Read the dedupe numbers out loud

```bash
jq '.dedupe' recon.json      # {commit_rows, unique_commits, duplicate_rows, excluded_backdated}
```

This is the first thing to report, because it is the difference between a plausible total and a wrong one.

**Shared repos are cloned into every site that uses them.** A plugin lives in its own checkout and again
inside each Flywheel install, so the same commit is readable from several paths. On a real month-end run
this was **470 commit rows across the clone groups, 323 unique commits** — and the undeduplicated read
came to roughly **92h** where the honest figure was **59h**. Nothing about the 92h looks wrong.

So state both figures whenever they differ:

> *Read 470 commit rows across the mapped repos; 323 unique commits after deduplicating by SHA. The 147
> duplicate rows are the same work readable from more than one clone — counting them would have inflated
> the period by about a third.*

Two related rules the script applies, both reported:

- **A clone group is measured as the UNION of its paths, never as one nominated canonical repo.** The
  standalone checkout is frequently the copy that is *behind*: a `claude-smalls` copy of a plugin at 58
  commits next to the site clone at 63 is not the authority. When row counts differ, the script says so —
  read that as "these are copies at different points", not "this one has extra work".
- **Commits authored before `--from` are excluded.** `--since`/`--until` filter *committer* date, which is
  what you want for "when was this done" — a rebase is work. But a cherry-pick carries an author date from
  weeks earlier, and that work belongs on the earlier invoice. `--allow-backdated` keeps them if the user
  decides otherwise; say which way you ran it.

## Step 4 — Reconcile per date, not per project total

**This is the step that stops a duplicate.** Subtracting a project's logged total from its measured total
tells you a number and hides where it came from.

Some existing records deliberately **over-cover their own date** — someone logs 5h on the 18th to account
for work spread across the 17th and 18th, as an upward correction. Compare project totals and that project
looks settled. Look per date and the 17th looks empty. Post it and the client pays twice for the same
afternoon.

So walk the per-date table:

```bash
jq -r '.projects[] | "\(.slug) (\(.project_id))  measured \(.measured_hours)h  logged \(.logged_hours)h  covered=\(.already_fully_covered)",
       (.dates[] | "   \(.date)  measured \(.measured_hours)h  logged \(.logged_hours)h  \(.status)")' recon.json
```

Each date carries a status:

| Status | Meaning | What to do |
|---|---|---|
| `missing` | measured hours, nothing logged | Candidate for a record — subject to the check below. |
| `partial` | logged less than measured | Candidate for the difference. |
| `covered` | logged ≥ measured | Leave it. |
| `logged-only` | logged hours, no commits | Normal. Meetings, support, admin, page building. |

### The duplicate-risk check

Before proposing anything on a `missing` date, look at whether the **project as a whole** is already
covered:

```bash
jq '.totals.duplicate_risk_hours, [.projects[] | select(.already_fully_covered) | .slug]' recon.json
```

`already_fully_covered` means the project's logged total already meets or exceeds its measured total. Every
empty-looking date on such a project is almost certainly paid for by a record that over-covers its own
date. The script flags those proposals with `duplicate_risk: true` and sums them as
`duplicate_risk_hours`.

**Surface that number before asking for approval**, and do not bury it in a list of proposals. On the
reference run, posting every "missing" date would have put the timesheet **10.9h above the measured
floor** — which is not a discovery of unlogged work, it is a duplication about to happen.

Then separate the two reasons logged can exceed measured, because they look identical in a total and mean
opposite things:

- **Non-commit work** — meetings, support, WP admin, Breakdance page building, client calls. Logged
  legitimately exceeds measured and there is nothing to fix. This is the common case and `overshoot` alone
  cannot tell you it is happening.
- **An over-covering correction** — the same hours already on the timesheet under a neighbouring date.
  This is the duplication, and `duplicate_risk_hours` is the number that measures it.

Say which one you think it is, show the dates it rests on, and let the user decide. Never resolve it
silently in either direction.

## Step 5 — Report single-commit sittings separately, as a floor

```bash
jq '.totals | {measured_hours, measured_floor_only_hours, measured_excluding_floor_hours}' recon.json
```

A sitting with one commit has no span to measure, so it gets the lead-in allowance alone: 0.25h. That is a
**floor** — the work took *at least* that long, and routinely took an hour.

On the reference run this was **36 of 90 sittings, credited 9.00h in total.** Folding that into a headline
would present 9h of floors as 9h of measurement.

So keep it out of the total you present, and list them so the user can raise the ones they remember:

```
  single-commit sittings — a floor, not a measurement (9.00h across 36 sittings):
    2026-07-04   "fix: ACF sync on parent theme"          >= 0.25h
    2026-07-09   "chore: bump plugin version"             >= 0.25h
    …
  Any of these that were actually longer sessions, tell me and I will use your figure.
```

Never quietly inflate a floor to something more plausible. A guessed number on a timesheet is worse than a
visibly conservative one, because nobody knows to question it. And never present the floor total as
measured time — say *"at least 9.00h, which is an undercount"*.

## Step 6 — Propose, one record per sitting, and show every one

```bash
jq -r '.proposals[] | "\(.record_date)  \(.value)h  project \(.project_id)  task \(.task_id // "NONE")  \(if .duplicate_risk then "DUP-RISK" else "" end)  \(.suggested_summary // "")"' recon.json
```

**One record per sitting, each under its own `record_date`.** Collapsing a month into one entry is wrong on
a timesheet even when the total matches — the entries are what someone reads when a line item is queried
six months later. Where two sittings fall on the same date, two records is the honest default; offer to
merge them if the user would rather see one line, but do not merge across dates.

Every proposal needs a task and a job type before it can be written:

- `task_id` comes from the map's `default_task_id`, or from
  `project-map.sh tasks <project-id>` — which merges the open list with `/projects/<id>/tasks/archive`.
  **Include the archived ones.** Completed tasks still accept time records, and for work already done the
  honest match is usually archived — id 12088 *"ACF Fields from Parent theme Sync"* is a real example that
  the open list does not show at all. Use the global `id`, never the small `task_number`.
- `job_type_id` is never auto-picked. More than one job type is flagged `is_default` on this instance
  (both `Design` and `Programming`), so there is no "the default". Ask, or infer from the project and say
  so out loud.
- `billable_status`: check the project's `budget_type` first. `not_billable` projects **store 0 whatever
  you send** — the proposal carries a `billable_hint` for this. Say it before the user approves, not after.

Then show the whole set in plain language and **wait for explicit approval**:

```
Reconciliation 2026-07-01 .. 2026-07-31 — Jón Tryggvi Unnarsson (6)

  Basis   : git commit sittings, 45min gap, +15min lead-in, 0.25h rounding,
            SHA-deduplicated across clone groups (470 rows -> 323 unique commits),
            commits authored before 2026-07-01 excluded
  Measured: 59.00h   of which 9.00h is single-commit floors (36 sittings)
  Logged  : 48.10h
  Proposed: 6 records, 4.25h            ! 2.00h of that is DUPLICATE RISK (see below)

  2026-07-08   1.50h   Iðnú (388)          #12088 ACF Fields from Parent theme Sync
  2026-07-11   0.75h   Iðnú (388)          #12088  (floor — single commit)
  …
  ! Avista Connect (154) is already fully covered in aggregate. The 2.00h below sits on
    dates that look empty but are covered by the 5.00h record on 2026-07-18, which
    over-covers its own date. I have left these out of the proposal — confirm if you
    want them anyway.
  ! Avista Connect (154) is budget_type=not_billable — anything logged there stores as
    non-billable whatever we send.

Post these 6 records? (nothing has been written yet)
```

**Nothing is written before that answer.** Time records feed invoicing, and this skill proposes numbers it
derived rather than numbers the user stated — which is exactly why the human has to see each one.

## Step 7 — Post, then verify by re-reading

Hand each approved record to `activecollab-log-time`. Payload to a **file** — the shell runs under
`LC_CTYPE="C"` and Icelandic summaries break as inline arguments — and set `LC_ALL=en_US.UTF-8` for the
call:

```bash
LC_ALL=en_US.UTF-8 ~/.claude/bin/ac POST /projects/388/time-records "$(cat rec-01.json)" > /tmp/resp.json
jq -r '.single | "record \(.id): \(.value)h on \(.record_date|todate[:10])  billable_status=\(.billable_status)"' /tmp/resp.json
```

Then **re-read the period and confirm it moved as expected**:

```bash
bash "../activecollab-time-audit/scripts/time-logged.sh" --from 2026-07-01 --to 2026-07-31 --user 6
```

Report the before and after totals. Two things this catches that the POST response alone does not: a
record that landed on the wrong date, and a `billable_status` the project silently coerced to 0. Never
report "logged 4.25h billable" from the payload you sent — the only authority is what came back.

If a post fails partway through a set, say exactly which records exist and which do not. A half-posted
reconciliation re-run from the top double-posts the first half.

## What this skill must never do

- Post anything before the user has seen every record. No exceptions, including "just the obvious ones".
- Sum per-clone totals. A clone group is one body of work; dedupe by SHA and report rows vs unique.
- Nominate a canonical repo and drop the rest of its group. Measure the union.
- Fold single-commit sittings into a headline total, or inflate them to a more plausible number.
- Propose a record on a date whose hours are already covered by an over-covering correction, without
  flagging it as duplicate risk and saying so first.
- Collapse several dates into one record because the total matches.
- Present `logged > measured` as over-logging. It is the normal shape of any month containing meetings.
- Multiply a gap by an hourly rate. Measure, do not price — and unlogged hours are not automatically
  billable hours.
- Include commits authored before the window without saying that is what it did.

## Failure modes

| Symptom | Cause |
|---|---|
| `both --user and --author are required` | Working as intended — one filtered side is not a comparison. |
| Measured total roughly 1.5× what anyone worked | Clone groups recorded as separate map entries, so their commits counted once per copy. Fix the map. |
| A project's hours are missing entirely | Its repo group is not in the map. `project-map.sh scan` finds it. |
| `unmapped_logged_projects` is long | Logged hours in projects with no mapped repo. Real hours, just unattributable — non-commit work, or a map gap. |
| Everything shows `signal_quality: poor` | Squash-merged or commit-at-the-end work. Do not propose numbers; ask what to measure from. |
| Proposals all carry `task_id: null` | The map has no `default_task_id`; resolve one per project, archives included. |
| Records posted but the audit total did not move | Wrong `record_date`, or they landed on a project outside the window filter. Re-read before assuming. |
| A billable record reads back non-billable | The project is `budget_type: not_billable`. An override, not an error — report it. |
| `total 0.00` anywhere in the flow | `/usr/sbin/ac` answered. Nothing is logged looks identical to nothing was read. |
