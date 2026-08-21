# Testing this plugin without touching live data

```bash
bash tests/run-tests.sh              # everything
bash tests/run-tests.sh trashed      # only tests whose section matches
bash tests/run-tests.sh idempotent
```

83 assertions, no network. Nothing reads ActiveCollab, nobody's mailbox, nobody's calendar, and nothing is
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
