---
name: avista-claude-design-overview
description: Overview of the avista-claude-design plugin — what it bundles, the list_projects blind spot it works around, and which skill to reach for. Use when the user asks "what does avista-claude-design do", "what's in this plugin", "how do I brand a report", "how do I get started", or right after installing the plugin.
---

# avista-claude-design — overview

Two skills for getting the org's Claude Design design systems out of claude.ai and onto a client-ready
document.

## The blind spot it works around

`DesignSync method:list_projects` **returns writable projects only** — its own documentation says
*"Filtered to writable projects only."*

Most org design systems are owned by a teammate and shared **view-only**, so they never appear there. The
symptom is misleading: you get a short, confident list that omits the system the user is looking straight at
in their browser, and it reads as "that system doesn't exist" rather than "I looked in the wrong place".

The workaround is that **all DesignSync read methods work on any accessible project when addressed directly
by `projectId`** — `get_project`, `list_files` and `get_file` don't care that `list_projects` skipped it.
So this plugin keeps a registry of ids, verifies them live, and never treats `list_projects` as the answer.

Measured on this org: `list_projects` returned one project, while the Avista Design System — invisible to it
— returned a full valid project and 70+ files when addressed by id.

## What's in the box

| Skill | What it does | When to use it |
|---|---|---|
| `fetch-design-systems` | Builds the list of reachable design systems from four sources (writable projects, a local id registry, a pasted share link, optional browser harvest), confirms each with `get_project`, and records new ids so the next run is instant. | "What design systems do I have?" · "Why can't you see the ÖRLÖ system?" · registering a new share link. |
| `brand-doc` | Picks a system, reads its real tokens and logo, writes the document as Markdown + self-contained HTML, and renders a PDF through headless Chrome so the system's webfont embeds properly. | "Brand this report" · "Make a client-facing PDF" · "Style this like RMK". |

## Getting started

1. Run **`/design-consent`** once if design reads aren't authorized yet (some builds call it
   `/design-login`).
2. **`/fetch-design-systems`** to see what's reachable. Anything listed under *known but not yet reachable*
   needs a `claude.ai/design/p/<UUID>` share link — the UUID is the project id, and it gets saved.
3. **`/brand-doc`** with your content. It'll ask which system if you haven't said.

## Registry

Candidate ids live in two places, live winning over shipped:

- `~/.claude/avista-claude-design/design-systems.json` — the live registry, survives plugin updates
- `skills/fetch-design-systems/references/design-systems.json` — the shipped seed, **overwritten on every
  plugin update**

Entries are hints, not facts. Every id is re-confirmed with `get_project` before use, because ids differ by
login and environment — one of the seeded ids already 404s on the account it was captured from.

## Requirements

- Design scope on the claude.ai login (`/design-consent`)
- Google Chrome, Chromium, Edge or Brave for PDF rendering
- Optional: `poppler` (`brew install poppler`) for `pdftotext`/`pdffonts` verification
