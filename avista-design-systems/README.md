# avista-design-systems

Brand documents in the org's [Claude Design](https://claude.ai/design) design systems, rendered to a
client-ready PDF.

## Skills

| Skill | Purpose |
|---|---|
| `/fetch-design-systems` | List the design systems the login can reach; resolve any that don't enumerate. |
| `/brand-doc` | Read a system's tokens + logo, build the document, render a print-ready PDF via headless Chrome. |
| `/avista-design-systems-overview` | What's in the box and how the pieces fit. |

## Install

```bash
/plugin install avista-design-systems@avista
```

No authorization step to run first. The first DesignSync read raises the design-access prompt itself;
approve it inline and carry on. If that prompt never appears, `/design-consent` (or `/design-login` in some
builds) grants the scope manually.

## How branding works

1. **Pick a system** — `list_projects` covers everything the login can write to.
2. **Read its tokens** — `list_files` first, then detect `styles.css` → `colors_and_type.css` →
   `theme.json`. Filenames are never assumed, and neither is layout (see below).
3. **Honour the system** — its fonts, heading weights, tracking, radii, divider style, and the constraints
   written in its token-file comments (e.g. Avista's `--accent`: *"One per viewport max"*).
4. **Render with Chrome** — not reportlab or WeasyPrint, which won't fetch and embed the system's Google
   Font. `--virtual-time-budget` gives the font time to load before the print snapshot.
5. **Verify** — `pdftotext` for content, `pdffonts` for embedding. A fallback-font PDF looks fine in a file
   listing and wrong to anyone who knows the brand.

## Two things that bite

**`list_projects` is filtered to writable projects only.** A system shared *view-only* never enumerates, and
the failure is quiet — a short, confident list that omits the system you're looking straight at. Access and
enumeration are separate concerns: every read method works on such a system when addressed directly by
`projectId`.

```
list_projects            →  only what you can write to
get_project <any-id>     →  full read access, enumerated or not
```

No API lists view-only projects, so the id comes from a share link (`claude.ai/design/p/<UUID>` — the UUID
*is* the projectId) and gets recorded in `skills/fetch-design-systems/references/design-systems.json`, which
ships with the plugin so nobody resolves it twice.

**Token layouts differ.** Some systems put everything in one file; others use an *import barrel*:

```css
/* styles.css — every value lives one hop away */
@import url("tokens/fonts.css");
@import url("tokens/colors.css");
```

Parsing the entry file alone on the second kind yields zero tokens and a silently unbranded document.
`brand-doc` follows the chain — a `tokens/` directory is the tell.

## Known systems

| System | Layout | Logo | Notes |
|---|---|---|---|
| Avista Design System | single-file | `assets/avista_logo.svg` | Editorial. Manrope + JetBrains Mono |
| Avista Core Design System | import barrel → `tokens/` | `guidelines/wordmark.html` | Product/admin, full component library |
| RMK Design System | single-file | `assets/rmk-logo.png` | Raster — won't recolour |

## Output

- Default directory: the project's `production-notes/`
- Filename: `<Client>-<DocType>-<YYYY-MM-DD>.pdf`
- The Markdown source is kept alongside, so content stays editable without touching CSS

## Requirements

- Design scope on the claude.ai login — granted inline on the first DesignSync read
- Chrome, Chromium, Edge or Brave
- Optional: `brew install poppler` for render verification
