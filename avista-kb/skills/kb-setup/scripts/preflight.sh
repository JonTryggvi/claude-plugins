#!/usr/bin/env bash
# Read-only setup check for avista-kb. Prints key=value lines; changes nothing.
#   tools        git, gh, python3 present (missing ones listed)
#   gh_login     the active gh account, or none
#   gh_sees_kb   yes/no: can the active gh account see Avista/avista-knowledge-base
#   gh_accounts  every logged-in gh account (to switch to the org one if needed)
#   ssh_alias    github.com-avista if ~/.ssh/config defines it, else none
#   kb_path      existing clone found by the kb helper, or none
#   kb_branch / kb_dirty / kb_remote   state of that clone
#   default_dir  where a new clone should go
#   claude_md    yes/no: ~/.claude/CLAUDE.md already has the knowledge base section
#   share / setup / snooze             current kb config values
#   hook_last_run                      last time a plugin hook ran, or never
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KB="$HERE/../../kb-pickup/scripts/kb"
REPO="Avista/avista-knowledge-base"

missing=""
for t in git gh python3; do command -v "$t" >/dev/null 2>&1 || missing="$missing $t"; done
echo "tools=${missing:-ok}"

if command -v gh >/dev/null 2>&1; then
  login=$(gh api user --jq .login 2>/dev/null || true)
  echo "gh_login=${login:-none}"
  if gh repo view "$REPO" --json name >/dev/null 2>&1; then echo "gh_sees_kb=yes"; else echo "gh_sees_kb=no"; fi
  echo "gh_accounts=$(gh auth status 2>&1 | sed -nE 's/.*Logged in to github.com account ([^ ]+).*/\1/p' | paste -sd, -)"
else
  echo "gh_login=none"; echo "gh_sees_kb=no"; echo "gh_accounts="
fi

if grep -qiE '^\s*Host\s+.*\bgithub\.com-avista\b' ~/.ssh/config 2>/dev/null; then echo "ssh_alias=github.com-avista"; else echo "ssh_alias=none"; fi

path=$(python3 "$KB" where 2>/dev/null || true)
echo "kb_path=${path:-none}"
if [ -n "$path" ]; then
  echo "kb_branch=$(git -C "$path" branch --show-current 2>/dev/null)"
  if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then echo "kb_dirty=yes"; else echo "kb_dirty=no"; fi
  echo "kb_remote=$(git -C "$path" remote get-url origin 2>/dev/null || echo none)"
fi

if [ -d "$HOME/Dropbox/dev" ]; then echo "default_dir=$HOME/Dropbox/dev/avista-knowledge-base"
else echo "default_dir=$HOME/dev/avista-knowledge-base"; fi

if grep -q '^## Knowledge base' "$HOME/.claude/CLAUDE.md" 2>/dev/null; then echo "claude_md=yes"; else echo "claude_md=no"; fi

for k in share setup snooze; do echo "$k=$(python3 "$KB" config "$k" 2>/dev/null)"; done
echo "hook_last_run=$(cat "$HOME/.claude/avista-kb/hook-last-run" 2>/dev/null || echo never)"
