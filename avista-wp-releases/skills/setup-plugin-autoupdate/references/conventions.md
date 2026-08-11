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
