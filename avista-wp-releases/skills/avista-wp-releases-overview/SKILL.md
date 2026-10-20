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
| `release-plugin` | Ships a new version of a plugin that already has the pipeline. It bumps, commits, pushes and tags; releases as a pre-release; verifies the built zip (regex, sha256, contents); then marks it Latest. Also cuts **betas** that stay pre-releases. | **Every plugin release or beta.** |
| `release-theme` | The same for a theme. | **Every theme release or beta.** |

> **If you are adapting either scaffold by hand:** never hardcode a `v5pN` PUC namespace. `^5.6` floats to `v5p7`, so a pinned `v5p6` disables the updater — silently for the factory, fatally for `REQUIRE_RELEASE_ASSETS`. Use the `v5` alias and resolve the constant off `get_class( $api )`. Also keep PUC on GitHub Releases only: without the `vcs_update_detection_strategies` filter, PUC falls back to tags and branches and can install a beta's source zip. Existing updaters get it through `setup-plugin-autoupdate` → "Retrofit an existing updater".

## Releases, Latest, and betas

- **Latest is a fleet-wide rollout.** WPMU DEV Hub Automate with "update all" was on for 29 of the 55 fleet sites running an Avista plugin (2026-10-20), mostly Sundays 00:00 UTC. Whatever the updater offers gets installed, so marking a release Latest reaches those sites within about a week. To exclude a plugin on a site, switch that site's Automate setting in the Hub to selected plugins.
- **No Latest without its zip.** Every release is created as a pre-release first. It is marked Latest only after the build is green and the zip is checked: its name against the updater's regex, its sha256 against GitHub's digest, and its contents.
- **Betas never reach production.** A beta is `vX.Y.Z-beta.N`, published `--prerelease` and never marked Latest. Only sites whose `wp-config.php` defines `AVISTA_UPDATE_CHANNEL` as `'beta'` are offered it. That opt-in is explicit, never inferred from the environment or the domain, and it is meant for staging servers only.

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
