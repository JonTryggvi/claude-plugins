---
name: fetch-design-systems
description: List the Claude Design design systems this login can reach, and resolve any that don't enumerate. Use when the user asks "what design systems do I have", "list our design systems", "which brands can I use", "is the <X> design system available", "why can't you see <X> design system", when they paste a claude.ai/design share link, or whenever another skill needs a design system picked before it can proceed.
---

# Fetch Claude Design systems

Produce a live list of the design systems the current login can read, so the user can pick one.

## The normal path

`DesignSync method:list_projects` — returns `name`, `projectId`, `updatedAt` for every project the login
can **write** to. For an org that keeps its design systems editable, this is the whole job.

Confirm anything you're about to use with `get_project`; it returns `canEdit` and the project `type`, which
is how you verify a candidate is really a design system (`PROJECT_TYPE_DESIGN_SYSTEM`) and not a regular
project.

## Design access

The reads need design scope on the login — but **don't front-load a consent step. Just make the first
read.** DesignSync raises the access prompt on its own first call, so the user approves inline and you carry
straight on. Only when a call *hard-fails* with an auth error instead of prompting is the manual route worth
mentioning: **`/design-consent`** (some builds name it `/design-login`). It's a one-time grant — don't loop
on it.

## When a system doesn't show up

`list_projects` is **filtered to writable projects only** — its own docs say so. A system shared *view-only*
never appears there, and the failure is quiet: you get a short, confident list that omits the system the
user is looking straight at in their browser, which reads as "it doesn't exist" rather than "I looked in the
wrong place".

The escape hatch is that **every read method works on any accessible project when addressed directly by
`projectId`** — `get_project`, `list_files` and `get_file` don't care that `list_projects` skipped it. Access
and enumeration are separate things: the login can usually *read* the system fine, it just can't *discover*
it.

There is no API that enumerates view-only projects. So when the user names a system that isn't in the list,
get its id from outside the API:

1. Ask for its share link. The UUID in `https://claude.ai/design/p/<UUID>` **is** the `projectId`.
2. `get_project` to confirm it resolves and is a design system.
3. Record it in `references/design-systems.json` so nobody resolves it twice — the file ships with the
   plugin, so a resolved id benefits everyone who installs it.

Say plainly that read-only is not a limitation for branding work — every read the job needs still works.
Otherwise "read-only" reads as "broken".

## Reading a system's shape

Once confirmed, `list_files projectId:<id>` and detect — **never assume filenames**, the layouts differ
materially between systems:

| What | How to find it |
|---|---|
| Token entry | First of `styles.css` → `colors_and_type.css` → `theme.json` |
| Real token values | If the entry file is only `@import` lines, the tokens are in the imported files — follow the chain (see `brand-doc`'s notes; this trips people up) |
| Logo | `assets/*logo*.svg` → `assets/*logo*.png` → a `guidelines/wordmark.html`-style page |

## Reporting back

A short table the user can pick from — name, and whether it's writable or read-only (from the live
`get_project` `canEdit`, not from a cached guess). If a known system is missing, say so and offer the
share-link route rather than leaving a silent gap.
