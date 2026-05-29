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

use YahnisElsts\PluginUpdateChecker\v5\PucFactory;
use YahnisElsts\PluginUpdateChecker\v5p6\Vcs\Api as PucVcsApi;

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
                $vcs_api->enableReleaseAssets(
                    '/__THEME_SLUG__\.zip($|[?&#])/i',
                    PucVcsApi::REQUIRE_RELEASE_ASSETS
                );
            }
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
