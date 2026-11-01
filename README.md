# Codomax Linux & Cloud Internship

Hands-on notes and scripts from my Linux / cloud internship tasks at **Codomax**.
Everything was done on **AlmaLinux 9** (RHEL-compatible: `dnf`, `firewalld`, `systemctl`, SELinux), with Ubuntu equivalents noted where they differ.

## Tasks

| # | Task | Folder |
|---|---|---|
| 1 | Learn Linux CLI operations, files/permissions, users, groups, process management, services, and SSH keys | [`01-linux-cli/`](01-linux-cli/) |
| 2 | Learn IP addressing, DNS setup, ports, firewalls, and security group configurations | [`02-networking/`](02-networking/) |
| 3 | Deploy a Linux server: Create VM → Configure Linux → Secure Access → Deploy Service → Test Connectivity | [`03-linux-server-deploy/`](03-linux-server-deploy/) |

## Repo map

```
codomax-linux-cloud-internship/
├── 01-linux-cli/
│   ├── notes.md                    # files, permissions, users/groups, processes, systemd, SSH keys
│   └── scripts/
│       ├── user_setup.sh           # create user + group, sudo via wheel (dry-run supported)
│       ├── permissions_demo.sh     # chmod / umask / SUID-SGID-sticky demo in a temp dir
│       ├── process_monitor.sh      # read-only health snapshot (load, memory, top processes, services)
│       └── ssh_key_setup.sh        # ed25519 key, perms, ssh-copy-id, key-only login test
├── 02-networking/
│   ├── notes.md                    # IPv4, subnetting, DNS, ports, firewalld, security groups vs NACLs
│   ├── security-group-example.json # example AWS-style web server security group
│   └── scripts/
│       ├── firewall_setup.sh       # firewalld: ssh/http/https, optional SSH-from-one-IP rule
│       ├── dns_check.sh            # A/AAAA/CNAME/MX/TXT/NS lookup + resolver config
│       └── port_check.sh           # ss -tulnp + nc/curl port tests
├── 03-linux-server-deploy/
│   ├── steps.md                    # full walkthrough of the 5 stages
│   ├── scripts/
│   │   ├── provision.sh            # dnf update, nginx, firewall, deploy page, SELinux labels
│   │   ├── harden_ssh.sh           # key-only SSH, no root login, backup + sshd -t before restart
│   │   └── test_connectivity.sh    # PASS/FAIL checks, on the server or from my laptop
│   ├── site/index.html             # the page nginx serves
│   └── screenshots/                # screenshots of my run
├── LICENSE
└── README.md
```

## How to use

On the AlmaLinux VM:
```bash
sudo dnf install -y git
git clone https://github.com/Lucifer-Newstar/codomax-linux-cloud-internship.git
cd codomax-linux-cloud-internship
chmod +x */scripts/*.sh
```

Then follow [`03-linux-server-deploy/steps.md`](03-linux-server-deploy/steps.md). Short version:
```bash
# on the server
sudo ./01-linux-cli/scripts/user_setup.sh devuser devops --sudo
# on my laptop
./01-linux-cli/scripts/ssh_key_setup.sh devuser@<server-ip>
# on the server, logged in as devuser
sudo ./03-linux-server-deploy/scripts/harden_ssh.sh
sudo ./02-networking/scripts/firewall_setup.sh
sudo ./03-linux-server-deploy/scripts/provision.sh
sudo ./03-linux-server-deploy/scripts/test_connectivity.sh
# from my laptop
./03-linux-server-deploy/scripts/test_connectivity.sh <server-ip> devuser
```

Every script that changes the system checks for root and supports `--dry-run` (or asks before anything risky), so you can see what it will do first. All scripts use `set -euo pipefail` and pass `shellcheck`.

## Skills learned

- **Linux CLI:** navigation, file operations, `find`/`grep`, pipes and redirection
- **Permissions:** `chmod` (octal + symbolic), `chown`, `umask`, SUID/SGID/sticky bit
- **Users & groups:** `useradd`, `usermod -aG`, `groupadd`, `wheel` and `visudo`/sudoers drop-ins
- **Processes:** `ps`, `top`, signals, `kill`, `nice`/`renice`, background jobs
- **Services:** `systemctl` (enable/start/status), `journalctl`, writing a basic unit file
- **SSH:** ed25519 keys, `authorized_keys` permissions, key-only login, `sshd_config.d` drop-ins
- **Networking:** IPv4, CIDR, subnetting a /24 into /26s, private ranges, NAT
- **DNS:** record types, `/etc/hosts` vs `/etc/resolv.conf`, `dig`/`nslookup`
- **Ports & firewalls:** `ss -tulnp`, `nc`, firewalld zones/services/rich rules, SELinux port labels
- **Cloud security:** security groups (stateful) vs NACLs (stateless), least-privilege inbound rules
- **Deployment:** VM setup, hardening, nginx, SELinux file contexts, connectivity testing

## License

[MIT](LICENSE) © 2026 Navin Jairam M
