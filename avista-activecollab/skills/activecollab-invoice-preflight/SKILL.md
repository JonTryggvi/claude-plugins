---
name: activecollab-invoice-preflight
description: Check one client's period before it is invoiced — what is logged, how much is billable but not yet on an invoice, and which dates have commits with no time record — so billing day is a check rather than archaeology. Use when the user says "check before I invoice", "invoice preflight", "is this client ready to bill", "what can I invoice for <client> this month", "anything unlogged before I send the invoice", "how many billable hours for <client> in July", "are we about to under-bill", or is closing a month for a specific client. Read-only. It also reports what it could NOT verify — the invoice list is unreadable through the API, and non-commit work is invisible to it — because a preflight that hides its blind spots is worse than none.
---

# Invoice preflight, per client

Billing day should be a **check**, not an investigation. Run this per client before the invoice goes out:

1. What is logged for this client in the period.
2. How much of that is billable but **not yet on an invoice** — presumably what this invoice is for.
3. Which dates have **commits but no time record** — work that gets billed late, or never.
4. **What this check could not verify.** That list is not a disclaimer; it is the most useful part.

Read-only, always. Requires `activecollab-setup`; the commits check additionally needs
`activecollab-project-map`, and without it that question is simply unanswered rather than clean.

## Call the client by its full path

`~/.claude/bin/ac`, never bare `ac`. macOS ships `/usr/sbin/ac` and `~/.claude/bin` is not on `PATH`, so a
bare call prints `total 0.00` and **exits 0**. On a preflight that reads as "nothing billable this period",
which is the one wrong answer that costs money directly.

## Step 1 — Run it

```bash
bash "<this-skill-dir>/scripts/invoice-preflight.sh" \
  --from 2026-07-01 --to 2026-07-31 --company 202

bash "<this-skill-dir>/scripts/invoice-preflight.sh" \
  --from 2026-07-01 --to 2026-07-31 --client 'Tækniskólinn' \
  --author jontryggvi@avista.is --author 'Jón Tryggvi'
```

A **client is a company** in ActiveCollab, and every project carries a `company_id` — that is how one
client's projects are gathered. `--client` matches the company name and refuses on an ambiguous match
rather than picking one, because preflighting the wrong client and declaring it clean is worse than an
error.

Two flags worth understanding:

- **`--user` is usually wrong here.** An invoice covers whoever worked on the client, not one person.
  Default to everybody; pass `--user` only when the question really is about one person's hours.
- **`--author` enables the commits-vs-time check** and is repeatable. Without it that check is *skipped*
  rather than run against every committer, and the report says so — because measuring the whole team's
  commits and comparing to one person's records is how a fake shortfall gets manufactured. Pass every
  identity of everyone whose commits should count.

The script uses `GETALL /projects`: that endpoint caps at **100** and this instance has **213**, so a plain
`GET` would silently drop most of a client's projects and report a clean, confident, far-too-low total.

## Step 2 — Read the four numbers, then the flags

```bash
jq '.totals' preflight.json
```

| Number | Meaning |
|---|---|
| `logged_hours` | Everything on the client's projects in the window. |
| `billable_not_yet_invoiced_hours` | `billable_status == 1` and `invoice_item_id == 0`. What the invoice is for. |
| `already_invoiced_hours` | `invoice_item_id != 0`. Do not bill twice; do not edit these. |
| `non_billable_hours` | `billable_status == 0`. Real work that will not reach an invoice. |

Then the flags, each of which has cost someone money before:

- **Dates with commits and no time record.** The direct finding. Hand these to
  `activecollab-reconcile-period`, which reconciles per date and knows how to avoid duplicating an
  over-covering record.
- **Hours logged on a `budget_type: not_billable` project.** Those records store as non-billable *whatever
  was sent* — verified across all 7 such projects on this instance, where every record carries
  `billable_status: 0`. Real work, structurally unbillable. If the client is meant to be billed for it, the
  project setting is the thing to fix, and that is a conversation, not an edit.
- **Time logged on a project with tracking disabled.** Usually means the work belongs somewhere else.

## Step 3 — Say what could not be verified, out loud

```bash
jq -r '.cannot_verify[]' preflight.json
```

Read this section to the user rather than summarising it away. Four blind spots, and each one is a place
money goes missing:

**The invoice list is unreadable.** `GET /invoices` returns **404** for a normal API token on this instance
— verified. So there is no way to read existing invoices, check what is on one, or confirm that an invoice
for this period exists at all. The single invoice signal available is `invoice_item_id` on each time
record. So *"not yet invoiced"* means exactly *"that field is zero"* — not *"I checked the invoices and
this is missing"*. Say it that way.

**Non-commit work is invisible.** Support handled over email, meetings, phone fixes, WP admin — none of it
leaves a git trace, so nothing in this check can find it. On a real month-end run a genuine password-reset
job measured **0.00h**. Route this to `activecollab-evidence-sweep`, and until that has been run, say the
preflight covers commit-producing work only.

**Unmapped projects.** For any of the client's projects with no repo in the project map, "commits but no
time" is *unanswered*, not clean. The report names them. A client whose 15 of 16 projects are unmapped has
had almost nothing checked, and a green preflight there means very little.

**Projects this token cannot read.** Some projects 404 individually. Their hours are real and their names
are not available; report them as unattributed and never guess which client they belong to.

## Step 4 — Present it as a decision, not a total

```
Invoice preflight — Tækniskólinn ehf. (23), 2026-07-01 .. 2026-07-31
Scope: every person. Commits checked for 2 of 3 projects.

  Logged                      42.50h
  Billable, not yet invoiced  38.00h     <- what this invoice would cover
  Already invoiced             0.00h
  Non-billable                 4.50h

  Flags
    ! Tskoli.is (108): 3 dates with commits but no time record — 07-09, 07-16, 07-24
    ! Innri vefur (359): 4.50h logged on a not_billable project — will not reach an invoice

  Could not verify
    ? whether an invoice already exists for this period — /invoices is 404 for this token.
      "Not yet invoiced" means invoice_item_id is zero, nothing more.
    ? commits vs time for Innri vefur (359) — no repo in the project map.
    ? email/meeting/phone work — no git trace. Run activecollab-evidence-sweep.

  Recommendation: settle the 3 flagged dates on Tskoli.is before invoicing
  (activecollab-reconcile-period), and ask whether the 4.50h on Innri vefur was
  meant to be billable. Nothing has been changed.
```

Never present `billable_not_yet_invoiced_hours` as *"the invoice total"*. It is the hours a bill would be
based on; the rate, any retainer or fixed-fee arrangement, discounts and rounding all sit outside anything
this skill can see. **Do not multiply hours by `default_hourly_rate` to produce an invoice figure** — job
types expose that field, and using it here quietly turns a measurement into a quote.

## What this skill must never do

- Write, edit or delete anything. Read-only without exception — this runs next to invoicing, where an edit
  to an already-invoiced record changes history a client was billed against.
- Report a total built from a plain `GET /projects`. That is 100 of 213 and drops most of a client.
- Claim an invoice does or does not exist. `/invoices` is unreadable; only `invoice_item_id` is available.
- Present a clean result without naming what was not checked. An unmapped project is an unanswered
  question, not a pass.
- Run the git check without `--author` and compare a whole team's commits to a filtered timesheet.
- Turn hours into money. Measure, do not price.
- Treat `non_billable_hours` as an error to correct. It is usually deliberate; surface it and ask.

## Failure modes

| Symptom | Cause |
|---|---|
| `no company matching '<name>'` | Clients are companies — `~/.claude/bin/ac GET /companies` lists them. |
| `matches N companies` | Deliberate. Pick one with `--company`; a wrong client declared clean is worse. |
| A client's projects are missing | Built from `GET /projects` instead of `GETALL`. |
| `billable not yet invoiced` is 0 but work clearly happened | Records are `billable_status: 0` — check the project's `budget_type`. |
| `measured` is `-` for every project | No `--author`, so the git check was skipped, or no repos are mapped. |
| Preflight looks clean, invoice comes back short | Almost always non-commit work. Run `activecollab-evidence-sweep` before believing a clean result. |
| `total 0.00` anywhere | `/usr/sbin/ac` answered instead of our client. |
