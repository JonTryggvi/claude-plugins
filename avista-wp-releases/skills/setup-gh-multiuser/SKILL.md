---
name: setup-gh-multiuser
description: Onboard an Avista developer's machine for GitHub multi-account releases — set up `gh` CLI auth + SSH keys so `git push` and `gh release create` target the correct account based on the repo's remote. Use when the user says "set up gh accounts", "onboard my machine for Avista GitHub", "fix gh 403 on release", "set up ssh keys for github", "wire up set_gh_user", "configure github.com-avista", or when a release skill fails because `gh`/git is on the wrong account. Do not use for WordPress scaffolding (that's setup-plugin-autoupdate / setup-theme-autoupdate).
---

# Onboard a machine for Avista GitHub multi-account releases

Avista repos live under two GitHub accounts: each developer's **personal** account and the **Avista org**
account (username convention `<firstname>Avista`). Releases fail with `403` when the `gh` CLI is left on
the wrong account, and `git push` fails when the machine has no SSH key for the account that owns the repo.

This skill walks a developer through the full one-time setup, covering both auth layers a release depends on:

- **`gh` CLI auth** — a token per account, toggled automatically by a `set_gh_user` shell function that
  reads the repo's remote URL. This is what `gh release create` (used by `release-plugin` / `release-theme`)
  relies on.
- **git transport (SSH)** — a personal key on `github.com` and an Avista-org key wired to a
  `github.com-avista` Host alias in `~/.ssh/config`. That alias is what org remotes
  (`git@github.com-avista:Avista/<repo>.git`) and `set_gh_user` key off to pick the right identity.

## Operating mode — guide, don't mutate

**Run only read-only detection yourself** (`gh --version`, `gh auth status`, `ls ~/.ssh`, `ssh-add -l`,
reading config files, `ssh -T` tests). For **every mutating step** — `ssh-keygen`, `gh auth login`,
`gh ssh-key add`, editing `~/.ssh/config`, editing shell rc files — **present exact, copy-pasteable
commands or blocks for the user to run themselves.** Do not write to the user's home directory, generate
keys, or change their shell config on their behalf. This skill onboards *their* machine; they stay in control
of every change to it.

## Account mapping (Avista convention)

| Remote URL pattern | Account to use |
|---|---|
| `github.com[:/]<personal-username>/*` | personal account |
| `github.com-avista[:/]Avista/*` | Avista org account |
| `github.com[:/]Avista/*` | Avista org account |

## Workflow

### Part 0 — Gather identity

Ask for / confirm before anything else, because these values thread into every command block below:

- **Personal GitHub username** (e.g. `JonTryggvi`).
- **Avista org username** — convention is `<firstname>Avista` (e.g. `jontryggviAvista`), but **confirm it,
  don't assume**.
- **Email** to stamp on the SSH keys (the GitHub account email is fine).
- **A machine label** for SSH key titles (e.g. `jon-macbook-2024`) so keys are identifiable on GitHub.

### Part A — `gh` CLI auth (release creation)

**A1. Check `gh` is installed** — run `gh --version`. If missing:
- macOS (`uname` → `Darwin`): `brew install gh`
- Linux / other: point to `https://cli.github.com/` (no Homebrew).

**A2. Inventory accounts (read-only)** — run `gh auth status`. Parse which accounts are logged in and which
scopes each has. A usable account needs at minimum **`repo`** and **`workflow`**. Flag any account missing
`workflow` — that's the usual cause of a `403` when creating a release that triggers Actions.

**A3. Authenticate missing / under-scoped accounts** — for each account that's absent or missing scopes,
present the login flow for the user to run:

```
gh auth login --hostname github.com --git-protocol ssh
```

When it asks how to authenticate, choose **"Paste an authentication token"** and paste a **classic** PAT.

> **Use a classic PAT, not a fine-grained one.** Fine-grained tokens (`github_pat_…`) frequently lack the
> `workflow` scope and cause `403`s when a release fires the build workflow. Create a **classic** token at
> **https://github.com/settings/tokens** (Tokens → *Tokens (classic)*) with the **`repo`** and **`workflow`**
> scopes checked.
>
> **Prefix check:** a classic token starts with `ghp_` (accept it). If it starts with `github_pat_` it's
> fine-grained — reject it and have the user generate a classic one instead.

Repeat for both the personal and the Avista org account so both tokens are stored. `gh` keeps them
side-by-side and `gh auth switch --user <account>` toggles the active one.

### Part B — git transport over SSH

**B1. Detect existing keys & config (read-only):**

```
ls -la ~/.ssh
ssh-add -l
```

Read `~/.ssh/config` (if it exists) and check for an existing `Host github.com-avista` block. Note which
private keys (`id_ed25519*`, `id_rsa*`) are already present and loaded.

> **One key per account.** GitHub rejects a public key that's already registered to another account, so the
> two accounts need **two distinct keys** — a personal key and a separate Avista-org key.

**B2. Generate any missing key** — present the `ssh-keygen` command(s) for the keys the user is missing:

```
# Avista org key (only if absent)
ssh-keygen -t ed25519 -C "<email>" -f ~/.ssh/id_ed25519_avista

# Personal key (only if absent)
ssh-keygen -t ed25519 -C "<email>" -f ~/.ssh/id_ed25519
```

If they already have a personal `id_ed25519` registered to their personal account, keep it and only create
the org key. Add the new key to the agent:

```
ssh-add ~/.ssh/id_ed25519_avista
```

**B3. Upload each public key to its account.** `gh ssh-key add` uploads to the **currently active** `gh`
account, so the order matters — present the matched pair per account:

```
# Avista org key
gh auth switch --user <avista-username>
gh ssh-key add ~/.ssh/id_ed25519_avista.pub --title "<machine-label> (avista)"

# Personal key
gh auth switch --user <personal-username>
gh ssh-key add ~/.ssh/id_ed25519.pub --title "<machine-label>"
```

Web-UI fallback: paste the `.pub` contents at **https://github.com/settings/keys** while signed in as the
matching account.

> If `gh ssh-key add` returns *"key already in use"*, that public key is registered to a different account —
> generate a fresh key (B2) for this account and upload that instead.

**B4. Wire the `~/.ssh/config` alias.** Read `references/ssh-config-block.txt` from this skill bundle,
substitute the real `IdentityFile` paths, and present it for the user to append:

```
cat >> ~/.ssh/config <<'EOF'
<the substituted block>
EOF
```

The `github.com-avista` alias is mandatory — it's what `set_gh_user` and the org remotes match on.

**B5. Test transport (read-only):**

```
ssh -T git@github.com          # expect: Hi <personal-username>! …
ssh -T git@github.com-avista   # expect: Hi <avista-username>! …
```

If a line greets the wrong username, the `IdentityFile`/`IdentitiesOnly` mapping in `~/.ssh/config` is off —
revisit B4.

### Part C — `set_gh_user` shell function + `gsend` hook

**C1. Detect the shell config (read-only).** Read `$SHELL`, then check which of these exist:
`~/.zsh/git.zsh`, `~/.zshrc`, `~/.zprofile`, `~/.bash_profile`, `~/.bashrc`, `~/.profile`.

> **Placement:** `set_gh_user` is for *interactive* shells, so it belongs in `~/.zsh/git.zsh` (if the user has
> a modular zsh setup) or otherwise `~/.zshrc` — **not** `~/.zprofile`. `.zprofile` runs only at login and is
> for environment setup; a function defined there won't be available in new interactive terminals. (Check for
> `.zprofile` since it's a common file, but recommend the interactive file.) For bash, use `~/.bashrc`.

**C2. Inject the function (idempotent).** Grep the chosen file for an existing `set_gh_user` definition — if
it's already there, skip. Otherwise read `references/set-gh-user.zsh`, substitute `__PERSONAL_GH_USER__` and
`__AVISTA_GH_USER__` with the real usernames from Part 0, and present it for the user to append:

```
cat >> ~/.zsh/git.zsh <<'EOF'
<the substituted function>
EOF
```

**C3. Hook into `gsend` (if present).** Check whether the user has a `gsend` function defined in their shell
config. If they do and it does **not** already call `set_gh_user`, present a one-line edit adding the call
right after `set_git_user` (or at the top of the function if there's no `set_git_user`). If there is no
`gsend`, tell the user to run `set_gh_user` manually in the repo before any release command, or add it to
whatever commit/push alias they use.

**C4. Reload.** Tell the user to run `source <the file>` or open a new terminal so the function is live.

### Part D — Verify

From a known **Avista** repo directory:

```
set_gh_user
gh api user --jq .login     # should print the Avista org username
git remote -v               # should show a github.com-avista (or Avista) remote
ssh -T git@github.com-avista
```

From a **personal** repo directory, repeat with the personal account expected. Report pass/fail for each
case. If `gh auth switch` complains the target user isn't authenticated, loop back to **A3** — that account's
token was never stored.

## Edge cases

- **Single GitHub account.** Skip the second auth and second key. `set_gh_user` is still safe to install — it
  no-ops (prints a warning) on remotes it has no mapping for.
- **Linux.** No Homebrew — install `gh` from `https://cli.github.com/`. `ssh-keygen` is identical; clipboard
  helpers differ (`xclip`/`wl-copy` instead of `pbcopy`), but the web-UI fallback avoids needing one.
- **Pre-existing fine-grained PAT.** If `gh auth status` shows an account authenticated with a `github_pat_…`
  token, warn that it likely lacks `workflow` scope and offer to replace it: re-run `gh auth login` (A3) with
  a classic `ghp_` token.
- **Public key already in use.** GitHub returns a 422 if the key is registered to another account — generate
  a fresh key for this account (B2) and upload that.
- **`gh auth switch` fails** because the target user isn't authenticated — that account's token was never
  stored; go back to A3.

## Bundled files

- `references/set-gh-user.zsh` — the account-switch shell function, with `__PERSONAL_GH_USER__` /
  `__AVISTA_GH_USER__` placeholders.
- `references/ssh-config-block.txt` — the `~/.ssh/config` Host-alias template (`github.com-avista` + default
  `github.com`).

## Downstream

Once this is set up, `release-plugin` and `release-theme` can switch accounts during pre-flight and create
releases without `403`s. This skill is their prerequisite.
