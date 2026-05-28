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

## `class_exists(PucFactory::class)` after autoload

```php
if ( ! class_exists( \YahnisElsts\PluginUpdateChecker\v5p6\PucFactory::class ) ) {
    return;
}
```

**Why.** Defends against a partially-installed `vendor/` (e.g. broken composer install, manual file copy that missed a dependency). The autoloader registers but the class still can't resolve. Without the guard, the next line throws `Error: Class not found`.

## `method_exists()` around `getVcsApi()` and `enableReleaseAssets()`

```php
if ( method_exists( $checker, 'getVcsApi' ) ) {
    $vcs = $checker->getVcsApi();
    if ( is_object( $vcs ) && method_exists( $vcs, 'enableReleaseAssets' ) ) {
        $vcs->enableReleaseAssets( /* … */ );
    }
}
```

**Why.** Future-proofs against PUC API changes between minor versions. PUC v5p6 has these methods; earlier versions don't, and a future cleanup could remove them. The guards mean a PUC upgrade can never crash the plugin — at worst, asset-zip matching silently degrades.

## Specific regex on `enableReleaseAssets()`

```php
$vcs->enableReleaseAssets(
    '/__RELEASE_ZIP_BASE__\.zip($|[?&#])/i',
    \YahnisElsts\PluginUpdateChecker\v5p6\Vcs\Api::REQUIRE_RELEASE_ASSETS
);
```

**Why.** Without this, PUC matches *any* zip on the release, including GitHub's auto-generated source archive (`<owner>-<repo>-<sha>.zip`). That archive does not include `vendor/`, so a one-click update from it bricks the plugin on the next page load. The specific regex + `REQUIRE_RELEASE_ASSETS` together mean PUC ignores the release entirely if our CI-built zip isn't attached, which fails closed (no update offered) rather than open (broken update).

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
gh release upload "${RELEASE_TAG}" __RELEASE_ZIP_BASE__.zip --clobber
```

**Why.** A re-dispatched workflow against an existing release would otherwise refuse to overwrite the existing asset. `--clobber` makes the upload idempotent.
