<?php
/**
 * WP Grid Builder + TranslatePress AJAX language fix.
 *
 * Fixes the bug where, on a translated WPGB listing (e.g. /en/courses/),
 * facets revert to the default language after the initial AJAX sync and
 * AJAX pagination returns default-language cards.
 *
 * Deploy as a WP Code Box PHP snippet (codeType = php) via the bundled
 * installer in the wp-prod-ssh-ops skill, OR drop in mu-plugins/.
 *
 * Safe to deploy on any site running WPGB + TRP — early-returns on the
 * default language and when TRP is not active.
 */

// =========================================================================
// Half 1 — query-var AJAX transport (default WPGB AJAX).
// =========================================================================
// WPGB short-circuits before template_redirect, so TRP's output buffer
// never starts. Translate the response ourselves via TRP's translation_render
// component, using the referer URL to determine the requested language.

add_filter( 'wp_grid_builder/async/refresh_response', 'org_trp_translate_wpgb_response', 99 );
add_filter( 'wp_grid_builder/async/render_response',  'org_trp_translate_wpgb_response', 99 );

if ( ! function_exists( 'org_trp_translate_wpgb_response' ) ) {
	/**
	 * Translate the WPGB AJAX response body to the language of the referer URL.
	 *
	 * @param array $response WPGB response array (keys vary by version; v2 uses
	 *                        `posts` for grid HTML and `facets[i]['html']` for facets).
	 * @return array
	 */
	function org_trp_translate_wpgb_response( $response ) {
		if ( ! class_exists( 'TRP_Translate_Press' ) ) {
			return $response;
		}

		$trp    = TRP_Translate_Press::get_trp_instance();
		$url    = $trp->get_component( 'url_converter' );
		$render = $trp->get_component( 'translation_render' );
		if ( ! $render || ! $url ) {
			return $response;
		}

		$referer  = isset( $_SERVER['HTTP_REFERER'] ) ? $_SERVER['HTTP_REFERER'] : '';
		$lang     = $referer ? $url->get_lang_from_url_string( $referer ) : null;
		$settings = get_option( 'trp_settings' );
		$default  = isset( $settings['default-language'] ) ? $settings['default-language'] : '';

		// No-op on the default language — page is already in source strings.
		if ( empty( $lang ) || $lang === $default ) {
			return $response;
		}

		global $TRP_LANGUAGE;
		$prev          = $TRP_LANGUAGE;
		$TRP_LANGUAGE  = $lang;

		// Grid cards / "posts" body.
		if ( isset( $response['posts'] ) && is_string( $response['posts'] ) && '' !== $response['posts'] ) {
			$response['posts'] = $render->translate_page( $response['posts'] );
		}

		// Facet labels.
		if ( ! empty( $response['facets'] ) && is_array( $response['facets'] ) ) {
			foreach ( $response['facets'] as $i => $f ) {
				if ( isset( $f['html'] ) && is_string( $f['html'] ) && '' !== $f['html'] ) {
					$response['facets'][ $i ]['html'] = $render->translate_page( $f['html'] );
				}
			}
		}

		// Older WPGB schemas occasionally used these keys. Uncomment if needed.
		// if ( isset( $response['results'] ) && is_string( $response['results'] ) && '' !== $response['results'] ) {
		// 	$response['results'] = $render->translate_page( $response['results'] );
		// }
		// if ( isset( $response['html'] ) && is_string( $response['html'] ) && '' !== $response['html'] ) {
		// 	$response['html'] = $render->translate_page( $response['html'] );
		// }

		$TRP_LANGUAGE = $prev;
		return $response;
	}
}

// =========================================================================
// Half 2 — REST transport insurance.
// =========================================================================
// Harmless when WPGB is using the query-var transport. When WPGB is using
// the REST transport (wpgb_settings.endpoint === "rest_api"), this adds
// the WPGB namespace to TRP's route map so its rest_pre_echo_response
// translator visits the right keys.

add_filter(
	'trp_rest_api_translation_config',
	function ( $config ) {
		$config['wpgb/'] = array( 'posts', 'html', 'name', 'title', 'content', 'excerpt' );
		return $config;
	}
);
