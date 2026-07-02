---
name: wp-bot-mitigation
description: Deploy a bot firewall (mu-plugin) + robots.txt to an Avista WordPress site whose PHP workers are being saturated by aggressive crawlers hitting uncached Breakdance pages — the fix for the "bots are ~a third of traffic and crawling cold pages" finding from wp-perf-audit. The mu-plugin returns an early 403 to zero-value scrapers / AI-trainers / broken crawlers BEFORE the expensive render (it loads before regular plugins), while leaving Googlebot, bingbot, the WP loopback, cron, admin, REST, admin-ajax, and facebookexternalhit (link previews) untouched; the robots.txt politely tells compliant AI/SEO bots to leave and keeps all crawlers out of expensive query-string / feed / REST URL spaces. Use when the user says "block the bots", "deploy the bot firewall", "crawlers are hammering the site", "set up robots.txt for scrapers", "stop the AI bots", "the site is getting crawled to death", or right after wp-perf-audit shows bot/crawler overload. Approval-gated and per-site: it reviews the block list against THIS site (never blindly blocks a crawler the site relies on), backs up the existing robots.txt first, deploys only on explicit approval, verifies blocked-vs-allowed before/after, and ships a one-line rollback. Do not blanket-deploy the list without reviewing which bots and IPs this specific site can afford to lose.
---

# WP bot mitigation — firewall + robots.txt

Recover PHP workers from crawler overload. On this stack a cache MISS is a heavy Breakdance render (4–45s) against a fixed worker pool; when ~a third of traffic is bots crawling *cold* URLs, real users and editors queue behind those renders. Two layers fix it:

1. **`avista-bot-firewall.php`** (mu-plugin) — hard 403 for zero-value crawlers, *before* the render. mu-plugins load ahead of regular plugins/theme, so a match exits in ~0.18s instead of triggering a ~3s+ render. It fires only on cache MISSes (nginx cache sits in front of PHP — exactly where the cost is).
2. **`robots.txt`** (physical file in web root) — layer-1 politeness: compliant AI/SEO bots are told to leave and *all* crawlers are kept out of expensive query-string/feed/REST URL spaces. Bots that ignore robots.txt are caught by layer 1.

Both templates ship beside this skill in `templates/`. They are the deployed-and-verified versions — but the block list is **not** a blanket to paste onto every site.

## This changes production — the discipline

This skill deploys code to a live site. Follow the [`avista-wp-prod-ops`](../../../avista-wp-prod-ops/) posture: inspect first, back up before you change, deploy only on **explicit** approval, verify before/after, keep a one-line rollback. Run [`wp-perf-audit`](../../wp-perf-audit/) first (or confirm its findings) — don't deploy a bot firewall on a hunch; deploy it because the access log showed bots dominating request-time.

## Step 1 — Review the block list against THIS site (the judgment step)

The single most important step, and the one you must not skip. The template's `BLOCK_UA` and `BLOCK_IP` lists are the *audited site's* answer, not a universal one. Blocking a crawler a site depends on will quietly break search visibility or link previews.

Read the site's own access log first (from `wp-perf-audit`, or `bash scripts/…/loganalyze.sh`) and reconcile the template against it:

- **Never block, by design:** `Googlebot`, `bingbot` (SEO), the WP loopback (`WordPress/x.x`), `facebookexternalhit` (Facebook/Messenger/WhatsApp share previews — note this is *distinct* from `meta-externalagent`/`FacebookBot`, which are AI crawlers and *are* blocked). Confirm none of these are in the list you're about to deploy.
- **Confirm the UA list matches the site's actual offenders.** The template blocks DataForSeoBot, meta-externalagent, Amazonbot, Bytespider, ClaudeBot, anthropic-ai, GPTBot, ChatGPT-User, CCBot, PerplexityBot, PetalBot, DotBot, MJ12bot, SemrushBot, AhrefsBot, ImageSift, TimpiBot, Java-http-client, python-requests, Go-http-client, Scrapy, libwww-perl, "Microsoft Office", and empty-UA front-end hits. If this site's business *uses* one of these (e.g. an SEO team lives in Ahrefs/Semrush dashboards, or a monitoring service uses a generic HTTP-client UA), pull it from the list before deploying.
- **IP blocks need explicit confirmation.** The template blocks two confirmed broken crawlers by IP and leaves a third (`89.160.223.119`) commented out precisely because it presents a *browser* UA with high volume — it might be a legit partner or monitor. Apply that same caution: any IP you add must be a confirmed heavy offender that is not a real user/partner. When in doubt, leave it commented with a `// REVIEW FIRST` note.
- **empty-UA blocking**: the template 403s front-end hits with no User-Agent. Confirm nothing legitimate on this site hits the front end with an empty UA (rare, but check the log) before keeping it.

Produce a short "block list for `<site>`" diff from the template and get the user's OK on it. That approved list is what you deploy.

## Step 2 — Back up what you're about to overwrite

```bash
# Is there already a physical robots.txt (vs WP's virtual default)? Back it up if so:
$SSH "cd ~/site/public_html && [ -f robots.txt ] && cp -v robots.txt robots.txt.bak.\$(date +%F) || echo 'no physical robots.txt (WP virtual default) — removal reverts to it'"
# Is there already a bot firewall / conflicting mu-plugin?
$SSH "ls -la ~/site/public_html/wp-content/mu-plugins/ 2>/dev/null || echo 'no mu-plugins dir yet'"
```

Also keep the source of truth in the project's `production-notes/bot-mitigation/` (copy the deployed files + a `DEPLOYED.md` record), so there's version history for DB-less/file-less artifacts.

## Step 3 — Deploy (only after approval)

Edit `templates/avista-bot-firewall.php` to the approved list, then push both files:

```bash
# mu-plugin (create the dir if missing):
$SSH "mkdir -p ~/site/public_html/wp-content/mu-plugins"
scp skills/wp-bot-mitigation/templates/avista-bot-firewall.php <user>@<host>:~/site/public_html/wp-content/mu-plugins/avista-bot-firewall.php
# robots.txt in the web root (this makes it a physical file, overriding WP's virtual default):
scp skills/wp-bot-mitigation/templates/robots.txt <user>@<host>:~/site/public_html/robots.txt
```

Update the `Sitemap:` line in `robots.txt` to the site's real sitemap URL, and review the commented site-specific `Disallow` lines (e.g. the IS-slug variant) before pushing.

## Step 4 — Verify (before/after)

The firewall is worthless if it 403s a real user or lets the offenders through. Check both:

```bash
# Normal browser — must be 200:
curl -s -o /dev/null -w '%{http_code}\n' -A 'Mozilla/5.0' "$SITE/"
# Googlebot / bingbot — must be 200 (NOT blocked):
curl -s -o /dev/null -w 'google=%{http_code}\n' -A 'Googlebot/2.1 (+http://www.google.com/bot.html)' "$SITE/"
# A blocked UA — must be 403, and FAST:
curl -s -o /dev/null -w 'blocked=%{http_code} ttfb=%{time_starttransfer}s\n' -A 'Java-http-client' "$SITE/"
curl -s -o /dev/null -w 'empty-ua=%{http_code}\n' -A '' "$SITE/"
# Skipped paths with a bad UA — admin-ajax / wp-login must NOT be 403 (still reachable):
curl -s -o /dev/null -w 'ajax=%{http_code}\n' -A 'Java-http-client' "$SITE/wp-admin/admin-ajax.php"
# robots.txt now serving the new rules:
curl -s "$SITE/robots.txt" | head -20
```

Expected: browser & Googlebot 200; blocked UA & empty-UA 403 at ~0.18s (vs a ~3s full render — that gap *is* the recovered worker time); admin-ajax/wp-login reachable. Then measure real-world impact with the bundled script:

```bash
# Edit the deploy-time threshold in the script first (it defaults to 11:41 — set it to your
# actual deploy HH:MM), then:
scp skills/wp-bot-mitigation/scripts/since_deploy.sh <user>@<host>:~/since_deploy.sh
$SSH "bash ~/since_deploy.sh"   # 403 blocks since deploy, avg 403 time (should be fast), non-403 avg, top blocked UAs
```

Impolite bots (Java-http-client, no-UA, listed IPs) are 403'd immediately from the first request; compliant bots (Meta, Amazon, DataForSeo, GPTBot…) taper off over hours/days as they re-read robots.txt. Re-run `wp-perf-audit`'s log stage a day later to confirm HIT rate up / request-time down.

## Step 5 — Record the rollback

Write a `DEPLOYED.md` (mirror `production-notes/bot-mitigation/DEPLOYED.md`: what was deployed, the verification table, expected effect, rollback). The rollback is one line:

```bash
$SSH "cd ~/site/public_html && rm -f wp-content/mu-plugins/avista-bot-firewall.php robots.txt"
```

Removing `robots.txt` reverts to WordPress's virtual default; removing the mu-plugin removes all blocking instantly (no cache to clear — mu-plugins load per request). If a physical `robots.txt` pre-existed, restore the `.bak` instead of deleting.

## Guardrails

- **Per-site review is mandatory** (step 1). The list is a starting point, not a default. The cost of over-blocking (lost SEO, broken share previews) is invisible until someone notices weeks later — that's why Googlebot/bingbot/facebookexternalhit are protected and IP blocks stay conservative.
- **Approval-gated.** Present the reviewed list + the exact files, deploy only on explicit OK.
- **Skips are load-bearing.** The firewall must never touch `/wp-admin`, `wp-cron.php`, `wp-login.php`, `/wp-json/`, `admin-ajax.php`, or CLI — breaking cron or REST breaks the site. Don't remove those skips.
- This is a mitigation, not the cure. It recovers workers wasted on bots, but a cold cache and heavy renders still hurt real users — pair it with the TTL/preload hand-off, `wp-render-optimize`, and the Breakdance builder work from `wp-breakdance-render-profile`.
