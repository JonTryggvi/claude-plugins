---
name: avista-wp-performance-overview
description: Overview of the avista-wp-performance plugin — what it bundles, what each skill does, the diagnose-first order to run them in, and the safety guardrails. Use when the user asks "what does avista-wp-performance do", "what's in this plugin", "how do I get started with the WP performance toolkit", "which perf skill do I run first", "the site is slow, where do I start", or right after installing the plugin.
---

# avista-wp-performance — overview

A **modular, diagnose-first, approval-gated** toolkit for the recurring performance problem on Avista's WordPress + Breakdance stack: pages that "*sometimes*" take 30–60s and tiny media uploads that take ~30s. The stack (WPMU DEV managed hosting with a fixed PHP-worker count, Breakdance classic theme, TranslatePress, Smush Pro, Hummingbird) fails one way — **PHP-worker saturation**: heavy Breakdance renders on cache-MISS pages, a short cache TTL that keeps articles cold, aggressive crawlers hitting uncached pages, and Smush optimizing uploads synchronously against a remote API, all competing for a limited worker pool.

Run **only the piece a given site needs**. Always start with the read-only audit; it tells you which of the other skills to run.

## What's in the box

| Skill | What it does | When to use it |
|---|---|---|
| [`wp-perf-audit`](../wp-perf-audit/) | **Read-only** diagnostic funnel over SSH: TTFB on a cache HIT vs a cache-busted MISS, rules out object-cache/DB/autoload, tests cache warmth/TTL, analyzes the access log (bot %, HIT rate, 499s, worst IPs by request-time), reads `php_slow.log`. Produces a findings report + a ranked plan that routes to the fix skills. | **Start here, always.** Any "the site is slow" / "diagnose performance" request. Changes nothing. |
| [`wp-bot-mitigation`](../wp-bot-mitigation/) | Deploys a bot-firewall mu-plugin + `robots.txt` that 403s zero-value crawlers *before* the render, keeping Google/Bing/loopback/cron/admin/REST/share-previews untouched. | When the audit shows crawlers dominating request-time / a cold cache driven by bot crawl. |
| [`wp-breakdance-render-profile`](../wp-breakdance-render-profile/) | Flips Breakdance's render-performance-debug flag on for a couple of cache-busted requests, reads Server-Timing, names the heaviest templates/blocks/nodes, flips it back off, writes a builder to-do list. | When the audit fingers Breakdance SSR as the MISS cost and you need the exact hot spots. |
| [`wp-render-optimize`](../wp-render-optimize/) | Deploys a **guarded** mu-plugin that removes WP block-theme global-styles/font-face overhead — **classic (non-block) themes only**. | When `php_slow.log` shows `wp_get_global_settings`/`wp_print_font_faces` on a classic-theme site. |
| [`wp-media-upload-fix`](../wp-media-upload-fix/) | Diagnoses + fixes ~30s uploads: turns off Smush optimize-on-upload (after backup), **requires** a bulk-smush follow-up, surfaces image-size sprawl. | When uploads are slow / `async-upload.php` shows in `php_slow.log`. |

## The order that works

1. **`wp-perf-audit`** — measure, don't guess. It produces the plan.
2. Attack **MISS frequency** and **wasted load** first — the biggest, cheapest wins: hand off the cache **TTL + preloader** to the WPMU DEV Hub, and deploy **`wp-bot-mitigation`** over SSH.
3. Attack **MISS cost** — **`wp-render-optimize`** (small, safe) + the Breakdance builder work that **`wp-breakdance-render-profile`** hands to the builder team.
4. Fix **uploads** in parallel — **`wp-media-upload-fix`** (an independent worker-contention source).

## Guardrails (baked into every skill)

- **Read-only investigation first.** `wp-perf-audit` changes nothing; the fix skills act only after it.
- **Back up before any change; deploy only on explicit approval; verify before/after; ship a one-line rollback.**
- **Per-site judgment, not hardcoded fixes.** The bot block list is reviewed per site (never blindly block a crawler the site relies on). `wp-render-optimize` refuses to run on a block theme. Turning Smush `auto` off **requires** a bulk-smush follow-up. Breakdance template fixes are **always** builder-side (DB-stored — never edited over SSH).
- **Know what isn't SSH-fixable.** Cache TTL (WPMU DEV Hub) and Breakdance template internals (builder UI) are *diagnosed precisely and handed off* — the skills don't pretend to fix them over SSH.

## Pairs with

[`avista-wp-prod-ops`](../../../avista-wp-prod-ops/) — the SSH connection discipline and inspect-first / backup-before-change posture these skills build on. Read its `wp-prod-ssh-ops` skill for the SSH-to-production workflow.

## Trigger phrases

"the site is sometimes really slow" · "pages take 30 seconds" · "WordPress is slow on WPMU DEV" · "why is Breakdance so slow" · "uploads take forever" · "bots are hammering us" · "diagnose performance / audit site performance".

## More detail

See the plugin [README](../../README.md).
