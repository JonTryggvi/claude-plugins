---
name: overview
description: Overview of the avista-wp-releases plugin — what it bundles, what each skill does, the order to use them in, and the prerequisites. Use when the user asks "what does avista-wp-releases do", "what's in this plugin", "how do I get started with the WordPress release pipeline", "which skill do I run first", or right after installing the plugin.
---

# avista-wp-releases — overview

Avista's WordPress release pipeline for plugins **and** themes. It does two jobs: **scaffold** the
GitHub-Releases + plugin-update-checker (PUC v5p6) auto-update pipeline into a project, and **ship**
new versions through it. Auto-updates land in the WP admin as one-click updates from tagged releases.

Present this overview to the user, then point them at the right skill for what they're doing.

## What's in the box

| Skill | What it does | When to use it |
|---|---|---|
| `setup-gh-multiuser` | Onboards a developer's machine for multi-account GitHub — `gh` CLI auth + SSH keys so `git push` and `gh release create` hit the right account based on the repo's remote. | **Once per machine**, before your first release. The prerequisite for everything else. |
| `setup-plugin-autoupdate` | Wires GitHub Releases + PUC into a WordPress **plugin** (bootstrap class, Actions workflow, Composer dep, version constant). | **Once per plugin**, when adding the pipeline to a new plugin. |
| `setup-theme-autoupdate` | Same pipeline for a WordPress **theme** (version from `style.css`, theme-specific PUC args, `<theme-slug>.zip`). | **Once per theme**. |
| `release-plugin` | Ships a new version of a plugin that already has the pipeline — bump, commit, push, tag, release, verify the built zip. | **Every plugin release.** |
| `release-theme` | Ships a new version of a theme that already has the pipeline. | **Every theme release.** |

## Recommended order

```
1. setup-gh-multiuser          ← once per machine (gh accounts + SSH)
2. setup-plugin/theme-autoupdate ← once per project (scaffold the pipeline)
3. release-plugin / release-theme ← each time you ship a version
```

## Prerequisites

- **`setup-gh-multiuser` first.** Releases fail with `403` if `gh` is on the wrong account or the
  machine has no SSH key for the account that owns the repo. Run it before any release.
- A plugin/theme must have the pipeline scaffolded (`setup-*-autoupdate`) before `release-*` works. If
  it isn't wired up yet, `release-*` will tell you to run the matching setup skill first.

## More detail

See the plugin [README](../../README.md) for the plugin-vs-theme seams (version source, PUC arguments,
zip naming, brand-icon injection) and the conventions baked into the bootstrap class.
