---
name: release-skill-bundle
description: "Ship a new version of an Avista skill-bundle plugin to the org marketplace. Bumps the plugin.json version, commits the source via gsend, repackages the plugin as a .zip with the correct wrapper-directory structure, and walks through uploading it to the Avista organization marketplace via the Anthropic admin UI. Use when the user says release this plugin, release this skill bundle, ship this plugin, publish to the Avista marketplace, push this plugin to the org, cut a plugin release, or bump the plugin version. Targets plugins with .claude-plugin/plugin.json — do not use for WordPress plugins or themes (those have their own release skills in avista-wp-releases)."
---

# Ship a skill-bundle plugin to the Avista org marketplace

Bump the plugin's version, commit the source, repackage as a `.zip` (with a top-level wrapper directory matching the plugin name), and walk the user through the upload UI. The skill does the mechanical work; the actual upload step is a browser action the user performs.

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

Read `plugin.json` to record the current `name` and `version`. The `name` field is the canonical identifier and dictates the zip filename (`<name>.zip`) AND the wrapper-directory name inside the zip — both must match.

### Step 2 — Pre-flight checks

- Verify the `.claude-plugin/plugin.json` is valid JSON with a `name` and `version` field.
- For each `skills/<skill-name>/SKILL.md` in the plugin, verify the file exists, has YAML frontmatter, and the `name:` in frontmatter matches the directory name. A mismatch is the most common silent rejection.
- **Reserved-word check.** Verify that no skill's `name:` field contains the substring `claude` (case-insensitive). The Avista marketplace rejects skill names containing this reserved word with a "Plugin validation failed" error that *does* report the actual rule (unlike many other validation failures). Other reserved words may exist; if any future upload fails with a similar reserved-word message, add the new word to this check. If the check fails, stop and tell the user which skills need renaming and suggest alternatives (e.g. `release-claude-plugin` → `release-skill-bundle`, `claude-md-audit` → `agent-md-audit`).
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

### Step 6 — Build the upload zip

The Avista marketplace ingestion expects a regular `.zip` file (not `.plugin`) whose contents are wrapped in a single top-level directory matching the plugin name. Run from the *parent* of the plugin source directory — not from inside it:

```
cd <parent-of-plugin-source>
rm -f /tmp/<name>.zip
zip -r /tmp/<name>.zip <name> -x "<name>/.git/*" -x "<name>/.git" -x "*.DS_Store" -x "<name>/node_modules/*"
```

For the Avista monorepo, that means: `cd ~/Dropbox/dev/claude-plugins && zip -r /tmp/<name>.zip <name> -x ...`. Do not `cd` into the plugin directory before zipping — that produces a flat archive with no wrapper, which the marketplace silently rejects with "Plugin validation failed."

Verify the zip's structure:

```
unzip -l /tmp/<name>.zip | head -20
```

Every listed path must be prefixed with `<name>/` — e.g. `<name>/.claude-plugin/plugin.json`, `<name>/skills/.../SKILL.md`. If you see paths starting with `.claude-plugin/` or `skills/` at the root with no wrapper, the zip was built from the wrong directory and the marketplace will reject it. Rebuild.

Then copy the zip into the Cowork outputs folder so it's accessible from the chat UI:

```
cp /tmp/<name>.zip <outputs-folder>/<name>.zip
```

Use the Cowork outputs path appropriate to the current session (typically `~/Library/Application Support/Claude/local-agent-mode-sessions/<...>/outputs/`).

### Step 7 — Present the .zip file and upload instructions

Use Cowork's `present_files` tool to surface the `.zip` file as a card in chat, then give the user explicit upload instructions:

> The `<name>.zip` file is ready. Upload it to the Avista org marketplace through the Anthropic admin UI:
>
> 1. Open the Avista organization's plugin management page (the same place you uploaded the previous version from). If you can't find the page, check the Avista internal docs for the admin URL.
> 2. Click "Upload plugin" (or the equivalent button — the label may vary).
> 3. Select the `.zip` file from the card above (or from the outputs folder if your browser needs a file path).
> 4. Confirm the upload. The marketplace should accept the file and make the new version available to all Avista members on their next plugin sync.

Do not invent a specific URL or button name unless you can verify it. The skill stays correct longer if it points the user at "the place you uploaded the previous version" rather than a specific path that might change.

If the marketplace rejects the upload with "Plugin validation failed," verify the zip's wrapper structure with `unzip -l <name>.zip | head -5` — every path must be prefixed with `<name>/`. That's the most common cause.

### Step 8 — Verify the rollout (optional)

After the user confirms the upload, suggest they verify the new version is live:

- In a fresh Cowork or Claude Code session, open the plugin manager and check the version number for the plugin matches the one just uploaded.
- Or invoke one of the plugin's skills and check that any updated behavior is present.

If the version still shows as the old one, the marketplace may be caching — give it a few minutes and re-check. If it persists, the upload may have silently failed validation server-side; check the admin UI for any error messages on the upload that need addressing.

## Notes

- The `plugin.json` `version` field is the source of truth for what the marketplace serves. Bumping anywhere else (in a skill's SKILL.md frontmatter, in the README) does not affect the version users see.
- Cowork's outputs folder is ephemeral — the `.zip` file you produce here will be cleared between sessions. The durable source lives in the plugin's local working directory (typically `~/Dropbox/dev/claude-plugins/<name>/`); the .zip is just a build artifact you regenerate each release.
- The Avista marketplace ingestion path is a web upload through the Anthropic admin UI. There is no CLI command that publishes directly — the upload must be done manually each time. If a CLI command becomes available later, the skill should be updated to use it.
- **Wrapper directory matters.** The zip must contain a single top-level directory matching the plugin name. A flat zip (files at root with no wrapper) is silently rejected by the marketplace with "Plugin validation failed" and no detail. This was the bug that caused the first three release attempts to fail. Always verify with `unzip -l <name>.zip | head` before uploading.
- **File extension matters.** The marketplace accepts `.zip`, not `.plugin`. The `.plugin` extension is documented in the Anthropic plugin docs as an in-chat installer format, but the Avista org marketplace upload route doesn't accept it.
- The `zip` step does not respect `.gitignore` — exclusions must be specified on the `zip` command line via `-x`. The exclusion patterns above cover `.git/`, `.DS_Store`, and `node_modules/`; add more for any other build artifacts your plugin produces.

## Refusal cases

- The target directory has no `.claude-plugin/plugin.json`: not a Claude plugin. Tell the user the directory doesn't look like a plugin source and ask for the right path.
- The plugin's `name` field doesn't match the source directory name: refuse to package until the mismatch is resolved. (Renaming a plugin in `plugin.json` without renaming the directory will produce a zip that Cowork's installer silently rejects.)
- The plugin contains `commands/` instead of `skills/` (legacy format): warn the user that the new format is `skills/<name>/SKILL.md` directories. Offer to migrate, but don't auto-migrate as part of a release.
