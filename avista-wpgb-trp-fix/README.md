# avista-wpgb-trp-fix

Fix for the recurring bug where, on a translated WP Grid Builder listing (e.g. `/en/courses/`), the facets revert to the default language after the initial AJAX sync and AJAX pagination returns default-language cards — even though a full reload of the same URL is correctly translated.

Recurs across multiple Avista client sites running **WP Grid Builder + TranslatePress**.

## Skills

| Skill | Purpose |
|---|---|
| [`fix-wpgb-translatepress-ajax/`](skills/fix-wpgb-translatepress-ajax/) | Detect the WPGB AJAX transport (query-var vs REST), deploy the matching filter pair, verify via browser MCP. Includes a ready-to-paste PHP snippet. |

## When this plugin gets used

Trigger phrases the skill watches for:

- "filters flip back to the default language after load"
- "load more / page 2 comes back untranslated"
- "WPGB AJAX returns the default language"
- "WP Grid Builder + TranslatePress" interaction bugs

## Distribution

Released through the Avista org marketplace via [`avista-memory-tools:release-skill-bundle`](../avista-memory-tools/skills/release-skill-bundle/).
