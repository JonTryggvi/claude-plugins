# Retrofit — release-only updates and the beta channel

For a plugin whose updater already exists, whether scaffolded by an earlier
version of this skill or written by hand. A new scaffold already includes this;
skip this file for those.

What the patch does is explained in `conventions.md`, in "Release or nothing"
and "Update channels". In short:

- It drops PUC's tag and branch fallbacks. Today they can serve a `-beta` tag's
  source zip, which has no `vendor/`, whenever `/releases/latest` comes back
  empty: on a rate limit, or before CI has attached the zip.
- It adds the opt-in beta channel: `define( 'AVISTA_UPDATE_CHANNEL', 'beta' );`
  in a site's `wp-config.php`.

## Ground rules

- **One plugin per session, and only with the owner's go for that plugin.** Do not
  patch or release any other plugin from the session you are in.
- Ship it through `release-plugin` as a normal patch release. The retrofit
  protects a site only once that release is **installed** there. Until then the
  site runs the old code.
- **Until the patched release has reached the fleet, do not publish a beta tag
  that outranks the plugin's Latest release.** Old code's tag fallback would
  offer that tag's source zip to stable sites. With WPMU DEV Hub Automate
  running mostly on Sundays, allow a full week after the patched release before
  cutting such a beta. Check first with
  `gh api repos/<owner>/<repo>/releases/latest --jq .tag_name`.

**Shipped 2026-10-20**, each through the pre-release-first flow and now Latest:
Avista Core `v2.18.2`, ACMA `v0.24.2`, ERP Onboarding `v0.10.2`, Digital ID
`v2.1.3`. They are the first versions of each plugin that carry the
release-only filter and the beta channel. At release, no tag in those four repos
outranked them. **The earliest a beta above them may be cut is after the WPMU DEV
Automate runs of Sunday 2026-10-25 have been checked**, i.e. once the fleet
inventory shows those versions installed.

## 1. Find the updater

```bash
grep -rln "buildUpdateChecker\|enableReleaseAssets" --include="*.php" . | grep -v /vendor/
```

Known locations:

| Plugin | File | Entry point | API variables |
|---|---|---|---|
| Avista Commerce MyAccount (ACMA) | `includes/Support/Updater.php` | `Avista\CommerceMyAccount\Support\Updater::init()` | `$checker`, `$api`, `$api_class` |
| Avista Core | `includes/Support/Updater.php` | `Avista\Core\Support\Updater::init()` | `$checker`, `$api`, `$api_class` |
| Avista ERP Onboarding | `includes/class-update-checker.php` | `Avista_Onboarding_Update_Checker::bootstrap()` | `$checker`, `$vcs`, `$vcs_class` |
| Avista Digital ID | `includes/class-avista-update-checker.php` | `Avista_Update_Checker::bootstrap()` (PUC slug `avista-auth`) | `$checker`, `$vcs_api`; no class variable (see below) |
| Scaffolded by this skill | the main plugin file | `<Pascal>_Update_Checker::bootstrap()` | `$checker`, `$api`, `$api_class` |

**Digital ID is shaped differently** (read on `main`, 2026-10-20, Latest `v2.1.2`):

- It reads the constant through `$require_assets_const` and passes the regex inline to `enableReleaseAssets()`. Replace from the `$require_assets_const = …` line through the end of that `enableReleaseAssets( … );` call. Inside the block rename `$api` → `$vcs_api`. The block's own `$api_class = get_class(…)` line then supplies the class variable the rest of the block needs.
- Its old regex `/avista-digital-id(-v[\d.]+)?\.zip($|[?&#])/i` made the whole `-v<version>` group optional. It was not the dangerous `-v?` form, since GitHub's `Avista-Digital-Id-2.1.2.zip` never matched, but it also accepted the unversioned `avista-digital-id.zip`. The retrofit (2.1.3) tightens it to the house pattern. Stable: `/avista-digital-id-v[\d.]+\.zip($|[?&#])/i`. Beta: `/avista-digital-id-v[\d.]+(-beta\.\d+)?\.zip($|[?&#])/i`. That is safe because a regex is only ever tested against the *offered* release's asset. Older installs keep their own pattern, which matches versioned names, and every release since v1.2.0 ships `avista-digital-id-v<version>.zip`. The unversioned name appears only on v1.0.31–v1.0.42 (checked 2026-10-20, 24 releases). The old in-code comment claiming the optional group protects "a site still running an older build" was wrong. A build's regex only judges releases offered *after* that build, and none of those use the unversioned name.
- It is on PUC 5.6. Every API the block uses (`getUniqueName`, `setReleaseFilter`, `RELEASE_FILTER_ALL`, `STRATEGY_LATEST_RELEASE`, `REQUIRE_RELEASE_ASSETS`) exists there, checked in its `vendor/` by the plugin-audit session.

Confirm the file contains all of these before you patch:

- `$checker = $factory::buildUpdateChecker( … )` through the `v5` alias. A pinned
  `v5pN` is a separate bug, so fix it first (see `conventions.md`).
- A `$name_regex` for a **versioned** asset: `/<slug>-v[\d.]+\.zip($|[?&#])/i`.
- `enableReleaseAssets( $name_regex, constant( "$api_class::REQUIRE_RELEASE_ASSETS" ) )`.

If the regex is still the legacy static `<slug>-release.zip`, keep that regex
unchanged. Leave out the `$beta ?` split, and keep the release-filter and
strategy-filter parts. Its betas and finals share one asset name, so it gets no
asset-name defence. Say so in the release notes.

## 2. Replace the block

Replace everything from the `$name_regex = …` line through the closing `}` of
the `enableReleaseAssets()` if/else with the block below.

- Substitute `__RELEASE_ASSET_SLUG__` with the slug from the current regex: the
  part before `-v`, e.g. `avista-commerce-myaccount`.
- In ERP Onboarding, rename `$api` → `$vcs` and `$api_class` → `$vcs_class`
  inside the block to match the surrounding code.
- Indentation is two spaces per level, as in all three plugins. The block is
  written for ACMA's and Core's depth, directly inside `init()`. ERP
  Onboarding's sits two levels deeper, inside its `method_exists()` checks,
  so shift it right to match.

```php
    // ── Update channel ─────────────────────────────────────────────────────
    // Stable unless this site's wp-config.php says, exactly:
    //   define('AVISTA_UPDATE_CHANNEL', 'beta');
    // Explicit opt-in only. Never inferred from wp_get_environment_type() or
    // the domain: a misconfigured site has to land on stable, not on a beta.
    $beta = defined('AVISTA_UPDATE_CHANNEL') && AVISTA_UPDATE_CHANNEL === 'beta';

    // A beta's asset is <slug>-vX.Y.Z-beta.N.zip, and only the beta channel's
    // regex accepts it. A beta published as Latest by mistake therefore has no
    // matching asset on a stable site, and REQUIRE_RELEASE_ASSETS ignores it.
    // The literal `v` stays load-bearing in both patterns.
    $name_regex = $beta
      ? '/__RELEASE_ASSET_SLUG__-v[\d.]+(-beta\.\d+)?\.zip($|[?&#])/i'
      : '/__RELEASE_ASSET_SLUG__-v[\d.]+\.zip($|[?&#])/i';
    $api_class = get_class($api);
    if (defined("$api_class::REQUIRE_RELEASE_ASSETS")) {
      $api->enableReleaseAssets($name_regex, constant("$api_class::REQUIRE_RELEASE_ASSETS"));
    } else {
      $api->enableReleaseAssets($name_regex);
    }

    // Beta channel: read the newest releases with pre-releases included, not
    // /releases/latest (which never returns a pre-release). Only X.Y.Z and
    // X.Y.Z-beta.N tags count. PUC still offers a release only when it is
    // higher than the installed version, and still only its CI-built asset.
    if ($beta && method_exists($api, 'setReleaseFilter') && defined("$api_class::RELEASE_FILTER_ALL")) {
      $api->setReleaseFilter(
        static fn($version): bool => preg_match('/^\d+(\.\d+)*(-beta\.\d+)?$/', (string) $version) === 1,
        constant("$api_class::RELEASE_FILTER_ALL"),
        10
      );
    }

    // Update from a GitHub Release or not at all. When the release lookup
    // comes back empty (a rate limit, or a release whose zip CI has not
    // attached yet), PUC falls back to the highest version-looking tag, then
    // to the branch. Both serve GitHub's source zip with no vendor/, and the
    // tag fallback skips the asset rule and ranks v0.25.0-beta.1 above v0.24.1.
    if (method_exists($checker, 'getUniqueName')) {
      $keep = defined("$api_class::STRATEGY_LATEST_RELEASE")
        ? constant("$api_class::STRATEGY_LATEST_RELEASE")
        : 'latest_release';
      add_filter(
        $checker->getUniqueName('vcs_update_detection_strategies'),
        static fn($strategies): array => is_array($strategies) ? array_intersect_key($strategies, [$keep => true]) : []
      );
    }
```

Leave the rest of the class as it is: the token resolver, `BOOT_FLAG`, icon
injection, and the early returns on a missing `getVcsApi()` or
`enableReleaseAssets()`. When PUC or `vendor/` is missing, the class still
returns before this block runs.

This exact block was run against the real PUC v5.7 `GitHubApi::chooseReference()`
with canned GitHub responses (2026-10-20). Stable sites got no update on a rate
limit, on a release with no zip yet, and on a beta published without
`--prerelease`; a healthy release still gave the stable asset. Beta sites got the
beta's CI zip, skipped `-rc` tags, and got no update while a beta's zip was
missing.

## 3. Check before releasing

```bash
php -l <updater-file>
grep -n "v5p[0-9]" <updater-file>        # must print nothing
grep -n "AVISTA_UPDATE_CHANNEL\|vcs_update_detection_strategies\|RELEASE_FILTER_ALL" <updater-file>
```

Then the plugin's own tests, if it has a `tests.yml` workflow.

## 4. Release and confirm

Release with `release-plugin` (patch bump, normal flow). On a site that has
installed it:

```bash
# The strategy filter is registered (prints bool(true)):
wp eval 'global $wp_filter; var_dump( isset( $wp_filter["puc_vcs_update_detection_strategies-<puc-slug>"] ) );'
# The site's channel. Production must print "not defined":
wp config get AVISTA_UPDATE_CHANNEL
```

`<puc-slug>` is the slug PUC was built with, the third `buildUpdateChecker()`
argument (e.g. `ACMA_PLUGIN_SLUG`'s value).

To put a staging site on the beta channel once all three plugins have shipped
the retrofit, add `define( 'AVISTA_UPDATE_CHANNEL', 'beta' );` to its
`wp-config.php`. Then read `conventions.md`, "Update channels". It covers
version ordering, leaving the channel, and the WPMU DEV staging → production
push check.
