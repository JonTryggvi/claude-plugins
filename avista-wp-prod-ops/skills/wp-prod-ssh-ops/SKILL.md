---
name: wp-prod-ssh-ops
description: Operate safely on a WordPress site whose code lives on production and is reached over SSH, when the local working folder is a near-empty "shell" repo with no real code in it. Inspect production read-only first, back the relevant code into git locally, then make changes carefully — most often by installing or updating WP Code Box 2 (`wpcodebox2`) snippets without the admin UI. Use when the user says the code "lives on production", gives an SSH host for a WP site, mentions editing a live WP site without local files, says "this repo is empty, the real site is over ssh", asks to "back up the wpcodebox snippets before I change anything", or otherwise references WP Code Box / `wpcodebox` snippets, Breakdance pages, TempURL hosts, or any task on a remote WordPress install where there is no meaningful local checkout. Do not use for WordPress projects where the code is already checked out locally and developed normally — this is specifically the shell-folder / SSH-only workflow.
---

# Operating on shell-folder WordPress projects over SSH

You are working on a WordPress site where the local folder is a *shell* — typically a fresh `git init` with maybe a README — and the real codebase lives on production. SSH is your only window into the site. Everything below assumes that setup.

The dominant case this skill exists for: Avista client sites on TempURL-style hosts running WP Code Box 2 (the snippet manager), where business logic is rows in the database, not files in the theme. Page-builder pages (Breakdance) are also DB-stored. Theme files are stubs; editing them does nothing useful.

The rules are: **read before you write, back up before you change, never assume the schema.**

## Workflow

### Step 1 — Inspect production (read-only)

Open SSH to the host. The host may print a post-quantum / OpenSSH compatibility warning on every connection — filter that noise out of command output so it doesn't clutter your reasoning. Example: pipe through `grep -v 'post-quantum\|key exchange'` or just ignore the banner lines manually.

Find the WordPress root, then run wp-cli from there:

```bash
ssh user@host 'find ~ -maxdepth 4 -name wp-config.php 2>/dev/null'
# pick the right hit, then for every later command:
ssh user@host 'cd <wproot> && wp <subcommand>'
```

Map the stack before touching anything:

```bash
wp theme list
wp plugin list
wp config get table_prefix    # CRITICAL — never assume wp_
wp db tables                  # confirm prefix and see what's there
```

The table prefix is almost never `wp_` on Avista hosts (mímir uses `wp_zp_`). Burn this into your commands going forward. Anything that hardcodes `wp_` will silently target the wrong tables or fail.

### Step 2 — Find where the actual code lives

WordPress can house custom logic in many places. Check each, in this order, before assuming:

1. **Active theme** — `wp eval 'echo get_template_directory();'`, then grep `functions.php` and the theme directory. If the theme is `breakdance-zero` (or anything from the Breakdance "Zero" family), the theme files are intentional stubs — **do not edit theme files**. Breakdance keeps its pages and templates in the database, accessible only through the Breakdance UI.
2. **mu-plugins** — `ls $(wp eval 'echo WPMU_PLUGIN_DIR;')`. Real code sometimes lives here.
3. **Snippet plugin** — most often WP Code Box 2 (`wp-code-box-2` directory, slug `wpcodebox2`). If `wp plugin list` shows it active, custom code almost certainly lives in its DB table. Skip ahead to the WPCB section below.
4. **Page builder** — Breakdance, Elementor, etc. Page content and templates are DB-stored. If layout/content needs changing, the user does it in the builder UI; you do not.

Grep the theme and mu-plugins first. If both are empty of business logic, the snippet plugin or page builder owns the customization surface.

### Step 3 — Initialize the local shell folder as a backup repo

Before any change, the local folder becomes the authoritative backup of the parts of production you're about to touch. Structure:

```
.
├── backups/             # authoritative SQL dumps (re-importable)
├── snippets/            # source-of-truth copies of any snippet code you deploy
└── production-notes/
    └── findings.md      # stack map, root cause, fix, verification
```

`git init` (if not done), commit the initial layout, then continue.

DB-stored code is backed up via SQL dump piped from the host to the local folder:

```bash
ssh user@host 'cd <wproot> && wp db export - --tables=<prefix>_wpcb_snippets' \
  > backups/wpcb_snippets.sql
```

(That's a full re-importable dump with correctly-escaped contents — preferred over per-row text exports, which have a newline gotcha covered below.)

Commit the backup before changing anything on production. One task per commit, conventional commit messages, **never push unless the user asks**, and don't bump versions unless the user asks.

### Step 4 — Make the change

Most changes on these sites mean installing or updating a WP Code Box 2 snippet. The rest of this skill is the WPCB procedure.

For theme/mu-plugin edits, follow the same rules: back up first (clone the file into the local repo and commit), edit on production via SSH, commit the change locally with a conventional message describing what and why.

### Step 5 — Verify on the live site

After deploying any change, use the browser MCP to load the affected pages and confirm the behavior. Include a no-regression check on the languages/states the change should not affect. Record stack map, root cause, the fix, and verification steps in `production-notes/findings.md`. Commit.

## WP Code Box 2 (`wpcodebox2`) — the core procedure

WPCB stores snippets as **rows in a DB table**, not files. The table is `{prefix}wpcb_snippets`. Forget about FTP; the admin UI and `wp db query` / `wp eval-file` are the only ways in.

### Schema

Columns you care about:

| Column | Notes |
|---|---|
| `id` | PK |
| `title` | Human-readable, also your idempotency key on insert |
| `description` | Optional |
| `enabled` | `1` = active, `0` = inactive |
| `priority` | Execution order within a codeType |
| `runType` | `'always'`, `'once'`, etc. WPCB queries `enabled=1 AND runType='always'` on every request |
| `code` | The actual snippet body — **stores real newlines** |
| `original_code` | Pre-minification copy; keep in sync with `code` |
| `codeType` | `'php'`, `'css'`, `'js'`, … |
| `conditions` | JSON, where/when it runs |
| `location` | JSON, frontend/admin scoping |
| `tagOptions` | JSON |
| `hook` | JSON; maps WPCB-internal names like `custom_plugins_loaded` to real WP hooks (`plugins_loaded`) |
| `renderType` | How CSS/JS is emitted |
| `minify` | Bool |
| `snippet_order` | Sort order in the admin UI |

For full column descriptions and example hook JSON values, see `references/wpcb-snippets-schema.md`.

### Read / list

```bash
# list all
wp db query "SELECT id, title, enabled, codeType FROM {prefix}wpcb_snippets ORDER BY id"

# dump one snippet's code (note: see newline gotcha below)
wp db query --skip-column-names "SELECT code FROM {prefix}wpcb_snippets WHERE id=<N>"
```

### Newline gotcha — important

The `code` column **really does store newlines**. But `wp db query --skip-column-names` runs MySQL in batch mode, which escapes newlines and tabs as literal `\n` and `\t` in its output. So per-snippet text exports *look* mangled even though the DB content is fine.

This is a **display artifact only**. Two consequences:

1. Treat per-row text exports (`wp db query ... > snippet.txt`) as **read-only references** for diffing, not as your source of truth. Don't try to import them back; the escaping will be wrong.
2. The authoritative dump is `wp db export - --tables={prefix}_wpcb_snippets`, which uses standard SQL escaping that re-imports cleanly.

Confirm a snippet's code is real-newlines-in-DB (not escape-sequences-in-DB) with:

```bash
wp db query --skip-column-names \
  "SELECT HEX(SUBSTRING(code, 1, 8)) FROM {prefix}wpcb_snippets WHERE id=<N>"
# 0A = real newline ✓
# 5C 6E = literal '\n' (escape sequence stored as text) — something is wrong upstream
```

### How snippets execute

On every request, WPCB queries `enabled=1 AND runType='always'`, orders by `priority`, and `eval()`s each PHP snippet inside a try/catch that **auto-disables a snippet and logs on fatal**. That's a real safety net: a broken snippet won't take the site down, it'll just turn itself off. There's no compiled cache to bust — your edits to the DB row take effect on the next page load (for PHP affecting AJAX/POST) or after the page cache is cleared (for CSS/JS, see below).

### Inserting / updating a snippet without the admin UI

This is the safe pattern. Do not write the snippet straight into the DB with `wp db query "INSERT …"`. The `hook` / `conditions` / `location` JSON fields are easy to malform, and a malformed row may not match any execution branch and just silently never run.

**Step A — write the snippet source as a real file under `snippets/` locally and lint it.**

```bash
mkdir -p snippets
$EDITOR snippets/my-snippet.php
php -l snippets/my-snippet.php    # must say "No syntax errors detected"
```

CSS and JS snippets store **raw code** in the `code` column — no `<style>` or `<script>` wrapper. Don't add one.

**Step B — base64-transport the file to the host's `/tmp`** to avoid SSH and SQL quoting hell:

```bash
B64=$(base64 < snippets/my-snippet.php)
ssh user@host "echo '$B64' | base64 -d > /tmp/my-snippet.php"
```

**Step C — install via `wp eval-file` using the bundled `scripts/wpcb-install-snippet.php` template.** Do not hand-author the `hook` / `conditions` / `location` JSON. Clone a known-good row of the same `codeType` and override only the fields you care about (`title`, `code`, `original_code`, `enabled`, `snippet_order`).

The bundled script under `scripts/wpcb-install-snippet.php` is the template. Open it, fill in the four placeholders at the top (`$title`, `$source_path`, `$template_id`, optional `$snippet_order`), then deploy:

```bash
# transport the installer too
B64=$(base64 < scripts/wpcb-install-snippet.php)
ssh user@host "echo '$B64' | base64 -d > /tmp/wpcb-install.php"

# run it
ssh user@host 'cd <wproot> && wp eval-file /tmp/wpcb-install.php'

# cleanup
ssh user@host 'rm -f /tmp/wpcb-install.php /tmp/my-snippet.php'
```

The installer is **idempotent on title**: if a row with that title already exists, it prints `EXISTS` and exits without inserting. To force an update, change the script to UPDATE instead of INSERT, or delete the existing row first via `wp db query`.

**Picking the template row:** clone an enabled row of the same `codeType`. `codeType='php'` → clone a PHP row. `codeType='css'` → clone a CSS row. `codeType='js'` → clone a JS row. List candidates with:

```bash
wp db query "SELECT id, title, codeType FROM {prefix}wpcb_snippets WHERE enabled=1 ORDER BY codeType, id"
```

Use the `id` of any row from the right `codeType` group.

### Object-cache gotcha — flush before bulk regeneration

Many Avista/WPMU DEV-managed hosts run a **persistent external object cache** (Redis/Memcached). Detect it:

```bash
ssh user@host 'cd <wproot> && wp eval "echo wp_using_ext_object_cache() ? \"EXTERNAL_OBJECT_CACHE\" : \"no_persistent_object_cache\";"'
```

WPCB caches its **active-snippets query** in the object cache. The admin UI invalidates that cache on save — but a raw DB write (`$wpdb->update`, `wp db query "UPDATE …"`, or any non-UI write to the `{prefix}wpcb_snippets` row) does **not**. So after editing a snippet directly in the DB, a bulk regeneration run as a single `wp eval-file` request can execute a **stale** copy of the snippet for an unknown subset of items, leaving silent stragglers — even though the row in the DB is already correct.

This is deceptive in two ways:

- Reading the code back from the DB shows the NEW code (`SELECT code FROM {prefix}wpcb_snippets WHERE id=N`), so the row looks fine.
- Re-running a single item in isolation a bit later usually comes back clean (the object cache has refreshed by then), which fools you into thinking the bulk pass worked.

**Rule:** after editing a WPCB snippet directly in the DB, always flush the object cache **before** any bulk regeneration:

```bash
ssh user@host 'cd <wproot> && wp cache flush'
```

With the cache flushed, the single bulk request reads fresh snippet code once and applies it to every item deterministically. Then verify with a **site-wide count query**, not a spot-check of one or two items.

**Two different caches — don't conflate them:**

- **`wp cache flush`** clears the **object cache** — fixes stale snippet code / query data (this gotcha).
- The Hummingbird **page cache** is separate and clears the rendered HTML — see the page-cache gotcha below.

Editing a PHP snippet that affects rendered HTML may require **both**.

### Cache gotcha — separate "not deployed" from "cached"

- **PHP snippets affecting AJAX or POST responses** — take effect immediately. Those requests are not page-cached.
- **CSS / JS snippets** — baked into page HTML, which Hummingbird page-caches on these hosts. Your change is in the DB but the visitor still sees the old bytes until the page cache is cleared.

This host has no `wp hummingbird` CLI subcommand. Clear via the plugin's action hook:

```bash
ssh user@host 'cd <wproot> && wp eval "do_action(\"wphb_clear_page_cache\");"'
```

When verifying, **always hit the page with a cache-buster first** (`?cb=12345`) to separate "snippet didn't deploy" from "snippet deployed but page is cached". If the cache-busted URL shows the new behavior and the clean URL doesn't, you need to clear the page cache.

## Test trigger prompts

These are realistic prompts this skill is expected to fire on:

- "The code for this client lives on prod, here's the SSH: `ssh foo@bar.tempurl.host`. Add a snippet that hides the search bar for logged-out users."
- "Back up the wpcodebox snippets before I change anything on this site."
- "This repo is empty, the real site is at `ssh user@mimir.is`. Find where the language switcher logic lives."
- "Add a CSS rule to the live site to hide the admin bar for subscribers." (CSS path; reminder to clear Hummingbird.)

## Related

- [[fix-wpgb-translatepress-ajax]] — common follow-on: install a PHP snippet to fix the WP Grid Builder + TranslatePress AJAX language bug. Uses this skill's WPCB installer to deploy.
