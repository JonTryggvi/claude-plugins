---
name: avista-wp-algolia-chunker-overview
description: Overview of the avista-wp-algolia-chunker plugin — what it's for, the one rule that prevents oversized Algolia records, what its skill does, and when to reach for it. Use when the user asks "what does avista-wp-algolia-chunker do", "what's in this plugin", "how do I get started", or right after installing the plugin.
---

# avista-wp-algolia-chunker — overview

Keeps WordPress + Algolia records under Algolia's limits when a document is large — a long
post body, a denormalized search blob, or extracted PDF text (a 20–100 page PDF easily
exceeds Algolia's **100 KB hard per-record limit**, and anything over ~10 KB hurts relevance).

The whole plugin rests on **one rule**:

> **Big text → the chunked `content` path. Small fields → shared attributes.**
> `wp-search-with-algolia` already splits the `content` attribute into multiple
> `{post_id}-{i}` records with `distinct`. **Shared attributes are copied whole onto every
> chunk and are never split** — so a big value in a shared attribute is the one thing that
> can blow the 100 KB limit and get the whole record rejected (silently — the post just
> vanishes from search).

Present this overview, then hand off to the skill when the user is ready.

## What's in the box

| Skill | What it does | When to use it |
|---|---|---|
| `chunk-large-algolia-records` | Diagnoses oversized/missing Algolia records, applies the right fix (route long text through the chunked `content` path; keep the discrete searchable attribute bounded), and — for non-plugin or custom-attribute cases — ships a standalone word-boundary chunker that emits `{id}-{n}` `distinct` records. Includes a ready-to-use PHP helper. | Algolia record > 100 KB or rejected; a post missing from search; indexing a long PDF; any "split large records for Algolia" task. |

## Trigger phrases

"Algolia record too big / over 100KB / rejected" · "post missing from Algolia search" ·
"index a long PDF in Algolia" · "split large records" · "chunk content for Algolia" ·
"distinct search results / multiple records per document".

## More detail

See the plugin [README](../../README.md).
