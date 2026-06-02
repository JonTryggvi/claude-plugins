# Handoff: Build `setup-gh-multiuser` skill

## Context

Avista team members who use the `release-theme` and `release-plugin` skills run into a recurring
problem: the `gh` CLI defaults to whichever GitHub account was last active, causing 403 errors
when creating releases. The fix is to auto-switch `gh` to the correct account based on the repo's
remote URL — but new team members don't have this set up at all.

This skill should walk any Avista developer through the full setup in one Claude session.

## What already exists (do not duplicate)

In `jontryggvi`'s personal shell config (`~/.zsh/git.zsh`) there is a working `set_gh_user()`
function and it is called from `gsend`. That implementation is the reference — the skill should
produce equivalent behaviour for any team member regardless of their shell setup.

The `release-theme` and `release-plugin` skills in this repo already instruct Claude to call
`gh auth switch --user <account>` during pre-flight based on the remote URL pattern. Those skills
are the downstream consumers — this setup skill makes sure the accounts exist to switch between.

## Account mapping (Avista convention)

| Remote URL pattern | `gh` account to use |
|---|---|
| `github.com[:/]JonTryggvi/*` | personal account (e.g. `JonTryggvi`) |
| `github.com-avista[:/]Avista/*` | org account (e.g. `jontryggviAvista`) |
| `github.com[:/]Avista/*` | org account |

Each team member's personal GitHub username will differ — the skill must ask for it or detect it.
The Avista org account username follows the pattern `<firstname>Avista` but should be confirmed
during setup rather than assumed.

## Skill to build

**Name:** `setup-gh-multiuser`
**Location:** `skills/setup-gh-multiuser/skill.md` (or `SKILL.md` — match convention of siblings)
**Plugin:** `avista-wp-releases` (same plugin, new skill entry in `plugin.json` or equivalent)

### Steps the skill must perform

1. **Check `gh` is installed.**
   - If not: `brew install gh` (macOS) or surface the install URL for other platforms.

2. **Inventory authenticated accounts.**
   - Run `gh auth status` and parse which accounts are present and which scopes they have.
   - A valid account needs at minimum: `repo`, `workflow` scopes (classic PAT or OAuth with those scopes).
   - Flag any account with missing scopes.

3. **Authenticate missing accounts.**
   - For each missing account (personal + Avista org), guide the user through `gh auth login`.
   - Classic PAT is preferred over fine-grained PAT — fine-grained PATs (`github_pat_*`) often
     lack `workflow` scope and cause 403s on release creation. The skill must explicitly warn about
     this and direct the user to `github.com/settings/tokens` (legacy URL → classic token page).
   - Token prefix check: classic = `ghp_`, fine-grained = `github_pat_`. If the user pastes a
     `github_pat_` token, reject it and explain why.

4. **Inject `set_gh_user` into the user's shell config.**
   - Detect shell: `$SHELL` → `zsh` or `bash`.
   - Detect config file: check for `~/.zsh/git.zsh` (modular setup), then `~/.zshrc`, then
     `~/.bash_profile` / `~/.bashrc`. Prefer the most specific file.
   - Check if `set_gh_user` already exists in the file — skip injection if it does.
   - Write the function with the user's actual account usernames substituted in (not hardcoded
     `JonTryggvi` / `jontryggviAvista`).
   - The function should mirror this logic:
     ```zsh
     set_gh_user() {
       local repository_base
       repository_base=$(git config --get remote.origin.url 2>/dev/null) || return 1
       local target_user=""
       case $repository_base in
         *"github.com"[:/]"<PERSONAL_GH_USER>"*)
           target_user="<PERSONAL_GH_USER>"
           ;;
         *"github.com-avista"[:/]"Avista"*|*"github.com"[:/]"Avista"*)
           target_user="<AVISTA_GH_USER>"
           ;;
         *)
           echo "Warning: No gh account mapping for this remote URL."
           return 0
           ;;
       esac
       local current_user
       current_user=$(gh api user --jq .login 2>/dev/null)
       if [[ "$current_user" != "$target_user" ]]; then
         gh auth switch --user "$target_user" 2>/dev/null \
           && echo "gh: switched to $target_user" \
           || echo "Warning: could not switch gh to $target_user"
       fi
     }
     ```
   - After writing, instruct the user to `source` the file (or open a new terminal).

5. **Hook into `gsend` (optional).**
   - Check if the user has a `gsend` function defined anywhere in their shell config.
   - If yes: check if it already calls `set_gh_user`. If not, add the call after `set_git_user`
     (or at the top of the function if `set_git_user` isn't present).
   - If no `gsend`: inform the user that they should call `set_gh_user` manually before running
     release commands, or add it to whatever commit/push workflow they use.

6. **Verify.**
   - From a known Avista repo directory, run `set_gh_user` and confirm the correct account is
     active via `gh api user --jq .login`.
   - From a personal repo directory, do the same.
   - Report pass/fail for each.

### Edge cases to handle

- User only has one GitHub account — skip the second auth step, note that auto-switching is a
  no-op but the function is still safe to have.
- User is on Linux — `brew` won't work; surface `https://cli.github.com/` instead.
- User has a fine-grained PAT already stored — warn, explain the `workflow` scope limitation,
  offer to replace it with a classic PAT.
- `gh auth switch` fails because the target user isn't authenticated — loop back to step 3.

## Related files

- `skills/release-theme/skill.md` — pre-flight step references `gh auth switch`; this skill is
  the prerequisite.
- `skills/release-plugin/SKILL.md` — same.
- `jontryggvi`'s `~/.zsh/git.zsh` — reference implementation of `set_gh_user` and `gsend`
  integration (not in this repo, but available in their local environment).
