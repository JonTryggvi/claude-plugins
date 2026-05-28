---
name: bootstrap-agent-md
description: "Generate a project-local CLAUDE.md from the project's source — surveys structure, reads README and package manifests, scans recent commits, detects the project type, and proposes a CLAUDE.md covering architecture, conventions, workflows, and gotchas specific to that codebase. Use when the user says bootstrap CLAUDE.md, scaffold a CLAUDE.md, generate a project CLAUDE.md, this project needs a CLAUDE.md, set up CLAUDE.md for this repo, init agent-md, create CLAUDE.md from this project's source, or when joining an existing project that has no CLAUDE.md yet. Targets project-local CLAUDE.md files (loaded by both Cowork and Claude Code) — do not use to write the global ~/.claude/CLAUDE.md (that file is curated by hand, not generated). Pairs with agent-md-audit: bootstrap creates, audit prunes."
---

# Bootstrap a project's CLAUDE.md

Produce a project-local `CLAUDE.md` from what the project itself reveals — its structure, its docs, its package manifests, its recent history. The output is project-specific content that future sessions in this repo load automatically. Generic boilerplate is the failure mode; the skill exists to produce something the user wouldn't write by hand because it would be tedious, not to produce something a template could.

## When to invoke

- The user is starting work in a project that has no `CLAUDE.md` at the repo root.
- The user has joined an existing codebase and wants Claude to have proper context from session one.
- The user explicitly asks for bootstrap, scaffold, or "make a CLAUDE.md for this project."

Do not use this skill for:

- Writing the global `~/.claude/CLAUDE.md` — that file is hand-curated personal preferences, not project context. Out of scope.
- Editing an existing project `CLAUDE.md` that's already populated — route to `agent-md-audit` (for pruning) or to direct edits. This skill is for the empty-state case.
- Re-running on a project that already has `CLAUDE.md` — refuse and route to `agent-md-audit`.

## Workflow

### Step 1 — Identify the target project

Determine the project root. Typically the current working directory if running in Cowork (the mounted folder) or the repo root reachable from the current Claude Code session.

Confirm with the user: "Bootstrap a CLAUDE.md for `<project-path>`?" — get a yes before reading.

### Step 2 — Refusal check

If `<project-root>/CLAUDE.md` already exists, stop. Tell the user the file is present and route them:

- If they want to *update* it, suggest `agent-md-audit` (which prunes and reorganizes) or direct conversational edits.
- If they want to *replace* it from scratch, ask them to delete the existing file first as an explicit destructive action — never silently overwrite.

If the directory is not a git repo, warn but continue. CLAUDE.md works fine outside git; the user just loses the safety net of `git diff` to review your proposal.

### Step 3 — Survey the project

Read these in order, stopping when you have enough context to propose meaningful content:

1. **`README.md`** at the project root — the most condensed source of "what is this codebase, who is it for." Read this first.
2. **Package manifests** — pick the right one for the detected language ecosystem:
   - JavaScript / Node: `package.json` (look at `scripts`, `dependencies`, `name`, `description`)
   - PHP: `composer.json`
   - Python: `pyproject.toml`, `setup.py`, `requirements.txt`
   - Rust: `Cargo.toml`
   - Go: `go.mod`
   - WordPress plugin: the main `.php` file's header block
   - WordPress theme: `style.css` header block
3. **Top-level structure** — `ls` the project root. Look for `src/`, `lib/`, `includes/`, `tests/`, `docs/`, `.github/`. The presence/absence of each is a signal.
4. **In-repo docs other than README** — `DESIGN.md`, `ARCHITECTURE.md`, `RULES.md`, `CONTRIBUTING.md`, `REFACTOR-*.md` and similar. Many projects keep architecture notes in these. Read what's present.
5. **`.github/workflows/`** — CI/release pipelines reveal how the project ships.
6. **Recent commit history** — `git log --oneline -20` reveals current concerns, recent refactors, areas of active work.
7. **CLAUDE.md files in *parent* directories** if any — the user may have a higher-level CLAUDE.md that this project inherits from. Don't duplicate its content; reference it.

If the project is large or the survey turns up sparse signal, ask the user one or two targeted questions: "What does this project do?", "What's the main thing I'd be helping with here?", "Is there a non-obvious convention I should know?" Don't fabricate context from thin signal.

### Step 4 — Propose the CLAUDE.md

Compose a CLAUDE.md with these candidate sections — include only those that the survey gave you real material for. Skip a section entirely rather than fill it with vague filler.

**Project intro** — 1–3 sentences. What is this codebase, who is it for, what's the canonical purpose. Source: README, package manifest description, plus any disambiguation the user provided.

**Architecture** — the shape of the code. Where do major concerns live (`includes/`, `src/api/`, etc.). Key classes or modules and what they do. Any patterns used (strategy registry, repository pattern, plugin architecture). Source: top-level structure, README's architecture section if present, in-repo design docs.

**Workflows** — how to build, run, test, ship this codebase. Source: package manifest `scripts`, `.github/workflows/`, README "Development" or "Getting Started" sections.

**Conventions specific to this project** — anything non-obvious that the user's universal `~/.claude/CLAUDE.md` wouldn't already cover. Things like: file naming patterns, specific framework idioms used, the team's commit message format if it differs from the user's defaults. Source: existing code style, in-repo CONTRIBUTING or RULES docs.

**External system pointers** — production URL, deploy host, design files (Figma, etc.), project management (Linear, ActiveCollab, etc.). Source: README "Production" or "Deployment" sections, the user (ask), CI config.

**Gotchas** — non-obvious things that bit someone before. Source: in-repo docs that include "Why" or "Caveats" sections; recent commits with messages like "fix:" reveal what's been getting bitten. Ask the user to confirm any gotcha proposals — these are easy to misread.

**What this project does NOT need** to be in CLAUDE.md:

- Anything in the user's global `~/.claude/CLAUDE.md` (universal preferences, coding style, interaction rules). Reference the global file once if relevant: "Global rules apply per `~/.claude/CLAUDE.md`."
- Personal context about the user (that's memory, not CLAUDE.md).
- Tedious enumeration of every file in the project (that's what `ls` is for).
- Anything that's covered by a plugin/skill the project uses (reference the plugin instead).

### Step 5 — Present the proposal

Show the user the proposed `CLAUDE.md` in full — not as a diff (there's no existing file), as the *complete proposed content*. Below it, list:

- What sections you included and the signal for each ("Architecture: read from src/ structure and ARCHITECTURE.md")
- What sections you considered and skipped, and why ("Skipped Gotchas: no in-repo notes found, no obvious recent fix-pattern in commits — happy to add if you tell me what's bitten you")
- One open question per uncertainty ("The README mentions both `npm run build` and `npm run dev` — is one canonical?")

### Step 6 — STOP, wait for approval

Don't write until the user explicitly approves. This is a generative skill; first-draft accuracy is the load-bearing constraint, and the user is the only verifier.

The user may want to:

- Add or remove sections you proposed.
- Rephrase the project intro.
- Push back on a gotcha you misread.
- Defer entirely and just keep your proposal as a starting point they edit themselves.

Honor whichever response they give.

### Step 7 — Execute

After approval:

1. Back up nothing — there's no file to back up (refusal step caught the existing-file case).
2. Write `<project-root>/CLAUDE.md` with the approved content.
3. If the project is a git repo with a clean working tree, propose a commit: `chore: add CLAUDE.md`. Use `gsend` per the Avista convention (tell the user the command; the bash sandbox cannot run git). Do not auto-commit a dirty tree.

### Step 8 — Suggest follow-ups

After writing, tell the user:

- The file is loaded automatically by Cowork and Claude Code on the next session in this project.
- If the project gains a major component (new strategy, new pipeline, new external integration), come back and either rerun this skill (it'll refuse, route to audit) or edit by hand.
- `agent-md-audit` is the right tool for periodic pruning once the CLAUDE.md has been live for a while.

## Notes on quality

A good CLAUDE.md reads like a senior dev's mental model of the codebase, condensed. A bad one reads like generated boilerplate. Markers of generation that should be avoided:

- "This project uses modern best practices" — empty.
- "When working on this project, please follow established conventions" — instruction without content.
- "The code is organized in a typical X structure" — say what the structure *is*, or skip.
- Lists of files with one-line descriptions copy-pasted from comments — they go stale; reference patterns instead.

Better:

- "Game rules live in a per-mode Quiz CPT, resolved at session start via Regluvordur_Strategy_Registry. New game modes = new Quiz post + new strategy class." (concrete pattern, concrete extension point)
- "Production blocks `exec()`. Any tooling that shells out won't run there — use pure PHP." (specific gotcha, specific consequence)
- "SSH live host: `jontryggvi_ssh@regluvordur.tempurl.host`." (specific fact, no fluff)

If a section can't be that specific from the source material, skip it.

## Refusal cases

- Target directory has no readable files: ask if the path is right.
- Target is not a directory: refuse, ask for project root.
- CLAUDE.md already exists: refuse, route to agent-md-audit or manual edit.
- Survey turns up almost no signal (a single empty README, no manifests, no code): tell the user the project is too sparse to bootstrap meaningfully; ask them to either describe the project in prose or come back when there's more on disk.
