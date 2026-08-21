# Trashed records, decisions, and run state — the mechanics

Read this when you need the endpoint-level detail behind step 5 of `activecollab-reconcile-period`, or when
extending any of the three state mechanisms. The skill itself carries the rules; this carries the plumbing.

## Contents

- [Why trashed records are hard to see](#why-trashed-records-are-hard-to-see)
- [Resolving a trashed id to a date](#resolving-a-trashed-id-to-a-date)
- [The decisions schema](#the-decisions-schema)
- [`also_logged_under` and coverage](#also_logged_under-and-coverage)
- [The run log](#the-run-log)

## Why trashed records are hard to see

Every row verified against the live instance (ActiveCollab 8.x, `active.avista.is`):

| Endpoint | Trashed records included? | Notes |
|---|---|---|
| `GET /time-records?from&to` | **No — zero, ever** | The response *does* carry an `is_trashed` key, which is what makes this trap convincing. A client-side `select(.is_trashed != true)` on this endpoint is dead code: it filters nothing because the server already did. |
| `GET /projects/<id>/time-records` | No | Same. |
| `GET /users/<id>/time-records` | No | Same. |
| `GET /trash` | **Yes, ids only** | Object keyed by type: `TimeRecord`, `Task`, `TaskList`, `RecurringTask`. The `TimeRecord` value is a map of **id → summary string** — no date, no value, no project. |
| `GET /projects/<pid>/time-records/<id>` | **Yes, in full** | Serves a trashed record with `record_date`, `value`, `is_trashed: true`, `invoice_item_id`. **404s if `<pid>` is wrong.** |
| `GET /time-records/<id>` | n/a | Not a route — returns a `code/message/type` error object. |

The consequence for a reconciliation: a date whose only records were trashed is indistinguishable, through
the date-windowed endpoint, from a date that was never logged. That is why it gets re-proposed.

## Resolving a trashed id to a date

`/trash` gives ids; the fields need a project. So the resolution is a probe:

1. `GET /trash` → `.TimeRecord | keys` — the trashed record ids, across all projects.
2. For each id, try `GET /projects/<pid>/time-records/<id>` for each candidate project until one returns an
   object with a `record_date`. Candidates come from the project map (`project_id` plus every
   `also_logged_under`), which bounds the work: a handful of ids against ~15 projects.
3. Any id that no candidate accepts is **unresolved** — report it. Its date and value are unknown, and an
   unseen deleted record is precisely the one that comes back.

`scripts/trashed-records.sh` does this and reports `project_probes` so the cost is visible. On the reference
data: 2 trashed ids, 10 probes, both resolved to project 489 on 2026-08-12 (0.75h + 1.25h = 2.00h).

## The decisions schema

Stored per map entry, in `decisions`:

```json
{"date": "2026-08-12",
 "action": "never_propose",
 "reason": "already inside record 16112 of 2026-08-13, which itemises it",
 "decided": "2026-08-21"}
```

| Field | Required | Notes |
|---|---|---|
| `date` | yes | `YYYY-MM-DD`. The date the decision is about, not the date it was made. |
| `action` | yes | `never_propose` or `capped_at`. |
| `reason` | yes | Refused if empty. An unexplained decision is indistinguishable from a mistake and gets reversed. |
| `decided` | yes | Stamped by `decide`. Lets a stale call be spotted. |
| `hours` | `capped_at` only | What was deliberately logged, e.g. `2.40`. |

`project-map.sh decide` replaces any decision matching the same `date` **and** `action`, so re-running
updates instead of duplicating. Validation also runs on `put`, so a hand-written entry cannot smuggle a
malformed decision in.

`reconcile-period` matches on `(entry, date)`. A matched date is marked `settled-by-decision`, contributes
no proposals, and appears in `.decisions_applied` with its reason.

## `also_logged_under` and coverage

An array of project ids on a map entry. When deciding whether date *D* is covered for that entry,
`reconcile-period` adds the logged hours those projects hold on *D*:

```
covered_total = own logged hours + hours on also_logged_under projects
```

`covered_total` drives the date status, and the components stay separate in the output
(`logged_hours`, `logged_elsewhere_hours`, `logged_elsewhere[]`) so the attribution is inspectable. A date
covered only by another project reads `covered-elsewhere`, never plain `covered`.

Note the deliberate asymmetry: this affects **coverage**, not hour totals. It never adds another project's
hours into this project's measured or logged sums — that would double-count across a report. If the other
project is itself mapped, its own reconciliation still accounts for those hours normally.

## The run log

`~/.claude/activecollab-runs.jsonl` (override `AC_RUN_LOG`), mode 0600, append-only, one object per line:

```json
{"at":"2026-08-21T14:44:49Z","host":"mbp","window":{"from":"2026-08-01","to":"2026-08-31"},
 "user_id":6,"records_posted":84,"record_ids":[16301,16302],"decisions_applied":2,"note":"month-end 2026-08"}
```

`run-log.sh check` returns runs whose window overlaps the one being reconciled. `append` records a posting
run.

**It is a receipt, not a source of truth.** ActiveCollab holds the hours; reading this log to answer "how
much is logged" is how two sources of truth drift apart. It exists for the two questions the API cannot
answer:

- *Did a run already cover this window?* — so a re-run that surfaces a subset of proposals can say whether
  that is new work or the effect of a changed mapping.
- *Which records did this tool create?* — so a posting run that failed halfway can be resumed rather than
  repeated.

Judgement calls do not belong here. They are durable and reviewed, and they belong in the map's `decisions`
array where they are versioned alongside the mapping and read on every run.
