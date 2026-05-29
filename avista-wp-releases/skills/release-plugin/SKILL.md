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

- On any site with the plugin installed, go to **Plugins → Installed Plugins**. The plugin row should show an "Update available" link within ~12 hours of the release (PUC throttles its check to ~12h). To force an immediate check, click the **"Check for updates" link PUC adds under the plugin row** — it carries the nonce PUC requires. Don't tell users to hand-type a URL: PUC v5p6's trigger is `?puc_check_for_updates=1&puc_slug=<slug>` *plus* a `check_admin_referer` nonce (not the old `?wppuc_update_check=1`), so a typed URL just fails the nonce check.
- If the user wants to test the update *now*, they can run `wp plugin update <plugin-directory>/<plugin-main-file>` via WP-CLI on a non-production install. **Always use the full plugin file path, not the bare slug** — see Step 8 for why. If it reports "already updated" right after a release, that's PUC's CLI throttle — see Step 8 for how to force a fresh check.

### Step 8 — Deploy to production (optional)

The release is built and PUC will pick it up on its next ~12-hour check. If the user wants to push the update to a production install *now*, this step walks through it — but only if production access is already saved in memory. **Do not invent an SSH connection or prompt the user to type one out** — the point of this step is to use connection details the user has already trusted to memory.

**1. Check memory for a production SSH connection.**

Look in the reachable memory stores for a file describing production access. Common locations and patterns:

- Project-local memory directories: `<project>/memory/*.md`, `<project>/.claude/memory/*.md`, `<project>/docs/*.md`. Look for filenames containing `ssh`, `production`, `prod`, `live`, `deploy`, or section headings of the same names.
- Cowork's auto-memory store (`~/Library/Application Support/Claude/local-agent-mode-sessions/<...>/spaces/<id>/memory/`) — same name patterns.

If nothing matches, **skip this step silently**. Optionally tell the user once at the end: *"No production SSH found in memory. To enable one-step production deploys in future releases, save your SSH connection in project memory (`<project>/memory/production_ssh.md`)."*

**2. Confirm with the user before doing anything.**

If memory has matching content, surface it and ask:

> Found production SSH in `<memory-file-path>`. The release v<NEW_VERSION> is now live on GitHub. Want me to push the update to production now?

Wait for an explicit yes. A passive "sure" / "go ahead" counts; silence or "later" means skip.

**3. Run the WP-CLI update over SSH — use the FULL plugin file path, not the bare slug.**

```
ssh <ssh-target-from-memory> "cd <wp-root-from-memory-or-default> && wp plugin update <plugin-directory>/<plugin-main-file>"
```

Concrete example for the `avista-regluvordur` plugin (directory `avista-regluvordur`, main file `regluvordur.php`):

```
ssh jontryggvi_ssh@regluvordur.tempurl.host "cd ~/public_html && wp plugin update avista-regluvordur/regluvordur.php"
```

**Why the full path is mandatory.** WP-CLI looks up plugins by case-sensitive comparison. If the plugin's directory is `avista-regluvordur` (lowercase) but the plugin defines a slug constant like `REGLUVORDUR_SLUG = 'Avista-Regluvordur'` (capitalized), `wp plugin update avista-regluvordur` fails with "Plugin not found" — even though the plugin is installed. The full `directory/main-file.php` form bypasses slug lookup entirely and matches by file path. Use it always; works whether or not there's a case mismatch, no downside.

**If `wp plugin update` reports "Plugin already updated" right after you published a newer release**, that's PUC's WP-CLI throttle — not a missing asset. PUC v5p6 *does* check on `wp plugin update/list/status` (via its `WpCliCheckTrigger`), but only refetches from GitHub if its ~12h interval has elapsed since the last check; otherwise it returns instantly with stale data. Force a fresh check, then re-run the update:

```
ssh <ssh-target> "cd <wp-root> && wp eval '\$c = YahnisElsts\\\\PluginUpdateChecker\\\\v5p6\\\\PucFactory::buildUpdateChecker(\"<repo-url>\", WP_PLUGIN_DIR.\"/<dir>/<main-file>\", \"<slug>\"); if (defined(\"GITHUB_TOKEN\")) \$c->setAuthentication(GITHUB_TOKEN); \$v=\$c->getVcsApi(); if (\$v) \$v->enableReleaseAssets(); \$c->checkForUpdates();' && wp plugin update <dir>/<main-file>"
```

`checkForUpdates()` is the documented force method (vs. the throttled `maybeCheckForUpdates()` the CLI hook calls). The `setAuthentication(GITHUB_TOKEN)` + `enableReleaseAssets()` calls matter for private repos / `REQUIRE_RELEASE_ASSETS`. Nested-quote escaping over SSH is finicky — if the `wp eval` one-liner won't parse, drop the PHP into a temp file with a leading `<?php` and run `wp eval-file /tmp/check.php` instead. Do **not** reach for `wp plugin install <zip> --force` as a workaround unless the zip's top folder matches the install dir (older releases unpack a stray copy — see `setup-plugin-autoupdate`).

**4. Verify the update.**

```
ssh <ssh-target> "wp plugin list --status=active --name=<plugin-directory> --field=version"
```

The output should show the new version. If maintenance mode was toggled during the update, confirm it's off:

```
ssh <ssh-target> "wp maintenance-mode is-active"
```

Should return "Maintenance mode is not active."

**5. Report.**

Tell the user the new version is live on production, the verify command's output, and the URL of the site if known. If anything in steps 3–4 failed, surface the error verbatim and stop — don't try to debug or rollback automatically.

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
