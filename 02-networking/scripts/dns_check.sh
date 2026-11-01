#!/usr/bin/env bash
# dns_check.sh — look up the common record types for a domain and show local resolver config.
#
# Usage:
#   ./dns_check.sh example.com
#   ./dns_check.sh example.com 1.1.1.1      # query a specific DNS server
#
# Needs dig (AlmaLinux: sudo dnf install -y bind-utils | Ubuntu: sudo apt install dnsutils).
# Read-only: it changes nothing.
set -euo pipefail

DOMAIN="${1:-}"
SERVER="${2:-}"

if [[ -z "$DOMAIN" ]]; then
  echo "Usage: $0 <domain> [dns-server]" >&2
  exit 1
fi

if ! command -v dig >/dev/null; then
  echo "dig not found. Install: sudo dnf install -y bind-utils" >&2
  exit 1
fi

AT=()
[[ -n "$SERVER" ]] && AT=("@$SERVER")

echo "=== Local resolver setup ==="
echo "hosts line in /etc/nsswitch.conf: $(grep -E '^hosts:' /etc/nsswitch.conf 2>/dev/null || echo 'n/a')"
echo "nameservers in /etc/resolv.conf:"
grep -E '^(nameserver|search)' /etc/resolv.conf 2>/dev/null | sed 's/^/  /' || echo "  (none found)"
if grep -qw "$DOMAIN" /etc/hosts 2>/dev/null; then
  echo "NOTE: $DOMAIN appears in /etc/hosts — that entry wins over DNS:"
  grep -w "$DOMAIN" /etc/hosts | sed 's/^/  /'
fi
echo

echo "=== DNS records for $DOMAIN ${SERVER:+(asking $SERVER)} ==="
for type in A AAAA CNAME MX TXT NS; do
  result="$(dig +short "${AT[@]}" "$DOMAIN" "$type" 2>/dev/null || true)"
  printf '%-6s ' "$type"
  if [[ -n "$result" ]]; then
    echo "$result" | paste -sd ' ' -
  else
    echo "-"
  fi
done
echo

echo "=== Answer with TTL (A record) ==="
dig "${AT[@]}" "$DOMAIN" A +noall +answer || true
echo

echo "=== Reverse lookup of first A record ==="
first_ip="$(dig +short "${AT[@]}" "$DOMAIN" A | grep -E '^[0-9.]+$' | head -n1 || true)"
if [[ -n "$first_ip" ]]; then
  ptr="$(dig +short "${AT[@]}" -x "$first_ip" || true)"
  echo "$first_ip -> ${ptr:-no PTR record}"
else
  echo "no A record to reverse"
fi

echo
echo "=== System resolver (getent, respects /etc/hosts) ==="
getent hosts "$DOMAIN" || echo "getent could not resolve $DOMAIN"
