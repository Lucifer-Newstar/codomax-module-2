# Task 1 — Linux CLI Operations

My notes while working through the Linux basics on **AlmaLinux 9** (RHEL family).
Where Ubuntu/Debian does it differently, I've added a short `Ubuntu:` note.

Contents
1. Files & navigation
2. Permissions (chmod, chown, umask, special bits)
3. Users & groups
4. Process management
5. Services (systemd)
6. SSH keys

---

## 1. Files & navigation

| Command | What it does |
|---|---|
| `pwd` | print current directory |
| `ls -lah` | long list, all files (incl. hidden), human sizes |
| `cd -` | jump back to the previous directory |
| `mkdir -p a/b/c` | create nested dirs in one go |
| `cp -r src/ dst/` | copy a directory recursively |
| `mv old new` | move / rename |
| `rm -i file` | remove with confirmation (`-r` for dirs — careful) |
| `touch file` | create empty file / update timestamp |
| `cat`, `less`, `head -n 20`, `tail -f` | view files (`tail -f` follows a log live) |
| `find /etc -name "*.conf" -mtime -7` | find .conf files changed in last 7 days |
| `grep -rn "PermitRootLogin" /etc/ssh/` | search text recursively with line numbers |
| `wc -l file` | count lines |
| `du -sh dir/`, `df -h` | dir size / disk free |
| `ln -s target linkname` | symbolic link |
| `tar -czvf backup.tar.gz dir/` | compress a directory (`-xzvf` to extract) |

Useful bits:
- `>` overwrites, `>>` appends, `2>` redirects errors, `&>` both.
- `|` pipes output into the next command: `ps aux | grep nginx`.
- `which`, `type`, `man <cmd>`, `<cmd> --help` when stuck.

Linux filesystem layout (the ones I actually touched):

| Path | Holds |
|---|---|
| `/etc` | system config (`/etc/ssh/sshd_config`, `/etc/nginx/`) |
| `/var/log` | logs (`/var/log/secure` on RHEL, `/var/log/auth.log` on Ubuntu) |
| `/home` | user home dirs |
| `/usr/share/nginx/html` | default nginx web root on AlmaLinux (`/var/www/html` on Ubuntu) |
| `/tmp` | temp files, cleared on reboot |

---

## 2. Permissions

`ls -l` output: `-rwxr-x--- 1 navin devops 1024 Nov 1 10:00 deploy.sh`

```
-   rwx   r-x   ---
|   user  group other
type (- file, d dir, l link)
```

| Symbol | Octal | On a file | On a directory |
|---|---|---|---|
| r | 4 | read contents | list names |
| w | 2 | modify | create/delete files inside |
| x | 1 | execute | enter (`cd`) |

### chmod
```bash
chmod 755 script.sh        # rwxr-xr-x
chmod 640 app.conf         # rw-r-----
chmod u+x,g-w file         # symbolic form
chmod -R g+rX shared/      # capital X = execute only on dirs (and already-executable files)
```

### chown / chgrp
```bash
sudo chown navin:devops report.txt
sudo chown -R nginx:nginx /usr/share/nginx/html
sudo chgrp devops shared/
```

### umask
Default permissions for new files = `666 - umask`, for dirs = `777 - umask`.
- umask `022` → files `644`, dirs `755` (common default)
- umask `027` → files `640`, dirs `750` (stricter, no access for others)

```bash
umask          # show current
umask 027      # set for this shell (persist in ~/.bashrc)
```

### Special bits
| Bit | Octal | Example | Effect |
|---|---|---|---|
| SUID | 4000 | `/usr/bin/passwd` (`-rwsr-xr-x`) | runs as the file's owner |
| SGID | 2000 | `chmod 2775 shared/` | new files inherit the dir's group |
| Sticky | 1000 | `/tmp` (`drwxrwxrwt`) | only the owner can delete their files |

```bash
find / -perm -4000 -type f 2>/dev/null   # list SUID binaries (good security check)
```

Demo script: [`scripts/permissions_demo.sh`](scripts/permissions_demo.sh)

---

## 3. Users & groups

Key files: `/etc/passwd` (users), `/etc/shadow` (password hashes, root only), `/etc/group` (groups), `/etc/sudoers` + `/etc/sudoers.d/`.

```bash
sudo groupadd devops                       # new group
sudo useradd -m -s /bin/bash -c "Dev User" devuser   # -m creates /home/devuser
sudo passwd devuser                        # set password
sudo usermod -aG devops devuser            # ADD to supplementary group (-a is important!)
sudo usermod -aG wheel devuser             # sudo rights on AlmaLinux/RHEL
id devuser                                 # uid, gid, groups
groups devuser
sudo chage -l devuser                      # password ageing info
sudo userdel -r devuser                    # delete user + home (careful)
sudo groupdel devops
```

- **Ubuntu:** the sudo group is `sudo`, not `wheel` (`usermod -aG sudo devuser`). `adduser` is the friendlier interactive wrapper.
- Forgetting `-a` in `usermod -G` *replaces* all supplementary groups — easy way to lock yourself out of sudo.

### sudoers
Always edit with `visudo` (it syntax-checks before saving):
```bash
sudo visudo -f /etc/sudoers.d/devops
```
```
# members of devops can restart nginx without full root
%devops ALL=(root) /usr/bin/systemctl restart nginx, /usr/bin/systemctl status nginx
```
On AlmaLinux the line `%wheel ALL=(ALL) ALL` is already enabled in `/etc/sudoers`.

Script: [`scripts/user_setup.sh`](scripts/user_setup.sh)

---

## 4. Process management

```bash
ps aux                      # every process
ps -ef --forest             # tree view (parent/child)
pgrep -a nginx              # find PIDs by name
top / htop                  # live view (htop: sudo dnf install epel-release && sudo dnf install htop)
kill <PID>                  # SIGTERM (15) — polite stop
kill -9 <PID>               # SIGKILL — last resort, no cleanup
pkill -f "python app.py"    # kill by command line match
nice -n 10 ./backup.sh      # start with lower priority (-20 highest, 19 lowest)
renice -n 5 -p <PID>        # change priority of a running process
```

Jobs (foreground/background in one shell):
```bash
sleep 300 &        # run in background
jobs               # list jobs
fg %1              # bring job 1 to foreground
Ctrl+Z, then bg    # pause, then continue in background
nohup ./long.sh &  # keep running after logout
```

Common signals: `1 SIGHUP` (reload config), `2 SIGINT` (Ctrl+C), `9 SIGKILL`, `15 SIGTERM`, `19 SIGSTOP`.

Resource checks: `free -h`, `uptime` (load average), `vmstat 1 5`, `lsof -i :80`.

Script: [`scripts/process_monitor.sh`](scripts/process_monitor.sh)

---

## 5. Services (systemd)

```bash
systemctl status sshd
sudo systemctl start|stop|restart|reload nginx
sudo systemctl enable --now nginx     # start now AND at boot
sudo systemctl disable nginx
systemctl is-active nginx; systemctl is-enabled nginx
systemctl list-units --type=service --state=running
systemctl --failed
sudo systemctl daemon-reload          # after editing a unit file
```

Logs with journald:
```bash
journalctl -u nginx                   # logs for one service
journalctl -u sshd -f                 # follow live
journalctl -u nginx --since "1 hour ago"
journalctl -p err -b                  # errors since this boot
```

- **Ubuntu:** SSH service is `ssh` instead of `sshd`; same `systemctl` commands.

Minimal custom unit (`/etc/systemd/system/hello.service`):
```ini
[Unit]
Description=Hello demo service
After=network.target

[Service]
ExecStart=/usr/bin/bash -c 'while true; do echo hello; sleep 30; done'
Restart=on-failure
User=nobody

[Install]
WantedBy=multi-user.target
```

---

## 6. SSH keys

Generate a key pair **on my laptop** (client), not on the server:
```bash
ssh-keygen -t ed25519 -C "navin@laptop"     # ed25519 = modern, short, fast
# saves ~/.ssh/id_ed25519 (PRIVATE, never share) and ~/.ssh/id_ed25519.pub (public)
```

Copy the public key to the server:
```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub devuser@<server-ip>
# manual way if ssh-copy-id isn't available:
cat ~/.ssh/id_ed25519.pub | ssh devuser@<server-ip> \
  'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

Permissions sshd insists on (otherwise key login silently fails):

| Path | Mode |
|---|---|
| `~/.ssh/` | `700` |
| `~/.ssh/authorized_keys` | `600` |
| `~/.ssh/id_ed25519` (private key) | `600` |
| `~/.ssh/id_ed25519.pub` | `644` |
| home directory | not group/other writable |

On AlmaLinux with SELinux, if keys still fail after fixing modes: `restorecon -Rv ~/.ssh`.

Client shortcut in `~/.ssh/config`:
```
Host almavm
    HostName 192.168.56.10
    User devuser
    IdentityFile ~/.ssh/id_ed25519
```
Then just `ssh almavm`.

Debug a failing login: `ssh -v almavm` on the client, `sudo journalctl -u sshd -f` (or `/var/log/secure`) on the server.

Script: [`scripts/ssh_key_setup.sh`](scripts/ssh_key_setup.sh)
