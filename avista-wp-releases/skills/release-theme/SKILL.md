---
name: release-theme
description: Ship a new version of an Avista WordPress theme via GitHub Releases — bump version, commit, push, tag and release, verify the build. Use when the user says "release the theme", "ship a theme release", "publish a new theme version", "tag and release the theme", "bump the theme version", "do a full circle", "full PR circle", "full release circle", or when ready to deploy theme updates through the PUC auto-updater pipeline. Do not use for plugins (release-plugin handles those) or for themes that don't have the auto-updater wired up (run setup-theme-autoupdate first).
---

# Ship a new theme release

Bump the theme's `style.css` version, commit and push, create the GitHub release, and verify the workflow attached the release asset. The theme must already have the auto-updater wired up — if it doesn't, route the user to `setup-theme-autoupdate` first.

"Do a full circle" / "full PR circle" / "full release circle" are nicknames for this end-to-end flow — they mean run the workflow below from pre-flight through verify, not just one of the steps.

## Workflow

### Step 1 — Pre-flight

- The repo is on `main` and the working tree is clean.
- **Local `main` is in sync with `origin/main`.** Run `git fetch origin main --tags --quiet`, then verify `git rev-parse HEAD` equals `git rev-parse origin/main`. If local is behind, the release would ship stale code — stop and tell the user to `git pull --rebase` and rerun. If local is ahead with commits that aren't on the remote, those commits would be in the release; confirm with the user that's intended. (The `--tags` keeps the local tag list current — the previous release's tag was created on the remote by `gh release create` and is never pulled back automatically, so without this the latest-tag check in Step 2 reads a stale tag.)
- The theme's `style.css` has a valid `Version:` header (read it; record the current value).
- The theme has `.github/workflows/release-theme.yml`. If not, the user needs `setup-theme-autoupdate` first.
- `gh` CLI is authenticated (`gh auth status`).
- **Switch `gh` to the correct account for this repo.** Check the remote URL with `git config --get remote.origin.url`, then:
  - `*github.com[:/]JonTryggvi*` → `gh auth switch --user JonTryggvi`
  - `*github.com-avista[:/]Avista*` or `*github.com[:/]Avista*` → `gh auth switch --user jontryggviAvista`
  Do this silently — only report if the switch fails. Confirm the active account with `gh api user --jq .login`.

If anything is dirty or missing, report it and stop — and do not release from a stale `main`.

### Step 2 — Determine the next version

Look at the current version from `style.css` and the git log since the last release tag (`git log $(git describe --tags --abbrev=0)..HEAD --oneline`). Because Step 1 fetched tags, `git describe` now reflects the actual latest release. If the header is *still* ahead of the latest tag, that's a genuine "a prior bump was committed but the release was never created" case — flag it to the user and offer to create the missing release for the existing header version, rather than treating it as a normal bump. Propose a semver bump:

- **major** (X.0.0) — breaking template changes, removed page templates, dropped post-type support, anything that would break a site running this theme.
- **minor** (x.Y.0) — new templates, new theme features, new hooks/filters.
- **patch** (x.y.Z) — CSS tweaks, bug fixes, copy changes, asset updates.

Show current version, proposed next version, and a one-line summary. Ask the user to confirm or override.

### Step 3 — Bump the version

Edit the `Version:` line in `style.css` (the top comment block, in the theme metadata). Use the bare version with no `v` prefix.

Do not edit `functions.php` or anything else. The theme has no `_VERSION` constant by default — `style.css` is the single source of truth that WP reads.

### Step 4 — Commit and push

Run (or hand off to the user, depending on the environment):

```
git commit -am "chore: release v<NEW_VERSION>" && git push
```

If you have direct shell access on the user's machine (e.g. Claude Code on the local host), run it yourself. If you're in a sandboxed environment that can't write to the user's repo (e.g. Cowork, where the mounted `.git/index.lock` denies the operation), tell the user to run it in their own terminal and wait for confirmation.

The version-bump commit must be on the remote `main` before Step 5.

If the user prefers their own commit-and-push alias (e.g. `gsend`), that's fine — what matters is that the version-bump commit reaches the remote `main`.

### Step 5 — Create the GitHub release

```
gh release create v<NEW_VERSION> \
  --title "v<NEW_VERSION>" \
  --notes "<one-line summary>"
```

Or via the web UI: `https://github.com/<owner>/<repo>/releases/new`.

### Step 6 — Verify the build

Once the release is published, watch the Actions tab: `https://github.com/<owner>/<repo>/actions`. The "Build theme release asset" workflow should run within seconds and finish in under two minutes. If you can poll `gh run list --limit 1` directly, do; otherwise ask the user to confirm when it goes green.

Success criteria:

- The workflow completes successfully.
- The release page shows `<theme-slug>.zip` attached as an asset.

Once the release is confirmed, run `git fetch origin --tags --quiet` to pull the just-created `v<NEW_VERSION>` tag into the local repo. `gh release create` makes the tag on the remote only — without this, the local tag list stays a release behind and the next run's Step 2 check re-triggers the "was this version actually released?" detour.

Common failures:

- `composer install` failed — investigate `composer.json`, fix on `main`, re-dispatch the workflow against the existing tag.
- `softprops/action-gh-release@v2` failed with `fail_on_unmatched_files: true` — usually means the build step's zip command failed silently. Inspect the "Build zip" step logs.
- `RELEASE_TAG` resolution fell through to an empty string — happens when the workflow was dispatched without a tag input from a context that doesn't carry `github.ref_name`. Re-dispatch with the tag input.

### Step 7 — Confirm rollout

Optional. On any site with the theme installed, go to **Appearance → Themes**. The theme card should show an "Update available" notice within ~12 hours (PUC throttles its check to ~12h). To force an immediate check, use **Dashboard → Updates → "Check again"** (or click PUC's update-check link if present). Note: the old `?wppuc_update_check=1` URL trick does **not** work in PUC v5p6 — its trigger is `?puc_check_for_updates=1&puc_slug=<slug>` guarded by a `check_admin_referer` nonce, so a hand-typed URL fails the nonce check.

To apply the update via WP-CLI, the reliable path is force-installing the release zip — `gh release download … && wp theme install <zip> --force` (see Step 8). Do **not** rely on `wp theme update <theme-directory>`: PUC's CLI check (`WpCliCheckTrigger` hooks `theme update/list/status` → throttled `maybeCheckForUpdates()`) usually reports "already updated", and a forced `checkForUpdates()` in a separate process doesn't carry over to `wp theme update` — the same limitation proven for the plugin variant. The admin "Update" button (Appearance → Themes) is best-effort, not guaranteed — it can report "the theme is at the latest version" even right after a check shows the update, because PUC authoritatively rewrites the `update_themes` transient from its persisted `external_updates-<slug>` state on read, and a throttled or momentarily asset-less GitHub response nulls that state. `wp theme install --force` (Step 8) is the only deterministic path.

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

Wait for an explicit yes.

**3. Deploy by force-installing the release zip — the reliable CLI path.**

Do **not** use `wp theme update <theme-directory>` for a GitHub-PUC theme from CLI — PUC's CLI check is throttled and a forced check doesn't carry over to it (same limitation proven for the plugin variant). Download the release asset and force-install it. `gh` must be authed locally to read the (often private) asset.

```
gh release download v<NEW_VERSION> -R <owner>/<repo> -p '*.zip' -O /tmp/theme.zip
scp /tmp/theme.zip <ssh-target>:/tmp/theme.zip
ssh <ssh-target> "cd <wp-root> && wp maintenance-mode activate && wp theme install /tmp/theme.zip --force && wp maintenance-mode deactivate && wp theme get <theme-directory> --field=version && rm -f /tmp/theme.zip"
```

`--force` overwrites the theme directory in place; the active theme stays active and the version updates. Maintenance mode ensures no request hits half-swapped files. The theme zip's top folder is the theme slug (which equals the install directory), so `--force` lands in place — but if a site installed the theme under a different directory name, confirm with `wp theme list` first, since `--force` keys off the zip's folder name.

**4. Verify the update.**

```
ssh <ssh-target> "wp theme list --status=active --name=<theme-directory> --field=version"
```

Should show the new version.

**5. Report.**

Tell the user the new version is live on production, the verify command's output, and the URL of the site if known. If anything in steps 3–4 failed, surface the error verbatim and stop — don't try to debug or rollback automatically.

The release flow ends here. What the user does next — keep working on `main`, pull the new tag locally, branch off for the next piece of work — is up to them and outside this skill's scope.

## Rollback

Same shape as the plugin rollback story:

1. Delete the GitHub release (not the tag).
2. Immediately cut a patch release with the fix.
3. Don't delete the tag unless you also want to retag from an older commit.

If the release is broken *before any site has updated*, it's safe to delete both release and tag, fix, and recut the same version.

## Notes

- The `style.css` `Version:` line is the single source of truth. WP reads it for theme metadata; PUC reads it to detect updates.
- Git tag format: `v<version>` (with `v`). `style.css` header: bare version. Do not unify — WP's header format does not accept `v` prefixes.
- Themes use `screenshot.png` for the admin UI image. If you change it, the new screenshot only shows up after the user *updates* the theme (PUC includes it in the release asset).
- Child themes do *not* need their own release pipeline — they inherit the parent theme's update mechanism for any code they reference. They do need their own bump-and-release if they have independent versioning, but the autoupdater wiring lives on the parent.
