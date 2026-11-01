#!/usr/bin/env bash
# permissions_demo.sh — walk through chmod, umask and special bits in a throwaway directory.
# Safe to run as a normal user: everything happens inside a temp dir that is deleted at the end.
#
# Usage: ./permissions_demo.sh
set -euo pipefail

DEMO_DIR="$(mktemp -d /tmp/perm-demo.XXXXXX)"
trap 'rm -rf "$DEMO_DIR"' EXIT
cd "$DEMO_DIR"

section() { printf '\n=== %s ===\n' "$1"; }
show() { stat -c '%A  %a  %U:%G  %n' "$@"; }

section "1. umask decides default permissions"
echo "Current umask: $(umask)"
(
  umask 022
  touch file_umask022; mkdir dir_umask022
  show file_umask022 dir_umask022
)
(
  umask 027
  touch file_umask027; mkdir dir_umask027
  show file_umask027 dir_umask027
)

section "2. chmod — octal and symbolic"
echo 'echo "hello from script"' > script.sh
show script.sh
chmod 755 script.sh && show script.sh
./script.sh
chmod u=rw,go= script.sh && show script.sh
if ./script.sh 2>/dev/null; then
  echo "unexpected: still executable"
else
  echo "-> no execute bit, so ./script.sh is refused (Permission denied)"
fi

section "3. Directory permissions: x means 'can enter'"
mkdir locked && echo secret > locked/note.txt
chmod 644 locked && show locked
if ls locked/note.txt >/dev/null 2>&1 && [[ $EUID -ne 0 ]]; then
  echo "unexpected: could reach file without x on dir"
else
  echo "-> without x on the directory, files inside can't be reached (root ignores this)"
fi
chmod 755 locked

section "4. SGID on a shared directory"
mkdir shared
chmod 2775 shared && show shared
echo "-> the 's' in the group slot means new files inherit the directory's group"

section "5. Sticky bit (like /tmp)"
mkdir dropbox
chmod 1777 dropbox && show dropbox
show /tmp
echo "-> the 't' means users can only delete their own files"

section "6. SUID example on the real system"
show /usr/bin/passwd
echo "-> the 's' in the owner slot: passwd runs as root so it can update /etc/shadow"

section "7. Ownership (needs sudo, so only printed)"
echo "sudo chown nginx:nginx /usr/share/nginx/html/index.html"
echo "sudo chown -R devuser:devops /srv/project"

echo
echo "Demo finished, temp dir $DEMO_DIR cleaned up."
