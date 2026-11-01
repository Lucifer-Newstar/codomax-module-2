#!/usr/bin/env bash
# harden_ssh.sh — key-only SSH, no root login. For AlmaLinux/RHEL 9 (works on Ubuntu 22.04+ too).
#
# Safety checks before anything changes:
#   - refuses if the sudo user has no ~/.ssh/authorized_keys (would lock you out); --force overrides
#   - backs up /etc/ssh/sshd_config and the sshd_config.d/ directory
#   - validates with `sshd -t`; on failure it restores the backup and does NOT restart sshd
#
# Usage:
#   sudo ./harden_ssh.sh --dry-run     # show what would be written
#   sudo ./harden_ssh.sh               # apply
#   sudo ./harden_ssh.sh --force       # skip the authorized_keys check (you have console access)
#
# Keep your current SSH session open and test a NEW login before logging out.
set -euo pipefail

SSHD_CONFIG="/etc/ssh/sshd_config"
DROPIN_DIR="/etc/ssh/sshd_config.d"
# 01- so it is read before 50-redhat.conf / 50-cloud-init.conf: sshd keeps the FIRST value it sees.
DROPIN_FILE="$DROPIN_DIR/01-codomax-hardening.conf"
DRY_RUN=false
FORCE=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --force) FORCE=true ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

SETTINGS="# Managed by harden_ssh.sh (Codomax internship task 3)
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
PermitEmptyPasswords no
X11Forwarding no"

if [[ "$DRY_RUN" == true ]]; then
  echo "Would write $DROPIN_FILE (or edit $SSHD_CONFIG if it has no Include line):"
  echo "----"
  echo "$SETTINGS"
  echo "----"
  echo "Then: sshd -t (validate) -> systemctl restart sshd"
  exit 0
fi

[[ "$EUID" -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
[[ -f "$SSHD_CONFIG" ]] || { echo "$SSHD_CONFIG not found — is openssh-server installed?" >&2; exit 1; }

# sshd binary path differs slightly between distros
SSHD_BIN="$(command -v sshd || echo /usr/sbin/sshd)"

# Service name: sshd on RHEL, ssh on Ubuntu/Debian
if systemctl list-unit-files sshd.service &>/dev/null && systemctl cat sshd.service &>/dev/null; then
  SERVICE=sshd
else
  SERVICE=ssh
fi

# 1. Lock-out protection
ADMIN_USER="${SUDO_USER:-}"
if [[ "$FORCE" == false ]]; then
  if [[ -z "$ADMIN_USER" || "$ADMIN_USER" == "root" ]]; then
    echo "Run this via sudo from your normal (key-based) user, or use --force." >&2
    exit 1
  fi
  ADMIN_HOME="$(getent passwd "$ADMIN_USER" | cut -d: -f6)"
  if [[ ! -s "$ADMIN_HOME/.ssh/authorized_keys" ]]; then
    echo "No keys in $ADMIN_HOME/.ssh/authorized_keys for '$ADMIN_USER'." >&2
    echo "Set up key login first (01-linux-cli/scripts/ssh_key_setup.sh), or use --force." >&2
    exit 1
  fi
  echo "Found $(grep -cE '^(ssh-|ecdsa-)' "$ADMIN_HOME/.ssh/authorized_keys") key(s) for $ADMIN_USER — OK."
fi

# 2. Backup
STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP_DIR="/root/sshd-backup-$STAMP"
mkdir -p "$BACKUP_DIR"
cp -a "$SSHD_CONFIG" "$BACKUP_DIR/"
[[ -d "$DROPIN_DIR" ]] && cp -a "$DROPIN_DIR" "$BACKUP_DIR/"
echo "Backup saved in $BACKUP_DIR"

restore() {
  echo "Restoring previous config from $BACKUP_DIR" >&2
  cp -a "$BACKUP_DIR/sshd_config" "$SSHD_CONFIG"
  rm -f "$DROPIN_FILE"
}

# 3. Apply: drop-in if sshd_config includes sshd_config.d, else edit the main file
if grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$SSHD_CONFIG"; then
  mkdir -p "$DROPIN_DIR"
  printf '%s\n' "$SETTINGS" > "$DROPIN_FILE"
  chmod 600 "$DROPIN_FILE"
  command -v restorecon >/dev/null && restorecon "$DROPIN_FILE"
  echo "Wrote $DROPIN_FILE"
else
  echo "No Include line, editing $SSHD_CONFIG directly"
  if grep -qiE '^[[:space:]]*Match[[:space:]]' "$SSHD_CONFIG"; then
    # Lines appended after a Match block would only apply inside that block.
    echo "$SSHD_CONFIG has a Match block — add these settings above it by hand:" >&2
    echo "$SETTINGS" >&2
    exit 1
  fi
  while read -r key value; do
    [[ -z "$key" || "$key" == \#* ]] && continue
    # comment out any existing line for this key, then append ours
    sed -i -E "s/^[[:space:]]*($key)[[:space:]].*/# \1 (disabled by harden_ssh.sh)/I" "$SSHD_CONFIG"
    echo "$key $value" >> "$SSHD_CONFIG"
  done <<< "$SETTINGS"
fi

# 4. Validate before restart
if ! "$SSHD_BIN" -t; then
  echo "sshd -t FAILED — not restarting." >&2
  restore
  exit 1
fi
echo "sshd -t: config OK"

# 5. Restart and show the effective values
systemctl restart "$SERVICE"
echo "Restarted $SERVICE. Effective settings:"
"$SSHD_BIN" -T 2>/dev/null | grep -Ei '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|maxauthtries|permitemptypasswords|x11forwarding) ' || true

echo
echo "Now open a NEW terminal and test:  ssh $ADMIN_USER@<server-ip>"
echo "Root and password logins should be refused. Rollback: cp $BACKUP_DIR/sshd_config $SSHD_CONFIG && rm -f $DROPIN_FILE && systemctl restart $SERVICE"
