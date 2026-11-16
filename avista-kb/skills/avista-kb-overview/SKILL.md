---
name: avista-kb-overview
description: Overview of the avista-kb plugin — what the Avista knowledge base is, how its pages are laid out, and when to use kb-pickup versus kb-handoff. Use when the user asks "what does avista-kb do", "how does the knowledge base work", "what's in this plugin", "how do I hand off work", "how do I pick up someone else's feature", or right after installing it.
---

# avista-kb

The Avista knowledge base is a git repo (`Avista/avista-kb`) of markdown pages that say **where code
lives and what state it's in**: in an org repo, on someone's laptop, or only on a production server.
It holds no code and no secrets. The goal is that anyone, or Claude, can continue a feature someone
else built without asking them.

## Skills

| Skill | Use it for |
|---|---|
| `kb-pickup` | "Pick up <feature>", "where does X live", "brief me on <site>". Reads the pages and gives a cold-start briefing. Read-only. |
| `kb-handoff` | "Hand this off", "update the KB". At the end of a session it writes state and next steps and records where the code is. Commits locally, never pushes. |
| `avista-kb-overview` | This page. |

## The KB in one screen

```
sites/<domain>.md              where a site is hosted and where its custom code lives
features/<slug>/overview.md    what a feature is, its components, config and sites
features/<slug>/handoff.md     current state, open issues, next steps
clients/<slug>.md              a client's sites, stack and quirks
decisions/NNNN-*.md            choices that affect more than one feature
```

Each page has YAML frontmatter at the top that the tools read. Feature pages list their sites, and
site pages list their features, in both directions. A code location marked `lives: server-only` is a
valid state. It also queues that code for moving into an org repo.

## Needs

- A clone of `Avista/avista-kb`. Skills look in `$AVISTA_KB_DIR`, then the path saved by
  `kb where --set`, then `~/Dropbox/dev/avista-kb` and `~/dev/avista-kb`.
- `python3` and `git`. For site checks during pickup, SSH access set up with the `setup-site-access`
  skill (avista-dev-machine).
- New site pages are seeded from the fleet site map, which the `fleet-setup` skill
  (avista-wp-fleet) builds.
