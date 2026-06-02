---
name: setup-dev-machine
description: Set up a new Avista developer's Mac end-to-end — base tooling (Homebrew, gh, git), a working shell config (~/.zprofile + ~/.zshrc + ~/.zsh modules with the team functions), SSH keys wired to the right GitHub account, gh multi-account auth, and git identity. A plain-language, hand-holding guide for teammates who aren't comfortable with git or SSH. Use when the user says "set up my computer for work", "set up my new Mac", "onboard my machine", "set up git and GitHub", "set up ssh", "configure my zprofile", "I can't push to GitHub", "fix gh 403 on release", or when a release skill fails because git/gh is on the wrong account.
---

# Set up an Avista developer's Mac

This guide takes a fresh (or half-configured) Mac and gets it ready to write and ship Avista code:
install the tools, set up the shell, create SSH keys, sign in to GitHub for both the personal and the
Avista account, and wire up the team helper commands. It usually takes about 15 minutes.

**You do not need to already know git or SSH.** This skill explains each piece in plain language as it
goes. Your job as the assistant running it is to be patient, explain *why* before *how*, do one thing at
a time, and show the person what a successful result looks like.

## How to run this (ask first)

Before touching anything, offer the person a choice and remember their answer for the whole session:

> "I can do the setup steps on your computer for you — I'll explain each one first and check with you
> before anything that changes your machine. Or, if you'd rather, I can give you the commands to copy and
> paste into the Terminal yourself. Which do you prefer?"

- **They want you to do it** (the friendly default for someone new): run the commands yourself. Before any
  step that *changes* their machine (installing software, writing a config file, creating a key), say in
  one plain sentence what it does and why, and wait for a yes.
- **They want to paste commands**: show one command at a time with a plain-language note, and tell them
  what they should see when it works.

Either way: **read-only checks** (looking at what's already installed) you can just run. A few steps *must*
happen in a web browser and only they can do them (creating a GitHub account, making a token, pasting an
SSH key into GitHub) — for those, give clear click-by-click directions.

**Never overwrite an existing config file.** If `~/.zprofile`, `~/.zshrc`, or files in `~/.zsh/` already
exist, back them up to `~/.claude/backups/<timestamp>/` first and only *add* what's missing.

## Part 0 — Who are you?

Collect and confirm (these get written into the shell config and SSH keys):

- **Full name** — for git commit authorship (e.g. `Jane Doe`).
- **Personal GitHub username + email** (e.g. `JaneDoe` / `jane@janedoe.is`).
- **Avista GitHub username + email** — username convention is `<firstname>Avista` (e.g. `janeAvista` /
  `jane@avista.is`). **Confirm it, don't assume.** If they don't have an Avista GitHub account yet, help
  them create one at `github.com/signup` first.

Explain plainly: "You'll have two GitHub accounts — your personal one and your Avista work one. We set the
Mac up so it automatically uses the right one depending on which project you're in, so you never push work
code from your personal account or vice-versa."

If the person only has one account, that's fine — skip the second key/login later; the setup still works.

## Part A — Base tooling

Check what's already there (read-only), then install what's missing.

1. **git / Xcode Command Line Tools** — `git --version`. If missing, `xcode-select --install` (opens a
   macOS installer dialog — they click through it). git comes bundled with it.
2. **Homebrew** (the macOS package manager) — `brew --version`. If missing, install per the official
   command at `https://brew.sh` (`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`).
   On Apple Silicon it lands in `/opt/homebrew`; the shell config in Part B puts it on the PATH.
3. **gh** (the GitHub command-line tool) — `gh --version`. If missing, `brew install gh`.
4. **Optional, offer don't force** — `oh-my-zsh` + `powerlevel10k` (a nicer prompt) and `nvm` (Node version
   manager). Only install if they want them; the shell templates work with or without.

On Linux (not the common case here): no Homebrew — install `gh` from `https://cli.github.com/` and use the
distro's package manager for git. The shell config below is macOS-flavored (Homebrew paths, Apple keychain).

## Part B — Shell config (detect + merge, never clobber)

The shell config lives in three places. Explain it simply: "`~/.zprofile` runs when you open a new
Terminal window and sets things up; `~/.zshrc` runs for every prompt; and `~/.zsh/` holds the actual
helper commands, split into small files."

This skill bundles templates in `references/`:

- `references/zprofile.template` → `~/.zprofile`
- `references/zshrc.template` → `~/.zshrc`
- `references/zsh/env.zsh`, `references/zsh/git.zsh`, `references/zsh/ssh.zsh` → `~/.zsh/`

**Before writing the team toolkit (`zsh/git.zsh`), substitute the identity placeholders** with the Part 0
values: `__FULL_NAME__`, `__PERSONAL_EMAIL__`, `__AVISTA_EMAIL__`, `__PERSONAL_GH_USER__`,
`__AVISTA_GH_USER__`. The other templates have no placeholders.

Install logic (idempotent):

- If `~/.zsh/` doesn't exist: create it and copy the three module files in.
- If a module already exists: back it up, then add only the functions it's missing (grep for
  `set_gh_user`, `new_ssh_key`, etc. before appending). Don't duplicate.
- If `~/.zprofile` / `~/.zshrc` exist: back up, then ensure the "source all `~/.zsh/*.zsh`" loop is present
  (grep for it). Don't replace their file — just add the missing loop if absent.
- If they're fresh: copy the templates straight in.

Then have them open a new Terminal (or `source ~/.zprofile`) so the helpers load. Verify with
`type gsend` — it should report `gsend is a shell function`.

## Part C — SSH keys

Explain plainly: "An SSH key is like a special ID card your computer shows GitHub to prove it's you, so you
don't type a password every time. We make one for each account."

The `new_ssh_key` helper (now loaded from `~/.zsh/ssh.zsh`) does the whole job per account — generates the
key, stores it in the Mac keychain, adds the matching entry to `~/.ssh/config`, and copies the public key
to the clipboard:

```
new_ssh_key avista  <avista-email>     # Avista account → host alias github.com-avista
new_ssh_key personal <personal-email>  # personal account (skip if single-account)
```

> The helper creates a host alias `github.com-<alias>`. Avista repos use `github.com-avista`, so pass
> `avista` as the alias for the work key.

After each key, the public key is on the clipboard. **Browser step (they do this):**

> 1. Go to `https://github.com/settings/keys` (signed in as the matching account).
> 2. Click **New SSH key**, give it a title (e.g. your computer's name), paste (⌘V), click **Add SSH key**.

Repeat signed in as the *other* account for the personal key.

Test (read-only): `ssh -T git@github.com-avista` should say `Hi <avista-username>!`; `ssh -T git@github.com`
should greet the personal one. A wrong name means the `~/.ssh/config` IdentityFile mapping needs a look.

## Part D — Sign in to GitHub on the command line (gh)

Explain: "`gh` is GitHub's command-line login. It needs its own sign-in, separate from the SSH key — this
is what lets you create releases. We sign in to both accounts."

For each account:

```
gh auth login --hostname github.com --git-protocol ssh
```

Choose **"Paste an authentication token"** and paste a **classic** token.

> **Use a classic token, not a fine-grained one.** A token is like a temporary password for apps. Make a
> classic one at `https://github.com/settings/tokens` (**Tokens (classic)** → Generate new token) with the
> **`repo`** and **`workflow`** boxes ticked. Classic tokens start with `ghp_`. If yours starts with
> `github_pat_` it's the fine-grained kind — it often can't trigger release builds (causes `403` errors),
> so make a classic one instead.

Do this for both the personal and the Avista account; `gh auth switch --user <name>` flips between them
(the `set_gh_user` helper does this automatically per project).

## Part E — Git identity

The `set_git_user` helper (in the toolkit) already stamps the right name/email per project based on the
repo's address — explain that they don't have to think about it. Optionally, set a global fallback for
repos that don't match either account:

```
git config --global user.name "<full name>"
git config --global user.email "<personal email>"
```

## Part F — Check it all works

In an Avista project folder:

```
set_gh_user                    # should say: switched to <avista-username>
gh api user --jq .login        # should print <avista-username>
git remote -v                  # should show a github.com-avista (or Avista) address
ssh -T git@github.com-avista   # should greet <avista-username>
```

In a personal project folder, the same checks should land on the personal account. Report each result in
plain language ("✅ your Avista account is connected and working"). If `gh auth switch` says the account
isn't logged in, go back to **Part D** for that account.

## Edge cases

- **One GitHub account only** — skip the second key and second login. The helpers no-op safely on repos
  they have no mapping for.
- **Already has a fine-grained token stored** (`gh auth status` shows `github_pat_…`) — warn it may not be
  able to create releases; offer to replace it with a classic token (Part D).
- **"Key is already in use"** when adding to GitHub — that key is on another account; make a fresh one with
  `new_ssh_key` and add that.
- **Populated shell config** — never overwrite; back up and merge only what's missing (Part B).

## Bundled files

- `references/zprofile.template`, `references/zshrc.template` — shell startup files.
- `references/zsh/env.zsh` — Homebrew/nvm/locale on the PATH.
- `references/zsh/git.zsh` — the team git toolkit (`gsend`, `set_git_user`, `set_gh_user`, the Avista
  `git()` URL auto-correct, PR helpers). Identity placeholders to substitute before install.
- `references/zsh/ssh.zsh` — `new_ssh_key` plus keychain/clipboard helpers.

## Downstream

Once this is done, the machine is ready for everyday work and for the `release-plugin` / `release-theme`
skills, which rely on the gh account auto-switching set up here.
