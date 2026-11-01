# Screenshots

Add your screenshots here (PNG/JPG), one per stage, for example:

| File | What it should show |
|---|---|
| `01-vm-created.png` | VM settings / EC2 instance running |
| `02-configured.png` | `hostnamectl`, `timedatectl`, `id devuser` |
| `03-ssh-key-login.png` | key login working, `ssh root@...` refused |
| `04-sshd-hardened.png` | `sudo sshd -T \| grep -Ei 'permitrootlogin\|passwordauthentication'` |
| `05-firewall.png` | `sudo firewall-cmd --list-all` |
| `06-nginx-running.png` | `systemctl status nginx` and `ss -tlnp` |
| `07-site-in-browser.png` | the deployed page opened from the host machine |
| `08-test-results.png` | `test_connectivity.sh` output with all PASS |

Crop out public IPs/hostnames you don't want in a public repo.
