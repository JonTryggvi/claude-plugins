---
name: fix-wpgb-translatepress-ajax
description: Fix the recurring bug where WP Grid Builder (WPGB) facets and pagination return the default language on TranslatePress (TRP) sites — on a translated archive like `/en/courses/`, the facets revert to the default language after the initial AJAX sync and AJAX "load more" / page 2 comes back in the default language, even though a full reload of the same URL is correctly translated. Use when the user describes WPGB facets or grid cards showing the wrong language on a TranslatePress site, says "filters flip back to the default language after load", "WPGB load more / page 2 comes back untranslated", "AJAX returns the default language", "the English page works on reload but pagination breaks it", or any WP Grid Builder + TranslatePress / TRP interaction bug where AJAX responses are not getting translated. Do not use for translation-plugin bugs that are not WPGB-specific (e.g. WPML quirks, MultilingualPress, plain page templates not translating).
---

# Fix WP Grid Builder AJAX returning the default language on TranslatePress sites

One bug, two symptoms. WPGB's AJAX response body never passes through TranslatePress's dynamic-content translator. TRP's gettext/locale switching keys off the `/<lang>/` URL slug and works fine for framework strings, but dynamic strings — post titles, excerpts, taxonomy/facet labels — stay in the source/default language because TRP never sees the response.

`trp-form-language` is the **wrong** lever; that's language *detection*, which already works. The gap is *translating the response*.

## Root cause

The two symptoms (facets reverting, pagination cards untranslated) are the same problem in different transport channels:

- **Query-var AJAX transport** — requests go to `/<lang>/?wpgb-ajax=render|refresh`. TRP's output buffer only attaches after `template_redirect`; WPGB short-circuits *before* `template_redirect` to send its response. TRP's translator never runs. It's also not a REST request, so TRP's REST translator doesn't fire either.
- **REST transport** — requests go to `/<lang>/wp-json/wpgb/v2/filter/`. TRP's `handle_generic_rest_api_translations` (on `rest_pre_echo_response`) only translates *route-configured* keys, and the WPGB namespace isn't in TRP's default config.

Quick confirmation: POST to the REST endpoint under `/<lang>/` versus root. The validation error message comes back **translated** vs **default** — proving locale-switching works while content-translation doesn't.

## Workflow

### Step 1 — Detect the transport

Two ways:

**A. Inspect the localized settings.** View the page source on a WPGB grid and find `wpgb_settings`. Look at `endpoint`:

- `"endpoint": "rest_api"` → REST transport.
- Anything else / absent → query-var AJAX (default).

**B. Read the WPGB frontend JS.** It uses:

```js
this.isRestAPI = !ajaxUrl && "rest_api" === wpgb_settings.endpoint;
```

You can also confirm in DevTools Network tab: a request to `?wpgb-ajax=...` means query-var; a request to `wp-json/wpgb/v2/...` means REST.

### Step 2 — Ship both halves of the fix

You can't always tell which transport is active without inspection, and some sites switch on a per-grid basis. The fix below contains **both halves**. The query-var half runs only on the WPGB AJAX hooks; the REST half is a config filter that has no effect when WPGB isn't using REST. Both are safe to deploy together.

See `references/wpgb-trp-snippet.php` for the full file, ready to paste into WP Code Box as `codeType=php`. Inline summary:

```php
// Half 1 — query-var AJAX transport: translate WPGB's response HTML via TRP.
add_filter( 'wp_grid_builder/async/refresh_response', 'org_trp_translate_wpgb_response', 99 );
add_filter( 'wp_grid_builder/async/render_response',  'org_trp_translate_wpgb_response', 99 );
if ( ! function_exists( 'org_trp_translate_wpgb_response' ) ) {
    function org_trp_translate_wpgb_response( $response ) {
        if ( ! class_exists( 'TRP_Translate_Press' ) ) return $response;
        $trp    = TRP_Translate_Press::get_trp_instance();
        $url    = $trp->get_component( 'url_converter' );
        $render = $trp->get_component( 'translation_render' );
        if ( ! $render || ! $url ) return $response;

        $referer  = isset( $_SERVER['HTTP_REFERER'] ) ? $_SERVER['HTTP_REFERER'] : '';
        $lang     = $referer ? $url->get_lang_from_url_string( $referer ) : null;
        $settings = get_option( 'trp_settings' );
        $default  = isset( $settings['default-language'] ) ? $settings['default-language'] : '';
        if ( empty( $lang ) || $lang === $default ) return $response; // no-op on default lang

        global $TRP_LANGUAGE; $prev = $TRP_LANGUAGE; $TRP_LANGUAGE = $lang;

        if ( isset( $response['posts'] ) && is_string( $response['posts'] ) && '' !== $response['posts'] ) {
            $response['posts'] = $render->translate_page( $response['posts'] ); // grid cards
        }
        if ( ! empty( $response['facets'] ) && is_array( $response['facets'] ) ) {
            foreach ( $response['facets'] as $i => $f ) {
                if ( isset( $f['html'] ) && is_string( $f['html'] ) && '' !== $f['html'] ) {
                    $response['facets'][ $i ]['html'] = $render->translate_page( $f['html'] ); // facet labels
                }
            }
        }

        $TRP_LANGUAGE = $prev;
        return $response;
    }
}

// Half 2 — REST transport insurance (no-op on the query-var transport).
add_filter( 'trp_rest_api_translation_config', function ( $config ) {
    $config['wpgb/'] = array( 'posts', 'html', 'name', 'title', 'content', 'excerpt' );
    return $config;
} );
```

Why it works:

- The AJAX URL is `/<lang>/?wpgb-ajax=...`, not `wp-json/...`, so TRP's `translate_page()` does **not** trip its internal "we are inside REST" bail-out. It translates against the referer's language, which the snippet sets via `$TRP_LANGUAGE`.
- The REST half routes through TRP's own `rest_pre_echo_response` translator by adding the WPGB route prefix to TRP's config map.
- Both halves no-op cleanly on the default language (no work, no risk).

### Step 3 — Deploy the snippet

Deploy as a WP Code Box PHP snippet on the live site. Follow the [[wp-prod-ssh-ops]] WPCB installer procedure (inspect-first, base64 transport, clone an enabled PHP row as the template, `wp eval-file` the bundled installer).

> If you edit this snippet's row directly in the DB and then bulk-regenerate, run `wp cache flush` first — on hosts with a persistent object cache, a raw DB write leaves WPCB serving stale snippet code. See the object-cache gotcha in [[wp-prod-ssh-ops]].

If WPCB isn't available on the site, deploy as an mu-plugin:

```bash
ssh user@host 'mkdir -p <wproot>/wp-content/mu-plugins'
# scp or base64-transport references/wpgb-trp-snippet.php into:
#   <wproot>/wp-content/mu-plugins/org-wpgb-trp-fix.php
```

### Step 4 — Verify

This is a PHP fix on AJAX/POST responses. AJAX is not page-cached, so **no cache clear is required** — the fix is live the moment the snippet is enabled.

Verify via browser MCP on the live site:

1. Load `/<lang>/<archive>/` (e.g. `/en/courses/`). Confirm the page loads correctly translated.
2. Wait for the initial WPGB AJAX sync (watch the Network tab). Confirm facets stay translated.
3. Click a facet or pagination. Confirm the response cards and facets come back **translated**, not in the default language.
4. Repeat on the default-language archive (`/<archive>/`). Confirm nothing changed — the snippet's early-return makes it a no-op on the default language.
5. Tail the PHP error log for any warnings the snippet might be emitting.

Record findings in `production-notes/findings.md` per the [[wp-prod-ssh-ops]] workflow and commit.

## Compatibility notes

- WPGB response keys: v2 uses `posts` (cards) and `facets[i].html` (facet labels). Older WPGB versions sometimes used `results` / `html`. If the snippet appears to do nothing, dump one AJAX response body and verify the key names. If they differ, add the older keys to the snippet (handle both).
- The snippet is hooked at priority `99` to run after any other plugin filters on the same hooks.
- The `class_exists( 'TRP_Translate_Press' )` guard makes the snippet inert if TRP is deactivated.

## Test trigger prompts

- "On our /en/ courses page the WP Grid Builder filters flip back to the default language after it loads and page 2 comes back untranslated — we use TranslatePress."
- "WPGB load-more returns the default language on the English site. The page loads fine, it's just the AJAX."
- "Why are my WP Grid Builder facets not translating on TranslatePress? They show up in Icelandic the first paint and then snap back to English after the AJAX sync."

## Related

- [[wp-prod-ssh-ops]] — the deployment surface for this snippet on Avista client sites. The WPCB installer template lives there.
