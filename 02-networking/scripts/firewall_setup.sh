#!/usr/bin/env bash
# firewall_setup.sh — firewalld baseline for a web server on AlmaLinux/RHEL.
# Allows ssh, http and https in the default zone (permanent), optionally extra ports,
# and optionally restricts SSH to a single source IP/CIDR.
#
# Usage:
#   sudo ./firewall_setup.sh                          # ssh + http + https
#   sudo ./firewall_setup.sh --port 8080/tcp          # also open 8080
#   sudo ./firewall_setup.sh --ssh-from 203.0.113.10/32
#   sudo ./firewall_setup.sh --dry-run                # print commands only
#
# Ubuntu equivalent: sudo ufw allow OpenSSH && sudo ufw allow 80,443/tcp && sudo ufw enable
set -euo pipefail

DRY_RUN=false
SSH_FROM=""
EXTRA_PORTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --ssh-from) SSH_FROM="${2:?--ssh-from needs an IP/CIDR}"; shift 2 ;;
    --port) EXTRA_PORTS+=("${2:?--port needs e.g. 8080/tcp}"); shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

run() {
  echo "+ $*"
  if [[ "$DRY_RUN" == false ]]; then
    "$@"
  fi
}

if [[ "$DRY_RUN" == false ]]; then
  [[ "$EUID" -eq 0 ]] || { echo "Run with sudo (or use --dry-run)." >&2; exit 1; }
  command -v firewall-cmd >/dev/null || { echo "firewalld not installed: sudo dnf install -y firewalld" >&2; exit 1; }
fi

# 1. Make sure firewalld is running and starts at boot
run systemctl enable --now firewalld

ZONE="public"
if [[ "$DRY_RUN" == false ]]; then
  ZONE="$(firewall-cmd --get-default-zone)"
fi
echo "Default zone: $ZONE"

# 2. Web server services
for svc in ssh http https; do
  run firewall-cmd --permanent --zone="$ZONE" --add-service="$svc"
done

# 3. Extra ports, if any
for port in "${EXTRA_PORTS[@]}"; do
  [[ "$port" =~ ^[0-9]{1,5}/(tcp|udp)$ ]] || { echo "Bad port format: $port (use 8080/tcp)" >&2; exit 1; }
  run firewall-cmd --permanent --zone="$ZONE" --add-port="$port"
done

# 4. Optional: SSH only from one source. Rich rule first, THEN remove the open ssh service,
#    so there is never a moment with no SSH rule at all.
if [[ -n "$SSH_FROM" ]]; then
  echo
  echo "WARNING: after this, SSH will only be accepted from $SSH_FROM."
  echo "Keep a console/second session open in case you lock yourself out."
  if [[ "$DRY_RUN" == false ]]; then
    read -r -p "Continue? [y/N] " answer
    [[ "${answer,,}" == "y" ]] || { echo "Skipped SSH restriction."; SSH_FROM=""; }
  fi
  if [[ -n "$SSH_FROM" ]]; then
    run firewall-cmd --permanent --zone="$ZONE" \
      --add-rich-rule="rule family=\"ipv4\" source address=\"$SSH_FROM\" service name=\"ssh\" accept"
    run firewall-cmd --permanent --zone="$ZONE" --remove-service=ssh
  fi
fi

# 5. Apply and show
run firewall-cmd --reload
if [[ "$DRY_RUN" == false ]]; then
  echo
  firewall-cmd --zone="$ZONE" --list-all
fi
