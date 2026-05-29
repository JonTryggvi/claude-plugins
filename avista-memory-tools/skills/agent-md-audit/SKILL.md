---
name: agent-md-audit
description: "Audit a CLAUDE.md or AGENTS.md file and classify each section as either a universal rule to keep, a workflow that should become a skill, personal context that belongs in memory, a duplicate to replace with a one-line pointer, or content to delete. Proposes a pruned version with reasoning per section, waits for approval, applies the prune with a timestamped backup. Use when the user says audit my CLAUDE.md, audit my AGENTS.md, review CLAUDE.md, what should I prune from CLAUDE.md, is anything in here a skill, clean up CLAUDE.md, is CLAUDE.md bloated, or after migrating workflow content into a new plugin and wanting to find what is now redundant. Works on the global ~/.claude/CLAUDE.md, any project-local CLAUDE.md, or any agent-instructions file with the same shape."
---

# Audit a CLAUDE.md for content that belongs elsewhere

CLAUDE.md content is loaded into context on every turn. Anything that doesn't apply to *every* interaction is paying a per-turn token cost it doesn't deserve. This skill finds those sections, classifies them, and produces a pruned version with a backup of the original.

The audit surfaces *what* should move and *where*. For MOVE-TO-SKILL sections, the move itself is a separate act the user performs later (building a skill is its own job). For MOVE-TO-MEMORY sections, the audit performs the migration during Step 6 — writing the memory file *before* pruning from CLAUDE.md — so that approving the prune cannot accidentally drop an operational fact on the floor.

## When to invoke

- The user explicitly asks for an audit ("audit my CLAUDE.md", "what should I prune", etc.).
- The user has just shipped a new plugin and might have stale workflow content in CLAUDE.md (e.g. instructions that duplicate what the plugin's skills now cover).
- A CLAUDE.md file is conspicuously long (over ~150 lines is a soft signal; over ~250 is a strong one).

Do not use this skill on files that are not CLAUDE.md (skill audits, project doc audits — out of scope).

## Workflow

Execute in order. Stop at the explicit checkpoint.

### Step 1 — Identify the target

Ask which CLAUDE.md to audit, or infer from context:

- `~/.claude/CLAUDE.md` — global, applies to every Claude session. Default if the user says "audit my CLAUDE.md" without specifying.
- `<project>/CLAUDE.md` — project-local. Default if the user is currently in a session with a project open and says "audit this project's CLAUDE.md".

Confirm the path with the user before proceeding.

### Step 2 — Read and section the file

Read the file. Parse it into sections by headings (`#`, `##`, `###`). For each section, capture the heading, its body text, and its line count.

If the file has no headings (rare — a flat prose document), section by paragraph blocks of related content. Flat CLAUDE.md files are usually small enough that this whole skill is overkill, in which case report that and stop.

### Step 3 — Classify each section

For each section, pick exactly one classification:

**KEEP** — applies to every interaction; concise; safety-critical or universally-useful.

Examples: a global coding-style rule ("Always use single quotes in PHP"), an interaction preference ("No apology, no sycophancy"), a tool-environment quirk that affects every session ("Never run git from the bash sandbox — use gsend").

**MOVE-TO-SKILL** — workflow instruction triggered conditionally rather than always. The content describes a *procedure* the user runs sometimes, not a *rule* that's always in effect.

Examples: "Here's how to wire up PUC for a new plugin" (this is what triggered the skill `setup-plugin-autoupdate`), "Here's the release flow" (triggers `release-plugin`). If the section contains a multi-step procedure, code block to copy, or "first do X then do Y" workflow, it's almost always a skill candidate.

**MOVE-TO-MEMORY** — personal context masquerading as a rule. Facts about the user, the project, or external systems that aren't actually instructions for Claude.

Examples: "I'm Jón Tryggvi, dev at Avista" (user memory), "The 2026 competition deadline is August 31" (project memory), "ActiveCollab is at activecollab.avista.is" (reference memory). These are *facts*, not *rules*, and they belong in the auto-memory store.

**Operational facts get special treatment** — they must always be MOVE-TO-MEMORY, never DELETE, and the memory migration in Step 6 is mandatory for them. These are facts the user needs to find *during an outage* and losing them silently is a real cost. Patterns to recognize:

- SSH/SCP command lines: lines beginning with `ssh `, `scp `, `mosh `, `rsync `, `mysql -h`, `psql -h`, `wp @<env>`, `wp-cli` over SSH.
- Production / live / staging host strings (anything looking like a hostname with the words `prod`, `live`, `staging`, `.host`, `.live`, `tempurl`, or an explicit environment context nearby).
- Credential pointers: "API key is in 1Password under X", "the production DB password is in Bitwarden", "WP admin pwd lives in `wp_options`".
- Sections under headings like "SSH", "Production", "Live", "Deployment", "Credentials", "Access", "Database", or any section whose body is mostly a copy-pasteable connection / login command.

When in doubt about whether something is an operational fact, **err toward MOVE-TO-MEMORY**. The cost of needlessly migrating a non-critical fact is one extra memory file; the cost of accidentally DELETEing an SSH string is digging through git history at 11pm during an incident.

**REPLACE-WITH-POINTER** — content that already lives elsewhere (in a plugin, in a memory file, in another CLAUDE.md) and exists here only as a duplicated copy. Replace with a one-line pointer.

Examples: the full PUC class implementation after `avista-wp-releases` ships (the skill bundles the template; CLAUDE.md just needs to say "the autoupdater scaffold lives in `avista-wp-releases:setup-plugin-autoupdate`"). The "WordPress Composer / vendor" guards if the conventions doc inside `avista-wp-releases` already covers them — replace with "see `avista-wp-releases:setup-plugin-autoupdate` references/conventions.md".

**DELETE** — outdated, never actually applies, or contradicts current practice.

Examples: a rule referencing a tool the user no longer uses. A reference implementation pointer to a project that's been deleted. A workflow that was replaced by a skill and the original CLAUDE.md copy is now strictly redundant (use DELETE rather than REPLACE-WITH-POINTER if there's no value in even pointing to the replacement).

### Step 4 — Present the classification

Show the user a table:

```
| Section heading | Lines | Classification | Reasoning | Target |
|---|---|---|---|---|
| Git Workflow | 8 | KEEP | Universal rule | — |
| Auto-Updater (GitHub Releases) | 64 | REPLACE-WITH-POINTER | Covered by avista-wp-releases plugin | avista-wp-releases:setup-plugin-autoupdate |
| (etc.) | | | | |
```

Then show the proposed new file in full — not as a diff, as the *new* contents. The user needs to see what stays, not just what goes.

### Step 5 — STOP and wait for approval

This is the load-bearing checkpoint. Do not write until the user explicitly approves. The user may want to:

- Override a classification (something flagged DELETE that they actually want to keep).
- Adjust the wording of a REPLACE-WITH-POINTER pointer.
- Defer the audit entirely and just see what was found.

If the user wants to defer, leave nothing modified and exit.

### Step 6 — Execute

After approval:

1. **Backup.** Create `~/.claude/backups/<ISO-timestamp>/` (use `date -u +"%Y-%m-%dT%H-%M-%SZ"` for the timestamp). Copy the original CLAUDE.md preserving the relative path inside the backup directory.

2. **Migrate MOVE-TO-MEMORY sections** to the appropriate memory store *before* pruning them from CLAUDE.md. For each MOVE-TO-MEMORY section:

   - **Pick a target location.** In order of preference:
     1. Cowork's auto-memory store (`~/Library/Application Support/Claude/local-agent-mode-sessions/<...>/spaces/<id>/memory/`) — use this when running in a Cowork session and the space is reachable.
     2. The project's local memory directory if it exists (e.g. `<project>/memory/`, `<project>/.claude/memory/`, `<project>/docs/`) — use this when auditing a project-local CLAUDE.md.
     3. Ask the user where to save it — only if neither of the above is reachable.
   - **Write the memory file.** Frontmatter with `name`, `description`, `metadata: type: <user|project|reference>`, then the section content as body. For Cowork auto-memory, also add the file to `MEMORY.md` per the auto-memory rules.
   - **Verify the write.** Read the file back. If the read fails or the content doesn't match what was written, treat the migration as failed.
   - **If migration fails or no target is reachable:** add the section to a "could-not-migrate" list. Do **not** remove this section from CLAUDE.md in the next step. Operational-fact sections (per the patterns in Step 3) must succeed migration or stay in CLAUDE.md — refuse to prune them blindly even if the user asked you to.

3. **Write the pruned CLAUDE.md.** All KEEP sections stay verbatim. MOVE-TO-MEMORY sections that migrated successfully are removed. MOVE-TO-MEMORY sections in the could-not-migrate list stay in place. REPLACE-WITH-POINTER sections are replaced with their one-line pointer. DELETE sections are removed. MOVE-TO-SKILL sections stay in CLAUDE.md (with the suggestion preserved in the Step 7 report) since the user builds those skills separately.

4. **Commit (if applicable).** If the target is a project-local CLAUDE.md and the project's working tree is clean apart from the audit's changes, commit with `chore: prune CLAUDE.md (audit + relocate content)`. Skip the commit if the tree was dirty. Do not push. Do not commit the memory file writes (those go to memory stores outside the repo).

If the target is `~/.claude/CLAUDE.md`, there is no repo to commit to — just write and report.

### Step 7 — Report

After execution:

- Backup directory path.
- New file's line count (vs. original — show the delta).
- Per-classification counts (how many KEEP / MOVE-TO-SKILL / MOVE-TO-MEMORY / REPLACE-WITH-POINTER / DELETE).
- **Memory migrations performed** — for each MOVE-TO-MEMORY section that was migrated, list the section heading and the full path to the memory file written. Make this section prominent in the report; the user should be able to scan it and confirm nothing critical was misplaced.
- **Sections left in place** (if any) — MOVE-TO-MEMORY sections that couldn't be migrated. Show what couldn't migrate, why (no target reachable, write failed, operational-fact safety hold), and what the user needs to do to handle them manually.
- The list of MOVE-TO-SKILL items as suggested next actions: "These sections were classified as skill candidates — build a skill for each one when ready, then re-run this audit to replace them with one-line pointers."

## Classification edge cases

**"This rule only applies when I'm working in PHP."** Still KEEP if it's terse and the user does PHP frequently. The token cost of "always use single quotes in PHP" is two lines per turn; the alternative (a skill that loads when PHP context is detected) is heavier infrastructure for thinner payoff. Lean toward KEEP for terse conditional rules. Lean toward MOVE-TO-SKILL when the conditional content is a multi-step procedure or includes code blocks longer than ~15 lines.

**"This is a safety rule but it's also pretty long."** Bias toward KEEP. The token cost of an always-loaded safety rule is justified by the cost of one missed application of it.

**"I'm not sure if this is a rule or just a preference."** Phrase test: rewrite the section as a single imperative sentence. If it reads as "always do X" or "never do X", it's a rule (KEEP or MOVE-TO-SKILL). If it reads as "I am the kind of person who does X" or "this project is the kind of project where X is true", it's a fact (MOVE-TO-MEMORY).

**"This section has both global rules and project-specific content mixed together."** Subdivide. Classify each sub-section independently. The output may move parts of one heading to different destinations.

## Refusal cases

Refuse and explain if:

- The target file does not exist. Don't create it; ask the user if they meant a different path.
- The target file is binary or appears corrupted. Tell the user what you saw and bail.
- The user asks to audit a file that isn't named CLAUDE.md (case-sensitive). Out of scope — suggest they ask in a normal conversation rather than via this skill.
