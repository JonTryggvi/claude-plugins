# ─── Git ──────────────────────────────────────────────────────────────────────
# Avista team git toolkit. Identity is filled in per developer — substitute
# these placeholder tokens before installing:
#   __FULL_NAME__        e.g. Jane Doe
#   __PERSONAL_EMAIL__   e.g. jane@janedoe.is
#   __AVISTA_EMAIL__     e.g. jane@avista.is
#   __PERSONAL_GH_USER__ e.g. JaneDoe
#   __AVISTA_GH_USER__   e.g. janeAvista

# Aliases
alias gs="git status"
alias ga="git add ."
alias gd="git branch -d "
alias gfd="git branch -D "
alias gc="git commit -m "
alias gu="git push --set-upstream origin "
alias gch="git checkout "
alias gitm="git checkout master || git checkout main"
alias gn="git checkout -b "
alias gp="git pull --ff-only"
alias gl="git log"
alias gcb="git branch -m "
alias gsp="git stash pop"

# ── Helpers ───────────────────────────────────────────────────────────────────

# Small random branch suffix, used by gdown when you don't pass a name.
random_string() { LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 8; echo; }

parse_git_branch() {
    # $HOME can't be a repo — skip the check to speed up new terminal tabs.
    [ "$PWD" = "$HOME" ] && return
    ref="$(command git symbolic-ref --short HEAD 2> /dev/null)" || return
    echo "$ref"
}

git_default_branch() {
  local url
  url="$(git remote get-url origin 2>/dev/null)" || return 1
  case "$url" in
    *github.com*) echo "main" ;;
    *)            echo "master" ;;
  esac
}

# ── User identity ─────────────────────────────────────────────────────────────
# Sets the git author name/email for the CURRENT repo based on its remote, so
# personal repos are committed as you-personal and Avista repos as you-at-Avista.

set_git_user() {
  local repository_base
  repository_base=$(git config --get remote.origin.url 2>/dev/null) || return 1
  case $repository_base in
    *"github.com"[:/]"__PERSONAL_GH_USER__"*)
      git config user.name "__FULL_NAME__"
      git config user.email __PERSONAL_EMAIL__
      ;;
    *"github.com-avista"[:/]"Avista"*|*"github.com"[:/]"Avista"*)
      git config user.name "__FULL_NAME__"
      git config user.email __AVISTA_EMAIL__
      ;;
    *)
      echo "Warning: No specific identity found for this repo URL."
      ;;
  esac
  echo "Git user set to: $(git config user.name) <$(git config user.email)>"
}

# Switches the active `gh` CLI account to match the current repo's remote, so
# `gh release create` / API calls hit the account that owns the repo.
set_gh_user() {
  local repository_base
  repository_base=$(git config --get remote.origin.url 2>/dev/null) || return 1
  local target_user=""
  case $repository_base in
    *"github.com"[:/]"__PERSONAL_GH_USER__"*)
      target_user="__PERSONAL_GH_USER__"
      ;;
    *"github.com-avista"[:/]"Avista"*|*"github.com"[:/]"Avista"*)
      target_user="__AVISTA_GH_USER__"
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

# ── Pull request helpers ──────────────────────────────────────────────────────

get_pull_request_page() {
  local repository_base
  repository_base=$(git config --get remote.origin.url)
  case "$repository_base" in
    *"github.com"*|*"github.com-avista"*)
      openGitHubRepositoryPullRq "$(parse_git_branch)"
      ;;
    *)
      : # no-op
      ;;
  esac
}

openGitHubRepositoryPullRq() {
    local remote_url="$(git config --get remote.origin.url)"
    local repo_path_with_git="${remote_url#*:}"
    local urlString="${repo_path_with_git%.git}"
    local branch_name="$1"
    local theUrl="https://github.com/$urlString/compare/$branch_name"
    echo "---"
    echo "Opening PR URL:"
    echo "Repo Path:  $urlString"
    echo "Branch:     $branch_name"
    echo "Final URL:  $theUrl"
    echo "---"
    open "$theUrl"
    echo "Opened $branch_name pull request page in browser."
}

# ── Workflow functions ────────────────────────────────────────────────────────

# Add and commit in one step.
gcommit(){ ga; gc "$1"; }

# Add, commit, push, and open the PR page.
# On a claude/* branch: squash-merges into the default branch and cleans up.
gsend() {
  local commit_msg="$1"
  local branch
  branch="$(parse_git_branch)" || { echo "gsend: not a git repo."; return 1; }

  set_git_user
  set_gh_user

  local has_changes=0
  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null \
     || [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
    has_changes=1
  fi

  if (( has_changes )); then
    [[ -z "$commit_msg" ]] && { echo "gsend: uncommitted changes but no commit message."; return 1; }
    ga
    gc "$commit_msg"
  fi

  if [[ "$branch" == claude/* ]]; then
    _gsend_merge_claude "$branch"
    return $?
  fi

  echo "Pushing to branch $branch"
  gu "$branch"
  get_pull_request_page
  echo "Done!"
}

# Internal helper — squash-merges a claude/* branch into the default branch.
_gsend_merge_claude() {
  local claude_branch="$1"
  local current_wt main_wt default_branch in_worktree=0 stashed=0

  current_wt="$(git rev-parse --show-toplevel)"
  main_wt="$(git worktree list | head -1 | awk '{print $1}')"
  [[ "$current_wt" != "$main_wt" ]] && in_worktree=1

  default_branch="$(git -C "$main_wt" symbolic-ref --short HEAD 2>/dev/null)"

  if [[ "$default_branch" == "$claude_branch" ]]; then
    default_branch="$(git_default_branch)"
    echo "Switching main worktree to $default_branch…"
    git -C "$main_wt" checkout "$default_branch" || return 1
  fi

  echo "Merging $claude_branch → $default_branch (squash)"

  if ! git -C "$main_wt" diff --quiet 2>/dev/null \
     || ! git -C "$main_wt" diff --cached --quiet 2>/dev/null; then
    echo "  Stashing changes in $default_branch…"
    git -C "$main_wt" stash push -m "gsend: pre-merge stash for $claude_branch" || return 1
    stashed=1
  fi

  if ! git -C "$main_wt" merge --squash "$claude_branch"; then
    (( stashed )) && git -C "$main_wt" stash pop
    echo "gsend: merge failed."
    return 1
  fi

  if ! git -C "$main_wt" commit --no-edit -m "feat: merge $claude_branch"; then
    (( stashed )) && git -C "$main_wt" stash pop
    echo "gsend: commit failed."
    return 1
  fi

  echo "  ✓ Merged $claude_branch → $default_branch"

  if (( in_worktree )); then
    cd "$main_wt" || return 1
    git worktree remove "$current_wt" --force 2>/dev/null
  fi
  git -C "$main_wt" branch -D "$claude_branch" 2>/dev/null
  git -C "$main_wt" worktree prune 2>/dev/null

  local stale
  stale="$(git -C "$main_wt" branch --list 'claude/*' | tr -d ' ')"
  if [[ -n "$stale" ]]; then
    echo "  Cleaning stale claude/* branches:"
    echo "$stale" | while read -r b; do
      if ! git -C "$main_wt" worktree list | grep -q "\[$b\]"; then
        git -C "$main_wt" branch -D "$b" && echo "    deleted $b"
      fi
    done
  fi

  if (( stashed )); then
    echo "  Restoring stashed changes…"
    git -C "$main_wt" stash pop \
      || echo "  Warning: stash pop had conflicts — resolve manually."
  fi

  cd "$main_wt" 2>/dev/null
  echo "Pushing $default_branch"
  gu "$default_branch"
  echo "Done!"
}

# Switch to the default branch, pull, and create a new branch.
gdown(){
  local branchname default_branch
  [ -z "$1" ] && branchname="$(random_string)" || branchname="$1"
  default_branch="$(git_default_branch)" || { echo "Not a git repo / no origin remote"; return 1; }
  git checkout "$default_branch" || return 1
  git pull --rebase || return 1
  git checkout -b "$branchname"
}

# ── git() wrapper — auto-corrects Avista remote URLs ─────────────────────────
# Rewrites git@github.com:Avista/… to git@github.com-avista:Avista/… so clones
# and remote-adds use the Avista SSH identity without you having to remember.
git() {
  local args=("$@")
  local i original_url repo_path new_url
  for (( i=1; i<=${#args[@]}; i++ )); do
    if [[ "${args[i]}" == "git@github.com:Avista/"* ]] || [[ "${args[i]}" == "git@github.com:avista/"* ]]; then
      original_url="${args[i]}"
      repo_path="${original_url#*:}"
      new_url="git@github.com-avista:${repo_path}"
      args[i]=$new_url
      echo "---"
      echo "Auto-correcting Avista remote URL:"
      echo "From: $original_url"
      echo "To:   ${args[i]}"
      echo "---"
      break
    fi
  done
  command git "${args[@]}"
}
