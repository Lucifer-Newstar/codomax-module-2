# Task 3 — Deploy a Linux Server

**Create VM → Configure Linux → Secure Access → Deploy Service → Test Connectivity**

Target: AlmaLinux 9 VM running nginx, reachable over HTTP, with key-only SSH and firewalld on.
Scripts for each stage are in [`scripts/`](scripts/). Screenshots of my run go in [`screenshots/`](screenshots/).

All commands below are run from the **repo root** (`git clone` the repo onto the VM, or `scp` it over).

---

## Step 1 — Create the VM

### Option A: local (VirtualBox / VMware)
1. Download the **AlmaLinux 9 x86_64 minimal ISO** from almalinux.org.
2. New VM: Linux / Red Hat 64-bit, **2 vCPU, 2 GB RAM, 20 GB disk**.
3. Network:
   - Adapter 1: **NAT** (internet for `dnf`)
   - Adapter 2: **Host-only** (so my laptop can reach the VM, VirtualBox default range `192.168.56.0/24`)
   - (or a single **Bridged** adapter to get an IP on my home network)
4. Installer: *Minimal Install*, set timezone, create a user and tick **"Make this user administrator"** (adds it to `wheel`), keep root locked or set a strong root password.
5. After first boot: `ip a` to find the host-only IP (e.g. `192.168.56.10`).

### Option B: AWS EC2
1. EC2 → Launch instance → AMI: **AlmaLinux OS 9** (official AMI from the AlmaLinux OS Foundation, via AWS Marketplace).
2. Instance type: `t2.micro` / `t3.micro` (free-tier eligible types depend on the account/region).
3. Key pair: create one (ED25519), download the `.pem` → `chmod 400 mykey.pem`.
4. Security group: SSH 22 from **My IP**, HTTP 80 + HTTPS 443 from anywhere — same as [`02-networking/security-group-example.json`](../02-networking/security-group-example.json).
5. Connect: `ssh -i mykey.pem ec2-user@<public-ip>` (AlmaLinux AMIs use `ec2-user`).

---

## Step 2 — Configure Linux

```bash
sudo dnf update -y
sudo dnf install -y git vim curl wget tar bash-completion policycoreutils-python-utils
sudo hostnamectl set-hostname web01.codomax.local
sudo timedatectl set-timezone Asia/Kolkata
timedatectl                      # check "System clock synchronized: yes" (chronyd)
getenforce                       # should say Enforcing — keep SELinux on
```

Non-root admin user (if the installer didn't create one, or on EC2 I want my own):
```bash
sudo ./01-linux-cli/scripts/user_setup.sh devuser devops --sudo
sudo passwd devuser              # needed only until SSH keys are in
```
Log in as `devuser` from now on; `sudo whoami` should print `root`.

- **Ubuntu:** `sudo apt update && sudo apt upgrade -y`, sudo group is `sudo`.

---

## Step 3 — Secure access

1. **SSH key** — on my laptop:
   ```bash
   ./01-linux-cli/scripts/ssh_key_setup.sh devuser@192.168.56.10
   ```
   It creates `~/.ssh/id_ed25519` if needed, copies the public key, and tests key-only login.

2. **Harden sshd** — on the server, *only after* the key login works:
   ```bash
   sudo ./03-linux-server-deploy/scripts/harden_ssh.sh --dry-run    # preview
   sudo ./03-linux-server-deploy/scripts/harden_ssh.sh
   ```
   Settings applied:
   ```
   PermitRootLogin no
   PasswordAuthentication no
   KbdInteractiveAuthentication no
   PubkeyAuthentication yes
   MaxAuthTries 3
   PermitEmptyPasswords no
   X11Forwarding no
   ```
   The script backs up the config, writes a drop-in in `/etc/ssh/sshd_config.d/`, checks it with `sshd -t`, and only then restarts `sshd`. It refuses to run if the sudo user has no `authorized_keys` (so I can't lock myself out).

   Why a drop-in: AlmaLinux 9's `sshd_config` starts with `Include /etc/ssh/sshd_config.d/*.conf`, and sshd keeps the **first** value it reads for each setting. A file named `01-...` is read before `50-redhat.conf` / `50-cloud-init.conf`, so it wins.

3. **Firewall**:
   ```bash
   sudo ./02-networking/scripts/firewall_setup.sh
   sudo firewall-cmd --list-all
   ```

4. **Optional — fail2ban** (bans IPs after repeated failed logins):
   ```bash
   sudo dnf install -y epel-release
   sudo dnf install -y fail2ban
   sudo tee /etc/fail2ban/jail.local >/dev/null <<'EOF'
   [sshd]
   enabled  = true
   maxretry = 5
   bantime  = 1h
   EOF
   sudo systemctl enable --now fail2ban
   sudo fail2ban-client status sshd
   ```

Keep the current SSH session open and test a **new** login in a second terminal before closing anything.

---

## Step 4 — Deploy a service (nginx)

```bash
sudo ./03-linux-server-deploy/scripts/provision.sh            # or --dry-run first
```
What it does (manual equivalent):
```bash
sudo dnf install -y nginx
sudo systemctl enable --now nginx                   # start now + at boot
sudo firewall-cmd --permanent --add-service=http --add-service=https
sudo firewall-cmd --reload
sudo install -m 644 03-linux-server-deploy/site/index.html /usr/share/nginx/html/index.html
sudo restorecon -Rv /usr/share/nginx/html           # correct SELinux label
sudo nginx -t && sudo systemctl reload nginx
```

### SELinux notes (the part that bites)
- Web content must have the label `httpd_sys_content_t`. Check: `ls -Z /usr/share/nginx/html`.
- `cp` into the web root picks up the right label; **`mv` keeps the old label** (e.g. `user_home_t`) → nginx returns **403**. Fix: `sudo restorecon -Rv /usr/share/nginx/html`.
- Custom web root such as `/srv/site`:
  ```bash
  sudo semanage fcontext -a -t httpd_sys_content_t "/srv/site(/.*)?"
  sudo restorecon -Rv /srv/site
  ```
- nginx as a reverse proxy to an app port: `sudo setsebool -P httpd_can_network_connect 1`.
- Denials are logged in `/var/log/audit/audit.log` → `sudo ausearch -m avc -ts recent`.
- Don't "fix" it with `setenforce 0`.

- **Ubuntu:** `sudo apt install nginx`, web root `/var/www/html`, no SELinux (AppArmor instead), `sudo ufw allow 'Nginx Full'`.

---

## Step 5 — Test connectivity

On the server:
```bash
systemctl status nginx --no-pager
curl -I http://localhost                 # expect HTTP/1.1 200 OK
sudo ss -tlnp | grep -E ':(22|80)\b'     # nginx on 80, sshd on 22
sudo firewall-cmd --list-all             # services: http https ssh
sudo sshd -T | grep -Ei 'permitrootlogin|passwordauthentication'
```

From my laptop:
```bash
curl http://192.168.56.10                # the deployed page
ssh devuser@192.168.56.10                # key login works
ssh root@192.168.56.10                   # expect: Permission denied (publickey)
ssh -o PubkeyAuthentication=no devuser@192.168.56.10   # expect: Permission denied (password login off)
```

Or run it all at once:
```bash
sudo ./03-linux-server-deploy/scripts/test_connectivity.sh                       # on the server
./03-linux-server-deploy/scripts/test_connectivity.sh 192.168.56.10 devuser      # from the laptop
```

### Troubleshooting I ran into / checked
| Symptom | Likely cause | Check |
|---|---|---|
| `curl localhost` works, laptop times out | firewall / security group | `firewall-cmd --list-all`, SG inbound rules |
| 403 Forbidden | SELinux label or file perms | `ls -Z`, `restorecon -Rv`, `namei -l /usr/share/nginx/html/index.html` |
| 502 Bad Gateway (proxy) | backend down or SELinux boolean | `setsebool -P httpd_can_network_connect 1` |
| `Permission denied (publickey)` for my user | key not installed / bad perms | `~/.ssh` 700, `authorized_keys` 600, `restorecon -Rv ~/.ssh` |
| nginx won't start | config error or port in use | `nginx -t`, `journalctl -u nginx`, `ss -tlnp` |
