# WP Code Box 2 — `{prefix}wpcb_snippets` reference

Quick reference for the snippet table WPCB 2 stores its rules in. Use alongside `SKILL.md`.

## Columns

| Column | Type (typical) | Purpose |
|---|---|---|
| `id` | INT PK | Auto-increment row id. |
| `title` | VARCHAR | Human-readable label. Used as the idempotency key by the bundled installer. |
| `description` | TEXT | Optional notes. |
| `enabled` | TINYINT | `1` = active, `0` = inactive. WPCB auto-flips this to `0` if the snippet fatals at runtime. |
| `priority` | INT | Execution order within a `codeType`. Lower runs earlier. |
| `runType` | VARCHAR | `'always'`, `'once'`, etc. WPCB queries `enabled = 1 AND runType = 'always'` on every request. |
| `code` | LONGTEXT | The actual snippet body. **Stores real newlines** — see newline gotcha below. |
| `original_code` | LONGTEXT | Pre-minification copy. Keep in sync with `code` on insert; the installer does this. |
| `codeType` | VARCHAR | `'php'`, `'css'`, `'js'`. Pick a template row of the matching type when cloning. |
| `conditions` | LONGTEXT (JSON) | Where/when the snippet runs (URL/role/etc). |
| `location` | LONGTEXT (JSON) | Frontend/admin scoping. |
| `tagOptions` | LONGTEXT (JSON) | Tags and grouping. |
| `hook` | LONGTEXT (JSON) | Hook config. Custom values like `custom_plugins_loaded` are mapped internally by WPCB to real WP hooks (`plugins_loaded`). Do not hand-author — clone from a known-good row. |
| `renderType` | VARCHAR | For CSS/JS: how the asset is emitted (inline, file, etc). |
| `minify` | TINYINT | Whether to minify on render. |
| `snippet_order` | INT | Sort order in the admin UI. |

CSS and JS rows store **raw code** in `code` — no `<style>` or `<script>` wrapper.

## Recipes

### List

```bash
wp db query "SELECT id, title, enabled, codeType, priority
             FROM {prefix}wpcb_snippets
             ORDER BY codeType, priority, id"
```

### Read one snippet's code

```bash
wp db query --skip-column-names \
  "SELECT code FROM {prefix}wpcb_snippets WHERE id = <N>"
```

Remember: batch-mode output escapes newlines as `\n`. Display artifact, not a DB problem. Confirm with the HEX recipe below.

### Confirm real-newlines-in-DB

```bash
wp db query --skip-column-names \
  "SELECT HEX(SUBSTRING(code, 1, 8)) FROM {prefix}wpcb_snippets WHERE id = <N>"
```

`0A` in the hex output → real newline in DB (good). `5C 6E` → literal backslash-n stored as text (something is wrong upstream).

### Authoritative backup

```bash
ssh user@host 'cd <wproot> && wp db export - --tables=<prefix>_wpcb_snippets' \
  > backups/wpcb_snippets.sql
```

Standard mysqldump escaping — re-imports cleanly. Always prefer this over per-row text exports for backups.

### Disable a snippet

```bash
wp db query "UPDATE {prefix}wpcb_snippets SET enabled = 0 WHERE id = <N>"
```

### Delete a snippet (when you need to re-run the installer for the same title)

```bash
wp db query "DELETE FROM {prefix}wpcb_snippets WHERE id = <N>"
```

### Clear Hummingbird page cache (after CSS/JS snippet change)

```bash
wp eval 'do_action("wphb_clear_page_cache");'
```

Required for CSS/JS snippets to be visible to visitors. Not required for PHP snippets that only affect AJAX/POST responses.

## Hook JSON — examples observed in the wild

These are illustrative only. **Do not copy these JSON blobs by hand into an INSERT**; clone an existing enabled row of the same `codeType` instead.

- `custom_plugins_loaded` → maps to WP `plugins_loaded` action.
- `custom_init` → maps to WP `init` action.
- `custom_template_redirect` → maps to WP `template_redirect` action.

The mapping happens inside WPCB's own bootstrap. The full set of supported `hook` values lives in the plugin source; if a new hook is needed, find an existing snippet using it and clone that row.
