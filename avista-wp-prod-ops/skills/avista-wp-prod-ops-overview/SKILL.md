---
name: avista-wp-prod-ops-overview
description: Overview of the avista-wp-prod-ops plugin — what it's for, what its one skill does, and the safety preconditions. Use when the user asks "what does avista-wp-prod-ops do", "what's in this plugin", "how do I get started", or right after installing the plugin.
---

# avista-wp-prod-ops — overview

Tools for operating **safely** on Avista WordPress sites where the local working folder is a near-empty
*shell* repo and the real code lives on **production**, reached over SSH. The dominant case: clients on
TempURL-style hosts running WP Code Box 2 (`wpcodebox2`), where business logic is rows in the database
rather than files in the theme.

Present this overview to the user, then hand off to the skill when they're ready to act.

## What's in the box

| Skill | What it does | When to use it |
|---|---|---|
| `wp-prod-ssh-ops` | Inspect-first / backup-before-change workflow for WP-over-SSH projects: full WP Code Box 2 snippet install/update (clone known-good row → `wp eval-file`), Hummingbird cache-clear, and Breakdance-theme-stub awareness. | Whenever the real site lives on prod over SSH and there's no meaningful local checkout. |

## Safety preconditions (why this plugin exists)

- **Inspect before you touch.** The skill triages the live site first — it never assumes the local repo
  reflects production.
- **Mandatory git backup of DB-stored code** before any change, because WP Code Box snippets are
  database rows, not files — there's no other version history.
- No admin UI required — snippet install/update happens over `wp-cli` (`wp eval-file`).

## Trigger phrases

"the code for this client lives on prod, here's the SSH…" · "back up the wpcodebox snippets before I
change anything" · "this repo is empty, the real site is at host X over ssh" · any mention of WP Code
Box / `wpcodebox` snippets, Breakdance pages, or editing a live WP site with no local checkout.

## More detail

See the plugin [README](../../README.md).
