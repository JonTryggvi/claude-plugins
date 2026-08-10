# avista-claude-design

Fetch the org's [Claude Design](https://claude.ai/design) design systems — **including the view-only ones**
— and brand documents with them, rendered to a client-ready PDF.

## Why this exists

`DesignSync method:list_projects` returns **writable projects only**. Design systems shared view-only (which
is how most org-default systems are shared) are invisible to it. That looks like the system doesn't exist,
when in fact every read method works on it as long as you address it by `projectId`:

```
list_projects            →  RMK Design System                      (writable, 1 result)
get_project <avista-id>  →  Avista Design System, 70+ files        (read-only, invisible to list_projects)
```

So discovery here never relies on `list_projects` alone. It unions four sources — writable projects, a local
id registry, a pasted share link, and an optional browser harvest — then confirms every candidate with
`get_project` before offering it.

## Skills

| Skill | Purpose |
|---|---|
| `/fetch-design-systems` | List reachable design systems, resolve new ones from a share link, maintain the id registry. |
| `/brand-doc` | Read a system's tokens + logo, build the document, render a print-ready PDF via headless Chrome. |
| `/avista-claude-design-overview` | What's in the box and how the pieces fit. |

## Install

Through the Avista marketplace:

```bash
/plugin install avista-claude-design@avista
```

Then authorize design reads once:

```bash
/design-consent
```

## How branding works

1. **Pick a system** — verified live, read-only is fine.
2. **Read its tokens** — `list_files` first, then detect `styles.css` → `colors_and_type.css` →
   `theme.json`. Filenames are never assumed; the two systems verified in this org both use
   `colors_and_type.css`.
3. **Honour the system** — its fonts, heading weights, tracking, radii, divider style, and the constraints
   written in its token-file comments (e.g. Avista's `--accent`: *"One per viewport max"*).
4. **Render with Chrome** — not reportlab or WeasyPrint, which won't fetch and embed the system's Google
   Font. `--virtual-time-budget` gives the font time to load before the print snapshot.
5. **Verify** — `pdftotext` for content, `pdffonts` for embedding. A fallback-font PDF looks fine in a file
   listing and wrong to anyone who knows the brand.

## Output

- Default directory: the project's `production-notes/`
- Filename: `<Client>-<DocType>-<YYYY-MM-DD>.pdf`
- The Markdown source is kept alongside, so content stays editable without touching CSS

## Registry

| Path | Role |
|---|---|
| `~/.claude/avista-claude-design/design-systems.json` | Live registry — new ids are appended here, survives plugin updates |
| `skills/fetch-design-systems/references/design-systems.json` | Shipped seed — **overwritten on plugin update** |

Registry entries are candidates, not facts: ids vary by login and environment, and every one is re-probed
with `get_project` before use.

## Requirements

- Design scope on the claude.ai login (`/design-consent`, or `/design-login` in some builds)
- Chrome, Chromium, Edge or Brave
- Optional: `brew install poppler` for render verification
