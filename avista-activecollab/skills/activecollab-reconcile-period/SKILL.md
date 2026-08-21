---
name: activecollab-reconcile-period
description: Reconcile a whole date window against ActiveCollab — measures every mapped repo over the period from both git commits and Claude Code session attention, reads back what is already logged, compares per project AND per date, and proposes one time record per sitting for the difference. Use when the user says "reconcile last month", "month-end reconciliation", "what did I not log in July", "close out the period", "catch up my timesheet for the month", "reconcile the period before invoicing", "I need to log a month of work", "find everything I worked on but never logged", or has a window of hours to settle rather than one feature. Deduplicates shared repos cloned into several sites by SHA, excludes cherry-picked older work, replaces single-commit floors with real session spans where one covers the date, reports what is still a floor separately, and refuses to propose a record on a date whose hours are already covered by an over-covering correction. Never posts without showing the user every record first. For a single feature use activecollab-suggest-time; for a read-only look at logged hours use activecollab-time-audit.
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

## Step 4 — Read attention alongside commits

Commits are a weak proxy for time, and the script now measures a second way: **Claude Code's own session
logs**. Measured on a real three-week window in this repo:

| Source | Hours | |
|---|---|---|
| git commit sittings | 1.75h | `signal_quality: poor` |
| **Claude session attention** | **7.75h** | 4.4× closer |
| actually logged | 20.55h | |

The reason is structural rather than lucky. A sitting whose commits cluster at the end measures almost
nothing, and a single-commit sitting measures only the lead-in allowance — 0.25h for what was frequently an
hour. The session log recorded an event every time anything happened, so it can put a real span where the
commit log could only offer a floor.

```bash
bash "<this-skill-dir>/scripts/session-time.sh" --from 2026-07-01 --to 2026-07-31 --map ~/.claude/activecollab-project-map.json
```

`reconcile-period.sh` runs this itself; `--no-sessions` turns it off. Where a date measures higher from
sessions than from commits, the session figure is used and the date is **labelled** in `.dates[].basis`:

| `basis` | Meaning |
|---|---|
| `commits` | Commit spans measured this date. |
| `session>commits` | Sessions measured more; the session figure is used. |
| `session` | No commits at all on this date, but there was a session. |
| `session-replaced-floor` | The commit measurement was pure lead-in floor; a real span replaced it. |
| `none` | Neither. Nothing to propose. |

```bash
jq -r '.projects[].dates[] | "\(.date)  commits \(.commit_hours)h  sessions \(.session_hours)h  -> \(.measured_hours)h  [\(.basis)]"' recon.json
```

This changes conclusions, not just numbers. On the test window two dates that read `covered` under
commit-only measurement became `partial` once attention was counted — genuine shortfalls the commit log
had hidden.

### What attention is and is not

Say this plainly whenever you quote a session-derived figure, because it is a **different kind** of
measurement from a commit span and the two must not be blurred into one total:

- **It is still a lower bound.** Work in an editor, a browser, WP admin, a meeting or on the phone leaves
  no session events. That is why 7.75h still fell far short of the 20.55h really logged.
- **It measures attention, not billability.** A session open while you read documentation is real work; a
  session whose events are a background command running for two hours is not. Blocks over
  `MAX_BLOCK_HOURS` (default 8) are flagged for exactly this.
- **An idle session does not inflate it.** Events only fire when something happens, so a gap over 45
  minutes closes the block by itself. There is no timer to forget to stop — which is the whole reason this
  source is trustworthy in a way a manual tracker would not be.
- **Per-project hours do not add up to wall clock.** Two projects open in the same stretch each claim that
  hour. `session-time.sh` reports `wall_clock_hours` (the union of all blocks) next to the per-project sum
  — on a real month those were **69.82h** and **147.0h**. Quote the union as the headline and treat the
  split as an attribution question, never as arithmetic.

### Two things the script normalises, both reported

- **Subdirectories and worktrees fold into their repository.** A session opened in
  `skills/foo/scripts` is the same project as one opened in the repo root; counted separately they
  fragment one project into dozens of entries that then "overlap" with each other. Resolution uses
  `git rev-parse --git-common-dir`, not `--show-toplevel`, so a worktree folds back onto the project it
  branched from. On a real month this collapsed 72 directories to 31.
- **Grouping is on the `cwd` field inside the log, never the directory name.** The store mangles `/`, `.`
  and spaces all to `-`, so `claude-smalls/Avista Plugins` and `claude-smalls-Avista-Plugins` are
  indistinguishable once mangled. Only the recorded `cwd` is authoritative.

Sandboxed sessions under `local-agent-mode-sessions` are deliberately excluded: their `cwd` is a session
sandbox or an outputs folder, not a repo, so counting them would invent attribution.

### Never read session content

Only `timestamp` and `cwd` are parsed. Session transcripts hold every prompt, file, and credential ever
discussed in them — a reconciliation summary goes onto a shared timesheet, so message content must never
be read, quoted, or summarised into one. If you find yourself wanting a session's text to describe a
record, take the description from the commit subjects or ask the user.

## Step 5 — Reconcile per date, not per project total

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

## Step 6 — Report what is still a floor, as a floor

```bash
jq '.totals | {measured_hours, measured_floor_only_hours, measured_excluding_floor_hours}' recon.json
```

A sitting with one commit has no span to measure, so it gets the lead-in allowance alone: 0.25h. That is a
**floor** — the work took *at least* that long, and routinely took an hour.

On the reference run this was **36 of 90 sittings, credited 9.00h in total.** Folding that into a headline
would present 9h of floors as 9h of measurement.

Session attention (step 4) now rescues most of these: where a session covers the date, the floor is
replaced by a real span and the date reads `session-replaced-floor`. What remains a floor is a date with a
single commit and **no** session — work done outside Claude Code, which nothing here can measure. Those
are the ones to list.

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

## Step 7 — Propose, one record per sitting, and show every one

```bash
jq -r '.proposals[] | "\(.record_date)  \(.value)h  project \(.project_id)  task \(.task_id // "NONE")  \(if .duplicate_risk then "DUP-RISK" else "" end)  \(.suggested_summary // "")"' recon.json
```

**One record per sitting, each under its own `record_date`.** Collapsing a month into one entry is wrong on
a timesheet even when the total matches — the entries are what someone reads when a line item is queried
six months later. Where two sittings fall on the same date, two records is the honest default; offer to
merge them if the user would rather see one line, but do not merge across dates.

A "sitting" is whichever unit the date was actually measured on: commit sittings where the basis is
`commits`, session blocks where it is session-derived. And the proposals for a date are **trimmed to that
date's shortfall** (`measured - logged`), so a `partial` date proposes only what is missing rather than
re-posting hours already there. Each proposal carries `basis`, `commit_hours_that_date` and
`session_hours_that_date`, so the provenance of every number is visible — and the proposals sum exactly to
`totals.proposed_hours`. If they ever do not, something is wrong; say so rather than posting.

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

## Step 8 — Post, then verify by re-reading

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
- Blur session attention and commit spans into one undifferentiated "measured" figure. They are different
  kinds of evidence; every date and every proposal carries its `basis` for a reason.
- Add per-project session hours together and present the sum as time worked. Use `wall_clock_hours`.
- Read, quote or summarise session transcript **content**. Timestamps and `cwd` only.

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
| Session hours are 0 everywhere | The store is elsewhere — set `CLAUDE_SESSION_STORE`. Or the work genuinely happened outside Claude Code. |
| Session hours look implausibly high | Check for blocks flagged `over_max_block` — a long background command reads as attention. |
| Per-project session hours sum far above the month | Expected when projects were open in parallel. Use `wall_clock_hours`. |
| One project fragmented into many entries | Pre-0.5.0 behaviour; `cwd` now folds to the git common dir. If it persists, the paths are not in a repo. |
| A session in a worktree counted as its own project | Resolution uses `--git-common-dir`; `--show-toplevel` would do that. |
