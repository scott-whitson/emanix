#!/usr/bin/env bash
set -euo pipefail

# make-test-backup.sh — produce a tiny stand-in for a real dr_backup.sh output,
# for iterating on recovery scripts inside a VM without pulling 3 GiB from gdrive.
#
# Output: $OUT/dr-testbackup-2026-04-18-home.tar.zst and -system.tar.zst

OUT="${1:-/tmp/fake-gdrive/backups/dr}"
mkdir -p "$OUT"

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

# --- Fake home layer: dotfiles, minimal configs, a flag file ---
HOME_ROOT="${SCRATCH}/home-src"
mkdir -p "${HOME_ROOT}/scott/.config/rclone" "${HOME_ROOT}/scott/.ssh"
# Symlink the real dotfiles so restore tests use the current version
cp -r "$HOME/dotfiles" "${HOME_ROOT}/scott/dotfiles"
# Stub rclone config (non-secret placeholder)
cat > "${HOME_ROOT}/scott/.config/rclone/rclone.conf" <<'EOF'
[gdrive]
type = drive
scope = drive
EOF
# Stub ssh key (do NOT copy real one)
ssh-keygen -t ed25519 -N '' -f "${HOME_ROOT}/scott/.ssh/id_ed25519" -C "test-backup" >/dev/null
echo "TEST" > "${HOME_ROOT}/scott/.config/dr-marker.txt"

( cd "$HOME_ROOT" && tar --zstd -cf "${OUT}/dr-testbackup-2026-04-18-home.tar.zst" scott )

# --- Fake system layer: package list + etc.tar with a couple of files ---
SYS="${SCRATCH}/system-src"
mkdir -p "${SYS}/system" "${SYS}/etc-src/etc/pam.d"
echo "base linux zsh rclone openssh git neovim btrfs-progs snapper snap-pac grub-btrfs" \
    | tr ' ' '\n' > "${SYS}/system/packages.list"
echo "#shim pam.d/system-auth for test" > "${SYS}/etc-src/etc/pam.d/system-auth"
( cd "${SYS}/etc-src" && tar cf "${SYS}/etc.tar" etc )
( cd "$SYS" && tar --zstd -cf "${OUT}/dr-testbackup-2026-04-18-system.tar.zst" system etc.tar )

echo "Fake backup written to $OUT"
ls -lh "$OUT"
