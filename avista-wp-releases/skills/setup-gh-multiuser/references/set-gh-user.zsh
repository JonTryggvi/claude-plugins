# Avista multi-account gh switcher.
# Switches the active `gh` CLI account based on the current repo's origin remote.
# Substitute __PERSONAL_GH_USER__ and __AVISTA_GH_USER__ with the dev's real usernames
# before adding this to a shell config file (e.g. ~/.zsh/git.zsh or ~/.zshrc).
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
