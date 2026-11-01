#!/usr/bin/env bash
# process_monitor.sh — quick read-only health snapshot of a Linux box.
# Shows load, memory, disk, top CPU/memory processes and the state of chosen services.
#
# Usage:
#   ./process_monitor.sh                    # one snapshot, checks sshd + nginx
#   ./process_monitor.sh -s "sshd nginx firewalld" -n 5
#   ./process_monitor.sh -w 10              # refresh every 10 seconds (Ctrl+C to stop)
#
# Nothing here kills or changes anything — it only reads.
set -euo pipefail

SERVICES="sshd nginx"
TOP_N=5
WATCH=0

while getopts ":s:n:w:h" opt; do
  case "$opt" in
    s) SERVICES="$OPTARG" ;;
    n) TOP_N="$OPTARG" ;;
    w) WATCH="$OPTARG" ;;
    h|*) sed -n '2,10p' "$0"; exit 0 ;;
  esac
done

[[ "$TOP_N" =~ ^[0-9]+$ ]] || { echo "-n must be a number" >&2; exit 1; }
[[ "$WATCH" =~ ^[0-9]+$ ]] || { echo "-w must be a number of seconds" >&2; exit 1; }

snapshot() {
  echo "=== $(hostname) — $(date '+%Y-%m-%d %H:%M:%S') ==="
  echo
  echo "--- Uptime / load average ---"
  uptime
  echo
  echo "--- Memory ---"
  free -h
  echo
  echo "--- Disk (/) ---"
  df -h /
  echo
  echo "--- Top $TOP_N by CPU ---"
  ps -eo pid,user,ni,%cpu,%mem,comm --sort=-%cpu | head -n $((TOP_N + 1))
  echo
  echo "--- Top $TOP_N by memory ---"
  ps -eo pid,user,ni,%cpu,%mem,comm --sort=-%mem | head -n $((TOP_N + 1))
  echo
  echo "--- Services ---"
  if command -v systemctl >/dev/null && [[ -d /run/systemd/system ]]; then
    for svc in $SERVICES; do
      state="$(systemctl is-active "$svc" 2>/dev/null || true)"
      enabled="$(systemctl is-enabled "$svc" 2>/dev/null || true)"
      printf '%-12s active=%-10s enabled=%s\n' "$svc" "${state:-unknown}" "${enabled:-unknown}"
    done
  else
    echo "systemd not running here (container?), skipping service check."
  fi
  echo
  echo "--- Zombie processes ---"
  zombies="$(ps -eo stat= | awk '/^Z/ {c++} END {print c+0}')"
  echo "count: $zombies"
}

if [[ "$WATCH" -gt 0 ]]; then
  while true; do
    clear
    snapshot
    sleep "$WATCH"
  done
else
  snapshot
fi
