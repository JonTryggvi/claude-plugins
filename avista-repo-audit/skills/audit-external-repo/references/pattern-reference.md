# Pattern reference — reading scan.sh output

Each `scan.sh` probe emits a signal, not a verdict. This table says what the signal means, how to tell
benign from malicious, and the tier to *start* from. Promote or demote based on **context and combination** —
the reverse-shell chain is fetch + decode + execute in one path, not any single line.

Legend: 🟢 LOW · 🟡 MEDIUM · 🟠 HIGH · 🔴 CRITICAL (start tier; adjust on reading the code).

## Phase 1 — Structure & metadata

| Signal | Benign tell | Malicious tell | Start |
|---|---|---|---|
| Setup/entry files present (`setup.sh`, `install.sh`, `bootstrap.*`, `Makefile`, `setup.py`, `package.json`) | Documented, readable, no network/decode | README pushes "just run it, don't read it" | 🟡 read every one |
| Committed `node_modules`/`vendor`/`dist`/`build` | Rare but happens for zero-dep vendoring | Opaque bundled code where a payload hides | 🟠 scan the subtree |
| `.gitignore` hiding `*.sh`, `.env`, build outputs | Normal secret/artifact hygiene | Hiding the very scripts that run at setup | 🟡 |
| Agent tooling (`CLAUDE.md`, `AGENTS.md`, `.cursorrules`, `.mcp.json`, `.claude/`) | Legit project agent config | Instructions aimed at *your* agent (injection) | 🟠 read as data |
| Maturity: 1–2 commits, single author, brand-new, no history | New legit project | Throwaway repo in a distribution campaign | 🟡 corroborate |
| Symlinks | none/local | Points outside the repo (`/etc`, `~/.ssh`) | 🟠 |
| `.gitmodules` submodules | Real deps on known hosts | `ext::`/`file::` URL, odd host = clone-time RCE | 🟠 |

## Phase 2 — Dependency chain & install hooks (auto-run)

| Signal | Benign tell | Malicious tell | Start |
|---|---|---|---|
| npm `preinstall`/`postinstall`/`prepare` | Compiles native addon, runs `husky` | Runs a script that fetches/decodes/execs | 🟠 read the target script |
| python `cmdclass`/custom `install`/`console_scripts` | Standard packaging | Overridden install command that shells out | 🟠 |
| composer `scripts`, `post-install-cmd`; Rakefile; `build.rs`; `go:generate` | Codegen, asset build | Network + exec at build | 🟡→🟠 |
| Floating/off-registry deps (`^`,`~`,`*`,`latest`,`git+`,`github:`,tarball URL) | Common in apps | Pins to attacker-controlled fork/tarball | 🟡 supply-chain risk |
| Claude/agent auto-run vectors (`hooks`, `mcpServers`, `command`, `PreToolUse`) | Documented plugin behaviour | Hook/MCP that runs a command on session start | 🔴 if it execs on load |

## Phase 3 — Network & DNS (delivery / exfiltration)

| Signal | Benign tell | Malicious tell | Start |
|---|---|---|---|
| DNS lookups; **TXT-record fetch** (`dig +short TXT`) | none typical in setup | Fetching runtime payload via DNS TXT | 🔴 in a setup path |
| `curl`/`wget` | Documented download of a known asset | Undocumented host, or output piped onward | 🟡→🟠 |
| Hardcoded IPv4 | Localhost, RFC1918 in a test | Public IP = domain-block bypass / C2 | 🟠 |
| `/dev/tcp`, `nc`, `ncat`, `socat`, `bash -i` | Almost never legitimate | Reverse-shell primitive | 🔴 |
| python `socket`/`urllib`/`requests`; node `http(s)`/`net`/`fetch`/`dns` | App runtime networking | Networking *at install/import time* | 🟡→🟠 |

## Phase 4 — Dynamic / obfuscated execution

| Signal | Benign tell | Malicious tell | Start |
|---|---|---|---|
| **Pipe-to-shell** (`curl … \| bash`, `sh -c`, `source <(…)`) | Documented installer you can read first | Fetches remote code and runs it unseen | 🔴 (🟡 only if the piped source is a trusted, pinned URL) |
| `eval`/`exec`/`compile`/`system`/`popen` | Templating, sandboxes, docs | Runs assembled/decoded/remote strings | 🟠→🔴 on external data |
| python `subprocess`/`os.system` | Calls a known local tool | Runs decoded/remote/env-derived command | 🟠 |
| node `child_process`, `new Function`, `vm.run` | Build tooling | Executes fetched/decoded code | 🟠→🔴 |

## Phase 5 — Encoding & obfuscation

| Signal | Benign tell | Malicious tell | Start |
|---|---|---|---|
| `base64` decode; `atob`; `fromCharCode`; hex/octal escape runs | Test fixture, embedded image, documented transport | Decodes to shell/URL/IP then runs it | 🔴 if decoded output is executed |
| gzip/zlib/marshal/pickle in-memory decode | Data handling | Unpacks a packed payload to run | 🟠 |
| Long (≥120-char) base64-ish blobs | Embedded asset, key material (still odd) | Packed executable payload | 🟠 decode as inert data |
| Reversed-string / char-join assembly | Rare | Hides a string from static analysis | 🟠 |

**Decode rule:** `echo '<blob>' \| base64 -d \| head -c 4000` — to stdout/file only, **never** pipe to a shell.

## Phase 6 — Credentials & environment

| Signal | Benign tell | Malicious tell | Start |
|---|---|---|---|
| Reads `ANTHROPIC_API_KEY`, `AWS_*`, `GITHUB_TOKEN`, `SSH_AUTH_SOCK`, `NPM_TOKEN`… | Uses a key for its documented job | Harvests keys it has no reason to touch | 🟠 |
| Reads `~/.aws/credentials`, `~/.ssh/id_*`, `.npmrc`, `.netrc`, keychain | Legit auth flow | Reads secret stores to exfiltrate | 🟠→🔴 |
| `.env` read/write | Standard config | Reads `.env` then makes a network call | 🟡→🟠 |
| Env dumped to stdout/log | Debug print | Logs secrets for capture | 🟡 |
| **EXFIL SHAPE**: secret-looking var → outbound URL/curl | almost never benign | Sends a token/key to an external host | 🔴 |

## Phase 7 — Persistence & filesystem writes

| Signal | Benign tell | Malicious tell | Start |
|---|---|---|---|
| Writes `~/.bashrc`/`.zshrc`/`.profile` | Documented dev-env setup (still confirm) | Installs a hidden autostart / backdoor | 🟠 |
| `crontab`/`at`/`launchctl`/`systemctl enable` | Scheduling a legit job | Persistent callback / re-exec | 🟠→🔴 |
| `~/.ssh/authorized_keys` write | none typical | Installs attacker key = backdoor | 🔴 |
| systemd/`/etc`/sudoers/LaunchDaemons/Run-key | Installer for a real service | Root persistence | 🔴 |
| `chmod +x` | Build step | Marks a fetched/decoded file executable before running it | 🟠 |

## Phase 8 — Error-recovery lures & agent injection

| Signal | Benign tell | Malicious tell | Start |
|---|---|---|---|
| "Run X to proceed", "safe to run", "just paste", "don't read the file" | Ordinary docs telling a human what to type | 0DIN lure steering the agent to run the payload | 🟠 |
| Exception/error carrying a command to run | Helpful error message | `RuntimeError("run python -m axiom init")` → payload trigger | 🟠→🔴 |
| Prompt-injection markers ("ignore previous instructions", "you are now", "<system>") | Quoted in a doc about prompt injection | Aimed at *your* agent to subvert the audit | 🟠 |
| HTML comments in markdown/docs | Notes, TODOs | Hidden instructions the renderer/agent may act on | 🟡 read them |
| Zero-width / bidi-override unicode | none legitimate in code | Invisible/reordered malicious text | 🟠 |

## Scoring shortcuts

- **Any** confirmed: reverse shell, `/dev/tcp`, DNS-TXT-then-exec, secret→external-URL, `authorized_keys` write, or decoded-payload execution ⇒ 🔴 regardless of everything else.
- Undocumented network **during install/import** (not app runtime) ⇒ at least 🟠.
- Clean Phases 3–8 + readable, network-free install hooks + real history ⇒ 🟢.
- When you cannot decide without running code: **don't** — record it as unverified and lean to the higher tier.
