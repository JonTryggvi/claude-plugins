---
name: avista-wp-releases-overview
description: Overview of the avista-wp-releases plugin — what it bundles, what each skill does, the order to use them in, and the prerequisites. Use when the user asks "what does avista-wp-releases do", "what's in this plugin", "how do I get started with the WordPress release pipeline", "which skill do I run first", or right after installing the plugin.
---

# avista-wp-releases — overview

Avista's WordPress release pipeline for plugins **and** themes. It does two jobs: **scaffold** the
GitHub-Releases + plugin-update-checker (PUC v5) auto-update pipeline into a project, and **ship**
new versions through it. Auto-updates land in the WP admin as one-click updates from tagged releases.

Present this overview to the user, then point them at the right skill for what they're doing.

## What's in the box

| Skill | What it does | When to use it |
|---|---|---|
| `setup-plugin-autoupdate` | Wires GitHub Releases + PUC into a WordPress **plugin** (bootstrap class, Actions workflow, Composer dep, version constant). | **Once per plugin**, when adding the pipeline to a new plugin. |
| `setup-theme-autoupdate` | Same pipeline for a WordPress **theme** (version from `style.css`, theme-specific PUC args, `<theme-slug>.zip`). | **Once per theme**. |

> **If you are adapting either scaffold by hand:** never hardcode a `v5pN` PUC namespace. `^5.6` floats to `v5p7`, so a pinned `v5p6` disables the updater — silently for the factory, fatally for `REQUIRE_RELEASE_ASSETS`. Use the `v5` alias and resolve the constant off `get_class( $api )`.
| `release-plugin` | Ships a new version of a plugin that already has the pipeline — bump, commit, push, tag, release, verify the built zip. | **Every plugin release.** |
| `release-theme` | Ships a new version of a theme that already has the pipeline. | **Every theme release.** |

## Recommended order

```
0. setup-dev-machine             ← once per machine — now in the avista-dev-machine plugin
1. setup-plugin/theme-autoupdate ← once per project (scaffold the pipeline)
2. release-plugin / release-theme ← each time you ship a version
```

## Prerequisites

- **A machine set up for multi-account GitHub.** Releases fail with `403` if `gh` is on the wrong account
  or the machine has no SSH key for the account that owns the repo. The `setup-dev-machine` skill handles
  this and **lives in the `avista-dev-machine` plugin** (it moved out of this one — machine setup isn't
  part of a release pipeline). Install that plugin and run `setup-dev-machine` before your first release.
- A plugin/theme must have the pipeline scaffolded (`setup-*-autoupdate`) before `release-*` works. If
  it isn't wired up yet, `release-*` will tell you to run the matching setup skill first.

## More detail

See the plugin [README](../../README.md) for the plugin-vs-theme seams (version source, PUC arguments,
zip naming, brand-icon injection) and the conventions baked into the bootstrap class.
