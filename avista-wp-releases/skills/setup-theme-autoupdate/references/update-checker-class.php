<?php
/**
 * Template — Avista theme auto-updater bootstrap.
 *
 * Replace every __PLACEHOLDER__ token before writing. See SKILL.md for the
 * placeholder table.
 *
 * Append to the theme's functions.php after the vendor/autoload.php guard.
 * The add_action() at the bottom registers at init priority 30 — late enough
 * that any init-time setups have already run.
 */

// Only the version-agnostic `v5` alias may be imported. PUC's per-release
// namespace (v5p6, v5p7, …) floats under the `^5.6` Composer constraint, and
// `v5\Vcs\Api` does not exist at all — the REQUIRE_RELEASE_ASSETS constant is
// resolved off the runtime class below instead. See the plugin skill's
// conventions.md → "Never hardcode a v5pN namespace".
use YahnisElsts\PluginUpdateChecker\v5\PucFactory;

final class __THEME_PASCAL___Theme_UpdateChecker {
    private const REPO_URL   = 'https://github.com/__GH_OWNER__/__GH_REPO__/';
    private const THEME_SLUG = '__THEME_SLUG__';
    private const BOOT_FLAG  = '__THEME_CONST___PUC_BOOTSTRAPPED';

    public static function bootstrap(): void {
        if ( defined( self::BOOT_FLAG ) ) {
            return;
        }
        define( self::BOOT_FLAG, true );

        if ( ! class_exists( PucFactory::class ) ) {
            return;
        }

        $checker = PucFactory::buildUpdateChecker(
            self::REPO_URL,
            get_stylesheet_directory() . '/functions.php',
            self::THEME_SLUG,
            1 // checkPeriod (hours). PUC's default is 12 — too slow when you
              // cut several releases in a day, since a site only notices a
              // new release on its next poll. Hourly is well within the
              // GitHub API rate limit with a token. Force an immediate
              // pickup with the "Check for updates" link or a direct install.
        );

        $token = defined( 'GITHUB_TOKEN' ) ? GITHUB_TOKEN : '';
        if ( $token !== '' ) {
            $checker->setAuthentication( $token );
        }

        // Match only the CI-built release asset. Without this, PUC falls back
        // to GitHub's auto-generated source archive, which doesn't include
        // vendor/ and would brick the theme on a one-click update.
        if ( method_exists( $checker, 'getVcsApi' ) ) {
            $vcs_api = $checker->getVcsApi();
            if ( is_object( $vcs_api ) && method_exists( $vcs_api, 'enableReleaseAssets' ) ) {
                $name_regex = '/__THEME_SLUG__\.zip($|[?&#])/i';

                // Resolve the flag off the *runtime* class — it lives on the
                // concrete v5pN\Vcs\Api, which the `v5` alias does not cover.
                $api_class = get_class( $vcs_api );
                if ( defined( "$api_class::REQUIRE_RELEASE_ASSETS" ) ) {
                    $vcs_api->enableReleaseAssets( $name_regex, constant( "$api_class::REQUIRE_RELEASE_ASSETS" ) );
                } else {
                    $vcs_api->enableReleaseAssets( $name_regex );
                }

                // Update channel. Stable unless this site's wp-config.php says,
                // exactly: define( 'AVISTA_UPDATE_CHANNEL', 'beta' );
                // Explicit opt-in only, never inferred from the environment type
                // or the domain. On the beta channel, read the newest releases
                // with pre-releases included; only X.Y.Z and X.Y.Z-beta.N tags
                // count. See the plugin skill's conventions.md → "Update channels".
                $beta = defined( 'AVISTA_UPDATE_CHANNEL' ) && AVISTA_UPDATE_CHANNEL === 'beta';
                if ( $beta && method_exists( $vcs_api, 'setReleaseFilter' ) && defined( "$api_class::RELEASE_FILTER_ALL" ) ) {
                    $vcs_api->setReleaseFilter(
                        static fn( $version ): bool => preg_match( '/^\d+(\.\d+)*(-beta\.\d+)?$/', (string) $version ) === 1,
                        constant( "$api_class::RELEASE_FILTER_ALL" ),
                        10
                    );
                }

                // Update from a GitHub Release or not at all: drop PUC's tag and
                // branch fallbacks, which serve GitHub's source zip (no vendor/)
                // and pick -beta tags. See the plugin skill's conventions.md →
                // "Release or nothing".
                if ( method_exists( $checker, 'getUniqueName' ) ) {
                    $keep = defined( "$api_class::STRATEGY_LATEST_RELEASE" )
                        ? constant( "$api_class::STRATEGY_LATEST_RELEASE" )
                        : 'latest_release';
                    add_filter(
                        $checker->getUniqueName( 'vcs_update_detection_strategies' ),
                        static fn( $strategies ): array => is_array( $strategies ) ? array_intersect_key( $strategies, [ $keep => true ] ) : []
                    );
                }
            }
        }

        // Themes only: when no release qualifies, PUC's theme checker does not
        // stop the way the plugin checker does. It reads style.css from the
        // configured branch ('master') and can return an "update" with a
        // version and no download URL. Drop it rather than show an update that
        // cannot be applied. See conventions.md → "No release means no update".
        if ( method_exists( $checker, 'addResultFilter' ) ) {
            $checker->addResultFilter( static function ( $update ) {
                return ( is_object( $update ) && empty( $update->download_url ) ) ? null : $update;
            } );
        }
    }
}

add_action( 'init', static function (): void {
    __THEME_PASCAL___Theme_UpdateChecker::bootstrap();
}, 30 );

// Soft warning when vendor/ is missing. In local dev that's expected — vendor/
// is built by GitHub Actions on release. Only show to admins.
add_action( 'admin_notices', static function (): void {
    if ( ! current_user_can( 'manage_options' ) ) {
        return;
    }
    if ( ! class_exists( PucFactory::class ) ) {
        echo '<div class="notice notice-warning"><p>Theme updater: <code>vendor/</code> is missing. It is built automatically on GitHub release — no action needed on production.</p></div>';
    }
} );
