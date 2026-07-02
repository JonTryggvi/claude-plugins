# avista-wp-performance

A modular, **diagnose-first, approval-gated** toolkit for the recurring performance problem on Avista's WordPress + Breakdance stack — pages that "*sometimes*" take 30–60s and tiny media uploads that take ~30s.

The stack (WPMU DEV managed hosting with a fixed PHP-worker count, Breakdance classic theme, TranslatePress, Smush Pro, Hummingbird) fails one way: **PHP-worker saturation**. Heavy Breakdance server-side renders on cache-MISS pages, a short cache TTL that keeps articles perpetually cold, aggressive crawlers hitting uncached pages, and Smush optimizing uploads synchronously against a remote API all compete for a limited worker pool. The client experiences the contention as intermittent 30–60s pages.

The design principle throughout: **investigate read-only first, back up before any change, deploy only on explicit approval, verify before/after, and keep a one-line rollback.** Run only the piece a given site needs.

## Skills

| Skill | Purpose |
|---|---|
| [`wp-perf-audit/`](skills/wp-perf-audit/) | **Read-only** diagnostic funnel over SSH — TTFB HIT vs cache-busted MISS, rule out object-cache/DB/autoload, cache-warmth/TTL test, access-log analysis (bot %, HIT rate, 499s, worst IPs by total request-time), `php_slow.log`. Produces a findings report + a ranked plan that routes to the fix skills. **Start here.** Deep methodology in [`references/methodology.md`](skills/wp-perf-audit/references/methodology.md). |
| [`wp-bot-mitigation/`](skills/wp-bot-mitigation/) | Deploy a bot-firewall mu-plugin + `robots.txt` that 403s zero-value crawlers *before* the Breakdance render, keeping Google/Bing/loopback/cron/admin/REST/share-previews untouched. Per-site block-list review, before/after verification, one-line rollback. |
| [`wp-breakdance-render-profile/`](skills/wp-breakdance-render-profile/) | Flip Breakdance's render-performance-debug flag on for a couple of cache-busted requests, read Server-Timing, rank the heaviest templates/blocks/nodes, flip it back off, and hand the builder team an exact to-do list. Self-reverting. |
| [`wp-render-optimize/`](skills/wp-render-optimize/) | Deploy a **guarded** mu-plugin that removes WP block-theme global-styles/font-face overhead — **classic (non-block) themes only** (self-guards on `wp_is_block_theme()`). Verifies output is byte-identical minus the dead CSS. |
| [`wp-media-upload-fix/`](skills/wp-media-upload-fix/) | Diagnose + fix ~30s uploads: turn off Smush optimize-on-upload (after backup), **require** a bulk-smush follow-up, and surface image-size sprawl. Timed before/after verification. |
| [`avista-wp-performance-overview/`](skills/avista-wp-performance-overview/) | Prints a summary of this plugin — the skills, the order to run them in, and the guardrails. Run `/avista-wp-performance-overview` or ask "what does this plugin do?". |

## The order that works

1. **`wp-perf-audit`** — measure, don't guess; it produces the plan.
2. Attack **MISS frequency / wasted load** first (biggest, cheapest wins): hand the cache **TTL + preloader** off to the WPMU DEV Hub, and deploy **`wp-bot-mitigation`** over SSH.
3. Attack **MISS cost**: **`wp-render-optimize`** (small, safe) + the Breakdance builder work **`wp-breakdance-render-profile`** hands off.
4. Fix **uploads** in parallel with **`wp-media-upload-fix`**.

## What is / isn't SSH-fixable

Half the highest-leverage fixes on this stack are **not** SSH-fixable — the skills diagnose them precisely and hand off:

- **SSH:** bot firewall, Smush on-upload fix, block-theme overhead removal, Breakdance render *profiling*.
- **Not SSH:** cache TTL + preloader (WPMU DEV Hub), Breakdance *template* internals (builder UI), PHP-worker count (WPMU DEV plan).

## Bundled resources

- `wp-perf-audit/scripts/loganalyze.sh`, `loganalyze2.sh` — nginx access-log + `php_slow.log` analysis.
- `wp-bot-mitigation/templates/avista-bot-firewall.php`, `robots.txt`; `scripts/since_deploy.sh` — the deployables + a before/after firewall-impact measurement.
- `wp-breakdance-render-profile/scripts/bd_debug.php` — safe toggle for Breakdance render-performance-debug.
- `wp-render-optimize/templates/avista-render-opt.php` — the guarded block-theme-overhead mu-plugin.

## Pairs with

[`avista-wp-prod-ops`](../avista-wp-prod-ops/) — the SSH-to-production connection discipline and inspect-first / backup-before-change posture these skills build on.

## When this plugin gets used

Trigger phrases the skills watch for: "the site is sometimes really slow" · "pages take 30 seconds" · "WordPress is slow on WPMU DEV" · "why is Breakdance so slow" · "uploads take forever" · "bots are hammering us" · "diagnose / audit site performance".

## Distribution

Released through the Avista org marketplace via [`avista-memory-tools:release-skill-bundle`](../avista-memory-tools/skills/release-skill-bundle/). GitHub-sync path — no tags, no PUC, plain `git push` plus an "Update" click in the admin UI.
