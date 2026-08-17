---
name: dev-machine-doctor
description: Read-only health check for an Avista Mac — reports what's installed vs missing across base tooling, shell config, GitHub identity (gh accounts, token scopes, SSH reachability), the agent layer (Claude Code, house rules, token store, plugins), and role tooling, then names the skill that fixes each gap. Use when the user says "check my machine", "is my setup right", "what's missing on this Mac", "why can't I push", "why did the release 403", "diagnose my dev setup", "the skill can't find my token", "audit my machine setup", or before onboarding help so you know what actually needs doing. Start HERE — it changes nothing, installs nothing, and tells you which setup skill to run. Never prints a token value.
---

# Dev-machine doctor

Diagnose first. This skill **changes nothing** — no installs, no config writes, no file creation — it just
reports the state of the machine and routes each gap to the skill that fixes it.

Run it before any setup work so you're fixing what's actually broken, and run it after so you can show the
person their machine is genuinely ready.

## Run it

The bundled scanner does every check in one pass:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/dev-machine-doctor/references/doctor.sh"
```

If that variable isn't set in the current client, run it from the plugin's install path, or paste the
script's contents into a shell. Add `--no-net` to skip the two SSH probes on a flaky connection:

```bash
bash .../doctor.sh --no-net
```

It always exits `0` — it's a report, not a gate. Read the output back to the person in plain language;
don't just paste the raw block at them.

## What it checks, and why each one matters

**1. Base tooling** — `git`, Homebrew, `gh`. Nothing else works without these.

**2. Shell config** — `~/.zprofile`, `~/.zshrc`, the three `~/.zsh` modules, the glob loop that sources
them, the four team functions, and `~/.local/bin` on PATH.

> The **module source loop** is the sharp one. A machine can have every module file present and still have
> no working `gsend` / `set_gh_user`, because nothing sources them. It looks configured and silently isn't.
> The check matches the glob (`/*.zsh`) rather than a fixed path, so all the quoting styles hit —
> `for _f in "$HOME/.zsh"/*.zsh`, `~/.zsh/*.zsh`, and so on.

**3. GitHub identity** — which `gh` accounts are logged in, whether the token carries the `workflow` scope,
the `github*` Host entries in `~/.ssh/config`, how many `*.tempurl.host` site entries exist, and an actual
`ssh -T` probe against `github.com` and `github.com-avista` reporting **which username each greets**.

> Token **scopes** are the signal, not the token string. `gh auth status` reports scopes without exposing
> the secret, and a missing `workflow` scope is the real cause of the `403` on release. The doctor never
> runs `gh auth token`.

**4. Agent layer** — `claude` on PATH, `~/.claude/CLAUDE.md`, the `~/.claude/.env` **mode** and **key
names**, the `avista` marketplace registration, and which plugins are installed. It flags the specific
expected keys that are absent (`FIGMA_TOKEN`, `ACTIVECOLLAB_TOKEN`, …) and what that breaks.

**5. Role tooling** — `php`, `composer`, `phpunit`, `wp`, `node`, `jq`, `rg`, `op`, `docker`, `weasyprint`,
`pdftoppm`. These are listed with an install hint, not counted as gaps — most people legitimately don't
need all of them. Only `jq` ships with current macOS; the rest are Homebrew installs. `rg` is genuinely
optional, since Claude Code brings its own search.

## Secret handling

Non-negotiable, and the reason this is safe to run in front of anyone:

- The token store is read with `grep -oE '^[A-Z_]+'` — **key names only**. The file is never `cat`ed and no
  value is ever printed, logged, or read into your context.
- If `~/.claude/.env` turns out to be mode `0644` instead of `0600`, that's reported as a real finding: the
  fix is `chmod 600` **and rotating** the tokens, because they were readable by anything running as another
  user and may have gone into a backup. Don't soften that.
- The doctor asks for no credential and reads no keychain.

## Reading the output

The summary lists each gap with the skill and part that closes it:

```
  · module source loop (functions never load)      → setup-dev-machine (Part B)
  · token store missing                            → setup-agent-toolkit (Step 4)
```

Route accordingly:

| Gap area | Fix with |
|---|---|
| Base tooling, shell config, SSH keys, `gh` auth, git identity | `setup-dev-machine` (Parts A–E) |
| Claude Code PATH, marketplace/plugins, house rules, token store | `setup-agent-toolkit` (Steps 1–4) |
| `ACTIVECOLLAB_TOKEN` absent | `activecollab-setup` — it mints the token itself |
| Role tooling missing | The install hint printed next to it |
| `*.tempurl.host` entries absent | Not yet covered by a skill — add the host block by hand |

**"No gaps found" means the checks passed, not that the machine is perfect.** Say it that way. The doctor
doesn't verify a build runs, that Figma desktop is open, or that OAuth-gated MCP servers are authorized —
those need an interactive session.

## Edge cases

- **`claude` reported present but a colleague says it's "not found"** — they're in a shell that hasn't
  re-read the PATH. Have them open a new Terminal. If it persists, it's the `~/.local/bin` gap.
- **`ssh` shows "no greeting"** — the key exists locally but isn't on that GitHub account, or the
  `IdentityFile` mapping in `~/.ssh/config` points at the wrong key. `setup-dev-machine` Part C.
- **`ssh` greets the *wrong* username** — the host alias maps to the other account's key. Common cause of
  pushing work code from a personal account; worth fixing immediately.
- **`avista-dev-machine` reported "not installed as a plugin"** — expected when running from a source
  checkout of the plugins repo. Not a problem.
- **Network unreachable** — the SSH probes report that and are skipped rather than failing the run. Use
  `--no-net` to skip them outright.
- **Both shell startup files missing** — the source-loop line reports `n/a` rather than adding a redundant
  gap; the missing files are already the finding.

## Bundled files

- `references/doctor.sh` — the scanner. Strictly read-only: no writes, no installs, no `cat` of the token
  store, no `gh auth token`. Exits `0` always. macOS/zsh-flavored (`stat -f`, Homebrew paths).
