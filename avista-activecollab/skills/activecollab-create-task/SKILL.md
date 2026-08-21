---
name: activecollab-create-task
description: Create a task in Avista's ActiveCollab and assign it to a colleague — resolves the project, assignee, and task list from names to IDs, then writes the description to match what the task is for: a runnable prompt in a magic callout for work that has not started, or a short past-tense summary for work already finished that just needs somewhere to hang a time record. Sets estimate, due date and labels, and posts only after showing the user exactly what will be created. Use when the user says "create a task in ActiveCollab", "add a task for <person>", "assign this to <person> in ActiveCollab", "make an AC task", "add this to the <project> project", "put a prompt in the task description", "set an estimate on that task", "the work is done, create a task for it", "make a task so I can log this time against it", "create a task for the hours I just spent", or describes work that should become a ticket. Also handles updating an existing task's assignee, estimate, or due date. Writes into a shared system other people see, so it never posts without explicit approval.
---

# Create an ActiveCollab task

Turns a piece of work into a task on `active.avista.is`, assigned to a real person.

Requires `activecollab-setup`. If `ac` reports *not configured*, stop and point the user at that skill.

**This writes into a project your colleagues — and on client projects, clients — can see.** Resolve
everything to IDs first, show the user the exact payload, and only then POST. Never guess an assignee.

## Two rules that will bite you

**1. Always write the JSON payload to a file. Never inline it.** The shell here runs under `LC_CTYPE="C"`,
so any multibyte character in an inline argument throws `character not in range` — and Icelandic task
names are full of them (`þ ý ð æ ö á í`). Worse, a mangled call can still reach the API and create a
partial task before the error surfaces. Use the Write tool to create the payload, then:

```bash
ac POST /projects/479/tasks "$(cat /path/to/payload.json)"
```

From a file, UTF-8 round-trips perfectly (`þýðingar` → `þýðingar` → `þýðingar`).

**2. `estimate` requires `job_type_id`.** Sending an estimate without one fails with
`"Job type is required for tasks with estimates"`. Get the job type in the same breath as the estimate —
`ac GET /job-types` lists them, and note that **more than one can be flagged `is_default`** (both `Design`
and `Programming` are), so never auto-pick.

## Step 0 — Decide which kind of task this is

Two different things get called "a task" here, and they want different descriptions. Settle this **before
writing anything**, because it changes the description, the estimate, and what happens after the POST.

| | **Brief** — work that has not happened | **Record** — work that is already done |
|---|---|---|
| Why it exists | Someone has to pick it up and do it | Hours need something to attach to |
| Description | A runnable prompt — step 4A | Two or three lines of past tense — step 4B |
| `estimate` | Set it. It is the plan. | Omit it. There was never a plan. |
| Assignee | The person who will do the work | The person who **did** it — usually the user |
| After posting | Leave it open | Complete it — step 6 |
| Next skill | `activecollab-start-task` | `activecollab-log-time` |

Signals for **record** mode:

- The user arrived from `activecollab-suggest-time`, or has already stated a duration — *"I spent 3 hours
  on the caching work, put it in AC"*, *"log the time for that fix"*.
- Past tense about work that demonstrably exists — the commits are already in the log.
- The only reason a task is being created at all is that a time record needs a parent.

Signals for **brief** mode:

- An assignee other than the user. Handing work to someone means it is not done.
- Future or imperative framing — *"create a task for Daníella to fix the checkout rounding"*.
- No duration mentioned, because nothing has been spent yet.

Default to **brief** when neither set fits, and **name the mode you picked in the step 5 preview** so the
user can flip it in one word. Writing a prompt into a record task is the more expensive mistake: it lands
on someone's board as live work, and `activecollab-start-task` will hand it out as a brief for work that
was finished last week.

If the user wants both — a ticket for finished work *and* a follow-up for what is left — that is two
tasks, one in each mode. Do not compromise by putting a half-prompt in one.

## Step 1 — Resolve the project

```bash
ac GETALL /projects | jq -r '.[] | "\(.id)\t\(.name)"' | sort -k2
```

Use `GETALL`, not `GET`. ActiveCollab caps `/projects` at 100 per page and Avista has 213, so a plain
`GET` silently returns the first hundred — and the project you want is often not in it.

If two projects could plausibly match, **ask**. Posting into the wrong client's project is visible to that
client. If the user gave a numeric ID, trust it but echo the project name back so a typo is caught.

## Step 2 — Resolve the assignee

```bash
ac GET /users | jq -r '.[] | select(.is_archived != true) | "\(.id)\t\(.display_name)\t\(.email)\t[\(.class)]"'
```

- **`class` matters.** `Client` users are external. Assigning to a Client is occasionally correct and
  usually a mistake — if the resolved person is a Client, say so and confirm.
- **Match on the full `display_name`**, not a first-name substring; several people share first names.
- **In record mode**, the assignee is whoever did the work — default to the user's own ID from setup, and
  keep it consistent with the `user_id` that will go on the time record.

The assignee must be a project member. The membership endpoint is `/members` (there is no `/people`), and
it returns an **array of bare user IDs** — not objects:

```bash
ids=$(ac GET /projects/479/members)          # e.g. [2,3,6,21]
ac GET /users | jq -r --argjson m "$ids" '.[] | select(.id as $i | $m | index($i)) | "\(.id)\t\(.display_name)"'
```

## Step 3 — Pick a task list (optional but usually wanted)

The project's tasks endpoint already carries its task lists, so one call covers both:

```bash
ac GET /projects/<project-id>/tasks | jq -r '.task_lists[] | "\(.id)\t\(.name)"'
```

This endpoint returns an **object** (`.tasks`, `.task_lists`, `.project`, …), not an array — `GETALL` will
refuse it and a bare `.[]` will not work. Task lists are per-project; a list ID from another project is
silently wrong.

Omitting `task_list_id` drops the task into the project's default list.

## Step 4A — Brief mode: write the description as a runnable prompt

**A task for work that has not started should carry a prompt in its description** — written so whoever
picks it up can copy it straight into Claude Code and start, without reconstructing the context from the
task title. Treat the description as the handoff, not as a label.

A good prompt states the goal, names the files, gives a reproduction or verification step, and marks what
is out of scope. Write it to a file first:

```
Fix the rounding bug in checkout totals.

Context: `src/cart.php` sums line items with floats; totals drift by 1 ISK on
orders with >3 items and a discount.

Steps:
1. Read `src/cart.php` and `tests/CartTest.php`
2. Reproduce: `php test.php --items=4 --discount=10 > out.txt 2>&1`
3. Fix using integer aurar, not floats
4. Do NOT refactor anything else
```

Then wrap it with the helper, which handles the container markup and the escaping:

```bash
CONTAINER=magic bash "<this-skill-dir>/scripts/prompt-to-body.sh" \
  prompt.md "Prompt for this task — paste into Claude Code:" > /tmp/body.html

jq -n --arg n "$NAME" --rawfile b /tmp/body.html \
  '{name:$n, body:$b, assignee_id:6, task_list_id:1082}' > /tmp/payload.json
```

Build the payload with `jq --rawfile`, never by string-concatenating HTML into JSON.

### Which container

| `CONTAINER` | Markup | Use for |
|---|---|---|
| `magic` *(default for a brief)* | Code block inside ActiveCollab's magic callout — `<aside class="callout-wrapper aside-magic"><div class="callout-content">` | Prompts. Visually prominent *and* copy-safe. |
| `code` | `<pre data-syntax="markdown"><code>` alone | A prompt where the callout would be visual noise. |
| `plain` *(default for a record)* | Bare escaped `<p>` paragraphs | Record-mode summaries — step 4B. No callout, no code block. |
| `magic-only` | Callout with paragraphs, no code block | A note you want visually flagged — **whitespace and line breaks are not preserved**, so a prompt pasted from it arrives mangled. |

All of them round-trip through the API with classes and `data-syntax` intact — verified against the live
instance, including a code block nested inside a callout.

**Never hand-write the HTML.** The body is HTML, so text containing `<`, `>` or `&` — shell redirects,
comparisons, generics, file paths — silently corrupts the markup. `2>&1` becomes a broken tag and the rest
of the prompt disappears from the rendered task. The helper escapes `&` first, then `<` and `>`, which is
the order that matters. This applies to record-mode summaries just as much as to prompts.

## Step 4B — Record mode: write a short description

The work is done. Nobody is going to run this description, so a prompt in it is worse than wasted effort —
it reads as open work to everyone who sees the board, and `start-task` will serve it up as a brief.

Write **two or three lines of past tense**: what changed, where, and whatever a reader will need six
months from now when this line item turns up on an invoice and nobody remembers the week.

```
Fixed the rounding drift in checkout totals — `src/cart.php` now sums in integer
aurar instead of floats. Regression test added in `tests/CartTest.php`.
```

That is the whole description. No numbered steps, no "do NOT refactor", no reproduction command — those
are instructions for someone who still has the work ahead of them.

Nothing here is whitespace-sensitive, so use the plain container. Still go through the helper and still
write to a file: the `LC_CTYPE` trap applies to every call, and a summary of Icelandic work is exactly
where multibyte characters turn up.

```bash
CONTAINER=plain bash "<this-skill-dir>/scripts/prompt-to-body.sh" summary.txt > /tmp/body.html

jq -n --arg n "$NAME" --rawfile b /tmp/body.html \
  '{name:$n, body:$b, assignee_id:6, task_list_id:1082}' > /tmp/payload.json
```

Note what is **absent** from that payload: no `estimate` and no `job_type_id`. An estimate is a plan, and
there was no plan — the hours live on the time record, where they can be billed. Filling in an estimate
after the fact to make a plan-vs-actual report look tidy invents history. The job type still matters, but
it belongs on the time record; you will need it in `activecollab-log-time` either way.

Skip lifecycle labels too (`NEW` and friends) — they describe a queue this task was never in.

## Step 5 — Build the payload and get approval

`POST /projects/<project-id>/tasks`

| Field | Type | Notes |
|---|---|---|
| `name` | string | **Required.** |
| `body` | string | Description — HTML. Build it with `prompt-to-body.sh` (step 4A/4B), never by hand. |
| `assignee_id` | integer | Step 2. Notifies that person. |
| `task_list_id` | integer | Step 3. |
| `estimate` | decimal | Hours, e.g. `2.5`. **Requires `job_type_id`.** A *plan*, not logged time — **brief mode only.** |
| `job_type_id` | integer | Which rate the estimate is against. |
| `due_on` | date | `YYYY-MM-DD`. Also sets `start_on` to the same date if you omit it. |
| `start_on` | date | `YYYY-MM-DD`. |
| `is_important` | boolean | |
| `labels` | array | Label **names**, e.g. `["NEW"]`. `ac GET /labels` lists them (they have `id` and `name` only — no `type` field on this instance). |

Show the resolved values in plain language before posting — names, not just IDs — and **lead with the
mode**, so a wrong call in step 0 costs one word to fix instead of a stray ticket on someone's board:

```
Mode     : BRIEF — description is a runnable prompt, task stays open
Project  : Avista Core - Plugin Development Overview (479)
Assignee : Daniella Casanas (21)  [Owner]
List     : Avista Core (1082)
Name     : Fix the checkout total rounding
Estimate : 2.5h  (job type: Programming)
Due      : 2026-08-22
```

```
Mode     : RECORD — short summary, no estimate, completed after posting
Project  : Avista Core - Plugin Development Overview (479)
Assignee : Jón Tryggvi Unnarsson (6)
List     : Avista Core (1082)
Name     : Rounding fix in checkout totals
Estimate : none (actuals go on the time record)
Then     : 4.25h across 2 sittings via activecollab-log-time
```

Wait for explicit approval, then write the payload file and post. **The response is wrapped in
`single`** — the task is at `.single`, not the top level:

```bash
ac POST /projects/479/tasks "$(cat payload.json)" \
  | jq -r '"created #\(.single.task_number) (id \(.single.id)): \(.single.name)"'
```

## Step 6 — Record mode only: complete the task

A finished piece of work should not sit on the board as open. Completion has its own route — **global, not
project-scoped**, and it takes the task's global `id`, not its `task_number`:

```bash
ac PUT /complete/task/<task-id> '{}' | jq -r '(.single // .) | "completed=\(.is_completed)"'
```

`/open/task/<task-id>` reverses it. Both routes are verified to exist on this instance.

Do this **after** the time record is written if you are logging in the same flow — a completed task still
accepts time records, but doing it in that order means a failure mid-flow leaves an obviously-unfinished
task rather than a closed one with no hours on it.

Say out loud that you are completing it. Completion is visible to the project and, on client projects, to
the client.

## Step 7 — Confirm and hand back a link

```
https://active.avista.is/projects/<project-id>/tasks/<task-number>
```

The URL uses `task_number` (small, per-project); the API uses `id` (global). They are different numbers
and mixing them up sends the user to an unrelated task.

In record mode, follow straight on to `activecollab-log-time` with the project id, task `id` and job type
already in hand — the task exists only so those hours have a parent, so leaving it empty defeats the point.

## Updating an existing task

Same field names, `PUT`, same `single` wrapper:

```bash
ac PUT /projects/479/tasks/13375 "$(cat payload.json)" | jq -r '.single.estimate'
```

Reassigning notifies the new assignee — confirm before doing it.

If you are asked to *retro-fit* an existing brief-mode task whose work is now done, do not strip the
prompt out of the description. The prompt is the record of what was asked for; the divergence between it
and what happened is useful. Complete the task and log the time instead.

## Deleting

```bash
ac DELETE /projects/479/tasks/<id> | jq -r '.single.is_trashed'
```

This is a **soft delete** — the task moves to the project trash (it appears in `.trashed_task_ids`) and
stays recoverable from the UI. Purging permanently is a UI action.

## Estimates vs logged time

`estimate` is a plan. Actual hours are **time records**, a different endpoint — see
`activecollab-log-time`. If the user says "set the time to 3 hours", clarify which they mean; only time
records reach invoicing.

This is also the cleanest way to sanity-check step 0. If the number in play is an estimate, the task is a
**brief**. If it is hours already spent, the task is a **record** and the number does not belong on the
task at all.

## Failure modes

| Symptom | Cause |
|---|---|
| `character not in range`, then a stray task appears | Multibyte characters inline. Use a payload file (top of this skill). |
| `Job type is required for tasks with estimates` | `estimate` sent without `job_type_id`. |
| HTTP 401 | Token dead — re-run `activecollab-setup`. |
| `Failed to match 'projects/N/people' path` | Wrong endpoint; membership is `/members`. |
| Validation error on `assignee_id` | Not a member of the project (step 2). |
| `jq` returns null for `.id` | The response is wrapped — read `.single.id`. |
| Description renders half-empty, or a tag appears mid-sentence | Unescaped `<`, `>` or `&` in the text (e.g. `2>&1`). Use `prompt-to-body.sh`. |
| Prompt pastes out of the task with its line breaks gone | `CONTAINER=magic-only` or `plain` was used for a prompt. Prompts need a code block — use `magic` or `code`. |
| A finished piece of work is sitting on someone's board with a prompt in it | Step 0 called it a brief when it was a record. |
| `/complete/task/<n>` returns an empty 404 | `task_number` passed where the global `id` was wanted, or the task is trashed. |
