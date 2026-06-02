---
name: avista-memory-tools-overview
description: Overview of the avista-memory-tools plugin — what it bundles, what each skill does, when to reach for each, and how they fit together. Use when the user asks "what does avista-memory-tools do", "what's in this plugin", "how do I get started", "which memory/CLAUDE.md skill do I need", or right after installing the plugin.
---

# avista-memory-tools — overview

Maintenance tools for the three layers that quietly rot if left alone: **agent instructions**
(CLAUDE.md), the **Cowork auto-memory** store, and **git hygiene** before a push. All skills are
*propose-before-execute* and back up before modifying.

Present this overview to the user, then route them to the right skill.

## What's in the box

| Skill | What it does | When to use it |
|---|---|---|
| `bootstrap-agent-md` | Generates a project-local CLAUDE.md from the project's source (structure, README, manifests, recent commits). Refuses to overwrite an existing one. | Joining a project that has **no** CLAUDE.md yet. One-shot per project. |
| `agent-md-audit` | Classifies each section of an existing CLAUDE.md as keep / move-to-skill / move-to-memory / replace-with-pointer / delete; proposes a diff, backs up, applies. | Every few months, or when a CLAUDE.md feels bloated — and after migrating workflow content into a plugin. |
| `memory-health-check` | Lints the Cowork auto-memory store — frontmatter, wiki-link resolution, MEMORY.md size, stale dates, duplicates. | Monthly. (Cowork only — the auto-memory store doesn't exist in Claude Code.) |
| `pre-push-sync-check` | Checks whether the local branch is in sync with `origin/main` — fetches, compares HEAD, reports ahead / behind / diverged / in-sync. | Before any push or release where shipping stale code or a non-fast-forward push would hurt. |
| `release-skill-bundle` | Ships a new version of an Avista skill-bundle plugin to the org marketplace — bump `plugin.json`, land a squash-merged release PR, trigger marketplace sync (or build the upload zip). | Every time you've edited a plugin's source and want the next version live. |

## How they fit together

- **CLAUDE.md lifecycle:** `bootstrap-agent-md` creates (empty-state only) → `agent-md-audit` prunes
  and reclassifies over time. The audit *classifies*, it doesn't relocate — building the skill that
  absorbs moved content is a separate, deliberate act.
- **Memory lifecycle:** `memory-health-check` is the lightweight monthly linter; pair with the
  Anthropic `consolidate-memory` skill for the heavier quarterly reflective pass.
- **Shipping:** `pre-push-sync-check` before you push; `release-skill-bundle` to cut the version. This
  is also the skill that ships *this* plugin's own next version.

## More detail

See the plugin [README](../../README.md) for the persistence-layer table (which skill writes where) and
the propose-before-execute / backup conventions.
