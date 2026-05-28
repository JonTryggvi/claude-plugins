# avista-memory-tools

Maintenance tools for the agent-instructions and memory layers. Three skills:

| Skill | What it does |
|---|---|
| `agent-md-audit` | Audits a CLAUDE.md (or any equivalent agent-instructions file) and classifies each section as keep, move-to-skill, move-to-memory, replace-with-pointer, or delete. Proposes a diff, waits for approval, executes with a timestamped backup. Replaces the ad-hoc audit prompts otherwise needed for this work. |
| `memory-health-check` | Lints the auto-memory store. Checks frontmatter validity, wiki-link resolution, MEMORY.md size and consistency, stale-date detection, duplicates. Reports findings by severity; optionally fixes the mechanical issues with approval. |
| `release-skill-bundle` | Ships a new version of any Avista skill-bundle plugin to the org marketplace. Bumps `plugin.json` version, commits the source via `gsend`, repackages the plugin as a `.zip` with the correct wrapper-directory structure, and walks through the upload UI. Recursively applies to this plugin too — once `avista-memory-tools` is installed, this is the skill you'll use to ship its next version. |

## Why this exists

CLAUDE.md and memory both rot if left alone. CLAUDE.md accretes content that should have become a skill or a memory entry; memory accumulates stale project state, broken links to deleted entries, and quietly grows past the 200-line context limit. Both kinds of decay are easy to fix once surfaced but tedious to find by hand, which means they get skipped.

Releasing skill-bundle plugins through the Avista org marketplace is also a multi-step procedure (version bump, source commit, rezip with the right wrapper-directory structure, manual upload) that needs to happen consistently across every plugin Avista ships. Without a skill, the procedure is something you remember imperfectly each time, and the consequences of getting the zip shape wrong are silent rejection at the marketplace ("Plugin validation failed" with no detail).

All three skills turn what would otherwise be ad-hoc prompts into one-line invocations.

## Conventions

- All skills are **propose-before-execute**. They show you the proposed change, wait for explicit approval, and only then write. No surprise edits.
- All skills **back up before modifying**. Edits go through `~/.claude/backups/<ISO-timestamp>/` first.
- `agent-md-audit` and `memory-health-check` **classify, they don't relocate**. The audit skills tell you "this section should move to a skill" — they don't actually create the skill. Building the skill that absorbs the relocated content is a separate, deliberate act.
- `release-skill-bundle` **packages, it doesn't upload**. The .zip is produced in the outputs folder; the upload to the Avista marketplace is a manual browser step. The skill walks you through it but doesn't automate the click.

## When to invoke

- **`agent-md-audit`** every few months, or any time a CLAUDE.md file starts feeling bloated. Also after migrating workflow content into a new plugin (the audit finds what's now redundant).
- **`memory-health-check`** monthly — light enough to be a habit, thorough enough to catch broken wiki-links and stale entries before they mislead future sessions. Pairs with the `consolidate-memory` skill (an Anthropic standard skill that ships with Cowork) — that one is a quarterly reflective pass; this one is a monthly linter.
- **`release-skill-bundle`** every time you've edited a plugin's source and want the next version live for the Avista org.

## Installation

Upload `avista-memory-tools.zip` (the bundle from your outputs folder) through the Avista organization marketplace via the Anthropic admin UI. After install, updates propagate to all Avista members through the same channel on their next plugin sync.

## Companion skills

- `consolidate-memory` (Anthropic, already installed in Cowork) — heavier quarterly reflective pass over the memory store. Use after `memory-health-check` if the lint finds more than ~5 issues, or independently every 3 months.
- `cowork-plugin-management:create-cowork-plugin` — guided plugin scaffolding from scratch. Use when starting a new Avista skill-bundle plugin; pair its output with `release-skill-bundle` from this bundle to ship the first version.
- `cowork-plugin-management:cowork-plugin-customizer` — customize an existing plugin if Avista's conventions evolve.
