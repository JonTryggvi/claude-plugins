---
name: activecollab-audit
description: Audit what was worked over a window — yesterday, last week or the billing period — and say which hours are on the ActiveCollab timesheet and which are not, with the project and task each belongs to, measured from session time, git commits and client email together. Use when the user says "audit yesterday", "what did I work on yesterday", "hours from last week", "is my time logged", "did I log everything", "close the period", "period audit", "what should I log", or asks whether their timesheet matches the work. Read-only until it proposes records.
---

# Audit a window

One question: **what did I work on, and is it logged?** Over one of three windows.

Requires `activecollab-setup` and `activecollab-project-map`. Reconciliation without a map is guesswork
with a confident total attached — an unmapped repo is simply absent from the answer, and nothing says so.

| Skill | Scope |
|---|---|
| **this skill** | yesterday / last week / the period — measure, compare, propose |
| `activecollab-reconcile-period` | the deep month-end machinery this one calls into |
| `activecollab-time-audit` | read the timesheet back, never measure |
| `activecollab-log-time` | write one record |

## Call the client by its full path

Every `ac` call is `~/.claude/bin/ac`. macOS ships `/usr/sbin/ac` (login accounting) and `~/.claude/bin`
is not on `PATH`, so a bare `ac GET /time-records` prints `total 0.00` and **exits 0**. In an audit that
reads as "nothing is logged", and the proposal that follows double-posts the window.

## This is the desktop app, and it reads one person

Nobody at Avista uses the CLI. That is fine — the Claude desktop app writes its transcripts into
`~/.claude/projects/<mangled-cwd>/*.jsonl`, the same store `session-time.sh` reads. Verified 2026-08-25:
entrypoint `claude-desktop`, `~/Library/Application Support/Claude/local-agent-mode-sessions` held **0**
`.jsonl` files, `~/.claude/projects` held 56 modified that week. The excluded `local-agent-mode-sessions`
folder holds sandbox state, not transcripts.

Two consequences that matter more than they look:

- **There is no shared store.** `~/.claude/projects`, `~/.claude/activecollab-project-map.json` and
  `~/.claude/activecollab-runs.jsonl` are all per-person, per-machine. Never hardcode a user id — resolve
  the ActiveCollab user from the client's own credentials and **say whose timesheet this is**. If David
  and Thorvaldur start running period audits too, three maps will drift apart and three run logs will not
  know about each other, and the run log is the only thing stopping periods from overlapping.
- **An empty store and an idle window both read 0.00h.** `attention-split.sh` refuses to conflate them
  and says which it found. Repeat that distinction in the answer; never report a silent zero.

## Step 1 — Resolve the window, and show your working

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/resolve-window.sh" yesterday
bash "${CLAUDE_SKILL_DIR}/scripts/resolve-window.sh" week [--trailing]
bash "${CLAUDE_SKILL_DIR}/scripts/resolve-window.sh" period
```

`yesterday` and `week` are calendar arithmetic and need no confirmation. **`period` does.**

### Why `period` is half arithmetic

**The billing period ends on the 20th** (`AC_PERIOD_DAY`, default 20) **and the next one starts the day
after.** The two ends are resolved differently, and the script labels which is which in `provenance`:

- **START is the day after last month's 20th — or later, never earlier.** If the last period run in the
  run log ended past the 20th (a cut made on the Monday after a weekend 20th), the period starts the day
  after that cut instead (`provenance.start: "run-log"`), so the slipped days are not proposed twice. It
  never moves earlier: a previous period that stopped short of the 20th produces a `GAP:` note naming the
  uncovered dates. (It used to follow the last run both ways, and drifted — the 2026-09-01..09-13 patch
  run left **2026-08-22..08-31 covered by no period at all**, and the next resolve proposed a start of
  2026-09-14, burying the hole.) **Read the notes**, and stop on a `CHECK:` or `ALREADY COVERED:` one.
- **END is a proposal.** The 20th is recommended, weekend or not; when the 20th is a Saturday or Sunday
  the following Monday is offered beside it. Put `end_alternatives` to the user as a **selection list**
  (`AskUserQuestion`), recommended first, with each option's reasoning as its description:

  > **Period window** — start is 21 Aug 2026, the day after August's 20th. Which end date?
  > - **21 Aug – 20 Sep** *(recommended)* — the period ends on the 20th (a Sunday)
  > - **21 Aug – 21 Sep** — if the cut is made on Monday, end there; the next period then starts the 22nd
  > - *Other* — for when it slips again

### Which prior runs count as periods

`run-log.sh` entries carry no `kind` field, so "the most recent run" is ambiguous: a one-day audit logged
today has a **later** window end than a period audit appended eight minutes after it. Verified
2026-08-25 — the log held a `2026-08-24..2026-08-24` day audit beside a `2026-07-21..2026-08-21` period
run, and naive max-by-window-end would have started the next period on 2026-08-25, **silently losing
22–23 August**.

`resolve-window.sh` therefore counts a run as a period only if `kind == "period"` or, for entries
predating that field, if its window spans ≥ 21 days. **Write `kind` on every run this skill appends.**

The script also reports `overlapping_runs` for any window. A day audit sitting inside a period window is
expected and useful — those records are already posted. Read it before proposing anything.

## Step 2 — Measure attention, correctly

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/attention-split.sh" --from … --to …
```

`session-time.sh` reports **per-directory** totals, and those overlap — two projects open in the same
stretch each claim that hour. `attention-split.sh` adds the two columns that make them safe to quote:

| Column | Meaning | Use for |
|---|---|---|
| `union_hours` | wall clock that actually passed | **the headline** |
| `fair_share_hours` | each instant split evenly among directories open then | **proposing records** — the only per-project column that sums back to the union |

It also folds by **project id, not map slug**. Project 479 is reached by four map entries and 412 by two.
Counting per-slug is what produced a *"204.0h measured / 120.55h logged / 83.45h missing"* headline against
an authoritative **71.45h** logged and a real gap of **16.58h** — and 111 proposals worth 101.6h that would
have gone straight onto a client's invoice.

**Never quote `reconcile-period.sh`'s summary line for a project with more than one map entry.** Recompute.

Three more traps the script reports rather than hides:

- **A per-directory total is not a window total.** `claude-plugins` read 9.00h per-directory, 7.27h as a
  union, **4.58h** fair-share. All three are "correct"; only one belongs on a timesheet.
- **Private entries are excluded and listed separately**, never silently dropped — "where did the other
  hour go" is the first thing anyone asks.
- **`over_max_blocks`** flags a long background command reading as attention. Check before proposing.

Everything here is a **lower bound**. Browser, WP admin, DK, phone and meetings leave no events. Say it
every time; never present attention as the window's total.

## Step 3 — Read what is logged, from the API

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/activecollab-time-audit/scripts/time-logged.sh" --from … --to … --user <id>
```

`/time-records?from&to` is the only date-windowed endpoint, and it ignores the `user_id` it is given —
filter client-side. The run log is a receipt, never an authority on how many hours are logged.

For `period`, also check deliberately-trashed records on candidate dates
(`${CLAUDE_PLUGIN_ROOT}/skills/activecollab-reconcile-period/scripts/trashed-records.sh`). A date whose duplicate was trashed on
purpose looks identical to an unlogged date, and re-posting it charges the client twice.

## Step 4 — Read the email. This is not optional for `yesterday` and `week`

Client communication is real work that leaves no commit. On one audited day it was **six** substantive
IÐNÚ messages and **five** ISON messages — reconciliations, root-cause writeups, decisions requested —
none of which any commit or session directory attributed correctly.

Search the window (sent **and** received), then call **`get_thread` on every thread** before
characterising it. `search_threads` silently returns only the first ~5 messages of a thread, oldest-first,
with no truncation notice. Verified twice: an ISON thread appeared to end on 1 July while carrying **8
messages on 24 August**.

**Flag where email disagrees with the session split.** Sessions are credited to whichever directory was
open, not the client the work was for — a block labelled `avistaconnect` produced an ISON email, and a
block labelled `ison` produced two IÐNÚ ones.

## Step 5 — Report

A table per window: hours (union **and** fair-share), ActiveCollab project, and the task each should land
on. Resolve the project name from the id; the fold label is only whichever member slug came first.

Flag explicitly, every time:

- working directories with **no map entry** — they fall out of every reconciliation silently
- projects where **no open task fits** the work. Note `project-map.sh tasks <id>` merges archived lists,
  but completed lists **reject** new tasks with `Invalid task list`. Check `/projects/<id>/task-lists`
  for what actually accepts one — project 2 has 19 lists and only Inbox (3) does.
- projects with `budget_type: not_billable` — they store `billable_status 0` whatever is sent. Say it
  before approval, not after.
- dates where **logged already exceeds measured**, and say which of the two it is: normal non-commit work
  (the common case), or a record over-covering a neighbouring date (the duplication).
- decisions applied, each with its reason and decided-date. A run shaped by an invisible rule cannot be
  checked.

## Step 6 — Propose, then post only on approval

Trim every proposal to that date's **headroom** (day union minus already-logged). Never propose past what
the day can support — on 2026-08-21 the fair share was 1.77h against 1.32h of headroom, and the honest
record was 1.25h with the cap stated in its own summary.

One record per sitting, each under its own `record_date`. Round to 0.25h; anything below that floor is
noise — drop it and record a decision rather than posting a three-minute record.

Post through `${CLAUDE_PLUGIN_ROOT}/skills/activecollab-log-time/scripts/post-and-verify.sh`, which pre-flights `budget_type` and
diffs sent-vs-stored. Then **re-read the window from the API** and report before/after totals from what
came back — never from the payload sent.

Finally, append the run **with `kind`** and record every judgement call:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/activecollab-reconcile-period/scripts/run-log.sh" append --from … --to … --user … \
  --records 16241,16242 --note "period 2026-08-22..2026-09-21" --kind period
bash "${CLAUDE_PLUGIN_ROOT}/skills/activecollab-project-map/scripts/project-map.sh" decide --slug kfum --date 2026-08-24 \
  --action never_propose --reason "0.02h fair-share; below the 0.25h floor"
```

An audit that settles ten questions and writes none of them down has settled nothing.

## What this skill must never do

- Add per-project or per-directory attention totals. They overlap. Union for the headline, fair-share for
  proposals.
- Quote `reconcile-period.sh`'s delta for a project reached by more than one map entry.
- Present attention as the window's total. It is a floor.
- Report a silent 0.00h without saying whether the store was empty or the window idle.
- Resolve a period start by arithmetic when a prior period run exists, or from a day/week run.
- Judge an email thread from `search_threads` output.
- Propose a date past its headroom, or one whose records were deliberately trashed, without saying so.
- Post anything before the user has seen every record — including "just the obvious ones".
- Hardcode a user id, or assume the map and run log are shared.
