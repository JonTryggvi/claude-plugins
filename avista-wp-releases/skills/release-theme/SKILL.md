---
name: release-theme
description: Ship a new version of an Avista WordPress theme via GitHub Releases — bump version, commit, push, tag and release as a pre-release, verify the built zip, then mark it Latest. Also cuts beta pre-releases that the updater never offers to production. Use when the user says "release the theme", "ship a theme release", "publish a new theme version", "tag and release the theme", "bump the theme version", "cut a theme beta", "ship a theme beta", "theme pre-release", "do a full circle", "full PR circle", "full release circle", or when ready to deploy theme updates through the PUC auto-updater pipeline. Do not use for plugins (release-plugin handles those) or for themes that don't have the auto-updater wired up (run setup-theme-autoupdate first).
---

# Ship a new theme release

Bump the theme's `style.css` version, commit and push, create the GitHub release as a **pre-release**, verify the workflow attached the right zip, and only then mark it **Latest**. The theme must already have the auto-updater wired up — if it doesn't, route the user to `setup-theme-autoupdate` first.

Two modes, as in `release-plugin`:

- **Normal release** (`vX.Y.Z`), the default. It ends with the release marked Latest.
- **Beta** (`vX.Y.Z-beta.N`). It stays a pre-release and is never marked Latest. Only sites with `define( 'AVISTA_UPDATE_CHANNEL', 'beta' );` are offered it. The full beta rules are in `release-plugin` → "Beta mode" and apply here unchanged.

"Do a full circle" / "full PR circle" / "full release circle" are nicknames for this end-to-end flow — they mean run the workflow below from pre-flight through verify, not just one of the steps.

**Marking a release Latest is a fleet-wide rollout.** WPMU DEV Hub Automate with "update all" installs whatever the updater offers, on its schedule (mostly Sundays 00:00 UTC). To keep a site off a release, switch that site's Automate setting in the Hub to selected plugins/themes. See `release-plugin` → "What marking a release Latest does".

## Workflow

### Step 1 — Pre-flight

- **Branch.** A normal release ships from `main`. A beta ships from the branch that holds the work (a feature branch pushed to `origin`, or `main`). Record it as `BRANCH`. The working tree is clean.
- **The branch is in sync with `origin`.** Run `git fetch origin "$BRANCH" --tags --quiet`, then verify `git rev-parse HEAD` equals `git rev-parse "origin/$BRANCH"`. If local is behind, the release would ship stale code — stop and tell the user to `git pull --rebase` and rerun. If local is ahead with commits that aren't on the remote, those commits would be in the release; confirm with the user that's intended. (`--tags` matters: release tags are created on the remote by `gh release create` and are never pulled back automatically.)
- The theme's `style.css` has a valid `Version:` header (read it; record the current value).
- **The build workflow fires for pre-releases.** The scaffold is `.github/workflows/release-theme.yml`, but check the trigger, not the filename:

  ```bash
  grep -nE "types:|prerelease|if:" .github/workflows/*.yml
  ```

  It must trigger on `release: types: [published]`, which fires for pre-releases too. Stop and fix the workflow first if the only trigger is `released`, or if anything is guarded by `github.event.release.prerelease`. The scaffolded workflow uploads with `softprops/action-gh-release@v2`. When v2 finds an existing release it keeps that release's `prerelease` flag (`src/github.ts`, read 2026-10-20), so a pre-release stays a pre-release. For a beta, the workflow file must exist on `BRANCH`.
- `gh` CLI is authenticated (`gh auth status`).
- **Switch `gh` to the correct account for this repo.** Check the remote URL with `git config --get remote.origin.url`, then:
  - `*github.com[:/]JonTryggvi*` → `gh auth switch --user JonTryggvi`
  - `*github.com-avista[:/]Avista*` or `*github.com[:/]Avista*` → `gh auth switch --user jontryggviAvista`
  Do this silently — only report if the switch fails. Confirm the active account with `gh api user --jq .login`.
- **Record the current Latest release**, the newest *non*-pre-release:

  ```bash
  R=<owner>/<repo>
  LATEST=$(gh api "repos/$R/releases/latest" --jq .tag_name)
  ```

  A `404` means no stable release yet, so treat `LATEST` as empty. Do **not** use `git describe --tags`, which reports the nearest beta as "the last release".
- **Check the updater.** Run `grep -n "name_regex\|vcs_update_detection_strategies" functions.php inc/*.php 2>/dev/null`. Record the asset regex as `THEME_RE`, e.g. `'/islandiamagica\.zip($|[?&#])/i'`. If there is no `vcs_update_detection_strategies` filter, the installed updater still has PUC's tag fallback. In that case, do not cut a beta that outranks `LATEST` until the theme has the retrofit (`setup-theme-autoupdate` → "Retrofit an existing updater"). Having the filter in the source is not enough. The rule holds until the first release carrying it has reached the fleet, about a week under Hub Automate.

If anything is dirty or missing, report it and stop — and do not release from a stale branch.

### Step 2 — Determine the next version

Compare the `style.css` version with `LATEST` and read `git log "$LATEST"..HEAD --oneline` (the whole history if `LATEST` is empty).

**Normal release:**

- **Header equals `LATEST`** → a normal bump, using the guide below.
- **Header carries `-beta.N`** → a promotion. Propose the bare `X.Y.Z`, after checking that it is above `LATEST` and that `gh release view vX.Y.Z -R "$R"` fails. If `vX.Y.Z` already exists, propose the next patch.
- **Header is a bare version above `LATEST`** → a bump was committed but never released. If `gh release view "v<header>"` finds nothing, offer to release the existing header version. If it finds a pre-release, offer to resume at Step 6.

**Beta:** `X.Y.Z-beta.N`. `X.Y.Z` is the final version this work will ship as, and `N` is one more than the highest `git tag -l "vX.Y.Z-beta.*" --sort=-v:refname`, starting at 1. Use only `-beta.N`, never a feature name in the version; the reason is in `release-plugin` → Step 2. Put the branch in the release title.

Semver guide:

- **major** (X.0.0) — breaking template changes, removed page templates, dropped post-type support, anything that would break a site running this theme.
- **minor** (x.Y.0) — new templates, new theme features, new hooks/filters.
- **patch** (x.y.Z) — CSS tweaks, bug fixes, copy changes, asset updates.

Show the mode, current version, `LATEST`, proposed version, and a one-line summary. For a normal release, say it reaches every Automate site within about a week.

**STOP. Do not bump, commit, tag, or release until the user explicitly approves
THIS release.** Being asked earlier to make the code change is NOT approval to
ship it, and approval for a previous release does not carry to this one. Wait for
an explicit go-ahead on both the version and the act of releasing. If they
haven't said yes, hold here.

### Step 3 — Bump the version

Edit the `Version:` line in `style.css` (the top comment block, in the theme metadata). Use the bare version with no `v` prefix. A beta carries the whole `X.Y.Z-beta.N`. PUC reads `style.css` at the tag and lets its header outrank the tag name, so the two must agree. When promoting, replace the whole `X.Y.Z-beta.N` with `X.Y.Z`.

**Check how the version reaches the asset cache-buster before assuming this is the only edit:**

```
grep -rn "wp_get_theme()->get\|get_file_data\|_VERSION" functions.php inc/ | head
```

- **Derived** (`wp_get_theme()->get( 'Version' )` / `get_file_data()` — e.g. `islandiamagica`) → edit `style.css` only; it is the single source of truth that WP and the enqueues both read.
- **Hardcoded** (`define( '<X>_VERSION', '1.2.3' )` in `functions.php`) → edit `style.css` AND the constant, then confirm no stale references remain (search for the old string, including any `-beta.N`):

  ```
  grep -rn "<old-version>" --include="*.php" . | grep -v vendor/
  ```

Bumping only `style.css` when the enqueue cache-buster is hardcoded ships CSS/JS still tagged `?ver=<old>`, so browsers and asset-optimizing caches keep serving the previous assets — for a CSS-only release, a silent total failure.

### Step 4 — Commit and push

Run (or hand off to the user, depending on the environment):

```
git commit -am "chore: release v<NEW_VERSION>" && git push origin "$BRANCH"
```

If you have direct shell access on the user's machine (e.g. Claude Code on the local host), run it yourself. If you're in a sandboxed environment that can't write to the user's repo (e.g. Cowork, where the mounted `.git/index.lock` denies the operation), tell the user to run it in their own terminal and wait for confirmation.

The version-bump commit must be on the remote `BRANCH` before Step 5, which tags that exact commit.

If the user prefers their own commit-and-push alias (e.g. `gsend`), that's fine — what matters is that the version-bump commit reaches the remote branch.

### Step 5 — Create the release as a pre-release

Only run this after the user approved the release in Step 2. If you skipped
that gate, go back and ask now.

Every release starts as a pre-release, in both modes, so no stable site can see it before its zip is attached and checked:

```bash
V=<NEW_VERSION>
gh release create "v$V" -R "$R" \
  --target "$(git rev-parse HEAD)" \
  --prerelease --latest=false \
  --title "v$V" \
  --notes "<one-line summary>"
```

Never pass `--latest` here. In the web UI (`https://github.com/<owner>/<repo>/releases/new`), tick **Set as a pre-release** and pick the right target.

### Step 6 — Verify the build and the zip

```bash
RUN=$(gh run list -R "$R" --event release --branch "v$V" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" -R "$R" --exit-status        # empty RUN: not registered yet, retry in a few seconds
gh release view "v$V" -R "$R" --json isPrerelease,assets \
  --jq '.isPrerelease, (.assets[] | [.name, .state, .size, .digest] | @tsv)'
ASSET=<theme-slug>.zip
php -r 'exit(preg_match($argv[1], $argv[2]) ? 0 : 1);' -- "$THEME_RE" "$ASSET" && echo "matches THEME_RE"
TMP=$(mktemp -d) && gh release download "v$V" -R "$R" -p "$ASSET" -D "$TMP"
echo "local: sha256:$(shasum -a 256 "$TMP/$ASSET" | cut -d' ' -f1)"   # must equal the digest above
unzip -l "$TMP/$ASSET" | grep -E "  <theme-slug>/(style\.css|functions\.php|vendor/autoload\.php)$"
```

Success means all of the following:

- The workflow is green.
- Exactly one `<theme-slug>.zip` is attached with state `uploaded`, roughly the previous release's size.
- It matches the theme's regex.
- Its local sha256 equals GitHub's digest.
- The zip lists `style.css`, `functions.php` and `vendor/autoload.php` under the theme folder. The theme workflow does not assert `vendor/` itself, so this is the only check that it is there.

Report the sha256. Theme assets are unversioned, so a beta's zip has the same name as a final's. Nothing in the asset name keeps a beta from stable sites; only its pre-release flag does, and Step 7 checks that.

Common failures:

- `composer install` failed — investigate `composer.json`, fix on `main`, re-dispatch the workflow against the existing tag.
- `softprops/action-gh-release@v2` failed with `fail_on_unmatched_files: true` — usually means the build step's zip command failed silently. Inspect the "Build zip" step logs.
- `RELEASE_TAG` resolution fell through to an empty string — happens when the workflow was dispatched without a tag input from a context that doesn't carry `github.ref_name`. Re-dispatch with the tag input.
- `Cannot upload asset … to an immutable release` — the repo has GitHub's immutable releases on. This pipeline attaches assets after publishing, so they must stay off.

If anything failed, do not run Step 7 for a normal release.

### Step 7 — Mark it Latest (normal release) or confirm it stayed out (beta)

**Normal release**, only after Step 6 passed:

```bash
gh release edit "v$V" -R "$R" --prerelease=false --latest
gh api "repos/$R/releases/latest" --jq .tag_name     # must print v$V
```

The flip fires `released`/`edited`, not `published`, so the build does not run again.

**Beta.** Never run that edit. Assert instead:

```bash
gh api "repos/$R/releases/latest" --jq .tag_name                       # must still print $LATEST
gh release view "v$V" -R "$R" --json isPrerelease --jq .isPrerelease    # must print true
```

For a theme this is the **only** thing keeping a beta off stable sites. If either check fails, run `gh release edit "v$V" -R "$R" --prerelease --latest=false` and `gh release edit "$LATEST" -R "$R" --latest` at once, then tell the user.

Then run `git fetch origin --tags --quiet` to pull the new tag locally.

### Step 8 — Confirm rollout

Optional. A beta is offered only to beta-channel sites, and only by a theme version that carries the channel code. Any other staging site needs a manual force-install (Step 9's commands, aimed at it).

On any site with the theme installed, go to **Appearance → Themes**. The theme card should show an "Update available" notice within ~12 hours (PUC throttles its check to ~12h). To force an immediate check, use **Dashboard → Updates → "Check again"** (or click PUC's update-check link if present). Note: the old `?wppuc_update_check=1` URL trick does **not** work in PUC v5 — its trigger is `?puc_check_for_updates=1&puc_slug=<slug>` guarded by a `check_admin_referer` nonce, so a hand-typed URL fails the nonce check.

To apply the update via WP-CLI, the reliable path is force-installing the release zip — `gh release download … && wp theme install <zip> --force` (see Step 9). Do **not** rely on `wp theme update <theme-directory>`: PUC's CLI check (`WpCliCheckTrigger` hooks `theme update/list/status` → throttled `maybeCheckForUpdates()`) usually reports "already updated", and a forced `checkForUpdates()` in a separate process doesn't carry over to `wp theme update` — the same limitation proven for the plugin variant. The admin "Update" button (Appearance → Themes) is best-effort, not guaranteed — it can report "the theme is at the latest version" even right after a check shows the update, because PUC authoritatively rewrites the `update_themes` transient from its persisted `puc_external_updates_theme-<slug>` state on read, and a throttled or momentarily asset-less GitHub response nulls that state. `wp theme install --force` (Step 9) is the only deterministic path.

### Step 9 — Deploy to production (optional)

**Never run this step for a beta against production.**

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

**4. Purge caches — install first, purge second. Order matters.**

`wp theme install --force` swaps the files, but on hosts with stacked caches (WPMU DEV hosting is the verified case, 2026-07-16) the site keeps serving the OLD markup and OLD asset bundles to real visitors indefinitely. Three independent caches sit between the new files and the visitor, and the install clears none of them:

1. **Hummingbird Asset Optimization bundles** — stored as `wphb_minify_group` posts with a per-URL mapping; clean URLs reuse the stored (stale) mapping.
2. **Hummingbird critical/used CSS** — `wp-content/wphb-cache/critical-css/<domain>/*-used.css`.
3. **The host's nginx FastCGI "Static Server Cache"** — sits IN FRONT of WordPress (`x-cache-enabled: true`, `x-cache: HIT`); invisible to WordPress.

Run this AFTER the install succeeds and BEFORE verifying. **Clearing before the install rebuilds the OLD assets and the deploy still ships stale** — a real trap that cost a full debugging cycle:

```
ssh <ssh-target> "cd <wp-root> && wp eval '
  // Hummingbird asset bundles + critical CSS, if HB is present.
  if ( class_exists( \"\\Hummingbird\\Core\\Utils\" ) ) {
    foreach ( [ \"page_cache\", \"minify\", \"critical_css\" ] as \$mod ) {
      \$m = \\Hummingbird\\Core\\Utils::get_module( \$mod );
      if ( ! is_object( \$m ) || ! method_exists( \$m, \"clear_cache\" ) ) { continue; }
      // minify: pass false. HB 4.0 defaults reset_settings=true, which wipes the AO settings.
      \$mod === \"minify\" ? \$m->clear_cache( false ) : \$m->clear_cache();
    }
  }
  // Host edge cache. Platform-provided on WPMU DEV hosting only — always guard.
  if ( function_exists( \"wpmudev_hosting_purge_static_cache\" ) ) {
    wpmudev_hosting_purge_static_cache();
    echo \"static cache purged\n\";
  } else {
    echo \"no wpmudev_hosting_purge_static_cache() — not WPMU DEV hosting, or platform changed\n\";
  }
'"
```

- **Always guard `wpmudev_hosting_purge_static_cache()` with `function_exists()`.** The function belongs to the hosting platform, not to any site — WPMU DEV defines it in a platform mu-plugin outside the site root (`/var/web/plugins/mu-plugins/misc-functions.php`). It issues an nginx `PURGE` to the site's own origin (127.0.0.1) and defaults to `/*` (purge everything, optional path argument). It does not exist off WPMU DEV hosting, and the platform can remove it — a bare call fatals the deploy. WPMU DEV's own Dashboard plugin calls it with exactly this guard.
- **Never call the minify module's `clear_cache()` without `false`.** Hummingbird 4.0.0's signature is `clear_cache( $reset_settings = true, $reset_minify = true, $keep_collection = false )`: the bare call resets every Asset Optimization setting (`dont_minify`, `dont_combine`, `block`, `position`, `defer`, `inline`, `fonts`, `preload`, `async`) and empties the sources collection. That is a production settings change, not a cache clear — the 2026-11-03 ACMA deploys ran it four times on rmk and innbak. `clear_cache( false )` deletes the files only.
- **The asset CDN keeps the old bundle.** HB names a combined bundle after its handles, not its contents, so a CSS release keeps the same bundle URL, and the WPMU DEV asset CDN (`*.assetcdn.net`) keeps serving the old file under it (`cdn-cache: HIT`) — the page then renders new markup with old CSS (rmk, 2026-11-03). There is no CDN purge to call from `wp eval`. The reliable clear is Hummingbird admin → **Asset Optimization → clear cache**. When verifying, fetch the bundle URL the page actually links and check its contents; some sites print `<link href='…'>` with single quotes, so grep for both quote styles — match `href=["']`, not `href="`.
- **Caveat (verified twice):** calling `clear_cache()` on the HB modules via `wp eval` reports success but does NOT delete the critical-CSS `*-used.css` files (some observed 3 months old afterward). Only Hummingbird's admin **Asset Optimization → clear cache** actually regenerated the bundles. After a CSS-affecting deploy, tell the user to clear Asset Optimization from the HB admin as well — do not promise the `wp eval` clear is sufficient.

**5. Verify the update — on disk AND on the front end.**

```
ssh <ssh-target> "wp theme list --status=active --name=<theme-directory> --field=version"
```

Should show the new version — but this only proves the files on disk. It cannot detect an edge cache still serving stale HTML to real visitors (the exact failure the purge above exists for; the disk check reported success while every visitor got the previous release). Also check the front end:

```
curl -skI "https://<site>/" | grep -i '^x-cache'   # expect MISS after a purge, not HIT
curl -sk  "https://<site>/" | grep -o "ver=[0-9.]*" | head   # expect the new version
```

**Verify on a CLEAN URL, never with a cache-buster.** Query-string URLs BYPASS the nginx static cache (`x-cache: BYPASS`, reason "Arguments found"), so a `?nocache=123` request renders fresh and looks correct while real traffic is still being served stale HTML. Checking `?nocache=` produced a false "fixed" verdict twice in one session.

If maintenance mode was toggled during the update, confirm it's off: `ssh <ssh-target> "wp maintenance-mode is-active"` should return "Maintenance mode is not active."

**6. Report.**

Tell the user the new version is live on production, the verify commands' output, and the URL of the site if known. If anything in steps 3–5 failed, surface the error verbatim and stop — don't try to debug or rollback automatically.

The release flow ends here. What the user does next — keep working on `main`, pull the new tag locally, branch off for the next piece of work — is up to them and outside this skill's scope.

## Rollback

Same shape as the plugin rollback story:

1. Delete the GitHub release (not the tag).
2. Immediately cut a patch release with the fix.
3. Don't delete the tag unless you also want to retag from an older commit.

If the release is broken *before any site has updated*, it's safe to delete both release and tag, fix, and recut the same version. That includes anything that failed Step 6 while still a pre-release.

A broken beta: cut the next `-beta.N`. Deleting a beta does not move beta sites off it.

## Notes

- The `style.css` `Version:` line is what WP reads for theme metadata and PUC reads to detect updates. In derived themes the enqueue cache-buster follows it too; if the theme hardcodes a version constant (see Step 3), bump that in the same commit.
- Git tag format: `v<version>` (with `v`). `style.css` header: bare version. Do not unify — WP's header format does not accept `v` prefixes.
- Beta channel, version ordering, leaving the channel, and the WPMU DEV staging-push check: `release-plugin` → "Beta mode", and `setup-plugin-autoupdate` → `references/conventions.md` → "Update channels". Themes differ in one way: PUC caches their state in `puc_external_updates_theme-<slug>`.
- Themes use `screenshot.png` for the admin UI image. If you change it, the new screenshot only shows up after the user *updates* the theme (PUC includes it in the release asset).
- Child themes do *not* need their own release pipeline — they inherit the parent theme's update mechanism for any code they reference. They do need their own bump-and-release if they have independent versioning, but the autoupdater wiring lives on the parent.
