---
name: memory-health-check
description: "Lint the Cowork auto-memory store. Validates frontmatter, resolves wiki-link references between memory files, checks MEMORY.md size and consistency against the filesystem, finds stale dates, detects duplicates and orphan files. Use when the user says check memory health, audit memory, lint my memory, review the memory store, find stale memories, is anything broken in memory, or as a monthly maintenance ritual. Reports findings grouped by severity first; applies fixes only with explicit per-category approval. Companion to the consolidate-memory skill, which is a deeper quarterly reflective pass; this skill is the lightweight monthly linter."
---

# Lint the auto-memory store

Find drift in the Cowork auto-memory store before it misleads a future session. Stale project state, broken wiki-links, MEMORY.md creeping past the 200-line truncation limit, orphan files that aren't in the index — none of these are critical alone, but they accumulate, and acted-on stale memory is worse than missing memory.

The skill is **report-first, fix-with-approval**. Findings come out as a categorized list. The user decides per-category whether to auto-fix, fix interactively, or leave for manual handling.

## When to invoke

- User asks explicitly for a memory audit/lint/health-check.
- Monthly cadence (the user can set a scheduled task that triggers this skill).
- After consolidating projects (an archived initiative leaves stale project memories behind).
- Before sharing the memory store across machines (catch broken state before sync).

Do not use when the user wants a deep reflective rewrite of memory — that's `consolidate-memory`'s job. This skill is a linter, not an editor.

## Workflow

### Step 1 — Locate the memory store

The memory store lives at:

```
~/Library/Application Support/Claude/local-agent-mode-sessions/<session-roots>/spaces/<space-id>/memory/
```

The current space's exact path is discoverable from the running session — Claude already has read/write access to it via the auto-memory system. If the path can't be determined from context, ask the user to confirm before proceeding.

If running outside Cowork (e.g. invoked from Claude Code on a machine where the user wants to audit a known memory directory), accept a path argument from the user.

### Step 2 — Inventory

List everything in the memory directory:

- `MEMORY.md` (index) — read it; record its line count.
- Every `*.md` file in the directory — record name, size, frontmatter.
- Anything that isn't a `.md` file — flag as unexpected.

### Step 3 — Run the checks

Run each check independently and collect findings. Don't stop at first error — collect everything.

**Check 1 — MEMORY.md size.** Count lines in MEMORY.md. The auto-memory system truncates entries after line 200. Findings:

- ≤150 lines: OK.
- 151-199: Warning. "Approaching the 200-line truncation limit — consider pruning low-value entries."
- ≥200: Error. "Entries after line 200 are not being loaded into context. Prune now."

**Check 2 — Frontmatter validity.** For each memory file, parse the YAML frontmatter and verify:

- `name:` present, kebab-case, matches the filename (e.g. `user-role.md` has `name: user-role`).
- `description:` present, non-empty, one line.
- `metadata.type:` present, exactly one of `user`, `feedback`, `project`, `reference`.

Findings are per-file errors with the specific failure ("missing description", "type is 'preference' which isn't valid", etc.).

**Check 3 — Wiki-link resolution.** For each `[[name]]` link in any memory file body, check that a memory file with `name: <linked-name>` exists in the same directory.

- Resolved link → OK.
- Broken link → Warning. "[[future-plans]] in project-regluvordur-roadmap.md does not resolve. Either create the linked memory or remove the link." (Note: broken links are intentional markers per the template's convention, so they are warnings, not errors. The user decides whether each one is a marker to keep or a typo to fix.)

**Check 4 — MEMORY.md ↔ filesystem consistency.** Parse `MEMORY.md` for every `[Title](file.md)` link in its list entries.

- Indexed file exists → OK.
- Indexed file missing → Error. "MEMORY.md references project-future-modes.md but that file is not in the directory."
- File exists but not in MEMORY.md → Warning. "user-favorite-foods.md exists but is not in the index. Add to MEMORY.md or delete the file."

**Check 5 — Stale dates.** Scan memory bodies for date patterns (ISO YYYY-MM-DD, or natural-language dates the user converted). For each date found in a `project` memory:

- ≤6 months old: OK.
- 7-12 months: Warning. "project-regluvordur-roadmap.md references 2025-11-15 — verify the state described is still current."
- >12 months: Error. "project-quiz-refactor.md references 2024-03-01 — almost certainly stale, consider archiving or rewriting."

For non-project memory types, only flag dates >24 months as warnings — those memories are usually less time-sensitive.

**Check 6 — Duplicate detection.** Compare memory bodies pairwise. For any two memories whose bodies share substantial overlapping content (e.g. >50% of substantive sentences match), flag as warning. "user-environment.md and user-workflow.md both describe the Cowork bash sandbox quirk — consider merging."

A lightweight heuristic is fine; this isn't expected to be perfect. False positives are acceptable as warnings; the user reviews.

**Check 7 — Type discipline.** Verify that each memory's body matches its declared type, using the type definitions from MEMORY-TEMPLATE.md:

- `user` memories are descriptive facts about the user. Flag if the body reads as a rule for Claude ("always do X").
- `feedback` memories should have a "Why:" or "How to apply:" structure. Warn if neither phrase appears.
- `project` memories should be dated. Warn if no date is present.
- `reference` memories should point to external resources. Warn if the body has no URL, path, or system name.

These are soft signals — warnings, not errors. The user reviews.

### Step 4 — Report

Group findings by severity:

```
ERRORS (n) — load-bearing issues, fix before they cause confusion
  - [file]: [issue]
  - ...

WARNINGS (n) — drift or accumulating debt, review at your leisure
  - [file]: [issue]
  - ...

OK (n checks passed)
```

If zero errors and zero warnings, report "Memory store is clean" and stop.

### Step 5 — Offer fixes

For categories with auto-fixable items, ask the user per-category whether to fix:

- **MEMORY.md size errors** — offer to prune to ≤200 lines by suggesting which entries to remove (lowest signal/highest staleness first). Show the suggested removals before applying.
- **Orphan files (file exists but not in index)** — offer to add to MEMORY.md with a generated one-line hook (derived from each file's `description:` frontmatter).
- **Broken MEMORY.md → file references** — offer to remove the stale index entries. Do not auto-create missing memory files.
- **Frontmatter errors** — offer to fix per-file with the user's confirmation of each correction. Some errors (missing `name:` field) are mechanically fixable; others (typo in `metadata.type:`) need the user to specify the intent.

Do not auto-fix:

- Broken wiki-links (might be intentional markers).
- Stale dates (the memory body might still be correct; only the user knows).
- Duplicate-detection warnings (consolidation is a judgment call).
- Type-discipline warnings (rewriting the body is `consolidate-memory`'s job).

For these, just leave them in the report for the user to address manually.

### Step 6 — Execute and re-report

If the user approved any fixes, apply them with a timestamped backup of the affected files at `~/.claude/backups/<ISO-timestamp>/memory/`. Then re-run checks 1-4 (the cheap ones) to verify the fixes landed and report the new state.

If nothing was approved, just exit.

## Notes on what's not in scope

This skill does *not*:

- Rewrite or merge memory bodies (use `consolidate-memory`).
- Verify that memory content is *factually correct* against the current codebase or external systems (would require live source-of-truth queries; too expensive for a routine lint).
- Sync the memory store to a backup location (would be a separate `memory-backup` skill — not in this bundle yet).
- Migrate memories between spaces (cross-space migration is manual and rare enough that automation would be overkill).

## Refusal cases

- The memory directory does not exist or contains no `.md` files: report "No memory store found at [path]" and stop. Do not create one.
- The memory directory is at a path the user can't normally access (sandbox restriction, missing permissions): report the error and suggest the user run the skill from a different context.
