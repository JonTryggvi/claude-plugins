# avista-memory-tools

Maintenance tools for the agent-instructions, memory, and git-hygiene layers:

| Skill | What it does |
|---|---|
| `bootstrap-agent-md` | Generates a project-local CLAUDE.md from the project's source — surveys structure, reads README and package manifests, scans recent commits, and proposes a CLAUDE.md covering architecture, conventions, workflows, and gotchas specific to that codebase. Use on any project that doesn't have a CLAUDE.md yet. |
| `agent-md-audit` | Audits an existing CLAUDE.md (or any equivalent agent-instructions file) and classifies each section as keep, move-to-skill, move-to-memory, replace-with-pointer, or delete. Proposes a diff, waits for approval, executes with a timestamped backup. |
| `memory-health-check` | Lints an auto-memory store. Checks the `MEMORY.md` index against its 200-line/25KB load budget, frontmatter validity, wiki-link resolution, index-vs-filesystem consistency, staleness by `modified` timestamp, oversized topic files, duplicates, and sensitive or instruction-like content that shouldn't have been saved. Reports findings by severity; optionally fixes the mechanical issues with approval. |
| `pre-push-sync-check` | Checks whether the local branch is in sync with `origin/main` before a push or release — fetches the remote, compares HEAD, and reports ahead / behind / diverged / in-sync. Use before any push where shipping stale code or hitting a non-fast-forward push would be costly. |
| `release-skill-bundle` | Ships a new version of any Avista skill-bundle plugin to the org marketplace. Bumps `plugin.json` version, commits the source via `gsend`, repackages the plugin as a `.zip` with the correct wrapper-directory structure, and walks through the upload UI. Recursively applies to this plugin too — once `avista-memory-tools` is installed, this is the skill you'll use to ship its next version. |

## Why this exists

CLAUDE.md and memory both rot if left alone. CLAUDE.md accretes content that should have become a skill, a path-scoped rule, or a memory entry; memory accumulates stale project state, broken links to deleted entries, and quietly grows past the index load budget (200 lines *or* 25KB, whichever comes first — the byte limit usually bites first). Both kinds of decay are easy to fix once surfaced but tedious to find by hand, which means they get skipped.

Releasing skill-bundle plugins through the Avista org marketplace is also a multi-step procedure (version bump, source commit, rezip with the right wrapper-directory structure, manual upload) that needs to happen consistently across every plugin Avista ships. Without a skill, the procedure is something you remember imperfectly each time, and the consequences of getting the zip shape wrong are silent rejection at the marketplace ("Plugin validation failed" with no detail).

All of these skills turn what would otherwise be ad-hoc prompts into one-line invocations.

Plus an `avista-memory-tools-overview` skill — run `/avista-memory-tools-overview` (or ask "what does this plugin do?") to print this summary and how the skills fit together in-session.

## Conventions

- All skills are **propose-before-execute**. They show you the proposed change, wait for explicit approval, and only then write. No surprise edits.
- All skills **back up before modifying** (where there's something to back up). Edits go through `~/.claude/backups/<ISO-timestamp>/` first.
- `bootstrap-agent-md` **refuses to overwrite**. If CLAUDE.md already exists, it routes to `agent-md-audit` instead. Use the audit for pruning, the bootstrap only for empty-state.
- `agent-md-audit` and `memory-health-check` **classify, they don't relocate**. The audit skills tell you "this section should move to a skill" — they don't actually create the skill. Building the skill that absorbs the relocated content is a separate, deliberate act.
- `release-skill-bundle` **packages, it doesn't upload**. The .zip is produced in the outputs folder; the upload to the Avista marketplace is a manual browser step. The skill walks you through it but doesn't automate the click.

## When to invoke

- **`bootstrap-agent-md`** when joining a project that has no CLAUDE.md yet. One-shot per project — once CLAUDE.md exists, use `agent-md-audit` to refine it.
- **`agent-md-audit`** every few months on each project's CLAUDE.md, or any time a file starts feeling bloated. Also after migrating workflow content into a new plugin (the audit finds what's now redundant).
- **`memory-health-check`** monthly — light enough to be a habit, thorough enough to catch broken wiki-links, stale entries and a saved credential before they mislead a future session. Pairs with Anthropic's `consolidate-memory` skill — that one is a quarterly reflective pass; this one is a monthly linter.
- **`pre-push-sync-check`** before any push or release — a quick fetch-and-compare against `origin/main` so you don't ship stale code or hit a non-fast-forward push.
- **`release-skill-bundle`** every time you've edited a plugin's source and want the next version live for the Avista org.

## A note on which persistence layer

| Skill | Persistence layer | Where it writes |
|---|---|---|
| `bootstrap-agent-md` | Project CLAUDE.md | `<project>/CLAUDE.md` — loaded at the start of every session in that tree |
| `agent-md-audit` | Any CLAUDE.md | Same as input file |
| `memory-health-check` | Auto-memory | `~/.claude/projects/<project>/memory/` by default; honors `autoMemoryDirectory`; also lints a Cowork space store |
| `pre-push-sync-check` | n/a | Read-only — fetches and compares, writes nothing |
| `release-skill-bundle` | n/a | Builds `.zip`, doesn't persist anything |

The two layers answer different questions. CLAUDE.md is what *you* tell Claude and loads in full every session, so it pays a per-turn token cost and wants to stay under ~200 lines. Auto-memory is what *Claude* writes down for itself: only the `MEMORY.md` index loads at startup (200 lines or 25KB, whichever comes first), and topic files are read on demand.

Auto-memory exists in Claude Code — one store per git repository, shared across its worktrees, at `~/.claude/projects/<project>/memory/`. Earlier versions of this README claimed it was Cowork-only. That was wrong, and it meant the linter spent four months pointed at a path holding almost nothing.

The spec `memory-health-check` lints against — paths, limits, frontmatter fields, the four types, the sensitive-content categories — is pinned in `skills/memory-health-check/references/memory-spec.md` along with the date it was last checked against Anthropic's docs. Re-verify it there rather than trusting numbers quoted in a skill body.

## Installation

Upload `avista-memory-tools.zip` (the bundle from your outputs folder) through the Avista organization marketplace via the Anthropic admin UI. After install, updates propagate to all Avista members through the same channel on their next plugin sync.

## Companion skills

- `consolidate-memory` (Anthropic) — heavier quarterly reflective pass over the memory store: merge duplicates, retire dated files, fold lasting takeaways into durable ones, prune the index. Use after `memory-health-check` if the lint finds more than ~5 issues, or independently every 3 months.
- `import-memory` (Anthropic) — brings a memory export from another assistant into claude.ai's memory. Note that it targets a *different* store with a different taxonomy (`/profile.md`, `/areas/`, `/people/`, `/topics/`) than the one `memory-health-check` lints. Don't cross the two.
- `cowork-plugin-management:create-cowork-plugin` — guided plugin scaffolding from scratch. Use when starting a new Avista skill-bundle plugin; pair its output with `release-skill-bundle` from this bundle to ship the first version.
- `cowork-plugin-management:cowork-plugin-customizer` — customize an existing plugin if Avista's conventions evolve.
