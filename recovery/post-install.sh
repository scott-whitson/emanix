#!/usr/bin/env bash
set -euo pipefail

# post-install.sh — orchestration that runs after first boot on a freshly-restored
# Arch install. Assumes user data (/home/scott) is already restored from backup.
#
# Usage: post-install.sh [--restore-system|--setup-snapshots|--full] [--backup DIR]

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/dr-restore}"
ALLOWLIST="${DOTFILES_DIR}/recovery/etc-allowlist.txt"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[post]${NC} $*"; }
warn() { echo -e "${YELLOW}[post]${NC} $*"; }
err()  { echo -e "${RED}[post]${NC} $*" >&2; }

ACTION=""
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] ACTION

Actions (pick exactly one):
  --restore-system    Selectively restore /etc from backup per etc-allowlist.txt
  --setup-snapshots   Install & configure snapper, snap-pac, grub-btrfs
  --full              Run --restore-system then --setup-snapshots

Options:
  --backup DIR        Directory holding the extracted dr-*-system.tar.zst
                      (default: \$HOME/dr-restore)
  --help              Show this message
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --restore-system)  ACTION="restore-system"; shift ;;
        --setup-snapshots) ACTION="setup-snapshots"; shift ;;
        --full)            ACTION="full"; shift ;;
        --backup)          BACKUP_DIR="$2"; shift 2 ;;
        --help|-h)         usage ;;
        *)                 err "Unknown arg: $1"; exit 1 ;;
    esac
done
[[ -n "$ACTION" ]] || usage

# --- /etc selective restore ---
restore_etc() {
    log "Selective /etc restore from ${BACKUP_DIR}"
    [[ -f "$ALLOWLIST" ]] || { err "Allowlist not found: $ALLOWLIST"; exit 1; }

    # Locate the extracted etc.tar
    local etctar=""
    # Prefer already-extracted etc.tar inside BACKUP_DIR
    if [[ -f "${BACKUP_DIR}/etc.tar" ]]; then
        etctar="${BACKUP_DIR}/etc.tar"
    else
        # Extract the system tarball if it hasn't been already
        local sys_archive
        sys_archive=$(find "$BACKUP_DIR" -maxdepth 1 -name 'dr-*-system.tar.zst' 2>/dev/null | head -1) || true
        [[ -n "$sys_archive" ]] || { err "No system tarball found in $BACKUP_DIR"; exit 1; }
        log "Extracting $sys_archive..."
        zstd -dc "$sys_archive" | tar xf - -C "$BACKUP_DIR/"
        etctar="${BACKUP_DIR}/etc.tar"
    fi
    [[ -f "$etctar" ]] || { err "etc.tar missing after extraction"; exit 1; }

    # Unpack etc.tar to a staging area
    local staging="${BACKUP_DIR}/etc-staged"
    rm -rf "$staging"; mkdir -p "$staging"
    tar xf "$etctar" -C "$staging"
    # tar was built with `/etc/` — so files land at $staging/etc/...
    local src="${staging}/etc"
    [[ -d "$src" ]] || { err "Expected ${staging}/etc after extraction"; exit 1; }

    # Parse allowlist
    local section=""
    while IFS= read -r line; do
        line="${line%%#*}"      # strip comments
        line="${line#"${line%%[![:space:]]*}"}"  # ltrim
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^\[(AUTO|REVIEW|NEVER)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi
        [[ -z "$section" ]] && continue

        case "$section" in
            AUTO)
                local s="${src}/${line}"
                local d="/etc/${line}"
                if [[ -e "$s" ]]; then
                    log "  [AUTO] cp -a $s → $d"
                    sudo mkdir -p "$(dirname "$d")"
                    sudo cp -a "$s" "$d"
                else
                    warn "  [AUTO] source missing, skipping: $s"
                fi
                ;;
            REVIEW)
                local s="${src}/${line}"
                local d="/etc/${line}"
                if [[ -e "$s" ]]; then
                    warn "  [REVIEW] differences for $line:"
                    diff -u "$d" "$s" 2>/dev/null || true
                    read -rp "  Apply? (y/N): " ans
                    if [[ "$ans" =~ ^[Yy] ]]; then
                        sudo mkdir -p "$(dirname "$d")"
                        sudo cp -a "$s" "$d"
                        log "    applied"
                    else
                        log "    skipped"
                    fi
                fi
                ;;
            NEVER)
                : # explicitly do nothing
                ;;
        esac
    done < "$ALLOWLIST"

    log "Done. /etc restore complete."
}

# --- Snapshot stack setup (Task 11) ---
setup_snapshots() {
    log "Installing snapper + snap-pac + grub-btrfs..."
    sudo pacman -S --needed --noconfirm snapper snap-pac grub-btrfs

    # Snapper requires /.snapshots to NOT exist before create-config; we handle the
    # case where the subvolume is already mounted there by unmounting temporarily.
    if mountpoint -q /.snapshots; then
        log "Unmounting /.snapshots temporarily so snapper can create its config..."
        sudo umount /.snapshots
    fi
    if [[ -d /.snapshots ]]; then
        sudo rmdir /.snapshots 2>/dev/null || true
    fi

    log "Creating snapper config for /..."
    sudo snapper -c root create-config /

    # Snapper creates a new @/.snapshots subvolume — we want to use OUR @snapshots instead.
    sudo btrfs subvolume delete /.snapshots
    sudo mkdir /.snapshots
    sudo mount -a  # re-mounts our @snapshots subvolume per fstab

    # Retention policy: adjust limits (edit /etc/snapper/configs/root)
    sudo sed -i \
        -e 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/' \
        -e 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' \
        -e 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="2"/' \
        -e 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/' \
        -e 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' \
        /etc/snapper/configs/root

    log "Enabling snapper timers + grub-btrfsd..."
    sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
    sudo systemctl enable --now grub-btrfsd.service

    log "Regenerating GRUB config so snapshot entries appear..."
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    log "Creating baseline snapshot..."
    sudo snapper -c root create --description "post-DR-restore baseline"

    log "Snapshot setup complete. Current snapshots:"
    sudo snapper list
}

case "$ACTION" in
    restore-system)  restore_etc ;;
    setup-snapshots) setup_snapshots ;;
    full)            restore_etc; setup_snapshots ;;
esac
