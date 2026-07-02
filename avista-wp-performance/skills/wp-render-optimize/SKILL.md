---
name: wp-render-optimize
description: Deploy the guarded block-theme-overhead removal mu-plugin (avista-render-opt.php) to an Avista WordPress site running a CLASSIC (non-block) theme such as breakdance-zero — WordPress still runs its full FSE global-styles + font-face machinery on classic themes, which is pure dead weight there (~30+ ms plus a WP_Query on the empty wp_global_styles CPT on every front-end render). Use when the user says "remove block-theme overhead", "strip the global-styles", "wp_print_font_faces is slow", "safe render micro-optimization", "trim WP core render", or after wp-perf-audit / php_slow.log shows wp_get_global_settings / wp_print_font_faces / global-styles-inline-css in the render path on a classic-theme site. HARD GUARDED on wp_is_block_theme() === false: the mu-plugin self-guards at runtime AND you must confirm the theme is classic before deploying, because on a real block (FSE) theme these exact callbacks generate the site's actual CSS and removing them strips its styling. Approval-gated — records a one-line rollback and verifies the rendered HTML is byte-identical minus the dead inline CSS, pages still return 200, and no PHP errors. Do not use on a block/FSE theme, and don't oversell it — it is a small, safe micro-opt that compounds with caching and the Breakdance template cuts, not a fix for a 30s page on its own.
---

# WP render optimization — remove block-theme overhead (classic themes only)

WordPress ships Full-Site-Editing (block theme) machinery that runs even when the active theme is a **classic** theme like `breakdance-zero`. On such a site it's dead weight: `wp_print_font_faces()` and `wp_enqueue_global_styles()` generate block-theme CSS/font-faces nothing uses, and `wp_get_global_settings()` fires a `WP_Query` + `get_terms()` against the (empty) `wp_global_styles` CPT on **every** front-end render. On the audited site that was ~30+ ms and a pointless query per render — small, but it's on the unavoidable first render and every preloader hit, so it compounds with the caching work.

The `templates/avista-render-opt.php` mu-plugin removes exactly that machinery, front-end only, admin/editor untouched.

## The one guardrail that matters: classic theme only

These removals are **only** correct when `wp_is_block_theme() === false`. On a real block/FSE theme the *same* callbacks generate the site's actual styling — removing them would strip the CSS and visually break the site. This is the non-negotiable gate. Two layers enforce it:

1. **The mu-plugin self-guards** — it `return`s early if `wp_is_block_theme()` is true, so it no-ops on a block theme even if deployed to the wrong site.
2. **You confirm at deploy time** anyway (belt and suspenders — step 1 below). Don't rely solely on the runtime guard; know the theme before you push.

If the theme is a block theme, **stop** — this skill does not apply, and there is nothing safe to remove here.

This changes production: follow the [`avista-wp-prod-ops`](../../../avista-wp-prod-ops/) posture (inspect, deploy only on explicit approval, verify, keep a rollback).

## Step 1 — Confirm it's safe AND worth it

```bash
# GO/NO-GO: must be false (classic theme). If true → STOP, this skill does not apply.
$SSH "cd ~/site/public_html && wp eval 'var_export(wp_is_block_theme()); echo \"\n\";'"
# Confirm the wp_global_styles CPT is actually empty (so the WP_Query is pure waste):
$SSH "cd ~/site/public_html && wp post list --post_type=wp_global_styles --format=count"
# See the dead weight in the current output (a cache-busted MISS render):
curl -s "$ART?cb=$RANDOM" > /tmp/before.html
grep -cE 'global-styles-inline-css|wp-fonts-local|classic-theme-styles' /tmp/before.html
```

Proceed only if `wp_is_block_theme()` is `false`, the CPT count is `0`, and the block-theme styles actually appear in the output (if they don't, there's nothing to remove — say so).

## Step 2 — Deploy (only after approval)

There's nothing to back up (this is a new mu-plugin, not an overwrite — confirm no `avista-render-opt.php` already exists), but keep the source of truth in `production-notes/render-opt/`.

```bash
$SSH "mkdir -p ~/site/public_html/wp-content/mu-plugins"
scp skills/wp-render-optimize/templates/avista-render-opt.php <user>@<host>:~/site/public_html/wp-content/mu-plugins/avista-render-opt.php
```

## Step 3 — Verify output is identical minus the dead CSS

The whole risk is "did I remove something the site actually renders?" So diff before/after and confirm *only* the block-theme inline CSS disappeared:

```bash
curl -s "$ART?cb=$RANDOM" > /tmp/after.html
# The global-styles inline block should now be gone:
grep -cE 'global-styles-inline-css|wp-fonts-local' /tmp/after.html   # expect 0
# Everything else identical — the diff should be ONLY the removed <style>/font-face block:
diff <(grep -v 'global-styles-inline-css' /tmp/before.html) /tmp/after.html | head -40
# Key pages still 200, no PHP errors:
for u in "$SITE/" "$ART"; do curl -s -o /dev/null -w "%{http_code} $u\n" "$u?cb=$RANDOM"; done
$SSH "tail -20 ~/site/public_html/wp-content/debug.log 2>/dev/null || tail -20 ~/site/logs/php_error.log 2>/dev/null || echo 'no error log / none new'"
```

Expected (matches the audited deploy): the `global-styles-inline-css` block gone, output otherwise identical (a small byte reduction), home + article still HTTP 200, no new PHP errors. If the diff shows anything *other* than the removed global-styles/font-face block, roll back and investigate — the site may use one of those handles.

## Step 4 — Record the rollback

Mirror `production-notes/render-opt/DEPLOYED.md` (what/why, before→after render numbers, rollback). Rollback is one line, instant (mu-plugins load per request, no cache to clear):

```bash
$SSH "rm -f ~/site/public_html/wp-content/mu-plugins/avista-render-opt.php"
```

## Guardrails

- **Classic theme only — this is the whole ballgame.** `wp_is_block_theme()` must be `false`. The runtime guard protects against misdeployment, but confirm it yourself too.
- **Approval-gated**, and verify by *diffing the actual HTML* — the failure mode (stripping a used style) is only visible by comparing output, not by "it returned 200."
- **Don't oversell it.** This is tens of milliseconds. It's a legitimate, safe cut that helps the first-render/preloader path, but the 30–60s problem lives in cache frequency, bots, and Breakdance template cost — this skill is a supporting player, run alongside `wp-bot-mitigation`, the TTL/preload hand-off, and `wp-breakdance-render-profile`, not instead of them.
- Front-end only by design — the mu-plugin leaves admin/editor untouched so the block editor (if ever used) still works.
