---
name: wp-perf-audit
description: Read-only performance triage for an Avista WordPress + Breakdance site that is "sometimes" slow — pages that intermittently take 30–60s, slow media uploads, or a vague "the site is slow" with no known cause. Runs a diagnose-first funnel over SSH — TTFB on a cache HIT vs a cache-busted MISS (reading the x-cache header), rules out object-cache/DB/autoload as the bottleneck, tests whether warmed URLs stay warm (cache TTL), analyzes the nginx access log for bot load / cache-HIT rate / 499 timeouts / worst offender IPs by total request-time, and reads php_slow.log to see where render time goes — then writes a findings report and a prioritized plan that routes to the fix skills. Use when the user says "the site is slow", "pages sometimes take 30 seconds", "WordPress is slow on WPMU DEV", "diagnose performance", "why is Breakdance so slow", "audit site performance", "TTFB is terrible", or gives an SSH host for a slow WP site and asks what's wrong. Start HERE before any performance fix — it is read-only, changes nothing, and tells you which of the other avista-wp-performance skills to run next. Do not use to actually deploy a fix (wp-bot-mitigation / wp-render-optimize / wp-media-upload-fix do that) or for functional bugs unrelated to speed.
---

# WP performance audit — read-only diagnostic funnel

A WordPress + Breakdance site is "sometimes" slow. Your job in this skill is to find out **why**, precisely, **without changing anything**, and hand the user a ranked plan that names the exact next skill (or off-SSH hand-off) for each problem.

The recurring shape on this stack (WPMU DEV managed hosting, fixed PHP-worker count, Breakdance classic theme, TranslatePress, Smush) is **PHP-worker saturation**: a cache MISS triggers a heavy Breakdance server-side render, aggressive crawlers hit uncached pages in bulk, the cache preloader's own requests time out so pages never warm, and Smush pins a worker for ~30s per upload. The symptom the client reports — "pages *sometimes* take 30–60s" — is contention, not a constant. The funnel below separates the cheap-warm-page reality from the expensive-cold-page reality and measures each contributor.

## The one rule: this skill is read-only

Investigate first, change nothing. Every command here is a measurement (`curl`, `wp eval` reads, log analysis). You do **not** deploy, edit options, or write files in this skill. When the funnel points at a fix, you *hand off* to the skill that owns it — those skills do their own backup-before-change and approval gating. If you catch yourself about to run `wp option update`, `rm`, or write to `mu-plugins/`, stop: that belongs to a fix skill, not the audit.

## Prerequisites

- **SSH access** to the site. This stack is the WP-over-SSH / shell-repo case that [`avista-wp-prod-ops`](../../../avista-wp-prod-ops/) governs — read its `wp-prod-ssh-ops` skill for the SSH connection discipline (the `IdentitiesOnly=yes` + explicit `-i` gotcha when the agent has several keys) and the inspect-first posture. Typical WPMU DEV layout: WP root at `~/site/public_html`, logs at `~/site/logs` (`access.log`, `php_slow.log`, `waf.log`).
- **The public URL** and one or two representative **slow URLs** (a news article / low-traffic single, not the homepage — the homepage is usually the *only* thing that stays warm).
- Confirm `wp` runs on the host (`wp --info`).

Set these once so the commands below are copy-pasteable:

```bash
SSH="ssh -i ~/.ssh/<key> -o IdentitiesOnly=yes <user>@<host>"   # per avista-wp-prod-ops
SITE="https://www.example.is"
ART="$SITE/some-low-traffic-article/"    # a page that is NOT the homepage
```

## The funnel

Run the stages in order. Each stage either *rules out* a class of cause or *localizes* it. Record the numbers as you go — the findings report at the end is built from them. The deep version of every command, the interpretation tables, and the expected-value baselines are in **[references/methodology.md](references/methodology.md)** — read it when a stage needs more than the summary below, or when a number is ambiguous.

### 1. TTFB — cache HIT vs cache-busted MISS

Establish the two realities: a warm page is fast, a cold page is expensive. The serving cache on this stack is the **hosting nginx layer**, reported in the `x-cache` response header (`HIT` / `MISS`), with `x-cache-enabled: true`.

```bash
# Warm it, then measure the HIT:
curl -s -o /dev/null "$ART"; \
curl -s -o /dev/null -D - -w '\nttfb=%{time_starttransfer}s code=%{http_code}\n' "$ART" | grep -iE 'x-cache|ttfb='
# Force a MISS (unique query string bypasses the cache key):
curl -s -o /dev/null -D - -w '\nttfb=%{time_starttransfer}s code=%{http_code}\n' "$ART?cb=$RANDOM" | grep -iE 'x-cache|ttfb='
```

Interpretation: a HIT ~0.15s + a MISS of several seconds means **the cache works but articles are cold** — the problem is MISS *frequency* (stage 3) and MISS *cost* (stages 5–6). If even the HIT is slow, it is not a render problem — re-check infra (stage 2) and the hosting layer. Repeat the MISS probe a few times and with 3–4 concurrent requests (`for i in 1 2 3 4; do curl ... "$ART?cb=$i" & done`) — MISS TTFB that balloons under concurrency is the PHP-worker-contention signature (idle ~4s → concurrent ~12s → real contention up to ~56s).

### 2. Rule out infra — object cache, DB, autoload

If these are healthy, the slowness is **render/contention**, not the data layer. Time them over SSH:

```bash
$SSH "cd ~/site/public_html && wp eval '
  \$t=microtime(true); for(\$i=0;\$i<1000;\$i++){wp_cache_set(\"k\$i\",\$i);wp_cache_get(\"k\$i\");}
  printf(\"objcache 1k set+get: %.1f ms\n\",(microtime(true)-\$t)*1000);
  \$t=microtime(true); \$GLOBALS[\"wpdb\"]->get_var(\"SELECT 1\");
  printf(\"db round-trip: %.1f ms\n\",(microtime(true)-\$t)*1000);
  printf(\"autoload bytes: %d\n\", array_sum(array_map(\"strlen\", wp_load_alloptions())));
'"
```

Healthy = object cache 1k ops in a few ms, DB round-trip low single-digit ms, autoload well under ~1MB. If all fine (the usual finding), **stop suspecting infra** and move to render/contention. See methodology.md for the thresholds and the deeper autoload breakdown.

### 3. Cache warmth — does a warmed URL stay warm?

The core finding on this stack: articles don't stay warm (short TTL / purge-on-publish + low per-article traffic), so nearly every real view pays a MISS. Warm several low-traffic URLs now, note the time, and re-check them after ~15–45 min:

```bash
for u in "$ART" "$SITE/another-article/" "$SITE/a-third/"; do curl -s -o /dev/null "$u"; done
# ...wait 15–45 min, then re-check x-cache on the SAME urls:
for u in "$ART" "$SITE/another-article/" "$SITE/a-third/"; do
  curl -s -o /dev/null -D - "$u" | grep -i x-cache; done
```

If they are back to `MISS`, the TTL is short and nothing re-warms low-traffic pages (the homepage stays HIT only because constant traffic re-warms it). **This is the highest-leverage finding and it is usually NOT SSH-fixable** — it's a WPMU DEV Hub static-cache-TTL setting + a preloader. Flag it for hand-off (see routing).

### 4. Access-log analysis — who is hammering the cold path

This is where "36% of traffic is bots crawling uncached pages" gets proven. Two bundled scripts read `~/site/logs/access.log` and print the whole picture. Copy them to the host and run, or pipe them in:

```bash
# copy up and run (scripts cd to ~/site/logs themselves):
scp skills/wp-perf-audit/scripts/loganalyze.sh  <user>@<host>:~/loganalyze.sh
scp skills/wp-perf-audit/scripts/loganalyze2.sh <user>@<host>:~/loganalyze2.sh
$SSH "bash ~/loganalyze.sh"    # window, aggregate, bot %, HIT rate, status codes, top IPs by TOTAL request-time, deep/looping paths
$SSH "bash ~/loganalyze2.sh"   # hourly volume + slow(>10s), profiles of the worst IPs, 499s by UA, php_slow top-of-stack, WAF
```

`loganalyze2.sh` hardcodes four example offender IPs in its profile loop — swap them for the top IPs that `loganalyze.sh` surfaces on *this* site before reading that section. What to pull out: **cache HIT rate** (single digits = the cache is barely helping), **bot %** and which bots, **worst IPs by total request-time** (not request count — a broken crawler doing 45s/req is worse than a fast one doing thousands), **499 count and whose UA** (if the site's own `WordPress/x.x` loopback is 499-ing, the preloader is timing out → the cache never warms → the vicious cycle), and the **301/404 surface** (a big legacy-redirect / malformed-URL surface gives bots infinite expensive URLs to crawl).

### 5. php_slow.log — where the render time actually goes

`loganalyze2.sh` already prints the most common top-of-stack functions from `php_slow.log`. On this stack they are **all Breakdance server-side rendering** (`_render`, `getRenderedNodes`, `getRenderedPost`, `renderGlobalBlock`, `loopBlockPosts`, `renderDynamicDataInProps`, `ssr`) — that confirms the slow uncached render *is* Breakdance SSR (post loops, global blocks, dynamic data), and that the fix is builder-side, not a plugin toggle. Also note how many slow events are front-end `index.php` vs `async-upload.php` (the latter confirms slow uploads → media-upload-fix).

### 6. Breakdance render depth (hand-off to the profiler)

If stage 5 fingers Breakdance SSR, don't node-profile here — that's a separate, slightly-invasive step (it flips a global debug flag). Hand off to **`wp-breakdance-render-profile`**, which enables Server-Timing for a couple of cache-busted requests, names the exact heavy `breakdance_template` / `breakdance_block` / `renderNode-N`, and turns the flag back off.

### 7. Smush + image-size sprawl (read the settings only)

If the complaint includes slow *uploads*, read (don't change) the Smush config and the registered image-size count:

```bash
$SSH "cd ~/site/public_html && wp option get wp-smush-settings --format=json"
$SSH "cd ~/site/public_html && wp eval '\$s=wp_get_registered_image_subsizes(); echo count(\$s).\" registered subsizes: \".implode(\", \", array_keys(\$s)).\"\n\";'"
```

`auto:true` + `lossy:"1"` (Super-Smush → remote WPMU DEV API) + `original:true` + `webp_*` across ~10 sizes = a blocking remote round-trip per size on every upload, inline in the request → the ~30s upload, and a worker pinned for ~30s that starves the front end. That's the **wp-media-upload-fix** signature. Just record the settings here.

## Turn the funnel into a plan (routing)

Map each confirmed finding to its owner. Present the plan ranked by impact, and be explicit about what is and isn't SSH-fixable — half the highest-leverage fixes on this stack live in the WPMU DEV Hub or the Breakdance builder, not over SSH.

| Finding from the funnel | Route to | SSH-fixable? |
|---|---|---|
| Bots/scrapers dominate request-time; low HIT rate driven by crawl of cold pages; 499 preloader loop | **`wp-bot-mitigation`** | ✅ yes (mu-plugin + robots.txt) |
| Slow MISS is Breakdance SSR (stage 5); need the exact heavy templates/nodes | **`wp-breakdance-render-profile`** | ✅ profile via SSH; ❌ the template edits are builder-side |
| Block-theme global-styles/font-face overhead on a classic (non-block) theme | **`wp-render-optimize`** | ✅ yes (guarded mu-plugin) |
| ~30s uploads; Smush `auto`+`lossy` synchronous; image-size sprawl | **`wp-media-upload-fix`** | ✅ yes (Smush setting + size review) |
| Short static-cache TTL; low-traffic pages go cold (stage 3) | **Hand off: WPMU DEV Hub** (raise TTL + enable preload). Optional SSH supplement: a *bounded* cache-warmer cron for key URLs. | ⚠️ mostly no |
| PHP-worker count too low for the traffic even after fixes | **Hand off: WPMU DEV** (raise worker count) | ❌ no |
| Heavy Breakdance template internals (node depth, loop item counts, per-item queries) | **Hand off: builder team** (Breakdance UI) — the profiler produces the exact to-do list | ❌ no |

The ordering that has worked: **make MISSes rarer** (cache TTL/preload — hand-off) and **stop paying for MISSes you shouldn't** (bot firewall — cheap, SSH, big win) first, because they cut load immediately; then **make each MISS cheaper** (render-optimize + Breakdance builder work); fix **uploads** in parallel since they're an independent contention source. Bot firewall + Smush fix are the two you can land over SSH today; the rest is diagnosis + hand-off.

## Findings report

Write the report to the project (e.g. `production-notes/findings.md` or the user's chosen path) and present a summary. Use this structure — it mirrors the proven audit and keeps evidence separate from recommendations:

```markdown
# <site> — Performance Audit (<date>)
Read-only investigation. No production changes made. Prompted by: <complaint>.

## Stack
<WP/PHP versions, hosting, worker model, the heavy plugins: Breakdance, TranslatePress, Smush, etc.>

## Measured evidence
- Cache serving: HIT ~<x>s vs MISS ~<y>s; concurrent MISS ~<z>s. <N>/<M> sampled articles cold.
- Infra (ruled out / not): objcache <>, DB <>, autoload <>.
- Cache warmth: <warmed URLs back to MISS after <t> min? yes/no>.
- Access log (<window>, <N> requests): HIT rate <>%, bots <>%, worst IP <>s over <> req, 499s <> (loopback? yes/no), 301 <> / 404 <>.
- php_slow.log: top-of-stack = <Breakdance SSR? / other>.
- Smush: <auto/lossy/original/webp>, <N> registered subsizes.

## Root causes (confirmed) / Disproven
<the chain, and what you ruled out — object cache, DB, "page cache off" myths, etc.>

## Remediation plan (ranked by impact) — NOT YET APPLIED
<the routing table above, per-finding, each naming the skill or hand-off + a one-line "why">

## What is / isn't SSH-fixable
<explicit split so nobody expects an SSH fix for a Hub/builder problem>
```

## Guardrails

- **Read-only.** No `wp option update`, no writes to `mu-plugins/`, no `rm`. Fixes belong to the fix skills, which gate on explicit approval.
- **Don't over-attribute.** A slow spike during your own concurrency/cache-bust testing is self-inflicted — note the caveat (organic slow spikes at off-hours are the real signal). Cache HIT of "off" in a *plugin* setting (e.g. Hummingbird `page_cache.enabled=false`) does not mean caching is off — the hosting nginx layer is the effective cache; always trust the `x-cache` header over a plugin toggle.
- **Per-site judgment, not a script.** The numbers differ per site; the funnel is fixed but the thresholds and the bot list are read in context, not assumed.
- Leave the site exactly as you found it. If you copied helper scripts to the host, remove them (`$SSH "rm -f ~/loganalyze.sh ~/loganalyze2.sh"`) unless the user wants them kept.
