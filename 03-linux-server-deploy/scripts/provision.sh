#!/usr/bin/env bash
# provision.sh — install and serve the site with nginx on AlmaLinux/RHEL 9.
# Safe to re-run: each step checks the current state first.
#
#   1. dnf update (skip with --skip-update)
#   2. install nginx, enable + start it
#   3. open http/https in firewalld (if firewalld is running)
#   4. deploy ../site/index.html to the web root, fix SELinux labels
#   5. nginx -t, reload, curl check
#
# Usage:
#   sudo ./provision.sh [--skip-update] [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITE_SRC="$SCRIPT_DIR/../site/index.html"
WEB_ROOT="/usr/share/nginx/html"
DRY_RUN=false
SKIP_UPDATE=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --skip-update) SKIP_UPDATE=true ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

run() {
  echo "+ $*"
  if [[ "$DRY_RUN" == false ]]; then
    "$@"
  fi
}
step() { printf '\n==> %s\n' "$1"; }

[[ -f "$SITE_SRC" ]] || { echo "Site file not found: $SITE_SRC" >&2; exit 1; }

if [[ "$DRY_RUN" == false ]]; then
  [[ "$EUID" -eq 0 ]] || { echo "Run with sudo (or --dry-run)." >&2; exit 1; }
  command -v dnf >/dev/null || { echo "dnf not found — this script targets AlmaLinux/RHEL. (Ubuntu: apt install nginx, web root /var/www/html)" >&2; exit 1; }
fi

step "1. System update"
if [[ "$SKIP_UPDATE" == true ]]; then
  echo "skipped (--skip-update)"
else
  run dnf -y update
fi

step "2. nginx"
if rpm -q nginx &>/dev/null; then
  echo "nginx already installed: $(rpm -q nginx)"
else
  run dnf -y install nginx
fi
run systemctl enable --now nginx

step "3. Firewall"
if systemctl is-active --quiet firewalld; then
  for svc in http https; do
    if firewall-cmd --permanent --query-service="$svc" &>/dev/null; then
      echo "$svc already allowed"
    else
      run firewall-cmd --permanent --add-service="$svc"
    fi
  done
  run firewall-cmd --reload
else
  echo "firewalld is not running — skipping (run 02-networking/scripts/firewall_setup.sh)."
fi

step "4. Deploy site"
TARGET="$WEB_ROOT/index.html"
if [[ -f "$TARGET" && ! -L "$TARGET" ]] && cmp -s "$SITE_SRC" "$TARGET"; then
  echo "index.html already up to date"
else
  if [[ -L "$TARGET" ]]; then
    # The packaged default page is a symlink to the distro test page; replace the link, not its target.
    echo "default index.html is a symlink -> $(readlink "$TARGET"), replacing it"
    run rm -f "$TARGET"
  elif [[ -f "$TARGET" ]]; then
    backup="$TARGET.bak.$(date +%Y%m%d%H%M%S)"
    run cp -p "$TARGET" "$backup"
  fi
  run install -m 0644 -o root -g root "$SITE_SRC" "$TARGET"
fi
if command -v restorecon >/dev/null; then
  run restorecon -Rv "$WEB_ROOT"     # give files the httpd_sys_content_t SELinux label
fi

step "5. Validate and check"
run nginx -t
run systemctl reload nginx
if [[ "$DRY_RUN" == false ]]; then
  if curl -fsS --max-time 5 http://localhost/ | grep -q "Codomax Internship"; then
    echo "OK: http://localhost/ serves the deployed page"
  else
    echo "WARNING: page check failed — see: journalctl -u nginx, ls -Z $WEB_ROOT" >&2
    exit 1
  fi
  echo
  echo "Server IPs: $(hostname -I)"
  echo "Open http://<one-of-those-IPs>/ from your laptop."
fi
