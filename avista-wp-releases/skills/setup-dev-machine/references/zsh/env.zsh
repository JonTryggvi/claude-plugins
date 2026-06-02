# ─── Environment ──────────────────────────────────────────────────────────────
# Loaded for every shell. Puts Homebrew on PATH, sets up nvm (Node), and locale.

# Homebrew (Apple Silicon path; Intel Macs use /usr/local).
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# nvm (Node Version Manager), if installed via Homebrew.
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && . "/opt/homebrew/opt/nvm/nvm.sh"
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && . "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# Load nvm on demand (faster shell startup if you don't always need Node).
load_nvm() {
  export NVM_DIR="${XDG_CONFIG_HOME:-$HOME}/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
}
