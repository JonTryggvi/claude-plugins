---
name: avista-kb-overview
description: Overview of the avista-kb plugin — what the Avista knowledge base is, how its pages are laid out, how to set it up, and when to use kb-setup, kb-handoff or kb-pickup. Use when the user asks "what does avista-kb do", "how does the knowledge base work", "what's in this plugin", "how do I hand off work", "how do I pick up someone else's feature", or right after installing it.
---

# avista-kb

The Avista knowledge base is a git repo (`Avista/avista-knowledge-base`) of markdown pages that say **where code
lives and what state it's in**: in an org repo, on someone's laptop, or only on a production server.
It holds no code and no secrets. The goal is that anyone, or Claude, can continue a feature someone
else built without asking them.

## Getting started

New on this Mac? Say *set up the knowledge base*, or wait: the plugin offers it in your first session.
One dialog, and Claude does the rest.

## Skills

| Skill | Use it for |
|---|---|
| `kb-setup` | First-time setup in one dialog, and changing a choice later (*change how handoffs are shared*). |
| `kb-handoff` | Tracks a feature from the start. One picker explains the knowledge base and offers to track the work as a **draft**. After that it updates the handoff at the end of each session without asking, and a second picker marks the feature **active** when it's finished. Works for repos (plugins, themes, tools) and for SSH work on sites. Shares the handoff as you chose in setup: pull request, push, or local. |
| `kb-pickup` | "Pick up <feature>", "where does X live", "brief me on <site or repo>". Reads the pages and gives a cold-start briefing that flags drafts. Read-only. |
| `avista-kb-overview` | This page. |

## The knowledge base in one screen

```
sites/<domain>.md              where a site is hosted and where its custom code lives
features/<slug>/overview.md    what a feature is, its components, config and sites
features/<slug>/handoff.md     current state, open issues, next steps
clients/<slug>.md              a client's sites, stack and quirks
decisions/NNNN-*.md            choices that affect more than one feature
```

Each page has YAML frontmatter at the top that the tools read. Feature pages list their sites, and
site pages list their features, in both directions. A code location marked `lives: server-only` is a
valid state. It also queues that code for moving into an org repo. A feature can be tracked by its repo
alone, with no sites.

A feature's `status:` is `draft` while it's tracked during the work. Its pages carry a banner saying
they may be incomplete. When the developer confirms it's finished, the status becomes `active`.

## Needs

`kb-setup` checks and sorts out all of this:
- a clone of `Avista/avista-knowledge-base`, and its saved location;
- `git`, `gh` (logged in with an account that can see the repo) and `python3`;
- for site checks during pickup, SSH access via the `setup-site-access` skill (avista-dev-machine).
