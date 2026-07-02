---
name: wp-breakdance-render-profile
description: Profile Breakdance server-side render cost on an Avista WordPress site to name the exact heavy templates, global blocks, and nodes — the drill-down after wp-perf-audit / php_slow.log shows the slow cache-MISS render is Breakdance SSR. It flips Breakdance's render-performance-debug flag on for a couple of cache-busted requests (which emits Server-Timing response headers — invisible to visitors, tiny overhead), reads and ranks the timing entries (heaviest breakdance_template / breakdance_block / breakdance_header/footer / renderNode-N), then turns the flag back off, and writes a builder to-do report. Use when the user says "profile Breakdance", "why is the Breakdance render slow", "which template is slow", "read the Server-Timing", "find the heavy Breakdance nodes", "Breakdance render performance", or after wp-perf-audit fingers Breakdance SSR as the MISS cost. It is invisible to visitors and self-reverting — it changes exactly one global debug option and always restores it. Do not use to edit the templates themselves (that is Breakdance-builder-UI work this skill hands off — it is NOT SSH-fixable) and do not use it as the first diagnostic (run wp-perf-audit first to confirm the render, not infra/bots/cache, is the target).
---

# Breakdance render profiling — Server-Timing

`wp-perf-audit` / `php_slow.log` tells you the slow cache-MISS render *is* Breakdance SSR. This skill tells you **which part** — the specific template, global block, and nodes eating the milliseconds — so the builder team gets an exact, ranked to-do list instead of "make Breakdance faster."

The mechanism is Breakdance's built-in **render-performance-debug** flag. When on, Breakdance emits `Server-Timing` response headers on cache-MISS renders, one entry per rendered post/component/node with its duration in ms. It's invisible to visitors and cheap, but it's a **global** flag, so the rule is: turn it on, take your measurements, turn it straight back off.

## What this skill does and doesn't touch

- It flips **one global option** (`enable_render_performance_debug`) on, then off. Nothing else changes; visitors see no difference.
- The bundled `scripts/bd_debug.php` is the safe toggle (handles the Breakdance namespaced setter with an `update_option` fallback and echoes the resulting state).
- It is a *diagnostic*. The fixes it points at — simplifying template node depth, reducing loop item counts, trimming per-item dynamic-data queries — are **builder-side in the Breakdance UI and are NOT SSH-fixable** (Breakdance templates are DB-stored; never hand-edit them over SSH). This skill hands off that work; it does not do it.

Follow the [`avista-wp-prod-ops`](../../../avista-wp-prod-ops/) posture even though the footprint is tiny: know the flag's current state before you touch it, and guarantee it ends up off.

## Step 1 — Record current state, then enable

```bash
scp skills/wp-breakdance-render-profile/scripts/bd_debug.php <user>@<host>:~/bd_debug.php
$SSH "cd ~/site/public_html && wp eval-file ~/bd_debug.php"        # prints current value — note it (should be false)
$SSH "cd ~/site/public_html && wp eval-file ~/bd_debug.php on"     # enable; confirms 'enable_render_performance_debug = true'
```

If `wp` reports the Breakdance functions are unavailable, the site may not be running Breakdance or the version differs — stop and confirm before proceeding.

## Step 2 — Capture Server-Timing on cache-busted renders

The flag only helps on a MISS (a HIT is served by nginx and never renders). Force a couple of MISSes on a *representative* page — the page type the client says is slow (a single news article, a heavy landing page) — and grab the headers:

```bash
ART="$SITE/a-representative-heavy-page/"
for i in 1 2; do
  echo "=== request $i ==="
  curl -s -o /dev/null -D - "$ART?cb=$RANDOM" | grep -i '^server-timing:' 
done > /tmp/bd-timing.txt
wc -l /tmp/bd-timing.txt
```

Two requests is enough — you want the flag on for as few requests as possible. If `grep` finds no `server-timing` header, the response was a HIT (add the cache-buster / confirm the flag took) or the page isn't Breakdance-rendered.

## Step 3 — Rank the entries

Server-Timing packs many `name;dur=NN` entries into the header(s). Rank them by duration to find the hot spots:

```bash
# Split on commas, pull "name ... dur=NN", sort by ms descending, show the top 25:
tr ',' '\n' < /tmp/bd-timing.txt \
  | grep -oE '[A-Za-z0-9_.-]+;dur=[0-9.]+' \
  | sed -E 's/;dur=/  /' \
  | awk '{printf "%8.1f ms  %s\n", $2, $1}' \
  | sort -rn | head -25
```

You're looking for three shapes (all seen on the audited site):

| Entry shape | What it is | The lever |
|---|---|---|
| `breakdance_template` (a post ID, e.g. *Page Template – Single News*) | the whole template render | its heaviest nodes (below) |
| `breakdance_block` (e.g. *Component – Post Card*) with a mid cost **× many** | a component rendered once **per loop item** | reduce loop item count and per-card dynamic fields — the multiplier is the cost |
| `renderNode-<N>` with a high ms | a specific element inside a template | simplify / de-dynamic that node |
| `breakdance_header` / `breakdance_footer` | global header/footer render | check for dynamic content/queries (a footer heavier than the header is a smell) |

On the audited single-news page the template (post 7791) was ~310ms, its nodes 147/151/100 were the heaviest (~269/266/163ms), the footer (82ms) outweighed the header (37ms), and the *Post Card* component cost ~38–45ms **× each loop item** — so a 12-item related-news loop alone was ~500ms. Note both the absolute hot nodes *and* the per-loop multipliers, because cutting a loop from 12→6 items is often the biggest single win.

## Step 4 — Turn the flag OFF (do not skip)

```bash
$SSH "cd ~/site/public_html && wp eval-file ~/bd_debug.php off"    # confirms 'enable_render_performance_debug = false'
$SSH "rm -f ~/bd_debug.php"
```

Verify it's off — the flag is global and shouldn't linger. If any step above errored, still run the `off` command; leaving debug on is the one lasting side effect this skill can have.

## Step 5 — Write the builder to-do report

The deliverable is a ranked, specific hand-off for the Breakdance builder team (mirror `production-notes/render-opt/DEPLOYED.md`'s "Builder to-do" section). For each hot spot: the template/component name + post ID, the node numbers, the measured ms, and the concrete action. Example shape:

```markdown
## Breakdance builder to-do (UI — not SSH)
1. Open "<template name>" (post <id>, <N> ms). Inspect nodes <a>, <b>, <c> (the heaviest,
   <ms>/<ms>/<ms>) — simplify / reduce dynamic-data lookups there.
2. "<component>" renders once per loop item (~<ms> each). If the page has a related/latest loop,
   cut item count (e.g. 12 → 4–6) and trim per-card dynamic fields — the loop×card cost is a
   big multiplier.
3. "<header/footer>" (<ms>) — check for dynamic content/queries.
4. Re-measure after changes: Breakdance → Settings → Advanced → render-performance-debug, read
   Server-Timing in the browser Network tab.
```

Close with the honest framing: the highest ROI is still **caching** (render each page rarely — the TTL/preload hand-off). These template cuts reduce the cost of the unavoidable first render + every preloader hit, so they compound with the cache work rather than replace it.

## Guardrails

- **Always end with the flag off.** It's global; a lingering debug flag emits headers on every MISS render forever.
- **Never edit Breakdance templates over SSH.** They're DB-stored builder data; hand-editing risks corrupting the builder tree. This skill's output is instructions for the builder UI, full stop.
- Profile a **representative** page, not the homepage (usually the only warm page — you want the expensive type).
- Keep the flag on for the fewest requests that give a stable ranking (two is usually enough).
