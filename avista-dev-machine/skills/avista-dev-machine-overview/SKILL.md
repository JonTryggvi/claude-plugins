---
name: avista-dev-machine-overview
description: Overview of the avista-dev-machine plugin — what it bundles, what each skill does, the order to run them in, and what is deliberately not covered yet. Use when the user asks "what does avista-dev-machine do", "what's in this plugin", "how do I set up a new Mac", "how do I onboard a new developer", "which setup skill do I run first", "how do I get started", or right after installing the plugin.
---

# avista-dev-machine — overview

Takes an Avista developer's Mac from nothing to shipping. Diagnose first, then two setup skills run in
order: the first makes the machine able to **write and push code**, the second makes it work **the way the
rest of the team works**.

Present this overview, then point the person at the right skill.

## What's in the box

| Skill | What it does | When to use it |
|---|---|---|
| `dev-machine-doctor` | **Read-only** scan of the whole machine — base tooling, shell config, `gh` accounts and token scopes, SSH reachability (which username each host greets), the agent layer, role tooling — then names the skill and part that closes each gap. Changes nothing. | **Start here, always.** Also the fastest answer to "why can't I push", "why did the release 403", or "the skill can't find my token". |
| `setup-dev-machine` | Base tooling (Xcode CLT/git, Homebrew, `gh`), a working shell config (`~/.zprofile` + `~/.zshrc` + `~/.zsh` modules with the team functions `gsend`, `set_gh_user`, `new_ssh_key`), SSH keys per GitHub account, `gh` multi-account auth, and git identity that switches itself per project. | **Once per machine.** Also the fix when `git push` or `gh release create` hits the wrong account or returns `403`. |
| `setup-agent-toolkit` | The agent layer: Claude Code on PATH, the Avista org marketplace and its plugins, the shared house rules in `~/.claude/CLAUDE.md`, the `~/.claude/.env` token store, and the Figma MCP choice. | **Once per machine, after the above.** Also the fix when a team skill reports a missing token or a newly installed skill "isn't showing up". |

## Recommended order

```
0. dev-machine-doctor    ← read-only; tells you which of the next two you actually need
1. setup-dev-machine     ← tooling, shell, SSH, gh accounts, git identity
2. setup-agent-toolkit   ← plugins, house rules, tokens, MCP
3. dev-machine-doctor    ← run again to confirm the gaps closed
   then: activecollab-setup (mints its own token), and the role plugins
```

On a half-configured machine — the common case, not the fresh-Mac case — the doctor usually turns a vague
"something's wrong" into one or two named gaps, and you skip most of the setup steps entirely.

## Two things that trip people up

- **A newly installed skill not appearing is a client-refresh problem, and the fix differs by client.**
  Claude Code CLI: `/plugin marketplace update` then `/plugin update`. Claude Desktop app: a full **⌘Q
  relaunch** — skills are indexed at app launch, a new chat does not re-index, and there are no `/plugin`
  slash commands. Ask which client before answering.
- **Token values are never handled by the assistant.** The person pastes them into their own `0600` file.
  Inspect that file by key name (`grep -oE '^[A-Z_]+' ~/.claude/.env`) — never `cat` it.

## Operating principles

The setup skills follow the same contract (the doctor writes nothing at all):

- **Ask once how to run it** — do the steps for them, or hand over commands to paste. Remember the answer.
- **Never clobber a config.** `~/.zprofile`, `~/.zshrc`, `~/.zsh/*`, `~/.claude/CLAUDE.md` are backed up to
  `~/.claude/backups/<timestamp>/` and merged section by section; only missing pieces get added.
- **Read-only checks run freely; changes are announced first** in one plain sentence, then confirmed.
- **Browser steps and secret pasting belong to the person**, never to the assistant.

## Not covered yet

Deliberately out of scope, so nobody assumes it's handled:

- **Installing the WordPress toolchain** — PHP 8 + Composer + phpunit, wp-cli, Node LTS via nvm, Docker
  Desktop, mkcert, and the `weasyprint`/`poppler` pair the `brand-doc` PDF render needs. The doctor
  *reports* which of these are missing and prints the `brew` line for each, but no skill installs them.
- **Per-site production access** — the `*.tempurl.host` SSH entries that `avista-wp-prod-ops` and
  `avista-wp-performance` need, plus 1Password CLI sign-in. The doctor counts the existing entries;
  adding one is still a manual edit. Note that `activecollab-setup` does install `op` in its own flow.

## More detail

See the plugin [README](../../README.md) for the file-by-file layout and the design decisions behind the
merge-not-clobber and secret-handling rules.
