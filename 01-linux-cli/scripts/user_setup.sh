#!/usr/bin/env bash
# user_setup.sh — create a group and a user, add the user to it, optionally give sudo.
#
# Usage:
#   sudo ./user_setup.sh <username> <group> [--sudo] [--dry-run]
#
# Example:
#   sudo ./user_setup.sh devuser devops --sudo --dry-run   # preview only
#   sudo ./user_setup.sh devuser devops --sudo             # do it
#
# On AlmaLinux/RHEL sudo access comes from the "wheel" group.
# On Ubuntu/Debian it is the "sudo" group — the script detects which one exists.
set -euo pipefail

usage() {
  echo "Usage: sudo $0 <username> <group> [--sudo] [--dry-run]" >&2
  exit 1
}

[[ $# -lt 2 ]] && usage

USERNAME="$1"
GROUP="$2"
shift 2

GIVE_SUDO=false
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --sudo) GIVE_SUDO=true ;;
    --dry-run) DRY_RUN=true ;;
    *) usage ;;
  esac
done

# Print the command; only execute it when not in dry-run mode.
run() {
  echo "+ $*"
  if [[ "$DRY_RUN" == false ]]; then
    "$@"
  fi
}

# Basic validation of the names (lowercase, digits, - and _ ; must start with a letter or _)
valid_name='^[a-z_][a-z0-9_-]{0,31}$'
[[ "$USERNAME" =~ $valid_name ]] || { echo "Invalid username: $USERNAME" >&2; exit 1; }
[[ "$GROUP" =~ $valid_name ]]    || { echo "Invalid group: $GROUP" >&2; exit 1; }

if [[ "$DRY_RUN" == false && "$EUID" -ne 0 ]]; then
  echo "Run as root (sudo), or add --dry-run to preview." >&2
  exit 1
fi

# 1. Group
if getent group "$GROUP" >/dev/null; then
  echo "Group '$GROUP' already exists, skipping."
else
  run groupadd "$GROUP"
fi

# 2. User (home dir + bash shell, primary group = the new group)
if id "$USERNAME" &>/dev/null; then
  echo "User '$USERNAME' already exists, adding to '$GROUP'."
  run usermod -aG "$GROUP" "$USERNAME"
else
  run useradd -m -s /bin/bash -g "$GROUP" "$USERNAME"
  echo "Set a password with: sudo passwd $USERNAME  (or use SSH keys only)"
fi

# 3. Sudo via wheel (RHEL) or sudo (Debian/Ubuntu)
if [[ "$GIVE_SUDO" == true ]]; then
  if getent group wheel >/dev/null; then
    SUDO_GROUP=wheel
  else
    SUDO_GROUP=sudo
  fi
  run usermod -aG "$SUDO_GROUP" "$USERNAME"
fi

# 4. Show the result
if [[ "$DRY_RUN" == false ]]; then
  echo
  id "$USERNAME"
fi
echo "Done."
