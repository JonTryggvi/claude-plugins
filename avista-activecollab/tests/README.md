# Testing this plugin without touching live data

```bash
bash tests/run-tests.sh              # everything
bash tests/run-tests.sh trashed      # only tests whose section matches
bash tests/run-tests.sh idempotent
```

101 assertions, no network. Nothing reads ActiveCollab, nobody's mailbox, nobody's calendar, and nothing is
written outside a `mktemp -d` that is removed on exit.

## Why this exists

The scripts here talk to a live ActiveCollab, a real mailbox and a real calendar. Verifying a change by
running them against that data is the obvious thing to do and the wrong thing to do: it pulls client
correspondence into a transcript, and on the write path it can put hours on a real timesheet. Without a
fixture harness that pull is the path of least resistance — so this is the harness.

**When extending a skill, add a fixture and an assertion. Reach for live data only to establish a fact
about the API that fixtures cannot tell you** — a response shape, whether a filter is honoured, whether a
route exists — and keep that read-only. Every fixture here started as exactly that kind of probe.

## How the real code gets tested

Every API-calling script resolves its client through `AC_BIN`, so the runner points that at
[`fake-ac`](fake-ac), which serves `fixtures/*.json` by route. The scripts under test are the shipped
files, unmodified — not copies.

| Seam | Pointed at |
|---|---|
| `AC_BIN` | `tests/fake-ac` |
| `AC_FIXTURES` | `tests/fixtures` |
| `AC_PROJECT_MAP` | a temp map built from `fixtures/project-map.json` |
| `AC_RUN_LOG` | a temp copy of `fixtures/runs.jsonl` |
| `CLAUDE_SESSION_STORE` | a temp session store the runner generates |
| `AC_POST_SPOOL` | a temp file capturing what was POSTed |

Git-backed scripts get throwaway repos built by the runner with **pinned author and committer dates**, so
sitting measurements are deterministic. A clone group is made with `git clone`, which reproduces the
duplicate-SHA case exactly rather than approximating it.

## The traps the fixtures deliberately reproduce

Each of these is a real behaviour of the live instance, verified before it was written down. They are the
reason the fixtures are shaped the way they are:

| Fixture | Reproduces |
|---|---|
| `time-records.json` | Carries `is_trashed` on every record and **no trashed records** — the server filters them. A date whose duplicate was deleted looks never-logged. |
| `trash.json` | `.TimeRecord` is a map of **id → summary**, not objects. Ids only. |
| `record-489-16179.json` | A trashed record is served **in full** under its own project — and `fake-ac` 404s it under any other, as the real API does. |
| `project-154.json` / `project-428.json` | Both `is_billable: false`; only 154 is `budget_type: not_billable`. `is_billable` is not the mechanism. |
| POST synthesis in `fake-ac` | A `not_billable` project stores `billable_status: 0` whatever was sent — no error, nothing in the response. This is what makes the write path testable offline. |
| `tasks-open-428.json` / `tasks-archive-428.json` | Open list is an **object** with bare `completed_task_ids`; the archive is an **array** of full objects. |
| `/invoices` | 404s, because it does for an API token. `invoice-preflight` must report it as unverifiable. |
| `time-records.json` record 16209 | A **colleague's** hours in the same project, so filtering to one user is actually tested. |
| `time-records.json` record 16208 | Hours on project 901, which is absent from `/projects` — real hours, unattributable. |
| `gmail-threads.json` | A thread that matches `from:me` with **no `SENT` message in the sample**, which is why thread presence is not evidence of a reply. |
| `calendar-events.json` | An accepted meeting, a **declined** one, and a personal appointment. |

## The neighbouring-date duplicate

`run-tests.sh neighbour` is worth reading on its own, because it is the one duplicate a per-date comparison
**cannot** see, and the test states the whole shape:

| Date | measured | logged | status |
|---|---|---|---|
| 2026-08-12 | 0.75h | 0h | `missing` → **proposed** |
| 2026-08-13 | 0.5h | 3.5h | `covered` |

The 13th's record itemises both days, so the 12th's hours are already paid for — but the 12th genuinely
holds no record, so per-date logic proposes it and the client pays twice. Nothing date-by-date can tell the
difference; the hours are inside another date's prose.

So two independent guards are asserted, and both fire:

1. **`duplicate_risk`** — the project's logged total (5.0h) already exceeds its measured total (1.25h), so
   `already_fully_covered` is true and every remaining proposal on it is flagged. A heuristic, not a proof.
2. **The trashed-record signal** — a previous run already deleted records on that date, which is evidence a
   human judged it. `needs_confirmation_reason` carries it.

Then the durable fix, exercised through the real `project-map.sh decide`: after recording the decision the
date reads `settled-by-decision`, is not proposed, and **stays** unproposed on a third run. That last
assertion is the point of recording anything at all.

## Adding a test

1. Drop the response into `fixtures/` under the name `fake-ac` expects (its header lists the mapping).
2. Add assertions in the matching section of `run-tests.sh`, using `check` (exact) or `checkc` (substring).
3. Wrap new sections in `if want <name>; then … fi` so `run-tests.sh <name>` can select them.
4. Run the whole suite, not just your section — the sections share a temp map and run log, and a test that
   only passes in isolation is not passing.

`fixtures/.next-record-id` is scratch state written by `fake-ac` during POST tests; it is git-ignored.

## What is still not covered

Worth stating plainly, because a suite that hides its gaps is worse than none:

- **No live write is ever exercised.** `post-and-verify.sh --post` is tested against `fake-ac`, which
  reproduces the coercion we know about. A coercion the real instance performs and the stub does not would
  pass here and fail in production.
- **The Gmail and calendar fixtures are shape checks only.** `evidence-sweep` reads those connectors
  through MCP tools, which the runner does not stub — the assertions confirm the fixture shapes a caller
  must handle, not the skill's end-to-end behaviour.
- **`activecollab-setup` is untested.** It installs a 1Password CLI, exchanges a password for a token and
  writes to `~/.claude/.env`. Faking that convincingly is more risk than the coverage is worth.
- **`create-task` / `start-task` writes** are not exercised; `fake-ac` stubs only `POST` to
  `/time-records`.
- **Fixtures drift.** They are snapshots of an instance as it was on 2026-08-21. When a test disagrees with
  production, re-probe the live API read-only before assuming the code is wrong.
