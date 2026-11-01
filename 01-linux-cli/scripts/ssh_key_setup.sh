#!/usr/bin/env bash
# ssh_key_setup.sh — run on YOUR LAPTOP (the SSH client).
# 1. Creates an ed25519 key pair if you don't have one (never overwrites without asking).
# 2. Fixes ~/.ssh permissions.
# 3. Optionally copies the public key to a server and tests key-based login.
#
# Usage:
#   ./ssh_key_setup.sh                          # just make sure a key exists
#   ./ssh_key_setup.sh devuser@192.168.56.10    # also install it on the server
#   ./ssh_key_setup.sh devuser@host -p 2222     # non-default SSH port
#
# The private key (~/.ssh/id_ed25519) never leaves this machine — only the .pub is copied.
set -euo pipefail

KEY="${KEY:-$HOME/.ssh/id_ed25519}"
TARGET="${1:-}"
PORT=22

if [[ $# -ge 3 && "$2" == "-p" ]]; then
  PORT="$3"
fi

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# 1. Key pair
if [[ -f "$KEY" ]]; then
  echo "Key already exists: $KEY"
  read -r -p "Keep using it? [Y/n] " answer
  if [[ "${answer,,}" == "n" ]]; then
    read -r -p "This will OVERWRITE $KEY. Type 'yes' to continue: " confirm
    [[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 1; }
    rm -f "$KEY" "$KEY.pub"
    ssh-keygen -t ed25519 -a 100 -C "$(whoami)@$(hostname)" -f "$KEY"
  fi
else
  echo "Generating new ed25519 key at $KEY (you'll be asked for a passphrase — recommended)."
  ssh-keygen -t ed25519 -a 100 -C "$(whoami)@$(hostname)" -f "$KEY"
fi

# 2. Permissions sshd/ssh expect
chmod 600 "$KEY"
chmod 644 "$KEY.pub"
if [[ -f "$HOME/.ssh/config" ]]; then chmod 600 "$HOME/.ssh/config"; fi

echo
echo "Public key fingerprint:"
ssh-keygen -lf "$KEY.pub"

# 3. Install on server (optional)
if [[ -z "$TARGET" ]]; then
  echo
  echo "No server given. To install the key later:"
  echo "  ssh-copy-id -i $KEY.pub user@server"
  exit 0
fi

echo
echo "Copying public key to $TARGET (port $PORT) — enter the server password one last time."
if command -v ssh-copy-id >/dev/null; then
  ssh-copy-id -i "$KEY.pub" -p "$PORT" "$TARGET"
else
  # Fallback: append the key and set the right permissions on the server side.
  ssh -p "$PORT" "$TARGET" \
    'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && (command -v restorecon >/dev/null && restorecon -R ~/.ssh || true)' \
    < "$KEY.pub"
fi

# 4. Test: BatchMode=yes fails instead of falling back to a password prompt
echo
echo "Testing key-only login..."
if ssh -p "$PORT" -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" 'echo "Key login OK on $(hostname)"'; then
  echo "Success. You can now disable password login (see 03-linux-server-deploy/scripts/harden_ssh.sh)."
else
  echo "Key login failed. Check ~/.ssh perms on the server and run: ssh -v $TARGET" >&2
  exit 1
fi
