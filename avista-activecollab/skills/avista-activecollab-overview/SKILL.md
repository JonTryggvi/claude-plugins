---
name: avista-activecollab-overview
description: Overview of the avista-activecollab plugin — what it bundles, what each skill does, the order to use them in, and how authentication works. Use when the user asks "what does avista-activecollab do", "what's in this plugin", "how do I get started with ActiveCollab", "which ActiveCollab skill do I run first", "how do I create a task from Claude", or right after installing the plugin.
---

# avista-activecollab — overview

Talks to Avista's ActiveCollab (`https://active.avista.is`, self-hosted 8.x) from Claude Code: create
tasks, assign them to colleagues, set estimates, and log tracked hours.

Present this overview, then point the user at the right skill.

## What's in the box

| Skill | What it does | When to use it |
|---|---|---|
| `activecollab-setup` | Installs the 1Password CLI, exchanges the user's ActiveCollab login for an API token, writes it to `~/.claude/.env`, installs the `ac` client, and verifies with a live call. | **Once per machine**, before anything else. |
| `activecollab-create-task` | Creates a task — resolves project, assignee and task list from names to IDs, sets estimate/due date/labels, posts on approval. Also updates existing tasks. | Turning described work into a ticket. |
| `activecollab-log-time` | Logs a time record against a task or project — resolves job type and person, posts on approval. | Recording hours actually worked. |
| `activecollab-suggest-time` | Measures working time from the git log (commits grouped into sittings), finds candidate tasks, and proposes one entry per sitting. Refuses to guess when commits are a poor signal. | After finishing a feature, when you need to know what to log and against what. |

```
1. activecollab-setup          ← once per machine
2. activecollab-create-task    ← whenever work needs a ticket
3. activecollab-suggest-time   ← when a feature lands: what to log, against which task
   activecollab-log-time       ← writes it
```

## Estimates are not logged time

The single most common mix-up. A task's `estimate` is a **plan**; a time record is **hours actually
worked**. Different endpoints, different reports, and only time records reach invoicing. When a user says
"set the time to 3 hours", find out which they mean before writing anything.

## How auth works

ActiveCollab 8 removed the API-token page from user profiles, so `POST /api/v1/issue-token` with the
account password is the only way to get a token. `activecollab-setup` does that exchange once — reading
the password straight out of 1Password into the request, never storing or echoing it — and keeps only the
resulting token.

The token lands in `~/.claude/.env` (mode `0600`) as `ACTIVECOLLAB_TOKEN`, next to the team's other
tokens. A 1Password-backed variant exists (`AC_STORE_OP=1`) that keeps the token off disk entirely, at the
cost of an unlock prompt on every API call — Claude Code starts a fresh shell per command, so those
prompts do not batch.

Tokens are revocable from ActiveCollab without touching the password. Re-running setup invalidates the
previous token, because ActiveCollab keys one subscription per `client_name` + `client_vendor`.

## The `ac` client

Setup installs `~/.claude/bin/ac`, a thin wrapper the skills call:

```bash
ac GET    /users
ac GETALL /projects                  # follows pagination
ac POST   /projects/428/tasks '{"name":"Fix it","assignee_id":6}'
ac PUT    /projects/428/tasks/91 '{"estimate":2.5}'
ac DELETE /users/6/api-subscriptions/511
```

**Use `GETALL` for collections.** `/projects` is capped at 100 per page; Avista has 213. A plain `GET`
returns the first page with no indication anything is missing, which quietly produces wrong answers.
`GETALL` reads the `X-Angie-Pagination*` headers, walks every page, and warns if the merged count does not
match the advertised total. Endpoints that ignore paging (`/users`, `/job-types`, `/labels`) pass through
unchanged, and object endpoints (like `/projects/:id/tasks`) are refused with a clear message.

## Safety posture

Everything here writes into a system the whole company and, on client projects, clients themselves can
see. Both write skills resolve names to IDs first, echo the resolved values back in plain language, and
post **only after explicit approval**. Assignments and reassignments notify people; time records feed
invoicing. Deleting a time record destroys billable history — correct the value instead where possible.

## More detail

See the plugin [README](../../README.md) for the API notes worth knowing before extending this —
pagination behaviour, the `id` vs `task_number` trap, and the multiple-defaults quirk in job types.
