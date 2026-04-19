#!/usr/bin/env bash
set -euo pipefail

# partition.sh — partition + LUKS + Btrfs for Arch DR reinstall.
# Runs from the Arch live ISO. Targets /dev/nvme0n1 by default.
#
# Usage: partition.sh [--target DEV] [--preserve LIST] [--dry-run] [--yes]
#
# --target DEV        block device to partition (default /dev/nvme0n1)
# --preserve LIST     comma-separated partition numbers to keep (default 8)
# --dry-run           print what would happen; don't touch the disk
# --yes               skip the WIPE confirmation prompt (use with care; meant for VM)

TARGET="/dev/nvme0n1"
PRESERVE="8"
DRY_RUN=false
ASSUME_YES=false

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[part]${NC} $*"; }
warn() { echo -e "${YELLOW}[part]${NC} $*"; }
err()  { echo -e "${RED}[part]${NC} $*" >&2; }

usage() {
    sed -n '4,12p' "$0"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --target)   TARGET="$2"; shift 2 ;;
        --preserve) PRESERVE="$2"; shift 2 ;;
        --dry-run)  DRY_RUN=true; shift ;;
        --yes)      ASSUME_YES=true; shift ;;
        --help|-h)  usage ;;
        *)          err "Unknown arg: $1"; exit 1 ;;
    esac
done

# --- Preflight ---
for cmd in sgdisk cryptsetup partprobe mkfs.fat mkfs.btrfs btrfs mount umount lsblk findmnt; do
    command -v "$cmd" &>/dev/null || { err "Missing command: $cmd"; exit 1; }
done

if [[ ! -b "$TARGET" ]]; then
    err "$TARGET is not a block device"
    exit 1
fi

# --- Partition-number → device-node helper (handles nvme and sd-style naming) ---
part_dev() {
    local num="$1"
    if [[ "$TARGET" =~ nvme|mmcblk|loop ]]; then
        echo "${TARGET}p${num}"
    else
        echo "${TARGET}${num}"
    fi
}

# --- Verify preserved partitions actually exist ---
if [[ -n "$PRESERVE" ]]; then
    log "Preserving partitions: $PRESERVE"
    IFS=',' read -ra PRESERVE_ARR <<< "$PRESERVE"
else
    log "Preserving partitions: (none)"
    PRESERVE_ARR=()
fi
for p in "${PRESERVE_ARR[@]}"; do
    dev="$(part_dev "$p")"
    if [[ ! -b "$dev" ]]; then
        err "Preserve partition $p ($dev) does not exist. Refusing to proceed."
        exit 1
    fi
    log "  $dev OK ($(lsblk -no SIZE,FSTYPE "$dev" | tr -s ' '))"
done

# --- Identify partitions that WILL be destroyed ---
# Exclude the parent device name (e.g. "nvme0n1") before extracting partition numbers;
# otherwise its trailing digit would be misread as partition 1.
mapfile -t ALL_PARTS < <(lsblk -lno NAME "$TARGET" \
    | grep -v "^$(basename "$TARGET")$" \
    | grep -oP '(?<=p)\d+$|\d+$' \
    | sort -un || true)
DESTROY=()
for p in "${ALL_PARTS[@]}"; do
    keep=false
    for kp in "${PRESERVE_ARR[@]}"; do
        [[ "$p" == "$kp" ]] && keep=true
    done
    [[ "$keep" == false ]] && DESTROY+=("$p")
done

echo
warn "======================================================================"
warn "  Will DESTROY partitions: ${DESTROY[*]} on $TARGET"
warn "  Will PRESERVE partitions: ${PRESERVE_ARR[*]}"
warn "======================================================================"
echo

if $DRY_RUN; then
    log "DRY RUN — stopping before any destructive operation."
    exit 0
fi

if ! $ASSUME_YES; then
    read -rp "Type WIPE to confirm: " confirm
    [[ "$confirm" == "WIPE" ]] || { err "Not confirmed. Aborting."; exit 1; }
fi

# --- Destructive work happens below this line (Tasks 8, 9) ---

# --- Destroy the target partitions ---
log "Deleting partitions: ${DESTROY[*]}"
for p in "${DESTROY[@]}"; do
    sgdisk -d "$p" "$TARGET" || warn "  sgdisk -d $p failed (may already be gone)"
done

# --- Create new p1 (EFI) and p2 (LUKS container) ---
# p1: 1 GiB at the earliest free sector
# p2: remainder of free space up to (but not into) any preserved partition
log "Creating p1 (1 GiB EFI) and p2 (rest of free space)..."
sgdisk -n 1:0:+1GiB -t 1:ef00 -c 1:"EFI" "$TARGET"
sgdisk -n 2:0:0     -t 2:8309 -c 2:"cryptroot" "$TARGET"

partprobe "$TARGET" || true
sleep 2

P1="$(part_dev 1)"
P2="$(part_dev 2)"
[[ -b "$P1" ]] || { err "$P1 did not appear after partprobe"; exit 1; }
[[ -b "$P2" ]] || { err "$P2 did not appear after partprobe"; exit 1; }

# --- Format EFI ---
log "Formatting $P1 as FAT32..."
mkfs.fat -F 32 -n EFI "$P1"

# --- LUKS2 format + verify ---
log "LUKS formatting $P2 (you will be prompted for a passphrase)..."
cryptsetup luksFormat --type luks2 --pbkdf argon2id "$P2"

log "Verifying passphrase by closing and reopening..."
cryptsetup open "$P2" cryptroot
cryptsetup close cryptroot
cryptsetup open "$P2" cryptroot

log "Backing up LUKS header to /tmp/luks-header.img..."
cryptsetup luksHeaderBackup "$P2" --header-backup-file /tmp/luks-header.img
ls -lh /tmp/luks-header.img

warn "CRITICAL: copy /tmp/luks-header.img off this machine NOW."
warn "If Tailscale/malt is reachable: scp /tmp/luks-header.img malt:~/dr-backups/"
warn "Or to a USB stick. Do not skip this step."

# --- Btrfs on cryptroot ---
log "Formatting /dev/mapper/cryptroot as Btrfs..."
mkfs.btrfs -L root /dev/mapper/cryptroot

# --- Create subvolumes ---
log "Creating subvolumes..."
mount /dev/mapper/cryptroot /mnt
for sub in @ @home @var_log @pkg @snapshots; do
    btrfs subvolume create "/mnt/$sub"
done
umount /mnt

# --- Mount hierarchy for pacstrap ---
log "Mounting subvolume hierarchy under /mnt..."
MOUNT_OPTS="compress=zstd,ssd,discard=async,space_cache=v2"

mount -o "$MOUNT_OPTS,subvol=@" /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,.snapshots,boot}
mount -o "$MOUNT_OPTS,subvol=@home"      /dev/mapper/cryptroot /mnt/home
mount -o "$MOUNT_OPTS,subvol=@var_log"   /dev/mapper/cryptroot /mnt/var/log
mount -o "$MOUNT_OPTS,subvol=@pkg"       /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o "$MOUNT_OPTS,subvol=@snapshots" /dev/mapper/cryptroot /mnt/.snapshots
mount "$P1" /mnt/boot

log "Partitioning complete. Layout:"
findmnt /mnt --tree --real
echo
log "Next step: run 'archinstall --config <path>/archinstall.json' — see runbook Phase 3."
