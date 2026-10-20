<?php
/**
 * Template — Avista plugin auto-updater bootstrap.
 *
 * Lifted from Avista/Avista-Regluvordur. Replace every __PLACEHOLDER__ token
 * before writing. See SKILL.md for the placeholder table and derivation rules.
 *
 * Insert this block in the plugin's main file immediately after the existing
 * define() constants. The matching add_action() at the bottom must register
 * at init priority 30 — late enough that ACF and other init-time setups have
 * already run.
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

define( '__PLUGIN_CONST___DIR', plugin_dir_path( __FILE__ ) );
define( '__PLUGIN_CONST___FILE', __FILE__ );
define( '__PLUGIN_CONST___SLUG', '__PLUGIN_SLUG__' );

// Single source of truth for the version: the `Version:` line in this file's
// plugin header. PUC and any asset cache-busters should derive from this same
// string — bump only the header on release.
define( '__PLUGIN_CONST___VERSION', (string) ( get_file_data( __FILE__, [ 'Version' => 'Version' ] )['Version'] ?? '0.0.0' ) );

// ── PUC — plugin auto-updates via GitHub releases ────────────────────────────

final class __PLUGIN_PASCAL___Update_Checker {
    private const REPO_URL  = 'https://github.com/__GH_OWNER__/__GH_REPO__/';
    private const BOOT_FLAG = '__PLUGIN_CONST___PUC_BOOTSTRAPPED';

    public static function bootstrap(): void {
        if ( defined( self::BOOT_FLAG ) ) {
            return;
        }
        define( self::BOOT_FLAG, true );

        $autoload = __PLUGIN_CONST___DIR . 'vendor/autoload.php';
        if ( ! file_exists( $autoload ) ) {
            if ( ! in_array( wp_get_environment_type(), [ 'local', 'development' ], true ) ) {
                add_action( 'admin_notices', function(): void {
                    if ( ! current_user_can( 'manage_options' ) ) return;
                    echo '<div class="notice notice-warning"><p><strong>__PLUGIN_TITLE__:</strong> The <code>vendor/</code> folder is missing. Run <code>composer install</code>.</p></div>';
                } );
            }
            return;
        }

        require_once $autoload;

        // PUC ships a version-pinned namespace per release (v5p6, v5p7, …) plus a
        // stable `v5` alias. The Composer constraint `^5.6` floats, so a hardcoded
        // v5pN namespace silently stops resolving on the next minor. Always use
        // the alias. See conventions.md → "Never hardcode a v5pN namespace".
        $factory = '\\YahnisElsts\\PluginUpdateChecker\\v5\\PucFactory';
        if ( ! class_exists( $factory ) ) {
            return;
        }

        $checker = $factory::buildUpdateChecker(
            self::REPO_URL,
            __PLUGIN_CONST___FILE,
            __PLUGIN_CONST___SLUG,
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

        if ( method_exists( $checker, 'getVcsApi' ) ) {
            $api = $checker->getVcsApi();
            if ( is_object( $api ) && method_exists( $api, 'enableReleaseAssets' ) ) {
                // Update channel. Stable unless this site's wp-config.php says,
                // exactly: define( 'AVISTA_UPDATE_CHANNEL', 'beta' );
                // Explicit opt-in only, never inferred from the environment type
                // or the domain: a misconfigured site must land on stable.
                // See conventions.md → "Update channels".
                $beta = defined( 'AVISTA_UPDATE_CHANNEL' ) && AVISTA_UPDATE_CHANNEL === 'beta';

                // Match only our CI-built, versioned asset. The literal `v` is
                // load-bearing: GitHub's auto-generated source archive for repo
                // `Avista-Core` at tag 2.0.0 is `Avista-Core-2.0.0.zip`, which a
                // permissive `v?` would match — and it ships no vendor/, so an
                // update from it bricks the plugin.
                //
                // A beta's asset is <slug>-vX.Y.Z-beta.N.zip, and only the beta
                // channel's pattern accepts it. A beta published as Latest by
                // mistake therefore has no matching asset on a stable site.
                $name_regex = $beta
                    ? '/__RELEASE_ASSET_SLUG__-v[\d.]+(-beta\.\d+)?\.zip($|[?&#])/i'
                    : '/__RELEASE_ASSET_SLUG__-v[\d.]+\.zip($|[?&#])/i';

                // Resolve REQUIRE_RELEASE_ASSETS off the *runtime* class. The
                // constant lives on the concrete v5pN\Vcs\Api and is NOT exposed
                // through the `v5` alias, so it cannot be referenced statically
                // without re-pinning the namespace we just stopped pinning.
                $api_class = get_class( $api );
                if ( defined( "$api_class::REQUIRE_RELEASE_ASSETS" ) ) {
                    $api->enableReleaseAssets( $name_regex, constant( "$api_class::REQUIRE_RELEASE_ASSETS" ) );
                } else {
                    $api->enableReleaseAssets( $name_regex );
                }

                // Beta channel: read the newest releases with pre-releases
                // included, instead of /releases/latest (which never returns a
                // pre-release). Only X.Y.Z and X.Y.Z-beta.N tags count. PUC still
                // offers a release only when it is higher than the installed
                // version, and still only its CI-built asset.
                if ( $beta && method_exists( $api, 'setReleaseFilter' ) && defined( "$api_class::RELEASE_FILTER_ALL" ) ) {
                    $api->setReleaseFilter(
                        static fn( $version ): bool => preg_match( '/^\d+(\.\d+)*(-beta\.\d+)?$/', (string) $version ) === 1,
                        constant( "$api_class::RELEASE_FILTER_ALL" ),
                        10
                    );
                }

                // Update from a GitHub Release or not at all. When the release
                // lookup comes back empty (a rate limit, or a release whose zip
                // CI has not attached yet), PUC falls back to the highest
                // version-looking tag, then to the branch. Both serve GitHub's
                // source zip with no vendor/, and the tag fallback skips the
                // asset rule and ranks v0.25.0-beta.1 above v0.24.1. Keep only
                // the release strategy. See conventions.md → "Release or nothing".
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

        // Replace WP's default electric-plug icon with the bundled brand mark.
        // Two hooks needed: PUC's result filter populates the update_plugins
        // transient (update-notice icon), while plugins_api at priority > 20
        // patches the "View details" modal — PUC's PluginInfo::toWpFormat()
        // drops the icons array so we re-add it after PUC's injectInfo runs.
        // Both calls are no-ops when assets/img/icon.svg or banner.svg are
        // missing — safe to leave wired even before brand assets exist.
        if ( method_exists( $checker, 'addResultFilter' ) ) {
            $checker->addResultFilter( [ self::class, 'inject_plugin_icons' ] );
        }
        add_filter( 'plugins_api', [ self::class, 'inject_view_details_icons' ], 30, 3 );
    }

    public static function inject_plugin_icons( $plugin_info, $http_result = null ) {
        if ( is_object( $plugin_info ) ) {
            $plugin_info->icons = self::icon_urls();
        }
        return $plugin_info;
    }

    public static function inject_view_details_icons( $result, $action = null, $args = null ) {
        if ( $action !== 'plugin_information' || ! is_object( $args ) ) {
            return $result;
        }
        $slug = (string) ( $args->slug ?? '' );
        if ( ! self::slug_refers_to_us( $slug ) ) {
            return $result;
        }

        if ( is_object( $result ) && ! is_wp_error( $result ) && isset( $result->name ) ) {
            $result->icons   = self::icon_urls();
            $result->banners = self::banner_urls();
            return $result;
        }

        // PUC bailed (slug WP passed isn't recognized, GitHub unreachable, no
        // release published yet, …). Without intervention WP falls through to
        // the WordPress.org API and the modal shows "Invalid plugin slug".
        // Build a minimal info object from the plugin header so the modal
        // renders the brand icon and basic metadata.
        return self::fallback_plugin_info();
    }

    private static function slug_refers_to_us( string $slug ): bool {
        if ( $slug === '' ) {
            return false;
        }
        $basename   = plugin_basename( __PLUGIN_CONST___FILE );
        $candidates = [
            __PLUGIN_CONST___SLUG,
            dirname( $basename ),
            basename( $basename, '.php' ),
            sanitize_title( '__PLUGIN_TITLE__' ),
        ];
        return in_array( $slug, $candidates, true );
    }

    private static function fallback_plugin_info(): \stdClass {
        $data = get_file_data( __PLUGIN_CONST___FILE, [
            'Name'        => 'Plugin Name',
            'Version'     => 'Version',
            'Description' => 'Description',
            'Author'      => 'Author',
            'AuthorURI'   => 'Author URI',
            'PluginURI'   => 'Plugin URI',
            'RequiresWP'  => 'Requires at least',
            'RequiresPHP' => 'Requires PHP',
        ] );

        $info               = new \stdClass();
        $info->name         = (string) $data['Name'];
        $info->slug         = __PLUGIN_CONST___SLUG;
        $info->version      = (string) $data['Version'];
        $info->author       = $data['AuthorURI'] !== ''
            ? sprintf( '<a href="%s">%s</a>', esc_url( $data['AuthorURI'] ), esc_html( $data['Author'] ) )
            : esc_html( (string) $data['Author'] );
        $info->homepage     = (string) $data['PluginURI'];
        $info->requires     = (string) $data['RequiresWP'];
        $info->requires_php = (string) $data['RequiresPHP'];
        $info->sections     = [
            'description' => '<p>' . esc_html( (string) $data['Description'] ) . '</p>',
        ];
        $info->icons        = self::icon_urls();
        $info->banners      = self::banner_urls();
        $info->external     = true;
        return $info;
    }

    /**
     * @return array<string, string>
     */
    private static function icon_urls(): array {
        $url = plugins_url( 'assets/img/icon.svg', __PLUGIN_CONST___FILE );
        return [
            'svg'     => $url,
            'default' => $url,
        ];
    }

    /**
     * @return array<string, string>
     */
    private static function banner_urls(): array {
        // WP renders the View details modal title bar with banners['low'] as
        // background-image (1544×500 high-DPI variant via banners['high']).
        // Same SVG works for both — it scales.
        $url = plugins_url( 'assets/img/banner.svg', __PLUGIN_CONST___FILE );
        return [
            'low'  => $url,
            'high' => $url,
        ];
    }
}
add_action( 'init', [ '__PLUGIN_PASCAL___Update_Checker', 'bootstrap' ], 30 );
