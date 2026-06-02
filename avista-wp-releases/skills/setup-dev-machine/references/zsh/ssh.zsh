# ─── SSH ──────────────────────────────────────────────────────────────────────
# Helpers for managing SSH keys and the macOS keychain.

# Add a named key to the agent.  Usage: addSSH id_ed25519_avista_github
addSSH(){
    ssh-add ~/.ssh/$1
}

# Load all keys stored in the Apple keychain.
addAllSSH(){
    ssh-add --apple-use-keychain --apple-load-keychain
}

# Copy a public key to the clipboard.  Usage: copykey id_ed25519_avista_github
copykey(){
    cat ~/.ssh/$1.pub | pbcopy
}

# Auto-load SSH keys in interactive shells when an agent socket is available,
# so you're not prompted for the passphrase on every push.
if [[ -o interactive && -S "$SSH_AUTH_SOCK" ]]; then
  if ! ssh-add -l >/dev/null 2>&1; then
    ( ssh-add --apple-use-keychain 2>/dev/null || true ) &
    disown
  fi
fi

# Create a new SSH key + matching GitHub SSH config entry in one step.
# Usage:   new_ssh_key <alias> <email>
# Example: new_ssh_key avista you@avista.is
#
# Produces a key at ~/.ssh/id_ed25519_<alias>, registers it in the macOS
# keychain, appends a `Host github.com-<alias>` block to ~/.ssh/config, and
# copies the public key to your clipboard ready to paste into GitHub.
new_ssh_key() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage:   new_ssh_key <alias> <email>"
    echo "Example: new_ssh_key avista_github you@avista.is"
    return 1
  fi
  local alias_name="$1"
  local email="$2"
  local key_filename="id_ed25519_${alias_name}"
  local key_path="$HOME/.ssh/${key_filename}"
  local config_path="$HOME/.ssh/config"
  local host_alias="github.com-${alias_name}"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  if [ -f "$key_path" ]; then
    echo "Error: Key file already exists at ${key_path}"
    return 1
  fi
  echo "Generating new SSH key at ${key_path}..."
  ssh-keygen -t ed25519 -C "$email" -f "$key_path" -N ""
  if [ $? -ne 0 ]; then
    echo "Error: ssh-keygen failed."
    return 1
  fi
  echo "Adding key to Apple Keychain..."
  ssh-add --apple-use-keychain "$key_path"
  echo "Updating SSH config file: ${config_path}"
  cat <<EOT >> "$config_path"
# ${alias_name} account (${email})
Host ${host_alias}
  HostName github.com
  User git
  IdentityFile ${key_path}
  IdentitiesOnly yes
EOT
  chmod 600 "$config_path"
  echo "Copying new public key to clipboard..."
  pbcopy < "${key_path}.pub"
  echo ""
  echo "---------------------------------------------------------------"
  echo "✅ Key for '${alias_name}' created and copied to your clipboard."
  echo "---------------------------------------------------------------"
  echo ""
  echo "NEXT STEP: add the public key to GitHub:"
  echo "  https://github.com/settings/keys  →  New SSH key  →  paste  →  Add"
  echo ""
  echo "Then use the host alias '${host_alias}' for repos on this account, e.g.:"
  echo "  git clone git@${host_alias}:Organization/repo-name.git"
  echo ""
}
