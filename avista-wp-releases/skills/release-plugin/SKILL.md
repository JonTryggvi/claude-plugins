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
- **Local `main` is in sync with `origin/main`.** Run `git fetch origin main --tags --quiet`, then verify `git rev-parse HEAD` equals `git rev-parse origin/main`. If local is behind, the release would ship stale code — stop and tell the user to `git pull --rebase` and rerun. If local is ahead with commits that aren't on the remote, those commits would be in the release; confirm with the user that's intended. (The `--tags` keeps the local tag list current — the previous release's tag was created on the remote by `gh release create` and is never pulled back automatically, so without this the latest-tag check in Step 2 reads a stale tag.)
- The plugin's main file has a valid `Version:` header (read it; record the current value).
- The plugin has `.github/workflows/release.yml`. If not, the user needs `setup-plugin-autoupdate` first.
- **Switch `gh` to the correct account for this repo.** Check the remote URL with `git config --get remote.origin.url`, then:
  - `*github.com[:/]JonTryggvi*` → `gh auth switch --user JonTryggvi`
  - `*github.com-avista[:/]Avista*` or `*github.com[:/]Avista*` → `gh auth switch --user jontryggviAvista`
  Do this silently — only report if the switch fails. Confirm the active account with `gh api user --jq .login`.

If anything is dirty or missing, report it and stop — do not bump version or commit against an unclean tree, and do not release from a stale `main`.

### Step 2 — Determine the next version

Look at the current version from the plugin header and the git log since the last release tag (`git log $(git describe --tags --abbrev=0)..HEAD --oneline`). Because Step 1 fetched tags, `git describe` now reflects the actual latest release. If the header is *still* ahead of the latest tag, that's a genuine "a prior bump was committed but the release was never created" case — flag it to the user and offer to create the missing release for the existing header version, rather than treating it as a normal bump. Propose a semver bump:

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

Once the release is confirmed, run `git fetch origin --tags --quiet` to pull the just-created `v<NEW_VERSION>` tag into the local repo. `gh release create` makes the tag on the remote only — without this, the local tag list stays a release behind and the next run's Step 2 check re-triggers the "was this version actually released?" detour.

If the workflow fails or no asset is attached, the release is not actually shippable — PUC won't pick up a release without the asset. Common failures:

- `RELEASE_TAG is empty` — workflow was run via `workflow_dispatch` without a tag input. Re-dispatch with the tag.
- `composer install` failed — `composer.json` has a new dependency that wasn't tested in CI. Investigate, fix on `main`, then re-run the workflow via `workflow_dispatch` against the existing tag.
- `gh release upload` failed with 403 — `permissions: contents: write` was removed from the workflow. Restore it.

### Step 7 — Confirm rollout

Optional but worth offering: tell the user how to verify the update actually rolls out.

- On any site with the plugin installed, go to **Plugins → Installed Plugins**. The plugin row should show an "Update available" link within ~12 hours of the release (PUC throttles its check to ~12h). To force an immediate check, click the **"Check for updates" link PUC adds under the plugin row** — it carries the nonce PUC requires. Don't tell users to hand-type a URL: PUC v5p6's trigger is `?puc_check_for_updates=1&puc_slug=<slug>` *plus* a `check_admin_referer` nonce (not the old `?wppuc_update_check=1`), so a typed URL just fails the nonce check.
- If the user wants to apply the update *now* (any site), the reliable path is force-installing the release zip — `gh release download … && wp plugin install <zip> --force`. See Step 8 for the full command. Note CLI `wp plugin update` is **not** dependable for GitHub-PUC plugins (PUC's CLI check is throttled and a forced check doesn't carry over to the update command). The admin "Update" button is also only best-effort — it can report "the plugin is at the latest version" even just after a check shows the update (see the Admin-UI note in Step 8 for the mechanism). The one *deterministic* path is `wp plugin install --force` (Step 8).

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

**3. Deploy by force-installing the release zip — this is the reliable CLI path.**

Do **not** use `wp plugin update <dir>/<file>` for a GitHub-PUC plugin from CLI. It is unreliable: PUC's WP-CLI check (`WpCliCheckTrigger` → the throttled `maybeCheckForUpdates()`) usually reports "Plugin already updated", and — verified — even forcing a fresh check with `$checker->checkForUpdates()` in a separate `wp eval` process does **not** make the subsequent `wp plugin update` apply it (the forced result doesn't survive cross-process into what `wp plugin update` reads). Instead, download the release asset and force-install it. This relies on the zip's top-level folder matching the install directory — guaranteed by `setup-plugin-autoupdate`'s `__BUILD_DIR_NAME__`; if it mismatches, `--force` unpacks a stray copy instead of upgrading in place.

`gh` must be authenticated locally to read the (often private) release asset. Run the download locally, scp it up, then force-install over SSH bracketed by maintenance mode:

```
gh release download v<NEW_VERSION> -R <owner>/<repo> -p '*.zip' -O /tmp/rv.zip
scp /tmp/rv.zip <ssh-target>:/tmp/rv.zip
ssh <ssh-target> "cd <wp-root> && wp maintenance-mode activate && wp plugin install /tmp/rv.zip --force && wp maintenance-mode deactivate && wp plugin get <plugin-directory> --field=version && rm -f /tmp/rv.zip"
```

Concrete example (`avista-regluvordur`):

```
gh release download v1.4.39 -R Avista/Avista-Regluvordur -p '*.zip' -O /tmp/rv.zip
scp -i ~/.ssh/jont /tmp/rv.zip jontryggvi_ssh@regluvordur.tempurl.host:/tmp/rv.zip
ssh -i ~/.ssh/jont jontryggvi_ssh@regluvordur.tempurl.host "cd ~/sites/regluvordur && wp maintenance-mode activate && wp plugin install /tmp/rv.zip --force && wp maintenance-mode deactivate && wp plugin get avista-regluvordur --field=version && rm -f /tmp/rv.zip"
```

`--force` overwrites the plugin directory in place; the plugin stays active and the version updates. Maintenance mode ensures no request hits half-swapped files. Afterward, confirm only `avista-<plugin>/` exists in the plugins dir (no stray `<repo>/` copy).

**Admin-UI alternative (no SSH) — works, but best-effort, not guaranteed.** PUC's `admin_init` check primes the update in wp-admin within ~12h, or immediately via the "Check for updates" link on the Plugins page; the user then clicks Update. Be aware this can intermittently fail with **"the plugin is at the latest version"** *even right after a check shows the update available*. Mechanism (verified): PUC hooks the `update_plugins` transient on read and authoritatively rewrites the plugin's entry from its persisted `external_updates-<slug>` option — anything not in that stored state is stripped on the next read. So if a throttled, rate-limited, or momentarily asset-less GitHub response has nulled the stored `->update`, WordPress's apply step finds no pending update and bails. A forced "Check for updates" repopulates the stored state, but a later poll can null it again before the user clicks Update, and the interactive check's *display* does not guarantee the *persisted* state agrees at apply time. Treat the admin button as best-effort; `wp plugin install --force` (above) is the only *deterministic* path.

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
