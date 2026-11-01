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
