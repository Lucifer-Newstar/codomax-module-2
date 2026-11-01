#!/usr/bin/env bash
# test_connectivity.sh — verify the deployment. Prints PASS/FAIL per check, exits 1 if anything failed.
#
# On the server (local checks: nginx, ports, firewall, sshd settings, SELinux):
#   sudo ./test_connectivity.sh
#
# From your laptop (remote checks: ping, ports, HTTP, key login, root/password refused):
#   ./test_connectivity.sh <server-ip> [ssh-user] [ssh-port]
#   ./test_connectivity.sh 192.168.56.10 devuser
#
# Read-only: nothing is changed on either side.
set -euo pipefail

PASS=0
FAIL=0
pass() { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
check() {  # check "description" command...
  local desc="$1"; shift
  if "$@" &>/dev/null; then pass "$desc"; else fail "$desc"; fi
}

port_open() {  # host port
  if command -v nc >/dev/null; then
    nc -z -w 3 "$1" "$2"
  else
    timeout 3 bash -c ">/dev/tcp/$1/$2"
  fi
}

local_checks() {
  echo "== Local checks on $(hostname) =="

  check "nginx is active" systemctl is-active --quiet nginx
  check "nginx is enabled at boot" systemctl is-enabled --quiet nginx
  check "nginx config valid (nginx -t)" nginx -t

  if ss -tln | grep -qE ':80\b'; then pass "something is listening on :80"; else fail "nothing listening on :80"; fi
  if ss -tln | grep -qE ':22\b'; then pass "sshd listening on :22"; else fail "nothing listening on :22"; fi

  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost/ || true)"
  if [[ "$code" == "200" ]]; then pass "curl http://localhost -> 200"; else fail "curl http://localhost -> HTTP ${code/#000/no response}"; fi
  if curl -fs --max-time 5 http://localhost/ | grep -q "Codomax Internship"; then
    pass "deployed page is being served"
  else
    fail "deployed page not found (default page still there?)"
  fi

  if systemctl is-active --quiet firewalld; then
    pass "firewalld is running"
    services="$(firewall-cmd --list-services 2>/dev/null || true)"
    for svc in http ssh; do
      if [[ " $services " == *" $svc "* ]] || firewall-cmd --list-rich-rules 2>/dev/null | grep -q "service name=\"$svc\""; then
        pass "firewall allows $svc"
      else
        fail "firewall does not allow $svc"
      fi
    done
  else
    fail "firewalld is not running"
  fi

  if [[ "$EUID" -eq 0 ]]; then
    effective="$(sshd -T 2>/dev/null || true)"
    if grep -qi '^permitrootlogin no' <<< "$effective"; then pass "sshd: PermitRootLogin no"; else fail "sshd: root login not disabled"; fi
    if grep -qi '^passwordauthentication no' <<< "$effective"; then pass "sshd: PasswordAuthentication no"; else fail "sshd: password login still on"; fi
  else
    echo "  [SKIP] sshd effective config (run with sudo)"
  fi

  if command -v getenforce >/dev/null; then
    mode="$(getenforce)"
    if [[ "$mode" == "Enforcing" ]]; then pass "SELinux Enforcing"; else fail "SELinux is $mode (expected Enforcing)"; fi
    echo "  [INFO] index.html SELinux label: $(stat -c '%C' /usr/share/nginx/html/index.html 2>/dev/null || echo n/a)"
  fi
}

remote_checks() {
  local host="$1" user="${2:-$USER}" port="${3:-22}"
  echo "== Remote checks against $host (ssh user: $user, port $port) =="

  if ping -c 2 -W 2 "$host" &>/dev/null; then
    pass "ping $host"
  else
    echo "  [INFO] ping failed (ICMP may be blocked by the security group — not fatal)"
  fi

  check "TCP $port (ssh) open" port_open "$host" "$port"
  check "TCP 80 (http) open" port_open "$host" 80

  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$host/" || true)"
  if [[ "$code" == "200" ]]; then pass "curl http://$host -> 200"; else fail "curl http://$host -> HTTP ${code/#000/no response}"; fi

  # BatchMode: never prompt, so a missing key shows up as a failure instead of a password prompt.
  # accept-new: trust the host key on first contact (fine for my own lab VM), reject if it CHANGES.
  local ssh_opts=(-p "$port" -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)

  check "key login as $user works" ssh "${ssh_opts[@]}" "$user@$host" true

  # Root must be refused. Require an actual "Permission denied" so a network error isn't counted as a pass.
  rc=0
  out="$(ssh "${ssh_opts[@]}" "root@$host" true 2>&1)" || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    fail "root login was ACCEPTED (should be refused)"
  elif grep -q 'Permission denied' <<< "$out"; then
    pass "root login refused"
  else
    fail "root login not clearly refused: ${out//$'\n'/ }"
  fi

  # With pubkey turned off, the error lists the methods the server still offers,
  # e.g. "Permission denied (publickey,gssapi-keyex,gssapi-with-mic)". password must not be in it.
  out="$(ssh "${ssh_opts[@]}" -o PubkeyAuthentication=no "$user@$host" true 2>&1 || true)"
  offered="$(sed -n 's/.*Permission denied (\([^)]*\)).*/\1/p' <<< "$out" | head -n1)"
  if [[ -z "$offered" ]]; then
    fail "could not read offered auth methods: ${out//$'\n'/ }"
  elif [[ "$offered" == *password* || "$offered" == *keyboard-interactive* ]]; then
    fail "password login still offered ($offered)"
  else
    pass "password login not offered ($offered)"
  fi
}

if [[ $# -ge 1 ]]; then
  remote_checks "$@"
else
  local_checks
fi

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
