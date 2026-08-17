---
name: setup-agent-toolkit
description: Set up the agent layer on an Avista Mac — Claude Code on PATH, the Avista org marketplace and its plugins, the shared global instruction file (~/.claude/CLAUDE.md), and the ~/.claude/.env token store that avista-figma-import, avista-activecollab and the release skills read. Use when the user says "set up my Claude tooling", "install the Avista plugins", "the Avista skills aren't showing up", "set up my tokens", "where does FIGMA_TOKEN go", "add my Figma token", "the figma-import skill can't find a token", "set up the global CLAUDE.md", "my new Mac has no plugins", or after setup-dev-machine when the machine has git and gh but no agent config. Run once per machine. Token values are pasted by the user and are never echoed, logged, or passed as process arguments.
---

# Set up the Avista agent toolkit

`setup-dev-machine` gets the machine able to *write and push code*. This skill gets it able to *work the
way the rest of the team works*: the Avista plugins installed, the shared house rules in place, and the
tokens the other skills read sitting in one file with the right permissions.

Run it once per machine, after `setup-dev-machine`. Re-run any single part later — every step detects what
is already there and only adds what is missing.

**You do not need to understand any of this to run it.** Explain each piece in one plain sentence before
doing it, do one thing at a time, and show the person what success looks like.

## How to run this (ask first)

Same contract as `setup-dev-machine` — offer the choice once and remember it:

> "I can do these steps for you, explaining each one and checking before anything changes your machine —
> or I can hand you the commands to paste yourself. Which do you prefer?"

**Read-only checks you can always just run.** Two things are *always* theirs to do and never yours:

- **Anything in a browser** — creating tokens, signing in.
- **Typing or pasting a token value.** You never type, echo, read back, or store a token value, and you
  never ask them to send you one in chat. Step 4 exists precisely so the secret goes from their clipboard
  into a `0600` file without passing through you or the shell history.

## Step 0 — What's already here

```bash
command -v claude && claude --version
echo "PATH has ~/.local/bin: $(case ":$PATH:" in *":$HOME/.local/bin:"*) echo yes;; *) echo NO;; esac)"
ls -la ~/.claude/CLAUDE.md 2>/dev/null || echo "no global CLAUDE.md"
[ -f ~/.claude/.env ] && { echo ".env exists, mode $(stat -f '%Lp' ~/.claude/.env), keys:"; grep -oE '^[A-Z_]+' ~/.claude/.env; } || echo "no ~/.claude/.env"
```

Report it back in plain language, then only do the parts that came back missing.

> `grep -oE '^[A-Z_]+'` prints **key names only, never values**. Use that form whenever you inspect this
> file. Never `cat ~/.claude/.env`.

## Step 1 — Claude Code on PATH

Check first — most Avista machines already have it, installed by the native installer into
`~/.local/bin/claude`.

If `command -v claude` found nothing, install per the official instructions at
`https://claude.com/claude-code` (the native installer is `curl -fsSL https://claude.ai/install.sh | bash`).

**The PATH gap that bites people:** the installer puts `claude` in `~/.local/bin`, which macOS does not
put on the PATH by default. If Step 0 said `PATH has ~/.local/bin: NO`, add it to the shell env module
that `setup-dev-machine` installed — idempotently, checking before appending:

```bash
grep -q '.local/bin' ~/.zsh/env.zsh 2>/dev/null \
  || printf '\n# Native installers (Claude Code, uv, pipx) land here.\nexport PATH="$HOME/.local/bin:$PATH"\n' >> ~/.zsh/env.zsh
```

If `~/.zsh/env.zsh` doesn't exist, the machine hasn't run `setup-dev-machine` yet — do that first, then
come back. Don't scatter PATH edits into `~/.zprofile` directly; the module is the one place they live.

Open a new Terminal, then `command -v claude` should print the path.

## Step 2 — The Avista marketplace and plugins

Explain plainly: "Plugins are how the team shares its skills. The marketplace is the list they come from."

Avista members usually receive the `avista` marketplace automatically through org settings. If they don't
have it, it can be added from the mirror repo:

```
/plugin marketplace add https://github.com/JonTryggvi/claude-plugins.git
```

Then install what they need:

```
/plugin install avista-dev-machine@avista
/plugin install avista-wp-releases@avista
/plugin install avista-memory-tools@avista
```

Add the rest by role — `avista-wp-prod-ops` and `avista-wp-performance` for anyone touching live sites,
`avista-activecollab` for anyone logging time, `avista-design-systems` and `avista-figma-import` for
design work, `avista-repo-audit` for anyone evaluating third-party code.

> **`/plugin` is an interactive terminal dialog.** It only works in an interactive `claude` session — it
> does not run from a script, and it isn't available in every client. If you are running this skill in a
> non-interactive or desktop context, hand the person the lines above to run themselves rather than
> attempting them.

### Making new skills actually appear — this differs by client

Installing a plugin does not always make its skills visible in the current session. **Check which client
they're in before telling them what to do**, because the wrong instruction is a dead end:

| Client | How to pick up new or updated skills |
|---|---|
| **Claude Code CLI** | `/plugin marketplace update` then `/plugin update` |
| **Claude Desktop app** | A **full quit and relaunch (⌘Q)**. Skills are indexed at app launch — opening a new chat does *not* re-index, and there are no `/plugin` slash commands to run. |

If someone reports "the skill isn't there" right after an install, this is almost always the cause. Ask
which client, then give the matching step.

## Step 3 — The shared global instruction file

Explain: "This file is the house rules — how we do git, how we format PHP and JavaScript, the WordPress
guards. It's loaded automatically in every session, on every project, so you don't have to repeat any of
it."

It belongs at `~/.claude/CLAUDE.md`. This skill bundles the team baseline at
`references/global-claude-md.template`.

- **No file there yet** — copy the template in.
- **A file is already there** — this one is hand-curated and often has personal sections. **Never
  overwrite it.** Back it up to `~/.claude/backups/<timestamp>/`, then show the person a diff of which
  baseline sections are missing from theirs and let them choose which to append. Append whole sections
  under their own headings; do not interleave or reword what they already wrote.

The template deliberately holds only the **shared** rules. Personal preferences, machine-specific paths
and account details stay out of it — those belong in each person's own additions to the file.

> Do not use `bootstrap-agent-md` (in `avista-memory-tools`) for this file. That skill generates
> *project-local* `CLAUDE.md` files from a codebase. The global file is curated, not generated.

## Step 4 — The token store (`~/.claude/.env`)

Explain: "Several team skills need an access token — Figma, ActiveCollab, GitHub. They all read one file,
locked so only you can read it."

Create it with restrictive permissions **before** anything goes in, so the file is never briefly readable:

```bash
mkdir -p ~/.claude
touch ~/.claude/.env
chmod 600 ~/.claude/.env
```

Confirm: `stat -f '%Lp %N' ~/.claude/.env` prints `600`.

### The tokens, and who reads them

Fill in only the ones the person's role needs. `references/env.template` has the same table as a
copy-pasteable skeleton.

| Key | Where it comes from | Which skills read it |
|---|---|---|
| `FIGMA_TOKEN` | `figma.com/settings` → **Personal access tokens** → Create new token, scope **File content (read)**. Starts `figd_`. Rotate every 90 days. | `avista-figma-import`; the Figma screenshot export in the global rules |
| `AVISTA_GITHUB_TOKEN` | `github.com/settings/tokens` → **Tokens (classic)**, scopes `repo` + `workflow`. Starts `ghp_`. | release skills that call the API directly |
| `ACTIVECOLLAB_URL` | Literal value `https://active.avista.is` — not a secret, safe to write directly | all `avista-activecollab` skills |
| `ACTIVECOLLAB_TOKEN` | **Don't hand-write this one.** Run `activecollab-setup`; it exchanges the 1Password-held login for a token and writes it here | all `avista-activecollab` skills |
| `EASY_CRON` | EasyCron account → API settings | scheduled-job checks |
| `LICHESS_TOKEN` | `lichess.org/account/oauth/token` — optional, personal | `avista-chess` |

> **Classic GitHub token, not fine-grained.** A `github_pat_`-prefixed token frequently cannot trigger
> release builds and surfaces as a `403`. Same rule as `setup-dev-machine` Part D.

### Getting a value into the file without it leaking

The value must not land in shell history, in your context, or in a process argument. Give the person
**one** of these two routes:

**Route A — they paste into their own editor (simplest, and the default):**

```bash
open -e ~/.claude/.env
```

They add one `KEY=value` line per token, save, close. Nothing passes through the shell or through you.

**Route B — prompted read, for anyone who prefers the Terminal.** They run this themselves; `read -rs`
keeps the value off the screen and out of history, and the heredoc keeps it out of the process list:

```bash
read -rs "?Paste FIGMA_TOKEN then press Enter: " v && (umask 077; printf 'FIGMA_TOKEN=%s\n' "$v" >> ~/.claude/.env) && unset v
```

Either way, verify by **name only**:

```bash
grep -oE '^[A-Z_]+' ~/.claude/.env
```

Never print the file's contents to confirm a token "looks right". If a token turns out to be wrong, the
fix is to revoke it at the source and issue a new one — not to inspect the stored value.

### Reading the file in a later session

Anything that consumes these tokens sources the file rather than exporting the keys globally:

```bash
set -a; . ~/.claude/.env; set +a
```

That is the form the global rules and the Figma export flow already use.

## Step 5 — MCP servers

**Figma** — when a design is open in the Figma desktop app, the team uses the **local `figma-desktop`
MCP**, never the cloud Figma MCP. The cloud one rate-limits immediately on a View seat and returns
`tool call limit` on the first call; the limit resets quarterly, so there is no useful wait. Confirm the
Figma desktop app is installed and running before any Figma work.

Other servers the team uses (GitHub, Slack, Atlassian, Linear, Notion, Cloudflare, ActiveCollab) are
OAuth-gated. **Their sign-in cannot be done from a non-interactive session** — the person authorizes them
in an interactive `claude` session or, for claude.ai connectors, in their claude.ai connector settings.
Say so plainly rather than attempting the flow. Never ask anyone for an authorization code, token, or
callback URL in chat.

## Step 6 — Check it all works

```bash
command -v claude && claude --version                 # Claude Code on PATH
ls ~/.claude/CLAUDE.md                                # house rules present
stat -f '%Lp' ~/.claude/.env                          # must print 600
grep -oE '^[A-Z_]+' ~/.claude/.env                    # expected key NAMES only
```

Then, in an interactive session, confirm the plugins resolve — typing `/avista` should cluster the
installed overview skills (`/avista-dev-machine-overview`, `/avista-wp-releases-overview`, …). If nothing
appears, it's the client-refresh step: **CLI** → `/plugin marketplace update`; **Desktop** → ⌘Q relaunch.

Report each result in plain language ("✅ your tokens are stored and locked to your account only").

## Edge cases

- **`claude` installed but not found in a new Terminal** — the `~/.local/bin` PATH line (Step 1) is
  missing or was added to a file that isn't sourced. Check `~/.zsh/env.zsh` and that `~/.zshrc` sources
  the `~/.zsh/*.zsh` loop.
- **`.env` exists at mode `644`** — it was created by hand without `umask`. `chmod 600` it and tell them
  the tokens in it were world-readable on a shared or backed-up machine; rotating them is the safe call.
- **Skill installed but not showing** — client refresh, per the Step 2 table. Ask which client first.
- **`~/.claude/CLAUDE.md` already long and personal** — merge by section with their approval; never
  replace. This is the common case on an existing machine, not an error.
- **Figma calls returning `tool call limit`** — they're on the cloud MCP. Switch to `figma-desktop` with
  the Figma app open.
- **No `~/.zsh/` directory** — `setup-dev-machine` hasn't run. Run that first.

## Bundled files

- `references/global-claude-md.template` — the shared house rules for `~/.claude/CLAUDE.md` (git
  workflow, sandbox detection, coding style, PHP/JS conventions, WordPress vendor guards).
- `references/env.template` — commented `~/.claude/.env` skeleton with a placeholder per token. Copy the
  structure; fill values per Step 4.

## Downstream

With this done the machine is ready for the role-specific plugins: `avista-figma-import` (needs
`FIGMA_TOKEN`), `avista-activecollab` (run `activecollab-setup` next to mint its token),
`avista-wp-releases` (needs the gh auth from `setup-dev-machine`), and `avista-wp-prod-ops` /
`avista-wp-performance` (need per-site SSH access, which is not yet covered by a skill — see the plugin
README).
