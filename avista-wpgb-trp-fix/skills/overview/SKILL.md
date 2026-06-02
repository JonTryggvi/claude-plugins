---
name: overview
description: Overview of the avista-wpgb-trp-fix plugin — the bug it fixes, what its one skill does, and how the fix works. Use when the user asks "what does avista-wpgb-trp-fix do", "what's in this plugin", "how do I get started", or right after installing the plugin.
---

# avista-wpgb-trp-fix — overview

A targeted fix for one recurring bug across Avista client sites running **WP Grid Builder + TranslatePress**:
on a translated listing (e.g. `/en/courses/`), the facets revert to the default language after the
initial AJAX sync and AJAX pagination ("load more" / page 2) returns default-language cards — even
though a full reload of the same URL is correctly translated.

Root cause: WPGB's AJAX response never passes through TRP's dynamic-content translator.

Present this overview to the user, then hand off to the skill when they're ready to apply the fix.

## What's in the box

| Skill | What it does | When to use it |
|---|---|---|
| `fix-wpgb-translatepress-ajax` | Detects the WPGB AJAX transport (query-var vs REST), deploys the matching transport-aware filter pair (query-var AJAX + REST insurance), and verifies via browser MCP. Includes a ready-to-paste PHP snippet. | When WPGB facets/pagination come back in the wrong language on a TranslatePress site. |

## Trigger phrases

"filters flip back to the default language after load" · "load more / page 2 comes back untranslated" ·
"WPGB AJAX returns the default language" · any "WP Grid Builder + TranslatePress" interaction bug.

## More detail

See the plugin [README](../../README.md).
