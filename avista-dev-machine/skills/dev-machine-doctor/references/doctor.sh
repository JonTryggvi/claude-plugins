#!/usr/bin/env bash
# Avista dev-machine doctor — READ-ONLY health check.
#
# Changes nothing. Creates no files, installs nothing, writes no config.
# Never prints a token value: the token store is inspected by key NAME only.
#
# Usage:  bash doctor.sh            full report
#         bash doctor.sh --no-net   skip the SSH reachability probes
#
# Exit status is always 0 — this is a report, not a gate.

set -u
LC_ALL=C

NO_NET=0
[ "${1:-}" = "--no-net" ] && NO_NET=1

# ── output helpers ────────────────────────────────────────────────────────────
if [ -t 1 ]; then B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[0m'; else B=''; DIM=''; R=''; fi

GAPS=""            # newline-joined "label|fix" pairs
gap() { GAPS="${GAPS}$1|$2
"; }

ok()   { printf '  ✅ %-30s %s\n' "$1" "${2:-}"; }
warn() { printf '  ⚠️  %-30s %s\n' "$1" "${2:-}"; }
bad()  { printf '  ❌ %-30s %s\n' "$1" "${2:-}"; }
head_() { printf '\n%s%s%s\n' "$B" "$1" "$R"; }

# have <cmd> — is it on PATH as an executable (not a shell alias/function)?
have() { command -v "$1" >/dev/null 2>&1; }

# first line, trimmed — for version strings
v1() { head -n1 2>/dev/null | tr -d '\r'; }

printf '%s%s%s\n' "$B" "Avista dev-machine doctor — read-only" "$R"
printf '%s%s%s\n' "$DIM" "$(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null) · $(uname -m) · nothing on this machine is modified" "$R"

# ══ 1. Base tooling ═══════════════════════════════════════════════════════════
head_ "1. Base tooling"

if have git; then ok "git" "$(git --version | v1)"
else bad "git" "missing"; gap "git / Xcode Command Line Tools" "setup-dev-machine (Part A)"; fi

if have brew; then ok "Homebrew" "$(brew --version | v1) · $(brew --prefix)"
else bad "Homebrew" "missing"; gap "Homebrew" "setup-dev-machine (Part A)"; fi

if have gh; then ok "gh" "$(gh --version | v1)"
else bad "gh" "missing"; gap "gh (GitHub CLI)" "setup-dev-machine (Part A)"; fi

# ══ 2. Shell config ═══════════════════════════════════════════════════════════
head_ "2. Shell config"

for f in "$HOME/.zprofile" "$HOME/.zshrc"; do
  if [ -f "$f" ]; then ok "$(basename "$f")" "$(wc -l <"$f" | tr -d ' ') lines"
  else bad "$(basename "$f")" "missing"; gap "$(basename "$f")" "setup-dev-machine (Part B)"; fi
done

if [ -d "$HOME/.zsh" ]; then
  missing_mod=""
  for m in env git ssh; do
    [ -f "$HOME/.zsh/$m.zsh" ] || missing_mod="$missing_mod $m.zsh"
  done
  if [ -z "$missing_mod" ]; then ok "~/.zsh modules" "env.zsh git.zsh ssh.zsh"
  else warn "~/.zsh modules" "missing:$missing_mod"; gap "~/.zsh modules ($missing_mod)" "setup-dev-machine (Part B)"; fi
else
  bad "~/.zsh modules" "directory missing"; gap "~/.zsh module directory" "setup-dev-machine (Part B)"
fi

# The loop that sources the modules — without it the team functions never load.
# Match the glob itself (/*.zsh), so quoting styles all hit:
#   for _f in "$HOME/.zsh"/*.zsh   ·   for f in ~/.zsh/*.zsh   ·   source $HOME/.zsh/*.zsh
if grep -qsE '/\*\.zsh' "$HOME/.zshrc" "$HOME/.zprofile"; then
  ok "module source loop" "present"
elif [ -f "$HOME/.zshrc" ] || [ -f "$HOME/.zprofile" ]; then
  # Half-configured machine: the files exist but nothing sources the modules.
  # This is the one that looks fine and silently breaks every team function.
  bad "module source loop" "not found in .zshrc/.zprofile"
  gap "module source loop (functions never load)" "setup-dev-machine (Part B)"
else
  # Both startup files are already reported missing — don't double-count.
  bad "module source loop" "n/a — no shell startup files yet"
fi

# Team functions — grep the modules; a live `type` check needs an interactive shell.
if [ -f "$HOME/.zsh/git.zsh" ] || [ -f "$HOME/.zsh/ssh.zsh" ]; then
  missing_fn=""
  for fn in gsend set_git_user set_gh_user new_ssh_key; do
    grep -qs "^${fn}()\|^${fn} ()\|^function ${fn}" "$HOME/.zsh/"*.zsh || missing_fn="$missing_fn $fn"
  done
  if [ -z "$missing_fn" ]; then ok "team functions" "gsend set_git_user set_gh_user new_ssh_key"
  else warn "team functions" "missing:$missing_fn"; gap "team functions ($missing_fn)" "setup-dev-machine (Part B)"; fi
fi

# ~/.local/bin on PATH — the native-installer gap.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ok "~/.local/bin on PATH" "yes" ;;
  *) if [ -d "$HOME/.local/bin" ]; then
       bad "~/.local/bin on PATH" "NO — but it exists and holds binaries"
       gap "~/.local/bin not on PATH" "setup-agent-toolkit (Step 1)"
     else
       warn "~/.local/bin on PATH" "no (directory doesn't exist yet)"
     fi ;;
esac

# ══ 3. GitHub identity ════════════════════════════════════════════════════════
head_ "3. GitHub identity"

if have gh; then
  gh_status="$(gh auth status 2>&1)"
  accounts="$(printf '%s\n' "$gh_status" | sed -n 's/.*account \([A-Za-z0-9_-]*\) .*/\1/p' | sort -u | tr '\n' ' ')"
  if printf '%s' "$gh_status" | grep -qs "Logged in"; then
    ok "gh accounts" "${accounts:-(see gh auth status)}"
    # Scopes matter more than the token string — and reading scopes leaks nothing.
    if printf '%s' "$gh_status" | grep -qs "workflow"; then
      ok "gh token scopes" "includes 'workflow' (can trigger release builds)"
    else
      warn "gh token scopes" "no 'workflow' scope seen — releases may 403"
      gap "gh token lacks 'workflow' scope" "setup-dev-machine (Part D) — use a CLASSIC token"
    fi
  else
    bad "gh auth" "not logged in"; gap "gh not authenticated" "setup-dev-machine (Part D)"
  fi
else
  bad "gh auth" "gh not installed"
fi

if [ -f "$HOME/.ssh/config" ]; then
  hosts="$(grep -is '^[[:space:]]*Host ' "$HOME/.ssh/config" | awk '{for(i=2;i<=NF;i++) print $i}')"
  gh_hosts="$(printf '%s\n' "$hosts" | grep -is 'github' | tr '\n' ' ')"
  if [ -n "$gh_hosts" ]; then ok "~/.ssh/config github hosts" "$gh_hosts"
  else warn "~/.ssh/config github hosts" "none found"; gap "no github Host entry in ~/.ssh/config" "setup-dev-machine (Part C)"; fi
  site_n="$(printf '%s\n' "$hosts" | grep -isc 'tempurl.host')"
  if [ "$site_n" -gt 0 ]; then
    ok "production site hosts" "$site_n *.tempurl.host entries"
  else
    warn "production site hosts" "none — wp-prod-ops / wp-performance can't connect"
    gap "no production site access configured" "setup-site-access"
  fi
else
  bad "~/.ssh/config" "missing"; gap "~/.ssh/config" "setup-dev-machine (Part C)"
fi

# 1Password SSH agent — how Avista serves keys for client sites.
# ssh-add -l prints key comments + fingerprints only; no key material.
OP_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
if [ -S "$OP_SOCK" ]; then
  if grep -qs 'IdentityAgent' "$HOME/.ssh/config" 2>/dev/null; then
    agent_keys="$(ssh-add -l 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${agent_keys:-0}" -gt 0 ]; then
      ok "1Password SSH agent" "$agent_keys key(s): $(ssh-add -l 2>/dev/null | awk '{print $3}' | tr '\n' ' ')"
    else
      warn "1Password SSH agent" "socket + config present but NO keys — 1Password locked?"
      gap "1Password agent serving no keys (locked?)" "unlock 1Password, then setup-site-access"
    fi
  else
    warn "1Password SSH agent" "agent running but no IdentityAgent line in ~/.ssh/config"
    gap "SSH not pointed at the 1Password agent" "setup-site-access (Step 1)"
  fi
else
  printf '  ·  %-30s %snot in use (fine if keys are on disk)%s\n' "1Password SSH agent" "$DIM" "$R"
fi

if [ "$NO_NET" -eq 0 ]; then
  for h in github.com github.com-avista; do
    greeting="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -T "git@$h" 2>&1)"
    who="$(printf '%s' "$greeting" | sed -n 's/^Hi \([A-Za-z0-9_-]*\)!.*/\1/p')"
    if [ -n "$who" ]; then ok "ssh $h" "greets $who"
    elif printf '%s' "$greeting" | grep -qs 'Could not resolve\|Operation timed out\|Connection timed out'; then
      warn "ssh $h" "network unreachable (skipped)"
    else
      warn "ssh $h" "no greeting — key not added to that account?"
      gap "ssh $h not authenticating" "setup-dev-machine (Part C)"
    fi
  done
else
  printf '  %s—  ssh probes skipped (--no-net)%s\n' "$DIM" "$R"
fi

gname="$(git config --global user.name 2>/dev/null)"
gmail="$(git config --global user.email 2>/dev/null)"
if [ -n "$gname" ] && [ -n "$gmail" ]; then ok "git global identity" "$gname <$gmail>"
else warn "git global identity" "unset (per-project helpers may still cover it)"; fi

# ══ 4. Agent layer ════════════════════════════════════════════════════════════
head_ "4. Agent layer"

if have claude; then ok "claude" "$(claude --version 2>/dev/null | v1) · $(command -v claude)"
else bad "claude" "not on PATH"; gap "Claude Code not on PATH" "setup-agent-toolkit (Step 1)"; fi

if [ -f "$HOME/.claude/CLAUDE.md" ]; then
  ok "~/.claude/CLAUDE.md" "$(wc -l <"$HOME/.claude/CLAUDE.md" | tr -d ' ') lines"
else
  bad "~/.claude/CLAUDE.md" "missing — no house rules loaded"
  gap "global CLAUDE.md missing" "setup-agent-toolkit (Step 3)"
fi

ENV_FILE="$HOME/.claude/.env"
if [ -f "$ENV_FILE" ]; then
  mode="$(stat -f '%Lp' "$ENV_FILE" 2>/dev/null)"
  if [ "$mode" = "600" ]; then ok "~/.claude/.env perms" "0600"
  else
    bad "~/.claude/.env perms" "0$mode — readable beyond your account"
    gap "token store is mode 0$mode, not 0600" "chmod 600 ~/.claude/.env, then ROTATE the tokens in it"
  fi
  # Key NAMES only. Never the values.
  keys="$(grep -oE '^[A-Z_]+' "$ENV_FILE" 2>/dev/null | sort -u)"
  ok "~/.claude/.env keys" "$(printf '%s' "$keys" | tr '\n' ' ')"
  for k in FIGMA_TOKEN AVISTA_GITHUB_TOKEN ACTIVECOLLAB_URL ACTIVECOLLAB_TOKEN; do
    printf '%s\n' "$keys" | grep -qx "$k" || {
      case "$k" in
        ACTIVECOLLAB_TOKEN) warn "  $k" "absent — run activecollab-setup to mint it" ;;
        FIGMA_TOKEN)        warn "  $k" "absent — avista-figma-import will fail" ;;
        *)                  warn "  $k" "absent" ;;
      esac
    }
  done
else
  bad "~/.claude/.env" "missing — token-dependent skills will fail"
  gap "token store missing" "setup-agent-toolkit (Step 4)"
fi

MP="$HOME/.claude/plugins/known_marketplaces.json"
if [ -f "$MP" ] && grep -qs '"avista"' "$MP"; then
  ok "avista marketplace" "registered"
else
  warn "avista marketplace" "not registered locally"
  gap "avista marketplace not registered" "setup-agent-toolkit (Step 2)"
fi

IP="$HOME/.claude/plugins/installed_plugins.json"
if [ -f "$IP" ]; then
  if have jq; then
    inst="$(jq -r '.plugins | keys[]' "$IP" 2>/dev/null | sed 's/@avista//' | sort | tr '\n' ' ')"
  else
    inst="$(grep -oE '"avista-[a-z-]+@avista"' "$IP" 2>/dev/null | tr -d '"' | sed 's/@avista//' | sort -u | tr '\n' ' ')"
  fi
  ok "installed plugins" "${inst:-none detected}"
  printf '%s\n' "$inst" | grep -qs 'avista-dev-machine' \
    || warn "  avista-dev-machine" "not installed as a plugin (running from source?)"
else
  warn "installed plugins" "no install record found"
fi

# ══ 5. Role tooling ═══════════════════════════════════════════════════════════
head_ "5. Role tooling (only needed for some work — setup-wp-toolchain installs these)"

# PHP extension set WordPress depends on. Homebrew's build has them all, so a
# gap here usually means a hand-rolled or system PHP is shadowing it.
if have php; then
  mods="$(php -m 2>/dev/null)"
  missing_ext=""
  for e in mysqli gd intl mbstring curl zip dom simplexml exif sodium bcmath fileinfo tokenizer; do
    printf '%s\n' "$mods" | grep -qix "$e" || missing_ext="$missing_ext $e"
  done
  if [ -z "$missing_ext" ]; then ok "php extensions" "all WordPress-required present"
  else
    warn "php extensions" "missing:$missing_ext"
    gap "php missing extensions ($missing_ext)" "setup-wp-toolchain (Step 1)"
  fi
fi

# Local WP site runners and the local-TLS CA — presence only, never a gap.
for app in "Local" "Docker"; do
  [ -e "/Applications/$app.app" ] && ok "$app.app" "installed" \
    || printf '  ·  %-30s %snot installed — setup-wp-toolchain (Step 6)%s\n' "$app.app" "$DIM" "$R"
done
if have mkcert; then
  caroot="$(mkcert -CAROOT 2>/dev/null)"
  [ -f "$caroot/rootCA.pem" ] && ok "mkcert local CA" "installed" \
    || warn "mkcert local CA" "mkcert present but CA not installed — run: mkcert -install"
fi

check_opt() { # check_opt <cmd> <what needs it> [install hint]
  if have "$1"; then ok "$1" "$2"
  else printf '  ·  %-30s %smissing — %s%s%s\n' "$1" "$DIM" "$2" "${3:+ · $3}" "$R"; fi
}
check_opt php        "WordPress plugin/theme work"        "brew install php"
check_opt composer   "WordPress vendor deps"              "brew install composer"
check_opt phpunit    "WordPress tests"                    "brew install phpunit"
check_opt wp         "wp-cli — often only needed server-side" "brew install wp-cli"
check_opt node       "build steps"                        "nvm install --lts"
check_opt jq         "JSON parsing in several skills"      "brew install jq"
check_opt rg         "faster greps; Claude Code has its own search, so optional" "brew install ripgrep"
check_opt op         "1Password CLI — activecollab-setup"  "brew install --cask 1password-cli"
check_opt docker     "local site containers"               "brew install --cask docker-desktop"
check_opt weasyprint "avista-design-systems brand-doc PDF render" "brew install weasyprint"
check_opt pdftoppm   "poppler — brand-doc PDF checks"      "brew install poppler"

# ══ Summary ═══════════════════════════════════════════════════════════════════
head_ "Summary"

if [ -z "$GAPS" ]; then
  printf '  ✅ No gaps found. This machine is set up.\n\n'
else
  n="$(printf '%s' "$GAPS" | grep -c '|')"
  printf '  %s gap(s) to close:\n\n' "$n"
  printf '%s' "$GAPS" | while IFS='|' read -r label fix; do
    [ -n "$label" ] && printf '  · %-46s → %s\n' "$label" "$fix"
  done
  printf '\n  Nothing was changed. Run the named skill to fix each gap.\n\n'
fi
exit 0
