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
    sed -n '4,10p' "$0"
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
for cmd in sgdisk cryptsetup mkfs.btrfs btrfs mount umount lsblk findmnt; do
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
log "Preserving partitions: $PRESERVE"
IFS=',' read -ra PRESERVE_ARR <<< "$PRESERVE"
for p in "${PRESERVE_ARR[@]}"; do
    dev="$(part_dev "$p")"
    if [[ ! -b "$dev" ]]; then
        err "Preserve partition $p ($dev) does not exist. Refusing to proceed."
        exit 1
    fi
    log "  $dev OK ($(lsblk -no SIZE,FSTYPE "$dev" | tr -s ' '))"
done

# --- Identify partitions that WILL be destroyed ---
mapfile -t ALL_PARTS < <(lsblk -lno NAME "$TARGET" | grep -oP '(?<=p)\d+$|\d+$' | sort -un)
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
err "STUB: destructive section not implemented yet (Task 8)"
exit 99
