---
name: release-plugin
description: Ship a new version of an Avista WordPress plugin via GitHub Releases — bump version, commit, push, tag and release as a pre-release, verify the built zip, then mark it Latest. Also cuts beta pre-releases that the updater never offers to production. Use when the user says "release the plugin", "ship a release", "publish a new version", "tag and release", "cut a release", "bump the plugin version", "cut a beta", "ship a beta", "release a pre-release", "beta for staging", "do a full circle", "full PR circle", "full release circle", or when ready to deploy plugin updates through the PUC auto-updater pipeline. Do not use for themes (release-theme handles those) or for plugins that don't have the auto-updater wired up (run setup-plugin-autoupdate first).
---

# Ship a new plugin release

Bump the plugin header version, commit and push, create the GitHub release as a **pre-release**, verify the workflow attached the right zip, and only then mark it **Latest**. The plugin must already have the auto-updater wired up. If it doesn't, route the user to `setup-plugin-autoupdate` first.

Two modes:

- **Normal release** (`vX.Y.Z`), the default. It ends with the release marked Latest, which is what every stable site updates to.
- **Beta** (`vX.Y.Z-beta.N`). It stays a pre-release forever and is never marked Latest. Only sites on the beta channel are offered it (see [Beta mode](#beta-mode)). Use it when the user asks for a beta, a pre-release, or a build for staging.

"Do a full circle" / "full PR circle" / "full release circle" are nicknames for this end-to-end flow — they mean run the workflow below from pre-flight through verify, not just one of the steps.

## What marking a release Latest does

WPMU DEV Hub **Automate** with "update all" was on for 29 of the 55 fleet sites that run an Avista plugin (Hub API, read 2026-10-20), mostly scheduled for Sundays 00:00 UTC. Automate installs whatever the updater offers. **Marking a release Latest is therefore a fleet-wide rollout within about a week**, with no further approval.

To keep a site off a given plugin, change that site's Automate setting in the Hub from "update all" to selected plugins. Nothing in the release can exclude a site. Say this to the user at the Step 2 gate when the release is risky.

## Workflow

### Step 1 — Pre-flight

Run these checks before touching anything. Bail if any fail.

- **Branch.** A normal release ships from `main`. A beta ships from the branch that holds the work: a feature branch pushed to `origin`, or `main`. Record it as `BRANCH`. The working tree is clean (no uncommitted changes, no untracked files that belong in the release).
- **The branch is in sync with `origin`.** Run `git fetch origin "$BRANCH" --tags --quiet`, then verify `git rev-parse HEAD` equals `git rev-parse "origin/$BRANCH"`. If local is behind, the release would ship stale code — stop and tell the user to `git pull --rebase` and rerun. If local is ahead with commits that aren't on the remote, those commits would be in the release; confirm with the user that's intended. (`--tags` matters: release tags are created on the remote by `gh release create` and are never pulled back automatically, and Step 2 needs them locally.)
- The plugin's main file has a valid `Version:` header (read it; record the current value).
- **The build workflow fires for pre-releases.** Every release in this flow is created as a pre-release first, so the workflow must trigger on `release: types: [published]`, which GitHub fires for releases and pre-releases alike. Check the trigger, not the filename (the scaffold uses `release.yml`; ACMA uses `build-and-release.yml`):

  ```bash
  grep -nE "types:|prerelease|if:" .github/workflows/*.yml
  ```

  Stop and fix the workflow first in either of these cases:
  - The only trigger is `released`. It does not fire when a pre-release is published, only later when the pre-release is turned into a release, so the zip would not exist for Step 6 to check. (`prereleased` alone would miss normal releases in other flows; `published` covers both.)
  - A job or step is guarded by `github.event.release.prerelease`, e.g. `if: ${{ !github.event.release.prerelease }}`. A beta would then never get its zip.

  The scaffolded workflow has neither problem. For a beta, the workflow file must also exist on `BRANCH`, because a release event runs the workflow file from the tagged commit.
- **Switch `gh` to the correct account for this repo.** Check the remote URL with `git config --get remote.origin.url`, then:
  - `*github.com[:/]JonTryggvi*` → `gh auth switch --user JonTryggvi`
  - `*github.com-avista[:/]Avista*` or `*github.com[:/]Avista*` → `gh auth switch --user jontryggviAvista`
  Do this silently — only report if the switch fails. Confirm the active account with `gh api user --jq .login`.
- **Record the current Latest release**, the newest *non*-pre-release. Steps 2, 6 and 7 compare against it:

  ```bash
  R=<owner>/<repo>
  LATEST=$(gh api "repos/$R/releases/latest" --jq .tag_name)   # e.g. v0.24.1
  ```

  A `404` means no stable release exists yet, so treat `LATEST` as empty. Do **not** use `git describe --tags`. It returns the nearest tag of any kind, so after a beta it reports `v0.25.0-beta.2` as "the last release".
- **Read the updater's asset regexes** and record them. Step 6 tests the zip against them:

  ```bash
  grep -rn "name_regex\|enableReleaseAssets\|vcs_update_detection_strategies" --include="*.php" . | grep -v /vendor/
  ```

  Record the stable pattern as `STABLE_RE`, e.g. `'/avista-core-v[\d.]+\.zip($|[?&#])/i'`. If there is a beta pattern, record it as `BETA_RE`. If there is **no** `vcs_update_detection_strategies` filter, the installed updater still has PUC's tag fallback. In that case, do not cut a beta that outranks `LATEST` until the plugin has shipped the retrofit (`setup-plugin-autoupdate` → `references/retrofit.md`), because stable sites could be handed that beta's source zip. **Finding the filter in the source is not enough.** Sites run what they have installed, so the same rule holds until the first release carrying the filter has reached the fleet. That takes about a week under Hub Automate. Check the fleet inventory, and see `retrofit.md` → "Shipped" for the plugins already retrofitted and their dates.

If anything is dirty or missing, report it and stop — do not bump version or commit against an unclean tree, and do not release from a stale branch.

### Step 2 — Determine the next version

Compare the plugin header with `LATEST`, the newest non-pre-release from Step 1, and read what changed since then: `git log "$LATEST"..HEAD --oneline` (the whole history if `LATEST` is empty).

**Normal release.** Propose `X.Y.Z` from the header:

- **Header equals `LATEST`** (minus the `v`) → a normal bump. Propose a semver bump, using the guide below.
- **Header carries `-beta.N`** (e.g. `0.25.0-beta.3`, because the beta's branch was merged) → this is a **promotion**. Propose the bare version `0.25.0`. Check that it is above `LATEST`, and that `gh release view v0.25.0 -R "$R"` fails because no such release exists yet. If `v0.25.0` already exists, the merge carried a stale suffix, so propose the next patch instead.
- **Header is a bare version above `LATEST`** → a bump was committed but never released. Check `gh release view "v<header>" -R "$R"`. If no release exists, flag it and offer to release the existing header version instead of bumping again. If it exists as a pre-release, a previous run stopped before Step 7, so offer to resume at Step 6 for it.

**Beta.** Propose `X.Y.Z-beta.N`:

- `X.Y.Z` is the version this work will ship as when final: a semver bump over `LATEST`. If the header already carries `X.Y.Z-beta.*`, keep its `X.Y.Z`.
- `N` is one more than the highest existing beta of that version: `git tag -l "vX.Y.Z-beta.*" --sort=-v:refname | head -1`. Start at `1`.
- Use only `-beta.N`. No feature name goes in the version, because PHP's `version_compare()`, which PUC uses, ranks unknown words below `beta`. Then `0.25.0-beta.checkout.1` sorts *below* `0.25.0-beta.2`, and the stable asset regex can't tell such a name apart. Put the branch or feature name in the release title and notes.

Semver guide:

- **major** (X.0.0) — breaking changes to the public API, REST contract, database schema, or shortcode signatures.
- **minor** (x.Y.0) — new features, additive REST endpoints, new shortcodes, new admin pages.
- **patch** (x.y.Z) — bug fixes, internal refactors, copy changes, asset updates.

Show the user: the mode, current header, `LATEST`, proposed version, and a one-line summary of why. For a normal release, also tell them it will reach every Automate site within about a week (see [What marking a release Latest does](#what-marking-a-release-latest-does)).

**STOP. Do not bump, commit, tag, or release until the user explicitly approves
THIS release.** Being asked earlier to make the code change is NOT approval to
ship it, and approval for a previous release does not carry to this one. Wait for
an explicit go-ahead on both the version and the act of releasing. If they
haven't said yes, hold here.

### Step 3 — Bump the version

Edit the `Version:` line in the plugin's main file (the plugin header, top comment block). Use the new version string with no `v` prefix — the header takes `1.4.26`, not `v1.4.26`. A beta's header carries the whole version, `0.25.0-beta.1`, identical to the tag minus the `v`. PUC reads the header **at the tag** and lets it outrank the tag name. When promoting, replace the whole `0.25.0-beta.3` with `0.25.0`, leaving no suffix behind. The `v` prefix is only for the git tag.

**Do not assume the header is the only edit.** Find how the version reaches the asset cache-buster before editing:

```
grep -rn "get_file_data\|wp_get_theme()->get\|_VERSION" <main-file> inc/ | head
```

- **Derived** — the constant comes from the header via `get_file_data()` (the `setup-plugin-autoupdate` scaffold does this) → edit the header only; it is the single source of truth.
- **Hardcoded** — a literal `define( '<X>_VERSION', '1.2.3' )` sits next to the header (e.g. `algolia-indexer`) → edit the header AND the constant, then confirm no stale references remain. Search for the *old* string including any `-beta.N` suffix:

  ```
  grep -rn "<old-version>" --include="*.php" . | grep -v vendor/
  ```

This matters because plugins commonly pass the constant as the `$ver` cache-buster on every `wp_enqueue_style()` / `wp_enqueue_script()`. Bumping only the header of a hardcoded plugin ships CSS/JS still tagged `?ver=<old>`, so browsers and asset-optimizing caches keep serving the previous assets. For a release whose entire payload is CSS/JS, that is a silent total failure — the release appears to do nothing.

### Step 4 — Commit and push

Run (or hand off to the user, depending on the environment):

```
git commit -am "chore: release v<NEW_VERSION>" && git push origin "$BRANCH"
```

If you have direct shell access on the user's machine (e.g. Claude Code on the local host), run it yourself. If you're in a sandboxed environment that can't write to the user's repo (e.g. Cowork, where the mounted `.git/index.lock` denies the operation), tell the user to run it in their own terminal and wait for confirmation.

The version-bump commit must be on the remote `BRANCH` before Step 5. Step 5 tags that exact commit. A release created before the push lands would tag the wrong commit and build the *old* version's zip.

If the user prefers their own commit-and-push alias (e.g. `gsend`), that's fine — what matters is that the version-bump commit reaches the remote branch.

### Step 5 — Create the release as a pre-release

Only run this after the user approved the release in Step 2. If you skipped
that gate, go back and ask now.

**Every release starts as a pre-release, in both modes.** A pre-release is never returned by `/releases/latest`, so no stable site can see it while CI is still building its zip. The old flow created the release as Latest straight away. That left a window in which Latest had no zip. Updaters without the retrofit then fell back to the highest tag's source archive, which has no `vendor/`.

```bash
V=<NEW_VERSION>                       # 0.25.0, or 0.25.0-beta.1
gh release create "v$V" -R "$R" \
  --target "$(git rev-parse HEAD)" \
  --prerelease --latest=false \
  --title "v$V" \
  --notes "<one-line summary of what's in this release>"
```

- `--target` with the full SHA tags exactly the commit Step 1 checked. Without it, `gh` tags the tip of the default branch, which is wrong for a beta cut from a feature branch.
- For a beta, put the branch in the title and notes, e.g. `--title "v$V (feature/checkout-v2)"`.
- Never pass `--latest` here, in either mode.
- For longer notes use `--notes-file`. If the user creates the release in the web UI (`https://github.com/<owner>/<repo>/releases/new`) instead, they must tick **Set as a pre-release** and choose the right target branch.

GitHub fires `release: published` for the pre-release, and that starts the build.

### Step 6 — Verify the build and the zip

**Wait for the workflow.** For release events the run's branch is the tag:

```bash
RUN=$(gh run list -R "$R" --event release --branch "v$V" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" -R "$R" --exit-status
```

If `RUN` is empty, the run hasn't registered yet, so re-run the first line after a few seconds. It normally finishes in under two minutes.

**Check the attached asset.** Exactly one zip must be attached, with state `uploaded`. Its name depends on how the plugin was scaffolded:

| Scaffolded | Expected asset |
|---|---|
| Current (versioned) | `<asset-slug>-v$V.zip`, e.g. `avista-core-v2.18.2.zip` or `avista-core-v2.19.0-beta.1.zip` |
| Legacy (static) | `<asset-slug>-release.zip` |

```bash
gh release view "v$V" -R "$R" --json isPrerelease,assets \
  --jq '.isPrerelease, (.assets[] | [.name, .state, .size, .digest] | @tsv)'
ASSET=<the zip's name>
```

The size should be roughly the same as the previous release's, give or take a few hundred KB.

**Test the name against the regex compiled into the plugin** (`STABLE_RE` / `BETA_RE` from Step 1):

```bash
re_match() { php -r 'exit(preg_match($argv[1], $argv[2]) ? 0 : 1);' -- "$1" "$2"; }
```

- **Normal release:** `re_match "$STABLE_RE" "$ASSET"` must succeed. If it fails, **no stable site will ever see this release**, because `REQUIRE_RELEASE_ASSETS` fails closed and logs nothing. Treat that as a failed release.
- **Beta:** `re_match "$STABLE_RE" "$ASSET"` must **fail**, so that even a mis-flagged beta stays invisible to stable sites. If the plugin has a beta pattern, `re_match "$BETA_RE" "$ASSET"` must succeed. A legacy static name can't make the first check; note that in the report.

**Verify the sha256 and the contents.** Download the asset and compare it with the digest GitHub recorded:

```bash
TMP=$(mktemp -d)
gh release download "v$V" -R "$R" -p "$ASSET" -D "$TMP"
DIGEST=$(gh release view "v$V" -R "$R" --json assets --jq ".assets[] | select(.name==\"$ASSET\") | .digest")
echo "github: $DIGEST"
echo "local:  sha256:$(shasum -a 256 "$TMP/$ASSET" | cut -d' ' -f1)"
unzip -l "$TMP/$ASSET" | grep -E "  <install-dir>/(<main-file>\.php|vendor/autoload\.php)$"
```

The two sha256 lines must be identical. If the API returns no digest, report the local sha256 instead. The `unzip` must list both the entrypoint and `vendor/autoload.php` under the install folder. A zip without the autoloader installs cleanly and then disables the updater on every site it reaches. Report the sha256 to the user. It identifies exactly what sites will install.

If the workflow fails or the asset is wrong, the release is not shippable. In a normal release, do not run Step 7. Common failures:

- `RELEASE_TAG is empty` — workflow was run via `workflow_dispatch` without a tag input. Re-dispatch with the tag.
- `composer install` failed — `composer.json` has a new dependency that wasn't tested in CI. Investigate, fix on `main`, then re-run the workflow via `workflow_dispatch` against the existing tag.
- `gh release upload` failed with 403 — `permissions: contents: write` was removed from the workflow. Restore it.
- `Cannot upload asset … to an immutable release` — the repo has GitHub's immutable releases switched on, which forbids attaching assets after publishing. This pipeline attaches after publishing, so immutable releases must stay off for it.

### Step 7 — Mark it Latest (normal release) or confirm it stayed out (beta)

**Normal release.** Only after Step 6 passed:

```bash
gh release edit "v$V" -R "$R" --prerelease=false --latest
gh api "repos/$R/releases/latest" --jq .tag_name     # must print v$V
```

Stable sites now see a Latest release that already carries its verified zip. Turning a pre-release into a release fires `released` and `edited`, not `published` (GitHub's webhook docs), so the build workflow does not run a second time. If `/releases/latest` prints anything else, stop and report it.

**Beta.** Never run the edit above. Instead assert that the beta changed nothing for stable sites:

```bash
gh api "repos/$R/releases/latest" --jq .tag_name       # must still print $LATEST (or 404 if it was empty)
gh release view "v$V" -R "$R" --json isPrerelease --jq .isPrerelease   # must print true
```

If either check fails, run `gh release edit "v$V" -R "$R" --prerelease --latest=false` immediately. Then point Latest back with `gh release edit "$LATEST" -R "$R" --latest`, and tell the user.

Once Step 7 passes, run `git fetch origin --tags --quiet` to pull the new tag into the local repo, so the next run's checks see it.

### Step 8 — Confirm rollout

Optional but worth offering: tell the user how to verify the update actually rolls out.

For a beta, only beta-channel sites (`AVISTA_UPDATE_CHANNEL` = `'beta'`) are offered it, and only if the plugin's updater has the channel code. Any other site gets a beta only through a manual force-install (Step 9's commands, aimed at that site).

- On any site with the plugin installed, go to **Plugins → Installed Plugins**. The plugin row should show an "Update available" link within ~12 hours of the release (PUC throttles its check to ~12h). To force an immediate check, click the **"Check for updates" link PUC adds under the plugin row** — it carries the nonce PUC requires. Don't tell users to hand-type a URL: PUC v5's trigger is `?puc_check_for_updates=1&puc_slug=<slug>` *plus* a `check_admin_referer` nonce (not the old `?wppuc_update_check=1`), so a typed URL just fails the nonce check.
- If the user wants to apply the update *now* (any site), the reliable path is force-installing the release zip — `gh release download … && wp plugin install <zip> --force`. See Step 9 for the full command. Note CLI `wp plugin update` is **not** dependable for GitHub-PUC plugins (PUC's CLI check is throttled and a forced check doesn't carry over to the update command). The admin "Update" button is also only best-effort — it can report "the plugin is at the latest version" even just after a check shows the update (see the Admin-UI note in Step 9 for the mechanism). The one *deterministic* path is `wp plugin install --force` (Step 9).

### Step 9 — Deploy to production (optional)

**Never run this step for a beta against production.** A beta goes to staging only, through the beta channel or through these same commands aimed at a staging site.

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

**4. Purge caches — install first, purge second. Order matters.**

`wp plugin install --force` swaps the files, but on hosts with stacked caches (WPMU DEV hosting is the verified case, 2026-07-16) the site keeps serving the OLD markup and OLD asset bundles to real visitors indefinitely. Three independent caches sit between the new files and the visitor, and the install clears none of them:

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
      if ( is_object( \$m ) && method_exists( \$m, \"clear_cache\" ) ) { \$m->clear_cache(); }
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
- **Caveat (verified twice):** calling `clear_cache()` on the HB modules via `wp eval` reports success but does NOT delete the critical-CSS `*-used.css` files (some observed 3 months old afterward). Only Hummingbird's admin **Asset Optimization → clear cache** actually regenerated the bundles. After a CSS-affecting deploy, tell the user to clear Asset Optimization from the HB admin as well — do not promise the `wp eval` clear is sufficient.

**5. Verify the update — on disk AND on the front end.**

```
ssh <ssh-target> "wp plugin list --status=active --name=<plugin-directory> --field=version"
```

The output should show the new version — but this only proves the files on disk. It cannot detect an edge cache still serving stale HTML to real visitors (the exact failure the purge above exists for; the disk check reported success while every visitor got the previous release). Also check the front end:

```
curl -skI "https://<site>/" | grep -i '^x-cache'   # expect MISS after a purge, not HIT
curl -sk  "https://<site>/" | grep -o "ver=[0-9.]*" | head   # expect the new version
```

**Verify on a CLEAN URL, never with a cache-buster.** Query-string URLs BYPASS the nginx static cache (`x-cache: BYPASS`, reason "Arguments found"), so a `?nocache=123` request renders fresh and looks correct while real traffic is still being served stale HTML. Checking `?nocache=` produced a false "fixed" verdict twice in one session.

If maintenance mode was toggled during the update, confirm it's off:

```
ssh <ssh-target> "wp maintenance-mode is-active"
```

Should return "Maintenance mode is not active."

**6. Report.**

Tell the user the new version is live on production, the verify commands' output, and the URL of the site if known. If anything in steps 3–5 failed, surface the error verbatim and stop — don't try to debug or rollback automatically.

The release flow ends here. What the user does next — keep working on `main`, pull the new tag locally, branch off for the next piece of work — is up to them and outside this skill's scope.

## Beta mode

A beta is how feature work reaches staging servers without reaching production. The updater side is explained in `setup-plugin-autoupdate` → `references/conventions.md` → "Update channels". In short:

- **Who gets it.** Only sites whose `wp-config.php` has `define( 'AVISTA_UPDATE_CHANNEL', 'beta' );`, and only from plugin versions that carry the channel code. Every other site stays on Latest. Opt-in is explicit and never inferred from the environment or the domain.
- **Version and tag.** `vX.Y.Z-beta.N` (Step 2). The header carries the same `X.Y.Z-beta.N`. The asset is `<asset-slug>-vX.Y.Z-beta.N.zip`, which the stable regex refuses.
- **Branch.** A beta is cut from the branch that holds the work: a feature branch pushed to `origin`, or `main`. Step 5's `--target <sha>` tags exactly that commit, and the release workflow runs from it. Feature branches are never exposed to the updater directly. A branch strategy would serve GitHub's source zip without `vendor/`, which is why the updater only ever reads releases.
- **Release.** Steps 1–6 as normal, with `--prerelease --latest=false`. Step 7 checks that `/releases/latest` is unchanged, and the beta is never marked Latest.
- **Version ordering.** A beta site on `0.25.0-beta.1` is not offered a stable `0.24.2`, because it is lower. It moves on only at `0.25.0` or a later beta. A stable hotfix published *after* a beta hides that beta from beta-channel sites still on stable, until the next beta is cut.
- **One channel, not one per feature.** If branch A ships `0.26.0-beta.1` and branch B ships `0.26.0-beta.2`, every beta site moves to B, and A's work is gone from those sites unless B contains it. Merge parallel features into one branch before cutting betas, or take turns.
- **Promotion.** When the branch merges to `main`, the header arrives as `X.Y.Z-beta.N`. The next normal release proposes `X.Y.Z` (Step 2) and strips the suffix (Step 3).
- **Leaving the channel, and WPMU DEV staging pushes.** Removing the constant does not downgrade a site. A WPMU DEV staging → production push may copy `wp-config.php`, constant included; WPMU DEV's docs don't say either way. After such a push, `wp config get AVISTA_UPDATE_CHANNEL` on production must fail. The steps for both are in the conventions doc.

## Rollback

If the release turns out to be broken after a few sites updated:

1. Delete the GitHub release (this does *not* delete the tag — installed sites that already updated stay on the broken version).
2. Cut a patch release with the fix immediately. PUC will offer the patch as the next update.
3. Do not delete the tag unless you also want to retag from an older commit — git tag deletion confuses PUC's version cache on installed sites.

If the release is broken before *any* site has updated, it's safe to delete both the release and the tag, fix on `main`, and recut the same version. That covers a workflow that failed before attaching the asset, a release caught within minutes, and anything that failed Step 6 while still a pre-release.

A broken beta: cut the next `-beta.N` with the fix. Beta sites move to it. Deleting a beta release does not move sites off it; they stay on it until a higher version ships.

## Notes

- The plugin header version is what PUC reads. In derived plugins the `_VERSION` constant and asset cache-buster follow it automatically; in hardcoded plugins (see Step 3) the constant must be bumped in the same commit, or the release ships assets with a stale `?ver=` cache-buster.
- The git tag format is `v<version>` (with the `v` prefix). The plugin header is the bare version. Do not unify them — WP's header format does not accept `v` prefixes.
- Releases without an attached zip are silently ignored by PUC (because of `REQUIRE_RELEASE_ASSETS`). This fails closed — no broken updates — but also means a release with a CI failure looks "published" while not actually shipping. The pre-release-first flow (Steps 5–7) means a stable site never sees a Latest release without its zip.
- Updaters without the retrofit fall back to the highest version-looking *tag* whenever `/releases/latest` comes back empty, and they ignore the asset rule when they do. A beta tag that outranks Latest is then offered to stable sites as a source zip with no `vendor/`. Check Step 1's `vcs_update_detection_strategies` grep before cutting such a beta.
