# Theme auto-updater — non-obvious guards and theme-specific divergences

Most of the standing conventions are shared with the plugin scaffold. This doc focuses on what's *different* about themes, then references the shared guards.

## Shared with the plugin scaffold

These conventions apply identically to themes. See the plugin skill's `conventions.md` for the long-form reasoning behind each:

- **`file_exists()` around `vendor/autoload.php`** — `vendor/` is git-ignored and built by Actions; the guard lets the theme load cleanly without the autoloader.
- **`class_exists(PucFactory::class)` after autoload** — defends against partial composer installs.
- **`method_exists()` around `getVcsApi()` and `enableReleaseAssets()`** — future-proofs against PUC API changes between minor versions.
- **`REQUIRE_RELEASE_ASSETS` + specific zip regex** — prevents PUC from grabbing GitHub's auto-generated source archive, which would brick the theme by not including `vendor/`.
- **`BOOT_FLAG` constant guard** — defends against double-initialization. Critical for themes because a child theme can also load the parent's `functions.php`, which would otherwise register two PUC checkers racing against the same option keys.
- **Init priority 30** — late enough that other init-time setups have run.
- **Env-gated `admin_notices`** — *not* env-gated in the theme version (see divergence below).

## Theme-specific divergences

### Version source is `style.css`, not the file header of `functions.php`

WordPress reads a theme's metadata from `style.css`. The `Version:` line there is the source of truth — bumping the version means editing `style.css`, not `functions.php`.

PUC's `buildUpdateChecker()` second argument needs the file whose plugin/theme header WP scans for the version. For plugins it's the main plugin file. For themes it's `get_stylesheet_directory() . '/functions.php'` — *not* because `functions.php` has the version, but because PUC needs a path to derive the theme's slug from, and WP's theme system points it at `functions.php` while reading the actual version metadata from the parallel `style.css`. This is a PUC convention — don't second-guess it.

### Release zip naming: `{theme-slug}.zip` (no `-release` suffix)

Plugin convention: `avista-<plugin>-release.zip`. Theme convention: `<theme-slug>.zip`.

The asymmetry exists because themes are typically installed by their slug being the same as the zip basename (WP's "Add New Theme → Upload" reads the directory name from inside the zip and matches it against existing themes). A `-release` suffix in the zip name would confuse some upload UIs. Keep theme zips plain.

The regex in the PUC config follows the zip name: `/<theme-slug>\.zip($|[?&#])/i`.

### No brand-icon injection

Plugins have a chunky icon/banner injection block — the "Update Available" notice on the Plugins page shows a 256×256 icon, and the "View Details" modal shows a 1544×500 banner. Themes have neither of those surfaces; the WP themes admin uses `screenshot.png` from the theme root.

The theme bootstrap class therefore omits:

- `addResultFilter()` for icon injection
- The `plugins_api` filter at priority 30
- `inject_plugin_icons()` / `inject_view_details_icons()` / `fallback_plugin_info()` methods
- The `icon_urls()` and `banner_urls()` helpers
- The `slug_refers_to_us()` candidate-list logic

If a theme later wants a banner in the WP themes screen, ship `screenshot.png` (1200×900) in the theme root — that's the standard WP mechanism.

### Workflow file is `release-theme.yml`, not `release.yml`

In case a single repo ever houses both a plugin and a theme (uncommon but happens — sites with a custom theme that ships a paired companion plugin), the workflow filenames must not collide. Plugin → `release.yml`. Theme → `release-theme.yml`. Same release-publish trigger; both fire on the same release event, both attach their own asset.

### Workflow uses `softprops/action-gh-release@v2`, not `gh release upload`

The plugin workflow uses `gh release upload --clobber` from the GitHub CLI; the theme workflow uses the `softprops/action-gh-release@v2` marketplace action. Functionally equivalent — both attach the zip to the release. The difference is historical: themes were scaffolded with the marketplace action first, plugins later moved to the CLI. Both work; don't unify them in a single edit without testing both pipelines.

### Admin notice is *not* env-gated

The plugin scaffold suppresses the "vendor/ missing" notice in `local`/`development`. The theme scaffold shows it always (to admins). This is intentional: themes are more likely to be edited locally without a Composer step, and the always-on notice catches devs who forget. If the noise becomes annoying, add the same `wp_get_environment_type()` check the plugin uses.

### Build dir conventions

The plugin workflow uses `build/<dir>` as a staging directory and the theme workflow uses `dist/<slug>`. Same idea, different naming. Don't try to unify — both are working and the deltas would just be churn.
