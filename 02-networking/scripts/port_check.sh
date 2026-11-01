#!/usr/bin/env bash
# port_check.sh — what is listening locally, and can I reach ports on a host?
#
# Usage:
#   ./port_check.sh                          # list listening TCP/UDP sockets
#   ./port_check.sh 192.168.56.10            # test 22, 80, 443 on that host
#   ./port_check.sh 192.168.56.10 22 8080    # test specific ports
#
# Uses ss (iproute), nc (AlmaLinux: dnf install nmap-ncat) and curl. Read-only.
set -euo pipefail

HOST="${1:-}"
shift || true
PORTS=("$@")
[[ ${#PORTS[@]} -eq 0 ]] && PORTS=(22 80 443)

echo "=== Listening sockets on $(hostname) ==="
if [[ "$EUID" -eq 0 ]]; then
  ss -tulnp
else
  echo "(run with sudo to see process names)"
  ss -tuln
fi
echo

[[ -z "$HOST" ]] && exit 0

echo "=== Port tests against $HOST ==="
for port in "${PORTS[@]}"; do
  [[ "$port" =~ ^[0-9]+$ ]] || { echo "skip invalid port: $port"; continue; }
  if command -v nc >/dev/null; then
    if nc -z -w 3 "$HOST" "$port" 2>/dev/null; then
      echo "port $port: OPEN"
    else
      echo "port $port: closed / filtered"
    fi
  else
    # Fallback using bash's /dev/tcp if nc is missing
    if timeout 3 bash -c ">/dev/tcp/$HOST/$port" 2>/dev/null; then
      echo "port $port: OPEN"
    else
      echo "port $port: closed / filtered"
    fi
  fi
done
echo

# HTTP(S) checks for web ports
for port in "${PORTS[@]}"; do
  case "$port" in
    80)  url="http://$HOST/" ;;
    443) url="https://$HOST/" ;;
    8080) url="http://$HOST:8080/" ;;
    *) continue ;;
  esac
  code="$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" || true)"
  if [[ -z "$code" || "$code" == "000" ]]; then
    echo "curl $url -> no HTTP response"
  else
    echo "curl $url -> HTTP $code"
  fi
done
