# Screenshots

My own run of Task 3, on **AlmaLinux 9.8 under WSL2** on my Windows laptop (2 Nov 2026).
Machine/boot IDs and server IPs are blurred.

| File | What it shows |
|---|---|
| `02-configured.png` | `hostnamectl`, `timedatectl`, `id`: hostname `web01.codomax.local`, IST timezone, user in `wheel` |
| `03-ssh-key-login.png` | `harden_ssh.sh` run (backup, `sshd -t`, restart), key login works, `ssh root@localhost` denied |
| `04-sshd-hardened.png` | `sshd -T`: `permitrootlogin no`, `passwordauthentication no` |
| `05-firewall.png` | `firewall_setup.sh` + `firewall-cmd --list-all` (ssh, http, https) |
| `06a-provision.png` | `provision.sh --skip-update` output |
| `06b-nginx-running.png` | `systemctl status nginx` |
| `06c-ports.png` | `ss -tlnp`: nginx on :80, sshd on :22 |
| `07-site-in-browser.png` | the deployed page opened from Windows |
| `08-test-results.png` | `test_connectivity.sh`: 12 passed, 0 failed |

## Notes from running it on WSL2 instead of a VM

- WSL2 is a lightweight VM managed by Windows, so there is no separate "VM created" screenshot.
- `System clock synchronized: no` is expected: Windows keeps the time for WSL.
- firewalld runs and the rules are set, but WSL2 traffic comes in through Windows' own networking, so on WSL2 the zone shows no interfaces and the rules don't filter much. On a real VM or EC2 they would.
- The page text describes the target setup (an AlmaLinux VM with SELinux enforcing). On this WSL2 run SELinux was not enforcing.
