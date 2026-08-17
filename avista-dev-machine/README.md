# avista-dev-machine

Onboarding a new Avista developer's Mac — from a fresh machine to one that can write, push and ship Avista
code the way the rest of the team does.

## Skills

| Skill | What it does |
|---|---|
| `dev-machine-doctor` | **Read-only** scan — base tooling, shell config, `gh` accounts + token scopes, SSH reachability, agent layer, role tooling — routing each gap to the skill that fixes it. Changes nothing. |
| `setup-dev-machine` | Base tooling (Xcode CLT/git, Homebrew, `gh`), shell config (`~/.zprofile` + `~/.zshrc` + `~/.zsh` modules with `gsend`, `set_gh_user`, `new_ssh_key`), SSH keys per GitHub account, `gh` multi-account auth, per-project git identity. |
| `setup-agent-toolkit` | Claude Code on PATH, the Avista marketplace + plugins, the shared `~/.claude/CLAUDE.md` house rules, the `~/.claude/.env` token store, and the Figma MCP choice. |
| `avista-dev-machine-overview` | Self-describing entry point — `/avista-dev-machine-overview`. |

Diagnose first, fix what the report names, then confirm:

```
/dev-machine-doctor        # read-only — tells you which of the next two you need
/setup-dev-machine
/setup-agent-toolkit
/dev-machine-doctor        # confirm the gaps closed
```

Most machines that "aren't working" are half-configured rather than fresh, so the doctor usually reduces
the job to one or two named gaps.

## Install

```
/plugin install avista-dev-machine@avista
```

## Why this is a separate plugin

`setup-dev-machine` previously lived in `avista-wp-releases`, where it was the "run this first"
prerequisite. That was the wrong home for two reasons: machine setup is not part of a release pipeline,
and everyone needs it whether or not they ever ship a WordPress release. It moved here in v0.1.0;
`avista-wp-releases` now cross-references it and covers only the release pipeline it is named for.

Skill names share a **flat namespace** in the desktop app, so the skill exists in exactly one plugin — it
was moved, not copied.

## Design decisions

**Diagnose before touching anything.** `dev-machine-doctor` is the entry point and writes nothing at all.
Machines that "aren't working" are almost always half-configured rather than fresh, so guessing at a fix
wastes the person's time and risks changing something that was fine. Same shape as `wp-perf-audit` in
`avista-wp-performance`: a read-only pass that names the gap and routes to the skill that closes it. Run it
again afterwards to prove the fix.

**Merge, never clobber.** Every file these skills touch (`~/.zprofile`, `~/.zshrc`, `~/.zsh/*.zsh`,
`~/.claude/CLAUDE.md`, `~/.claude/.env`) may already exist with content someone depends on. The skills back
up to `~/.claude/backups/<timestamp>/`, grep for what's already present, and append only what's missing.
Re-running any part is safe.

**The assistant never handles a secret.** Token values go from the person's clipboard into a `0600` file
via their own editor, or via a `read -rs` prompt they run themselves — so the value never enters the
assistant's context, the shell history, or the process list. Verification is by key *name*
(`grep -oE '^[A-Z_]+' ~/.claude/.env`); the file is never `cat`ed. Same discipline as
`avista-activecollab`'s password exchange.

**Plain language, one step at a time.** These skills are aimed at teammates who are not comfortable with
git, SSH or the Terminal. Explain *why* before *how*, announce anything that changes the machine, and show
what a successful result looks like.

**Client detection before advice.** "The skill isn't showing up" has two different fixes — `/plugin
marketplace update` in the Claude Code CLI, a ⌘Q relaunch in the Desktop app (which indexes skills at
launch and has no `/plugin` commands). Guessing wastes the person's time; ask which client.

## The PATH gap worth knowing about

The Claude Code native installer puts `claude` in `~/.local/bin`, which macOS does not put on the PATH.
`references/zsh/env.zsh` now exports it, so fresh machines are fine; `setup-agent-toolkit` Step 1 patches
existing machines idempotently. A machine where `claude` runs in one Terminal but "isn't found" in another
is almost always this.

## Bundled templates

```
skills/setup-dev-machine/references/
  zprofile.template, zshrc.template     shell startup files
  zsh/env.zsh                           Homebrew, ~/.local/bin, nvm, locale
  zsh/git.zsh                           team git toolkit — identity placeholders to substitute
  zsh/ssh.zsh                           new_ssh_key + keychain/clipboard helpers

skills/setup-agent-toolkit/references/
  global-claude-md.template             shared house rules for ~/.claude/CLAUDE.md
  env.template                          commented ~/.claude/.env skeleton (placeholders only)

skills/dev-machine-doctor/references/
  doctor.sh                             the read-only scanner (--no-net skips the SSH probes)
```

`zsh/git.zsh` carries identity placeholders — `__FULL_NAME__`, `__PERSONAL_EMAIL__`, `__AVISTA_EMAIL__`,
`__PERSONAL_GH_USER__`, `__AVISTA_GH_USER__` — substituted from the Part 0 answers before install. The
other templates have none.

`global-claude-md.template` holds only the rules that apply to **everyone**: git workflow, sandbox
detection, the dual-login account-identity trap, coding style, PHP/JS conventions, WordPress vendor
guards, and the Figma MCP choice. Personal preferences, machine paths and account details stay out, so the
baseline remains mergeable when the team updates it.

## Not covered yet

Named here so nobody assumes it's handled:

- **Installing the WordPress toolchain** — PHP 8, Composer, phpunit, wp-cli, Node LTS via nvm, Docker
  Desktop, mkcert, and the `weasyprint` + `poppler` pair `avista-design-systems`' `brand-doc` render needs.
  `dev-machine-doctor` *reports* which are missing and prints the `brew` line for each; nothing installs
  them. (Only `jq` ships with current macOS — `rg` does not, and is optional since Claude Code brings its
  own search.)
- **Per-site production access** — the `*.tempurl.host` SSH config entries `avista-wp-prod-ops` and
  `avista-wp-performance` assume, plus 1Password CLI sign-in (`activecollab-setup` installs `op` itself).
  Adding a host block is still a manual `~/.ssh/config` edit; the doctor only counts the entries already
  there.

## Downstream

| Then run | Because |
|---|---|
| `activecollab-setup` | Mints `ACTIVECOLLAB_TOKEN` into the `.env` this plugin created |
| `avista-figma-import` | Needs `FIGMA_TOKEN` and the `figma-desktop` MCP |
| `release-plugin` / `release-theme` | Need the `gh` multi-account auth from `setup-dev-machine` |
