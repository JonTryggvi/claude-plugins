---
name: avista-design-systems-overview
description: Overview of the avista-design-systems plugin — what it bundles and which skill to reach for. Use when the user asks "what does avista-design-systems do", "what's in this plugin", "how do I brand a report", "how do I get started", or right after installing the plugin.
---

# avista-design-systems — overview

Two skills for getting the org's Claude Design design systems onto a client-ready document.

## What's in the box

| Skill | What it does | When to use it |
|---|---|---|
| `fetch-design-systems` | Lists the design systems the login can reach, confirms each with `get_project`, and resolves any that don't enumerate. | "What design systems do I have?" · "Is the ÖRLÖ system available?" |
| `brand-doc` | Reads a system's real tokens and logo, writes the document as Markdown + self-contained HTML, and renders a PDF through headless Chrome so the system's webfont embeds properly. | "Brand this report" · "Make a client-facing PDF" · "Style this like RMK". |

## Getting started

1. **`/fetch-design-systems`** to see what's reachable.
2. **`/brand-doc`** with your content. It'll ask which system if you haven't said.

There's no setup step. If design access isn't granted yet, the first DesignSync call raises the prompt
itself — approve it inline and carry on. `/design-consent` (or `/design-login` in some builds) is only the
manual fallback for when that prompt never appears.

## How to actually use it

You don't need the slash commands — plain requests trigger the skills. Both forms work.

**See what's available**

```
/fetch-design-systems
```
> Lists each system with writable/read-only status. Start here if you don't know what exists.

**Brand something you already have**

```
Brand production-notes/rmk-audit.md in the RMK design system
```
> Names the system, so it skips the picker. Reads RMK's tokens and logo, builds the HTML, renders the PDF,
> verifies the font embedded.

**Brand something without naming a system**

```
Turn these notes into a client-facing PDF report
```
> Lists the systems and asks which one, then proceeds as above.

**Point it at loose content**

```
Make a branded one-pager from the findings in this conversation — use Avista Core
```
> Content doesn't have to be a file. It writes the Markdown source first, then renders from that, so you can
> edit wording later without touching CSS.

**What you get back**

```
production-notes/RMK-Performance-Audit-2026-08-11.pdf   ← the deliverable
production-notes/RMK-Performance-Audit-2026-08-11.md    ← editable source
```

Filename is `<Client>-<DocType>-<YYYY-MM-DD>`. Say so up front if you want a different directory.

**Add a system that doesn't show up**

```
Add this design system: https://claude.ai/design/p/0632251e-f4fd-4411-8251-3f673d9f0471
```
> Confirms the id, detects its token layout and logo, and records it so the whole team gets it.

## Two things that bite

**`list_projects` is filtered to writable projects only.** A system shared *view-only* never enumerates, and
the failure is quiet — a short, confident list that omits the system the user is looking straight at. Access
and enumeration are separate: every read method works on such a system when addressed directly by
`projectId`. There's no API that lists them, so the id comes from a share link
(`claude.ai/design/p/<UUID>`) and gets recorded in `references/design-systems.json`, which ships with the
plugin so nobody resolves it twice.

**Token files are laid out two different ways.** Some systems put everything in one file
(`colors_and_type.css`); others use an *import barrel* where `styles.css` is nothing but `@import` lines and
the real values live in `tokens/*.css`. Parsing the entry file alone on the second kind yields zero tokens
and a silently unbranded document. `brand-doc` follows the import chain — a `tokens/` directory in
`list_files` is the tell.

## Known systems

Three, all verified and recorded in the registry:

| System | Layout | Notes |
|---|---|---|
| Avista Design System | single-file | Editorial. Manrope + JetBrains Mono, accent one-per-viewport |
| Avista Core Design System | import barrel | Product/admin, full component library, WordPress-compatible |
| RMK Design System | single-file | Raster logo — won't recolour |

## Requirements

- Design scope on the claude.ai login — granted inline on the first DesignSync read
- Chrome, Chromium, Edge or Brave for PDF rendering
- Optional: `poppler` (`brew install poppler`) for `pdftotext`/`pdffonts` verification
