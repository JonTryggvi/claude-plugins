# Plugin auto-updater — non-obvious guards and why each exists

Every guard below was added in response to a real failure mode. Do not strip them when adapting the template.

## `file_exists()` around `vendor/autoload.php`

```php
$autoload = __PLUGIN_CONST___DIR . 'vendor/autoload.php';
if ( ! file_exists( $autoload ) ) {
    // …show admin notice in non-dev environments, then return early.
    return;
}
require_once $autoload;
```

**Why.** `vendor/` is git-ignored and compiled by GitHub Actions at release time. A fresh `git clone` (or a CI run before `composer install`) has no autoloader. A bare `require` would crash the plugin and the whole WP admin. The guard lets the plugin load cleanly without the autoloader; PUC just doesn't get wired up until `vendor/` exists.

## Env-gated `admin_notices` warning

```php
if ( ! in_array( wp_get_environment_type(), [ 'local', 'development' ], true ) ) {
    add_action( 'admin_notices', /* …warning… */ );
}
```

**Why.** In local dev, the plugin is loaded straight from the git working tree where `vendor/` is intentionally missing. A loud admin notice every page reload is noise. In production a missing `vendor/` *is* a bug — the release zip should always include it. Showing the warning only outside dev catches the real failures.

## Never hardcode a `v5pN` namespace — use the `v5` alias

**This is the highest-value rule in this document.** PUC ships a version-pinned
namespace per release (`v5p6`, `v5p7`, …) alongside a stable `v5` alias. The
Composer constraint we write is `^5.6`, which **floats** — as of PUC v5.7 it
resolves to `v5p7`, and `v5p6` no longer exists.

Verified against a fresh `composer install` of `"yahnis-elsts/plugin-update-checker": "^5.6"`
(resolved v5.7, PHP 8.5):

| Class | Exists | `REQUIRE_RELEASE_ASSETS` |
|---|---|---|
| `…\v5\PucFactory` | yes | — |
| `…\v5p7\PucFactory` | yes | — |
| `…\v5p6\PucFactory` | **no** | — |
| `…\v5\Vcs\Api` | **no** | — |
| `…\v5p7\Vcs\Api` | yes | `2` |
| `…\v5p7\Vcs\GitHubApi` | yes | `2` (inherited) |
| `…\v5p6\Vcs\Api` | **no** | — |

Two distinct traps, with two different failure modes:

1. **The factory.** A `class_exists( …\v5p6\PucFactory::class )` guard returns
   false, the bootstrap returns early, and the plugin loads normally. The guard is
   deliberately defensive ("no-op if PUC is absent"), so there is **no error, no
   log line, and no admin notice** — the only symptom is that update checks never
   happen, which nobody notices until a release fails to propagate.
2. **The constant.** `REQUIRE_RELEASE_ASSETS` is defined only on the concrete
   `v5pN\Vcs\Api`; it is **not** exposed through the `v5` alias (there is no
   `v5\Vcs\Api` at all). So swapping the factory to the alias but leaving the
   constant on a `v5pN` path still breaks — and this one is a hard **fatal**
   (`Error: Class "…\v5p6\Vcs\Api" not found`) on every request that reaches it,
   not a silent no-op.

```php
// Correct: alias for the factory…
$factory = '\\YahnisElsts\\PluginUpdateChecker\\v5\\PucFactory';
if ( ! class_exists( $factory ) ) {
    return;
}
$checker = $factory::buildUpdateChecker( /* … */ );

// …and the runtime class for the constant.
$api_class = get_class( $api );
if ( defined( "$api_class::REQUIRE_RELEASE_ASSETS" ) ) {
    $api->enableReleaseAssets( $name_regex, constant( "$api_class::REQUIRE_RELEASE_ASSETS" ) );
} else {
    $api->enableReleaseAssets( $name_regex );
}
```

If you ever find yourself typing `v5p` followed by a digit, stop. The only
acceptable literal namespace in this scaffold is `v5`.

## `class_exists()` on the factory after autoload

```php
$factory = '\\YahnisElsts\\PluginUpdateChecker\\v5\\PucFactory';
if ( ! class_exists( $factory ) ) {
    return;
}
```

**Why.** Defends against a partially-installed `vendor/` (e.g. broken composer install, manual file copy that missed a dependency). The autoloader registers but the class still can't resolve. Without the guard, the next line throws `Error: Class not found`.

The guard itself is sound either way — `class_exists()` triggers the autoloader
and correctly returned `false` for `v5p6`. What made the bug invisible was the
early `return` on the next line, not the guard.

Worth knowing regardless: `\Some\Class::class` is pure compile-time string
construction and never verifies the class exists, so it reads like a
compiler-checked reference while offering exactly none of that guarantee. Don't
let it lull you into trusting a hardcoded namespace.

## `method_exists()` around `getVcsApi()` and `enableReleaseAssets()`

```php
if ( method_exists( $checker, 'getVcsApi' ) ) {
    $vcs = $checker->getVcsApi();
    if ( is_object( $vcs ) && method_exists( $vcs, 'enableReleaseAssets' ) ) {
        $vcs->enableReleaseAssets( /* … */ );
    }
}
```

**Why.** Future-proofs against PUC API changes between minor versions. PUC v5.x has these methods; earlier versions don't, and a future cleanup could remove them. The guards mean a PUC upgrade can never crash the plugin — at worst, asset-zip matching silently degrades.

## Specific regex on `enableReleaseAssets()`

```php
$name_regex = '/__RELEASE_ASSET_SLUG__-v[\d.]+\.zip($|[?&#])/i';

$api_class = get_class( $api );
if ( defined( "$api_class::REQUIRE_RELEASE_ASSETS" ) ) {
    $api->enableReleaseAssets( $name_regex, constant( "$api_class::REQUIRE_RELEASE_ASSETS" ) );
} else {
    $api->enableReleaseAssets( $name_regex );
}
```

**Why.** Without this, PUC matches *any* zip on the release, including GitHub's auto-generated source archive. That archive does not include `vendor/`, so a one-click update from it bricks the plugin on the next page load. The specific regex + `REQUIRE_RELEASE_ASSETS` together mean PUC ignores the release entirely if our CI-built zip isn't attached, which fails closed (no update offered) rather than open (broken update).

### The literal `v` in the regex is load-bearing

Do **not** relax `-v[\d.]+` to `-v?[\d.]+` to tolerate un-prefixed tags. GitHub's
auto-generated source archive for repo `Avista-Core` at tag `2.0.0` is
`Avista-Core-2.0.0.zip`, which under the `/i` flag lowercases to
`avista-core-2.0.0.zip`. A permissive `v?` matches it:

| Asset | strict `-v[\d.]+` | permissive `-v?[\d.]+` |
|---|---|---|
| `avista-core-v2.0.0.zip` (ours, has `vendor/`) | match | match |
| `Avista-Core-2.0.0.zip` (GitHub's, **no** `vendor/`) | no | **match** ← bricks the site |

Handle un-prefixed tags in the **workflow** by normalising the tag
(`VER="${RELEASE_TAG#v}"`), never by loosening the regex.

## Release or nothing — drop PUC's tag and branch fallbacks

```php
if ( method_exists( $checker, 'getUniqueName' ) ) {
    $keep = defined( "$api_class::STRATEGY_LATEST_RELEASE" )
        ? constant( "$api_class::STRATEGY_LATEST_RELEASE" )
        : 'latest_release';
    add_filter(
        $checker->getUniqueName( 'vcs_update_detection_strategies' ),
        static fn( $strategies ): array => is_array( $strategies ) ? array_intersect_key( $strategies, [ $keep => true ] ) : []
    );
}
```

**Why.** The regex and `REQUIRE_RELEASE_ASSETS` above only govern *one* of
the ways PUC finds an update. Read in PUC v5.7
(`Puc/v5p7/Vcs/GitHubApi.php`, `Vcs/Api.php`): for branch `master` or `main`,
which is what you get without `setBranch()`,
`getUpdateDetectionStrategies()` returns three strategies in order, and
`Api::chooseReference()` takes the first one that returns anything:

1. `latest_release`: `getLatestRelease()` → `/releases/latest`. Never a
   pre-release, and the asset rule applies.
2. `latest_tag`: `getLatestTag()` → the highest version-looking tag.
   `looksLikeVersion()` accepts suffixes, so `v0.25.0-beta.1` outranks
   `v0.24.1`. Its download URL is the tag's `zipball_url` (GitHub's source
   archive, no `vendor/`), and **the release-asset rule is never applied.**
3. `branch`: the branch itself, again as a source archive.

`getLatestRelease()` returns `null`, and the fallbacks run, whenever:

- the API call fails. That covers a rate limit or a network error. Shared
  WPMU DEV hosting puts many sites behind one IP, and anonymous GitHub API
  calls are capped at 60 an hour per IP.
- `REQUIRE_RELEASE_ASSETS` is set and no asset matches yet. That is the window
  between publishing a release and CI attaching the zip.

A harness driving the real v5.7 `chooseReference()` with canned GitHub
responses (2026-10-20) showed the result. Without the filter, a stable site
was offered `v0.25.0-beta.1`'s **source zipball** in three cases: on a rate
limit, on a release whose zip wasn't attached yet, and on a beta published
without `--prerelease`. With the filter, all three gave no update, and the
healthy case still gave the stable asset.

Implementation notes:

- The filter name comes from `$checker->getUniqueName()`, not a literal. PUC
  builds it as `puc_vcs_update_detection_strategies-<slug>` for plugins and
  `puc_vcs_update_detection_strategies_theme-<slug>` for themes, and the
  method gets that suffix right in both.
- The kept key is read off the runtime class (`STRATEGY_LATEST_RELEASE` is
  `'latest_release'` in v5.7), for the same reason `REQUIRE_RELEASE_ASSETS`
  is. If a future PUC renamed the strategy, the intersection would come back
  empty and updates would stop. That fails closed, never open.
- If `getUniqueName()` is missing, the filter isn't added and PUC behaves
  as it did before. That only happens on a PUC that isn't v5.

## Update channels — stable by default, beta by explicit opt-in

```php
$beta = defined( 'AVISTA_UPDATE_CHANNEL' ) && AVISTA_UPDATE_CHANNEL === 'beta';
```

Every site is on the **stable** channel: `/releases/latest` only, so
pre-releases never reach it. A site joins the **beta** channel only through
this line in its own `wp-config.php`:

```php
define( 'AVISTA_UPDATE_CHANNEL', 'beta' );
```

One constant name serves every Avista plugin and theme, so a staging site that
sets it gets betas of everything that ships this code. Any other value (`'Beta'`,
`true`, `'staging'`) is stable.

**Never infer the channel** from `wp_get_environment_type()`, the domain, or a
`staging` in the URL. Those are exactly what a cloned or misconfigured
production site gets wrong, and the failure has to land on stable.

On the beta channel the bootstrap changes two things:

1. **The release filter.** `setReleaseFilter( $cb, RELEASE_FILTER_ALL, 10 )`
   makes `getLatestRelease()` read `/releases?per_page=10` instead of
   `/releases/latest`. It walks that list newest-first, skips drafts, and
   takes the first release whose version passes `$cb`, which accepts only
   `X.Y.Z` and `X.Y.Z-beta.N`. That release is then subject to the asset rule
   as usual. If its zip isn't attached yet, the lookup returns `null`, and the
   strategy filter makes that "no update" rather than a fallback.
2. **The asset regex** also accepts `-beta.N`:
   `/<slug>-v[\d.]+(-beta\.\d+)?\.zip(…)/i`. The stable pattern
   `/<slug>-v[\d.]+\.zip(…)/i` does not match `<slug>-v0.25.0-beta.1.zip`. So
   even a beta published *without* `--prerelease`, which GitHub may then make
   Latest, finds no matching asset on a stable site and is ignored. Do not
   share one widened regex across both channels; that second line of defence
   would be lost.

Still true on both channels: only the CI-built asset is ever installed, the
version comes from the remote plugin header at that tag (which outranks the tag
name), and PUC offers an update only when `version_compare( remote, installed,
'>' )` holds.

### Version ordering (verified with PHP's `version_compare`)

| Installed | Offered | Result |
|---|---|---|
| `0.24.1` | `0.25.0-beta.1` | update (beta channel only) |
| `0.25.0-beta.1` | `0.24.2` (stable hotfix) | **no update**: `0.24.2` is lower |
| `0.25.0-beta.1` | `0.25.0-beta.2` | update |
| `0.25.0-beta.9` | `0.25.0-beta.10` | update (numeric compare) |
| `0.25.0-beta.2` | `0.25.0` | update: the final outranks every beta of it |

A beta site therefore stays on its beta through any stable hotfix of the
previous line. It moves on only at the final `0.25.0` or a later beta.

The beta channel takes the **newest-created** qualifying release in GitHub's
list order, not the highest version. So a stable hotfix published *after* a beta
masks that beta from beta-channel sites that are still on stable. Those sites get
the hotfix, and the beta stays hidden until the next beta is cut. Sites already
on the beta are unaffected, because the hotfix is lower.

### Leaving the beta channel

1. Remove the constant from `wp-config.php`.
2. Clear PUC's cached result, so an already-fetched beta offer can't be applied
   (or auto-applied by WPMU DEV Hub Automate) before the next check:
   `wp option delete external_updates-<slug>` for each Avista plugin, or click
   **Check for updates** on each plugin row.
3. The site **keeps the beta it has installed**. It is not downgraded, and
   it moves on only when a stable release higher than that beta ships.
4. To go back down now, force-install the Latest zip:
   `gh release download <latest-tag> -R <owner>/<repo> -p '*.zip'`, then
   `wp plugin install <zip> --force` (see `release-plugin` Step 9).

### WPMU DEV staging pushes may carry the constant to production

Pushing staging to production may copy `wp-config.php`, and with it
`AVISTA_UPDATE_CHANNEL`, onto the live site. Checked against WPMU DEV's
docs on 2026-10-20: *Hosting → Staging* (last updated 2026-10-12) and
*Unlimited Hosting → Staging*. Neither page mentions `wp-config.php`
in its push description, either as included or as excluded. The dedicated
hosting page defines a **Files** push as moving everything visible over SFTP
or in the Hub's Manage Files, "including core WordPress files, themes,
plugins & media". `wp-config.php` sits in that tree. **Treat it as
riding along** until WPMU DEV support confirms otherwise:

- After every staging → production push from a beta-channel staging site, run
  `wp config get AVISTA_UPDATE_CHANNEL` on **production**. It must fail with
  "not defined". If it is defined, `wp config delete AVISTA_UPDATE_CHANNEL`,
  then follow "Leaving the beta channel" above.
- **Sync production to Staging** overwrites every staging file, so the
  constant can vanish from staging. Re-check it after a sync.

### Betas from more than one branch

There is one beta channel per plugin, not one per feature. If branch A ships
`0.26.0-beta.1` and branch B then ships `0.26.0-beta.2`, every beta site moves to
B, and A's work disappears from those sites unless B contains it. Betas are not
cumulative. Merge parallel features into one integration branch before cutting
betas from it, or take turns.

## Fail closed cuts both ways — mind the naming-change cliff

`REQUIRE_RELEASE_ASSETS` makes a regex miss fail closed, which is the behaviour we
want, but it has one sharp consequence: **the regex that decides whether an update
is visible is the one compiled into the version already installed on the site**, not
the one in the release you just cut.

So if a plugin currently shipping a statically-named asset
(`avista-<plugin>-release.zip`) switches to versioned naming, installed sites poll,
see the new release, fail to match their own old regex, and silently ignore it
forever. Those sites need one manual reinstall to cross over.

To migrate without a cliff, make the transition release attach **both** names, then
drop the legacy one a release later:

```bash
cp "${ASSET}" "__RELEASE_ASSET_SLUG__-release.zip"
gh release upload "${RELEASE_TAG}" "${ASSET}" "__RELEASE_ASSET_SLUG__-release.zip" --clobber
```

Old installs match `-release.zip` and update into the new code; from then on they
match the versioned name. New scaffolds skip this entirely — they start versioned.

## Asserting the artifact is installable before upload

```yaml
- name: Verify artifact is installable
  run: |
    for required in \
      __BUILD_DIR_NAME__/__MAIN_PLUGIN_FILE__ \
      __BUILD_DIR_NAME__/vendor/autoload.php
    do
      if ! unzip -l "${ASSET}" | grep -q "  ${required}$"; then
        echo "ERROR: ${required} missing from ${ASSET}"
        exit 1
      fi
    done
```

**Why.** A release zip missing `vendor/autoload.php` installs cleanly and then
trips the `file_exists()` guard forever after — meaning the updater is disabled on
every site that zip reaches, silently, and the site can no longer receive the fix.
That is the single most expensive way this pipeline can fail, and it is
one `grep` to rule out. The two-space prefix in the grep matches `unzip -l`'s
column layout; the `$` anchor stops `autoload.php` matching `autoload.php.bak`.

## `BOOT_FLAG` constant guard

```php
private const BOOT_FLAG = '__PLUGIN_CONST___PUC_BOOTSTRAPPED';

public static function bootstrap(): void {
    if ( defined( self::BOOT_FLAG ) ) {
        return;
    }
    define( self::BOOT_FLAG, true );
    // …
}
```

**Why.** Defends against double-initialization if the plugin file is loaded twice (mu-plugin + plugins/ symlink, or a misconfigured include chain). PUC happily registers a second checker, which then races with the first against the same option keys.

## Brand icon injection — two hooks

```php
$checker->addResultFilter( [ self::class, 'inject_plugin_icons' ] );
add_filter( 'plugins_api', [ self::class, 'inject_view_details_icons' ], 30, 3 );
```

**Why.** PUC's result filter populates the `update_plugins` transient (the icon shown on the update notice). The `plugins_api` filter at priority > 20 patches the "View details" modal, because PUC's `PluginInfo::toWpFormat()` strips the icons array. You need both — patching only one of them leaves the default electric-plug icon showing in the other surface. Both are no-ops if `assets/img/icon.svg` and `banner.svg` don't exist, so wiring them before adding the brand assets is safe.

## Init priority 30

```php
add_action( 'init', [ '__PLUGIN_PASCAL___Update_Checker', 'bootstrap' ], 30 );
```

**Why.** Late enough that ACF (priority 10) and other init-time setups have already fired, so any code the bootstrap calls into can safely assume the environment is configured. The exact priority isn't sacred; just don't run before priority 10.

## Excluding `CLAUDE.md` and `composer.json` from the release artifact

```yaml
--exclude 'CLAUDE.md' \
--exclude 'composer.json' \
--exclude 'composer.lock' \
```

**Why.** Production sites don't need the dev-facing instructions or the source manifest — only the compiled `vendor/`. Shipping `composer.json` could also confuse users who try to `composer install` against a production site and get a different `vendor/` than the release was built with.

## `workflow_dispatch` with a `tag` input

```yaml
workflow_dispatch:
  inputs:
    tag:
      description: 'Tag to build (e.g. 1.4.18). Defaults to the ref the workflow was dispatched against.'
      required: false
      type: string
```

**Why.** Escape hatch for re-running a build against a specific tag without re-publishing the release (which would generate a duplicate notification). Comes up when fixing a CI flake.

## `--clobber` on the `gh release upload`

```yaml
gh release upload "${RELEASE_TAG}" "${ASSET}" --clobber
```

**Why.** A re-dispatched workflow against an existing release would otherwise refuse to overwrite the existing asset. `--clobber` makes the upload idempotent.

## Writing `.github/workflows/` needs the `workflow` token scope

Committing this file through the GitHub **REST contents API** requires a token with
the `workflow` scope, not just `repo`. The Avista org account
(`jontryggviAvista`) currently has `repo` but **not** `workflow`.

The failure is badly signposted: the API returns **`404`**, not `403`, so it reads
as "repo not found" or "wrong path" and sends you auditing the URL instead of the
token. If you hit a 404 writing a workflow file to a repo you can otherwise read
and write, it's the scope.

Commit workflow files over **git-over-SSH** instead, which carries no such
restriction.
