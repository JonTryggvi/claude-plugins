---
name: release-claude-plugin
description: "Ship a new version of an Avista Claude plugin to the org marketplace. Bumps the plugin.json version, commits the source via gsend, re-zips the plugin directory into a .plugin file, and walks through uploading it to the Avista organization marketplace via the Anthropic admin UI. Use when the user says release this plugin, ship this Claude plugin, publish to the Avista marketplace, push this plugin to the org, cut a plugin release, bump the plugin version, or when iterating on a plugin and ready to distribute the next version. Targets Claude plugins (those with .claude-plugin/plugin.json) — do not use for WordPress plugins or themes."
---

# Ship a Claude plugin to the Avista org marketplace

Bump the plugin's version, commit the source, repackage as a `.plugin` zip, and walk the user through the upload UI. The skill does the mechanical work; the actual upload step is a browser action the user performs.

## When to invoke

- The user has edited the source of a Claude plugin (added/changed skills, refined SKILL.md content, fixed a bug) and is ready to distribute the next version.
- The user says "release this plugin", "ship this Claude plugin", "publish to the Avista marketplace", or any similar phrasing.

Do not use this skill for:

- WordPress plugins or themes — those have their own skills (`release-plugin` and `release-theme` in the `avista-wp-releases` bundle).
- First-time publish of a plugin that has never been in the marketplace — the skill assumes the upload mechanism is already known. If the user hasn't published any Claude plugin to Avista before, ask them to walk you through their upload flow once before automating it.
- Plugins distributed outside the Avista org (community marketplaces, claude-plugins-community, etc.) — those have different submission processes documented at the Anthropic docs.

## Workflow

### Step 1 — Identify the plugin source directory

Ask which plugin to release if it isn't obvious from context. The source directory must:

- Contain a `.claude-plugin/plugin.json` file.
- Be a regular directory on disk (typically under the user's local Avista plugins workspace — they keep these somewhere stable like `~/Dropbox/dev/claude-plugins/<plugin-name>/`).

Read `plugin.json` to record the current `name` and `version`. The `name` field is the canonical identifier and dictates the zip filename (`<name>.plugin`).

### Step 2 — Pre-flight checks

- Verify the `.claude-plugin/plugin.json` is valid JSON with a `name` and `version` field.
- For each `skills/<skill-name>/SKILL.md` in the plugin, verify the file exists, has YAML frontmatter, and the `name:` in frontmatter matches the directory name. (Cowork's installer is strict about this — a name mismatch is the most common silent rejection.)
- If the source directory is a git repo, verify the working tree is clean (no uncommitted changes outside the version bump you're about to make). If dirty, stop and report the dirty files. Do not bump version against an unclean tree.
- If `gh` CLI is available, optionally verify the user is authenticated (`gh auth status`) — only matters if the user wants to push the source repo too.

If any check fails, report the issue and stop.

### Step 3 — Propose the next version

Read the current version from `plugin.json`. If the source directory is a git repo, run `git log $(git describe --tags --abbrev=0 2>/dev/null)..HEAD --oneline` to surface what's changed since the last tag (if any tag exists). Propose a semver bump:

- **major** (X.0.0) — breaking changes to skill triggers, removed skills, renamed skills (anything that would break existing installs).
- **minor** (x.Y.0) — new skills added, new bundled references, new trigger phrases.
- **patch** (x.y.Z) — SKILL.md content refinements, typo fixes, README updates, conventions tightening.

Show the user: current version, proposed next version, one-line summary of why. Ask them to confirm or override.

### Step 4 — Bump the version

Edit `plugin.json` and update the `version` field to the new value. Do not touch any other field unless the user explicitly asked for a metadata change in the same release.

Re-validate the JSON after editing (avoid trailing-comma or other syntax mistakes from manual edits).

### Step 5 — Commit the source

If the source directory is a git repo, prepare a commit. Cowork's bash sandbox cannot run git against the user's repos — tell the user to run in their own terminal:

```
gsend "chore: release v<NEW_VERSION>"
```

Wait for the user to confirm the commit landed before proceeding to the zip step. Doing the zip before the commit risks a re-zip from a slightly different on-disk state.

If the source directory is not a git repo, skip the commit step and tell the user — they may want to consider putting the plugin under version control eventually for safer rollback.

### Step 6 — Build the .plugin zip

Run from the plugin source directory:

```
cd <plugin-source-dir>
rm -f /tmp/<name>.plugin
zip -r /tmp/<name>.plugin . -x "*.DS_Store" -x ".git/*" -x ".git" -x "node_modules/*"
```

The exclusion patterns above are deliberate — `.git/` directory and editor cruft must not be in the published bundle. Adjust if the plugin has other build artifacts (e.g. `dist/`, `build/`) that shouldn't ship.

Then copy the zip into the Cowork outputs folder so it's accessible from the chat UI:

```
cp /tmp/<name>.plugin <outputs-folder>/<name>.plugin
```

Use the Cowork outputs path appropriate to the current session (typically `~/Library/Application Support/Claude/local-agent-mode-sessions/<...>/outputs/`).

After the copy, verify the zip:

```
unzip -l <outputs-folder>/<name>.plugin
```

Confirm the listing shows `.claude-plugin/plugin.json`, the `skills/` directory with each expected `SKILL.md`, and any bundled `references/` folders. Catch missing files now, not after upload.

### Step 7 — Present the .plugin file and upload instructions

Use Cowork's `present_files` tool to surface the .plugin file as a card in chat, then give the user explicit upload instructions:

> The `<name>-<version>.plugin` file is ready. Upload it to the Avista org marketplace through the Anthropic admin UI:
>
> 1. Open the Avista organization's plugin management page (the same place you uploaded the previous version from — typically `platform.claude.com` or `claude.ai/settings` under the organization's Plugins / Marketplace section). If you can't find the page, ask Jón Tryggvi or check the Avista internal docs for the admin URL.
> 2. Click "Upload plugin" (or the equivalent button — the label may vary).
> 3. Select the `.plugin` file from the card above (or from the outputs folder if your browser needs a file path).
> 4. Confirm the upload. The marketplace should accept the file and make the new version available to all Avista members on their next plugin sync.

Do not invent a specific URL or button name unless you can verify it. The skill stays correct longer if it points the user at "the place you uploaded the previous version" rather than a specific path that might change.

### Step 8 — Verify the rollout (optional)

After the user confirms the upload, suggest they verify the new version is live:

- In a fresh Cowork or Claude Code session, open the plugin manager and check the version number for the plugin matches the one just uploaded.
- Or invoke one of the plugin's skills and check that any updated behavior is present.

If the version still shows as the old one, the marketplace may be caching — give it a few minutes and re-check. If it persists, the upload may have silently failed validation server-side; check the admin UI for any error messages on the upload that need addressing.

## Notes

- The `plugin.json` `version` field is the source of truth for what the marketplace serves. Bumping anywhere else (in a skill's SKILL.md frontmatter, in the README) does not affect the version users see.
- Cowork's outputs folder is ephemeral — the `.plugin` file you produce here will be cleared between sessions. The durable source lives in the plugin's local working directory; the .plugin file is just a build artifact you regenerate each release.
- The Avista marketplace ingestion path is a web upload through the Anthropic admin UI. There is no CLI command that publishes directly — the upload must be done manually each time. If a CLI command becomes available later, the skill should be updated to use it.
- If the plugin source directory contains a `.gitignore` with `vendor/` or `node_modules/` excluded for the source repo, those are already excluded from the zip via the explicit `-x` patterns above. The zip step does not respect `.gitignore` — exclusions must be specified on the `zip` command line.

## Refusal cases

- The target directory has no `.claude-plugin/plugin.json`: not a Claude plugin. Tell the user the directory doesn't look like a plugin source and ask for the right path.
- The plugin's `name` field doesn't match the source directory name: refuse to package until the mismatch is resolved. (Renaming a plugin in `plugin.json` without renaming the directory will produce a zip that Cowork's installer silently rejects.)
- The plugin contains `commands/` instead of `skills/` (legacy format): warn the user that the new format is `skills/<name>/SKILL.md` directories. Offer to migrate, but don't auto-migrate as part of a release.
