---
name: release-plugin
description: Ship a new version of an Avista WordPress plugin via GitHub Releases — bump version, commit, push, tag and release, verify the build. Use when the user says "release the plugin", "ship a release", "publish a new version", "tag and release", "cut a release", "bump the plugin version", "do a full circle", "full PR circle", "full release circle", or when ready to deploy plugin updates through the PUC auto-updater pipeline. Do not use for themes (release-theme handles those) or for plugins that don't have the auto-updater wired up (run setup-plugin-autoupdate first).
---

# Ship a new plugin release

Bump the plugin header version, commit and push, create the GitHub release, and verify the workflow attached the release asset. The plugin must already have the auto-updater wired up — if it doesn't, route the user to `setup-plugin-autoupdate` first.

"Do a full circle" / "full PR circle" / "full release circle" are nicknames for this end-to-end flow — they mean run the workflow below from pre-flight through verify, not just one of the steps.

## Workflow

### Step 1 — Pre-flight

Run these checks before touching anything. Bail if any fail.

- The repo is on `main` and the working tree is clean (no uncommitted changes, no untracked files that belong in the release).
- **Local `main` is in sync with `origin/main`.** Run `git fetch origin main --quiet`, then verify `git rev-parse HEAD` equals `git rev-parse origin/main`. If local is behind, the release would ship stale code — stop and tell the user to `git pull --rebase` and rerun. If local is ahead with commits that aren't on the remote, those commits would be in the release; confirm with the user that's intended.
- The plugin's main file has a valid `Version:` header (read it; record the current value).
- The plugin has `.github/workflows/release.yml`. If not, the user needs `setup-plugin-autoupdate` first.
- `gh` CLI is authenticated to the right GitHub owner (`gh auth status`). If not, ask the user to run `gh auth login` and rerun the skill.

If anything is dirty or missing, report it and stop — do not bump version or commit against an unclean tree, and do not release from a stale `main`.

### Step 2 — Determine the next version

Look at the current version from the plugin header and the git log since the last release tag (`git log $(git describe --tags --abbrev=0)..HEAD --oneline`). Propose a semver bump:

- **major** (X.0.0) — breaking changes to the public API, REST contract, database schema, or shortcode signatures.
- **minor** (x.Y.0) — new features, additive REST endpoints, new shortcodes, new admin pages.
- **patch** (x.y.Z) — bug fixes, internal refactors, copy changes, asset updates.

Show the user: current version, proposed next version, and a one-line summary of why. Ask them to confirm or override.

### Step 3 — Bump the version

Edit the `Version:` line in the plugin's main file (the plugin header, top comment block). Use the new version string with no `v` prefix — the header takes `1.4.26`, not `v1.4.26`. The `v` prefix is only for the git tag.

Do not edit any other file. The plugin derives `*_VERSION` from this header via `get_file_data()`, so this single edit is the source of truth.

### Step 4 — Commit and push

Run (or hand off to the user, depending on the environment):

```
git commit -am "chore: release v<NEW_VERSION>" && git push
```

If you have direct shell access on the user's machine (e.g. Claude Code on the local host), run it yourself. If you're in a sandboxed environment that can't write to the user's repo (e.g. Cowork, where the mounted `.git/index.lock` denies the operation), tell the user to run it in their own terminal and wait for confirmation.

The version-bump commit must be on the remote `main` before Step 5 — creating the GitHub release before the commit lands would build the *old* version's zip.

If the user prefers their own commit-and-push alias (e.g. `gsend`), that's fine — what matters is that the version-bump commit reaches the remote `main`.

### Step 5 — Create the GitHub release

Two options. Default to the `gh` CLI command.

**Option A — `gh` CLI (preferred for speed).** Run this command (or hand it off to the user if you can't execute it yourself):

```
gh release create v<NEW_VERSION> \
  --title "v<NEW_VERSION>" \
  --notes "<one-line summary of what's in this release>"
```

If the user wants more elaborate notes (changelog, breaking changes section), suggest `--notes-file` pointing at a markdown file, or omit `--notes` so the GitHub web UI prompts for them.

**Option B — Web UI.** Direct the user to `https://github.com/<owner>/<repo>/releases/new`, pick the tag `v<NEW_VERSION>`, enter title and notes, and click Publish.

Either way, the release publish event triggers the workflow.

### Step 6 — Verify the build

Once the release is published, watch the Actions tab: `https://github.com/<owner>/<repo>/actions`. The "Build and Upload Plugin Asset" workflow should run within seconds and finish in under two minutes. If you can poll `gh run list --limit 1` directly, do; otherwise ask the user to confirm when it goes green.

Success criteria:

- The workflow completes successfully (green check).
- The release page (`/releases/tag/v<NEW_VERSION>`) shows `avista-<plugin>-release.zip` attached as an asset, sized roughly the same as previous releases (give or take a few hundred KB).

If the workflow fails or no asset is attached, the release is not actually shippable — PUC won't pick up a release without the asset. Common failures:

- `RELEASE_TAG is empty` — workflow was run via `workflow_dispatch` without a tag input. Re-dispatch with the tag.
- `composer install` failed — `composer.json` has a new dependency that wasn't tested in CI. Investigate, fix on `main`, then re-run the workflow via `workflow_dispatch` against the existing tag.
- `gh release upload` failed with 403 — `permissions: contents: write` was removed from the workflow. Restore it.

### Step 7 — Confirm rollout

Optional but worth offering: tell the user how to verify the update actually rolls out.

- On any site with the plugin installed, go to **Plugins → Installed Plugins**. The plugin row should show an "Update available" link within ~12 hours of the release (PUC caches its update check; clicking "Check for updates" in the admin or appending `?wppuc_update_check=1` to the URL forces an immediate refresh).
- If the user wants to test the update *now*, they can run `wp plugin update <plugin-slug>` via WP-CLI on a non-production install.

The release flow ends here. What the user does next — keep working on `main`, pull the new tag locally, branch off for the next piece of work — is up to them and outside this skill's scope.

## Rollback

If the release turns out to be broken after a few sites updated:

1. Delete the GitHub release (this does *not* delete the tag — installed sites that already updated stay on the broken version).
2. Cut a patch release with the fix immediately. PUC will offer the patch as the next update.
3. Do not delete the tag unless you also want to retag from an older commit — git tag deletion confuses PUC's version cache on installed sites.

If the release is broken before *any* site has updated (the workflow failed before attaching the asset, or you caught it within minutes), it's safe to delete both the release and the tag, fix on `main`, and recut the same version.

## Notes

- The plugin header version is the single source of truth. PUC reads it, the `_VERSION` constant derives from it, the asset cache-buster (if used) reads it. Bumping anywhere else creates drift.
- The git tag format is `v<version>` (with the `v` prefix). The plugin header is the bare version. Do not unify them — WP's header format does not accept `v` prefixes.
- Releases without an attached zip are silently ignored by PUC (because of `REQUIRE_RELEASE_ASSETS`). This fails closed — no broken updates — but also means a release with a CI failure looks "published" while not actually shipping.
