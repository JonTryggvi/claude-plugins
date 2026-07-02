# WP + Breakdance performance methodology (deep reference)

The detailed version of the `wp-perf-audit` funnel: exact commands, interpretation tables,
expected-value baselines, the root-cause chain, and what is / isn't fixable over SSH. Read the
stage you need — you do not need to read this end-to-end. All values below are *reference points*
from a real audit of this stack, not thresholds to hardcode: measure the site in front of you and
interpret in context.

## Contents
1. [Why this stack goes slow (the model)](#1-why-this-stack-goes-slow-the-model)
2. [Stage 1 — TTFB: HIT vs MISS vs concurrency](#2-stage-1--ttfb-hit-vs-miss-vs-concurrency)
3. [Stage 2 — ruling out infra](#3-stage-2--ruling-out-infra)
4. [Stage 3 — cache warmth / TTL](#4-stage-3--cache-warmth--ttl)
5. [Stage 4 — access-log analysis](#5-stage-4--access-log-analysis)
6. [Stage 5 — php_slow.log](#6-stage-5--php_slowlog)
7. [Stage 7 — Smush + image sizes](#7-stage-7--smush--image-sizes)
8. [The root-cause chain](#8-the-root-cause-chain)
9. [What is / isn't SSH-fixable](#9-what-is--isnt-ssh-fixable)
10. [Common myths this funnel debunks](#10-common-myths-this-funnel-debunks)

---

## 1. Why this stack goes slow (the model)

Hold this mental model; every stage is testing one link in it.

> Managed hosting gives a **fixed number of PHP workers**. A cache **HIT** is served by nginx
> without touching PHP (~150ms). A cache **MISS** runs the full dynamic stack — Breakdance SSR +
> TranslatePress output processing + ACF + 30 plugins — and is expensive (~4s idle). Under any
> concurrency those heavy renders queue for the limited workers, so MISS TTFB balloons (4s → 12s
> at 4 concurrent → 56s under real contention). Anything that (a) increases MISS *frequency*
> (short TTL, no preloader, aggressive crawling of cold pages) or (b) increases MISS *cost* (heavy
> templates) or (c) *holds a worker for a long time* (synchronous Smush uploads, 499-timing-out
> preloader requests) pushes the site toward the cliff. The client experiences the cliff as
> "*sometimes* 30–60s."

So the funnel measures: how cheap is a HIT, how expensive is a MISS, how often is a page a MISS,
who is causing MISSes, and what is holding workers.

## 2. Stage 1 — TTFB: HIT vs MISS vs concurrency

```bash
# Full timing breakdown for one URL:
curl -s -o /dev/null -w 'dns=%{time_namelookup}s connect=%{time_connect}s ttfb=%{time_starttransfer}s total=%{time_total}s code=%{http_code}\n' "$URL"

# Read the cache header (this stack: nginx layer, header is x-cache):
curl -s -o /dev/null -D - "$URL" | grep -iE 'x-cache|cf-cache-status|age:'

# HIT baseline — warm first, then measure:
curl -s -o /dev/null "$ART"; curl -s -o /dev/null -w 'HIT ttfb=%{time_starttransfer}s\n' "$ART"

# MISS — unique query string dodges the cache key:
curl -s -o /dev/null -w 'MISS ttfb=%{time_starttransfer}s\n' "$ART?cb=$RANDOM"

# Concurrency — the contention test. 4 simultaneous MISS renders:
for i in 1 2 3 4; do curl -s -o /dev/null -w "c$i ttfb=%{time_starttransfer}s\n" "$ART?cb=$i" & done; wait
```

Reference values from the audited site:

| Condition | TTFB |
|---|---|
| Warm page (HIT) | ~0.15s |
| Core endpoints (wp-login / wp-json / robots) | ~1s |
| Article MISS, server idle | ~4–6s |
| Homepage, 4 concurrent MISS-class renders | ~11–12s each |
| Server under real contention (observed) | up to 56s |

Reading it: a fast HIT + an expensive-and-concurrency-sensitive MISS is the classic PHP-worker
contention signature. If the **HIT itself** is slow, the problem is upstream of PHP (hosting
network, TLS, an edge CDN misconfig) — do not go hunting in the render path. If MISS is only ~1s
and flat under concurrency, render cost is not your problem — look at frequency (stage 3) and
external load (stage 4).

## 3. Stage 2 — ruling out infra

The point is to *exclude* the data layer so the remaining budget is provably render/contention.
On the audited site object cache (Memcached), DB, and autoload were all healthy — not the
bottleneck. Expected-healthy ranges:

- **Object cache**: 1,000 set+get in low-single-digit to low-tens of ms. If this is hundreds of
  ms, the object cache backend (Memcached/Redis) is degraded or falling back to the DB.
- **DB round-trip**: a `SELECT 1` in ~1–5ms. Tens of ms means DB latency / a busy or remote DB.
- **Autoload**: total autoloaded options well under ~1MB. Bloated autoload (several MB) adds
  fixed cost to *every* request including would-be-cheap ones.

Deeper autoload probe when the total looks high:

```bash
$SSH "cd ~/site/public_html && wp eval '
  \$o=wp_load_alloptions(); arsort(\$o);
  \$i=0; foreach(\$o as \$k=>\$v){ printf(\"%8d  %s\n\", strlen(\$v), \$k); if(++\$i>=15) break; }
'"
```

If infra is healthy, write it down as *ruled out* and move on — it stops people re-litigating
"maybe it's the database."

## 4. Stage 3 — cache warmth / TTL

The subtle, high-leverage finding. A HIT is cheap, but if pages don't *stay* HIT, every real
visit pays a MISS. On the audited site, 8/8 random articles were cold on first hit, and 3 articles
that had been warmed ~45 min earlier were all back to MISS — the homepage stayed HIT only because
constant traffic re-warms it.

```bash
# Warm a spread of low-traffic URLs, stamp the time:
date; for u in $URLS; do curl -s -o /dev/null "$u"; done
# ... after 15–45 min, re-check the SAME urls (do not add cache-busters this time):
date; for u in $URLS; do printf '%s ' "$u"; curl -s -o /dev/null -D - "$u" | grep -i x-cache; done
```

If they revert to MISS, the static-cache TTL is short and nothing re-warms low-traffic URLs.
Contributing factors to check: is a preloader configured and *succeeding* (stage 4's 499 count
tells you if its own requests time out), and does the sitemap it would crawl actually exist
(`curl -sI "$SITE/sitemap_index.xml"` — a 404 means the preloader has nothing to crawl).

This is normally **not SSH-fixable**: raise the static-cache TTL in the WPMU DEV Hub and enable a
preloader there. The only SSH supplement worth offering is a **bounded** cache-warmer cron that
re-hits the homepage + main landing pages + recent posts every ~15–20 min — *bounded* is the
operative word; do not crawl thousands of articles or you recreate the load you're fighting.

## 5. Stage 4 — access-log analysis

`scripts/loganalyze.sh` and `scripts/loganalyze2.sh` do the heavy lifting (they `cd ~/site/logs`).
What each surfaces and how to read it:

**loganalyze.sh** — window; total requests; avg & max request-time; slow buckets (>2/5/10/20s);
bot-UA %; deep/looping-path count; suspicious endpoint counts; status-code and cache-status
distributions; the single slowest request; **top 20 IPs by request count**; **top 20 IPs by TOTAL
request-time** (the CPU-cost ranking — the one that matters); top user-agents; deepest/looping paths.

**loganalyze2.sh** — hourly request volume + slow(>10s) count; **profiles of the most expensive
IPs** (UA, status mix, sample paths — ⚠️ the four IPs are hardcoded examples; replace them with the
top offenders `loganalyze.sh` reports for this site); 499s grouped by UA; **php_slow.log** summary
(event count, window, top-of-stack functions); WAF log tail.

Signals and what they mean:

- **Cache HIT rate** — the audited site sat at ~8% (HIT 1,814 / MISS 11,738 / BYPASS 2,608 / "-"
  6,303). Single digits means the cache is barely helping and nearly all traffic pays render cost.
- **Bot %** — ~36% on the audited site (meta-externalagent, DataForSeoBot, Amazonbot,
  Java-http-client, bingbot, Googlebot, ClaudeBot, plus no-UA). Bots crawling *cold* URLs are the
  load; this is what `wp-bot-mitigation` recovers.
- **Worst IPs by total request-time**, not count. One broken crawler requesting malformed
  `/https%3A/...` URLs burned 16,260s over 359 requests (~45s each). Real users are victims too
  (an Icelandic IP: 3,251s over 153 real-article requests, ~21s each) — they're queued behind the
  bot renders, which is *why* it's worth blocking the bots.
- **499s (client gave up waiting)** — the tell. On the audited site, 647 of 833 499s were the
  site's **own loopback UA `WordPress/x.x`**: the cache preloader + WP-Cron requests were themselves
  timing out. That closes the vicious cycle — slow render → preloader 499s → cache never warms →
  more MISSes → slower. If you see the loopback in the 499 list, the preloader is a victim, not a fix.
- **301/404 surface** — 5,197 × 301 + 1,685 × 404 on the audited site. Malformed crawl targets
  (absolute URLs crawled as paths; WebP `srcset` strings requested as URLs) give bots an effectively
  infinite set of expensive uncacheable URLs. Killing that surface (fix the srcset bug, tame legacy
  redirect chains) is part of the durable fix but usually a builder/theme change, not SSH.

Caveat on self-inflicted spikes: your own concurrency and cache-bust probes show up in the log as
a slow spike at the hour you ran them. Discount that; trust organic slow spikes at off-hours.

## 6. Stage 5 — php_slow.log

`loganalyze2.sh` prints the most common top-of-stack functions. On this stack they are all
Breakdance SSR: `_render`, `getRenderedNodes`, `getRenderedPost`, `renderGlobalBlock`,
`renderBlockPost`, `loopBlockPosts`, `renderDynamicDataInProps`, `ssr`. Two representative slow
backtraces from the audited site:

- **Breakdance recursive render**: `renderPopup()` → `getRenderedPost()` → 5× nested `_render()`
  → a **WP Menu** element whose SSR calls `get_post_status()`/`get_post()` *per menu item*. Deep
  node recursion plus a popup rendered inline.
- **WP core global-styles/fonts**: `wp_print_font_faces()` → `wp_get_global_settings()` runs a
  `WP_Query` + `get_terms()` on **every** render — dead weight on a classic (non-block) theme.
  This one is exactly what `wp-render-optimize` removes.

Also count front-end `index.php` slow events vs `async-upload.php`: the latter appearing at all
confirms slow uploads (→ `wp-media-upload-fix`). Raw peek if you want backtraces yourself:

```bash
$SSH "grep -c script_filename ~/site/logs/php_slow.log; \
      grep -oE '[a-zA-Z_]+\(\) ' ~/site/logs/php_slow.log | sort | uniq -c | sort -rn | head -12"
```

## 7. Stage 7 — Smush + image sizes

```bash
$SSH "cd ~/site/public_html && wp option get wp-smush-settings --format=json"
$SSH "cd ~/site/public_html && wp eval '\$s=wp_get_registered_image_subsizes(); \
  echo count(\$s).\" subsizes: \".implode(\", \", array_keys(\$s)).\"\n\";'"
```

The costly combination: `auto:true` (optimize on upload) + `lossy:"1"` (Super-Smush → remote WPMU
DEV API) + `original:true` + `webp_mod:true` / `webp_direct_conversion:true`, across ~10 registered
sizes. Each upload becomes a sequential blocking HTTPS round-trip per size + original + WebP, inline
in the upload request — tens of seconds for a small file, and a PHP worker pinned the whole time
(so an editor uploading starves the front end). Just record it here; `wp-media-upload-fix` owns the
change and the mandatory bulk-smush follow-up.

## 8. The root-cause chain

The corrected, evidence-backed chain for the audited site (state it plainly in the report so the
plan's ordering makes sense):

> Aggressive bot crawling of uncached / deep / redirect / cross-language URLs → each is a heavy
> Breakdance SSR render (4–45s) → the limited PHP workers saturate → the cache preloader's own
> requests time out (499) so the cache never warms (~8% HIT) → real users and editors queue behind
> bot renders → "*sometimes* ~30s". Smush piles on: each upload holds a worker ~30s via the remote
> lossy API.

Every arrow is a lever: block zero-value bots (cut MISS-causing load), raise TTL + preload (cut
MISS frequency), cut render cost (cheaper MISS), fix Smush (free the worker uploads pin), raise
worker count (more headroom). The audit's job is to prove which arrows are live on *this* site and
rank the levers by measured impact.

## 9. What is / isn't SSH-fixable

Be explicit in the report — it prevents the client expecting an SSH fix for a Hub/builder problem.

| Fix | SSH? | Owner |
|---|---|---|
| Bot firewall (mu-plugin) + robots.txt | ✅ | `wp-bot-mitigation` |
| Smush on-upload optimization off + bulk follow-up | ✅ | `wp-media-upload-fix` |
| Block-theme overhead removal (classic themes only) | ✅ | `wp-render-optimize` |
| Breakdance render *profiling* (Server-Timing) | ✅ | `wp-breakdance-render-profile` |
| Breakdance *template* optimization (node depth, loop counts, per-item queries) | ❌ | builder team, Breakdance UI |
| Static-cache TTL + preloader | ⚠️ mostly no | WPMU DEV Hub (SSH supplement: bounded warmer cron) |
| PHP-worker count | ❌ | WPMU DEV plan/support |
| Legacy-redirect / malformed-URL surface (301/404) | ⚠️ | theme/redirect config; srcset bug is a build fix |

## 10. Common myths this funnel debunks

- **"Page cache is off."** A *plugin* setting (e.g. Hummingbird `page_cache.enabled=false`) is not
  the effective cache — the hosting nginx layer is, and the `x-cache` header proves it works. Trust
  the header, not the toggle.
- **"It's the database / object cache."** Stage 2 usually rules these out in seconds.
- **"A plugin's Action Scheduler failures are the cause."** Usually benign migration retries.
- **"broken-link-checker is hammering us."** Check its tables are actually populated before blaming it.
- **"DeepL/TranslatePress is spiking."** It adds fixed base render overhead (large dictionary), not
  an intermittent spike — confirm the dictionary is populated and query caching is on, but don't
  pin the *variance* on it.
- **"The slow spike at 11:00 is organic."** If you ran concurrency probes at 11:00, that's you.
  Off-hours organic spikes are the real signal.
