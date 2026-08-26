---
name: release-skill-bundle
description: "Ship a new version of an Avista skill-bundle plugin to the org marketplace — bump plugin.json version, land it through a squash-merged release PR, and trigger marketplace sync. Bumps the plugin.json version on a `release/<plugin>-v<VER>` branch, opens a PR with an auto-generated change-list body, squash-merges it into main, then either triggers a GitHub-sync refresh in the admin UI (preferred when the marketplace is connected to the source repo) or packages a .zip for manual upload (fallback). Each release leaves a permanent PR as a discoverable chapter in the repo history. Use when the user says release this plugin, release this skill bundle, ship this plugin, publish to the Avista marketplace, push this plugin to the org, cut a plugin release, bump the plugin version, do a full circle, full PR circle, or full release circle. Targets plugins with .claude-plugin/plugin.json — do not use for WordPress plugins or themes (those have their own release skills in avista-wp-releases)."
---

# Ship a skill-bundle plugin to the Avista org marketplace

Bump the plugin's version, commit the source, and trigger the marketplace to pick up the new version. The Avista marketplace supports two ingestion paths:

- **GitHub sync** — preferred when the marketplace is connected to the plugin's source repo. The skill bumps, hands off a `git commit && git push` to the user, and tells them to click "Update" on the marketplace in the admin UI. No zip-building, no file upload.
- **Manual .zip upload** — fallback for plugins whose marketplace isn't connected to a repo, for first-time publishes of a brand-new plugin, or when GitHub sync is unavailable. The skill packages a `.zip` and the user uploads it through the admin UI.

For the Avista monorepo (`Avista/claude-plugins`), GitHub sync is the path. Default to it unless the user indicates otherwise.

"Do a full circle" / "full PR circle" / "full release circle" are nicknames for this end-to-end flow — they mean run the workflow below from pre-flight through verify, not just one of the steps.

## When to invoke

- The user has edited the source of a Claude plugin (added/changed skills, refined SKILL.md content, fixed a bug) and is ready to distribute the next version.
- The user says "release this plugin", "ship this Claude plugin", "publish to the Avista marketplace", or any similar phrasing.

Do not use this skill for:

- WordPress plugins or themes — those have their own skills (`release-plugin` and `release-theme` in the `avista-wp-releases` bundle).
- Plugins distributed outside the Avista org (community marketplaces, claude-plugins-community, etc.) — those have different submission processes documented at the Anthropic docs.

## Workflow

### Step 1 — Identify the plugin source directory

Ask which plugin to release if it isn't obvious from context. The source directory must:

- Contain a `.claude-plugin/plugin.json` file.
- Be a regular directory on disk (typically under the user's local Avista plugins workspace — they keep these somewhere stable like `~/Dropbox/dev/claude-plugins/<plugin-name>/`).

Read `plugin.json` to record the current `name` and `version`. The `name` field is the canonical identifier and, if the manual-upload path ends up being needed, dictates the zip filename (`<name>.zip`) AND the wrapper-directory name inside the zip — both must match.

### Step 2 — Pre-flight checks

- Verify the `.claude-plugin/plugin.json` is valid JSON with a `name` and `version` field.
- For each `skills/<skill-name>/SKILL.md` in the plugin, verify the file exists, has YAML frontmatter, and the `name:` in frontmatter matches the directory name. A mismatch is the most common silent rejection.
- **Reserved-word check.** Verify that no skill's `name:` field contains the substring `claude` (case-insensitive). The Avista marketplace rejects skill names containing this reserved word with a "Plugin validation failed" error that *does* report the actual rule (unlike many other validation failures). Other reserved words may exist; if any future upload fails with a similar reserved-word message, add the new word to this check. If the check fails, stop and tell the user which skills need renaming and suggest alternatives (e.g. `release-claude-plugin` → `release-skill-bundle`, `claude-md-audit` → `agent-md-audit`).
- If the source directory is a git repo, verify the working tree is clean (no uncommitted changes outside the version bump you're about to make). If dirty, stop and report the dirty files. Do not bump version against an unclean tree.
- **If the source directory is a git repo, verify local `main` is in sync with `origin/main`.** Run `git fetch origin main --tags --quiet` (the `--tags` keeps the local tag list current so the `git describe` in Step 3 doesn't read a stale tag), then verify `git rev-parse HEAD` equals `git rev-parse origin/main` (when on main) or `git merge-base --is-ancestor origin/main HEAD` returns 0 (when on a feature branch). If local is behind, the marketplace sync would ship stale code — stop and tell the user to `git pull --rebase` and rerun. If local is ahead with commits not on the remote, those commits will be in the release; confirm with the user that's intended.
- **`gh` CLI is required.** This skill ships releases via a pull request, which needs `gh`. Run `gh auth status` — if it errors, stop and tell the user to `gh auth login` then rerun.
- **The ACTIVE `gh` account must match the remote's host alias.** `gh auth status` passing is not enough: it reports that *some* account is authenticated, not that the right one is active for this repo. Avista developers hold two accounts, and the mapping is by remote URL (see `HANDOFF-setup-gh-multiuser.md` in the monorepo):

  | Remote URL pattern | `gh` account |
  |---|---|
  | `github.com[:/]<personal>/*` | personal (e.g. `JonTryggvi`) |
  | `github.com-avista[:/]Avista/*` | org (e.g. `jontryggviAvista`) |
  | `github.com[:/]Avista/*` | org |

  The reliable test is whether the active account can actually *see* the repo — not what
  `gh auth status` claims. Derive `owner/repo` from the remote and ask:

  ```bash
  REMOTE=$(git remote get-url origin)
  # BSD sed has no non-greedy +?, so strip .git first, then take the last owner/repo pair.
  SLUG=$(printf '%s' "$REMOTE" | sed -E -e 's#\.git$##' -e 's#^.*[:/]([^/:]+/[^/]+)$#\1#')

  if ! gh repo view "$SLUG" --json nameWithOwner >/dev/null 2>&1; then
    echo "active gh account cannot see $SLUG — switching"
    case "$REMOTE" in
      *github.com-avista*|*Avista/*) gh auth switch --user <org-account> ;;
      *)                             gh auth switch --user <personal-account> ;;
    esac
    gh repo view "$SLUG" --json nameWithOwner >/dev/null \
      || { echo "still cannot see $SLUG — check 'gh auth status' and the account mapping"; exit 1; }
  fi
  ```

  Run this **before** `git push`, not after. Ask the user for the account names if they are not already
  known — the org username follows `<firstname>Avista`, but confirm rather than assume.

  **This failure is easy to misread.** `git push` succeeds regardless, because SSH resolves through the
  `github.com-avista` host alias independently of which `gh` account is active — so the branch lands on
  the remote and only the *next* step fails, with `GraphQL: Could not resolve to a Repository with the
  name 'Avista/claude-plugins'`. That message reads like a missing or renamed repo, not a wrong account.
  Verified 2026-08-25 releasing `avista-activecollab` v0.8.0: the push worked, `gh pr create` did not,
  and the fix was `gh auth switch --user jontryggviAvista`.

  **Leave the account where the release needed it, and tell the user you did.** Switching back silently
  is worse than not switching — a later bare `gh` command in a personal repo will use whichever account
  is active, and the user needs to know which that is.

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

### Step 5 — Branch, commit, push, open and squash-merge a release PR

Skill-bundle releases go to `main` through a pull request, so each release leaves a readable chapter in the GitHub history (title, summary body, files-changed view, permanent URL). The PR is created, body-populated with a change list, and squash-merged in the same step — the user doesn't need to click merge themselves. `main` stays linear; the release branch is deleted after merge.

If the source directory is not a git repo, skip ahead — there's nothing to PR. Fall through to the manual-upload path in Step 6; GitHub sync requires a connected repo anyway.

Run the following sequence. If you have direct shell access on the user's machine (e.g. Claude Code on the local host), run it yourself. If you're in a sandboxed environment that can't write to the user's repo (e.g. Cowork, where the mounted `.git/index.lock` denies the operation), hand the block to the user and wait for confirmation before proceeding.

Substitute `<plugin-name>` (e.g. `avista-memory-tools`), `<NEW_VERSION>` (e.g. `0.4.0`), and `<plugin-path>` (the directory containing `.claude-plugin/plugin.json`, e.g. `avista-memory-tools` when running from the monorepo root).

```bash
# 1. Cut the release branch off the up-to-date main (pre-flight already confirmed main is clean and synced).
BRANCH="release/<plugin-name>-v<NEW_VERSION>"
git checkout -b "$BRANCH"

# 2. Apply the bump (you've already edited <plugin-path>/.claude-plugin/plugin.json in Step 4).
git add <plugin-path>/.claude-plugin/plugin.json
git commit -m "chore(<plugin-name>): release v<NEW_VERSION>"

# 3. Push the branch.
git push -u origin "$BRANCH"

# 4. Compose the PR body. Auto-summarise what changed in this plugin's directory
#    since the previous release commit for the same plugin (or, if no previous
#    release commit exists yet, since the start of history). The body becomes
#    the chapter content for this release.
PREV_SHA=$(git log -n1 --format=%H \
  --grep="^chore(<plugin-name>): release " \
  origin/main -- <plugin-path>/ 2>/dev/null)
if [ -n "$PREV_SHA" ]; then
  CHANGES=$(git log --no-merges --oneline "${PREV_SHA}..HEAD^" -- <plugin-path>/)
else
  CHANGES=$(git log --no-merges --oneline HEAD^ -- <plugin-path>/)
fi
[ -z "$CHANGES" ] && CHANGES="(no changes outside the version bump itself)"
PR_BODY=$(printf 'Release **v%s** of \x60%s\x60.\n\n## Changes since last release\n\n%s\n' \
  "<NEW_VERSION>" "<plugin-name>" "$CHANGES")

# 5. Open the PR and immediately squash-merge it. Branch is deleted on merge.
gh pr create \
  --base main \
  --head "$BRANCH" \
  --title "chore(<plugin-name>): release v<NEW_VERSION>" \
  --body "$PR_BODY"

gh pr merge "$BRANCH" --squash --delete-branch

# 6. Sync the local main with the squashed commit so the next step starts clean.
git checkout main
git pull --ff-only
```

**Branch-protection fallback.** If `gh pr merge --squash --delete-branch` errors because branch protection requires reviews or status checks before merge, do not push around the protection. Tell the user to merge the PR in the GitHub UI (the URL was printed by `gh pr create`), wait for confirmation, then run `git checkout main && git pull --ff-only` and continue with Step 6 (marketplace ingestion).

**Why this design.** Each release ends up as a discoverable PR with a meaningful title, a body summarising what shipped, and the diff hung off it. `main` stays linear (squash merge), and the release branch deletes itself, so the only artifact left in the branch list is `main`. The chapter view lives in the PR list, not the branch list.

If the user prefers their own commit alias (e.g. `gsend`) for the bump, that's fine — but the rest of the sequence (branch, push, `gh pr create`, `gh pr merge`) is the skill's contract for landing the release. What matters is that the bump commit reaches `origin/main` through a PR, not as a direct push.

### Step 6 — Trigger marketplace ingestion

Choose the path based on how the marketplace is wired up. For an Avista plugin in the `Avista/claude-plugins` monorepo, default to Path A (GitHub sync) unless the user indicates otherwise.

#### Path A — GitHub-synced marketplace (preferred)

The marketplace is connected to the plugin's source repo. Picking up the new version is one click:

> The release PR has merged. To make v<NEW_VERSION> available to the Avista org:
>
> 1. Open Claude Desktop → Organization settings → Plugins.
> 2. Find the marketplace that hosts this plugin and click "Update" (or "Sync") on it.
> 3. The marketplace re-reads the connected repo and surfaces the new version on each member's next session or plugin refresh.

No zip, no upload. Skip to Step 7.

If the marketplace doesn't show the new version after clicking Update, the source repo's connection may be misconfigured, or the marketplace may be pointing at a different branch than the one you committed to. Fall through to Path B as a workaround while the connection is fixed.

#### Path B — Manual .zip upload (fallback)

Use this path when:

- The marketplace isn't connected to a source repo (e.g. first-time publish of a brand-new plugin in a new marketplace).
- The user explicitly wants a one-off manual upload.
- GitHub sync is failing and the new version is needed now.

Build the upload zip. The Avista marketplace ingestion expects a regular `.zip` file (not `.plugin`) whose contents are wrapped in a single top-level directory matching the plugin name. Run from the *parent* of the plugin source directory — not from inside it:

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

Now surface the zip to the user.

**If running in Cowork:** copy the zip into the session's outputs folder (typically `~/Library/Application Support/Claude/local-agent-mode-sessions/<...>/outputs/`) and use the `present_files` tool to render it as a card in chat:

```
cp /tmp/<name>.zip <outputs-folder>/<name>.zip
```

**If running in Claude Code or another terminal-attached environment:** the zip is already at `/tmp/<name>.zip` on the user's machine — just tell them the path.

Either way, give the user these upload instructions:

> The `<name>.zip` file is ready. Upload it through the Anthropic admin UI:
>
> 1. Open the Claude desktop app → Organization settings → Plugins.
> 2. Find the marketplace (or click "Add plugins" → "Upload a file" if this is a new marketplace).
> 3. Drop in the `.zip` file.
> 4. Confirm the upload. Uploading a zip with the same plugin `name` overwrites the existing version automatically — no need to delete the old one first.

If the marketplace rejects the upload with "Plugin validation failed," verify the zip's wrapper structure with `unzip -l <name>.zip | head -5` — every path must be prefixed with `<name>/`. That's the most common cause.

### Step 7 — Verify the rollout (optional)

After the user confirms the marketplace has picked up the new version, suggest they verify it's live:

- In a fresh session, open the plugin manager and check the version number for the plugin matches the one just released.
- Or invoke one of the plugin's skills and check that any updated behavior is present.

If the version still shows as the old one, the marketplace may be caching — give it a few minutes and re-check. If it persists, the new version may have failed validation server-side; check the admin UI for any error messages on the plugin that need addressing.

The release flow ends here. What the user does next — keep working on `main`, branch off for the next piece of work, or step away — is up to them and outside this skill's scope.

## Notes

- The `plugin.json` `version` field is the source of truth for what the marketplace serves. Bumping anywhere else (in a skill's SKILL.md frontmatter, in the README) does not affect the version users see.
- **GitHub sync vs. manual upload.** Anthropic's docs frame manual upload as the right fit for "quick iteration, one-off tools, or teams that don't use GitHub for plugin development." Avista's plugins live in a tracked monorepo, so GitHub sync is the better fit and saves the zip-building step entirely. Manual upload is the documented fallback when sync isn't configured.
- **Overwriting on upload.** In the manual-upload path, uploading a zip whose `plugin.json` `name` matches an existing plugin overwrites that plugin's version. You do not delete the old one first. This is also how legacy guidance in older sessions described it as a "delete + re-upload" flow — that was never required; uploading with the same name has always been an overwrite.
- When the manual-upload path runs in Cowork, the `.zip` lands in the session's outputs folder, which is ephemeral — it will be cleared between sessions. The durable source lives in the plugin's local working directory (typically `~/Dropbox/dev/claude-plugins/<name>/`). When the path runs in Claude Code or another terminal-attached environment, the `.zip` is just a regular file at `/tmp/<name>.zip` and stays until the next reboot.
- **Wrapper directory matters (manual path only).** The zip must contain a single top-level directory matching the plugin name. A flat zip (files at root with no wrapper) is silently rejected by the marketplace with "Plugin validation failed" and no detail. This was the bug that caused the first three manual-upload attempts to fail. Always verify with `unzip -l <name>.zip | head` before uploading.
- **File extension matters (manual path only).** The marketplace accepts `.zip`, not `.plugin`. The `.plugin` extension is documented in the Anthropic plugin docs as an in-chat installer format, but the Avista org marketplace upload route doesn't accept it.
- The `zip` step does not respect `.gitignore` — exclusions must be specified on the `zip` command line via `-x`. The exclusion patterns above cover `.git/`, `.DS_Store`, and `node_modules/`; add more for any other build artifacts your plugin produces.

## Refusal cases

- The target directory has no `.claude-plugin/plugin.json`: not a Claude plugin. Tell the user the directory doesn't look like a plugin source and ask for the right path.
- The plugin's `name` field doesn't match the source directory name: refuse to package until the mismatch is resolved. (Renaming a plugin in `plugin.json` without renaming the directory produces a zip that the marketplace installer silently rejects.)
- The plugin contains `commands/` instead of `skills/` (legacy format): warn the user that the new format is `skills/<name>/SKILL.md` directories. Offer to migrate, but don't auto-migrate as part of a release.
