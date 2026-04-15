#!/usr/bin/env bash
set -euo pipefail

# DR Restore — restore backup from Google Drive
# Usage: ~/tools/dr_restore.sh [--list] [--download-only] [--system-only] [--home-only] [--src gdrive:path]

SRC="gdrive:backups/dr"
TMPDIR="${TMPDIR:-/tmp}"
RESTORE_DIR="${TMPDIR}/dr-restore"
LIST_ONLY=false
DOWNLOAD_ONLY=false
SYSTEM_ONLY=false
HOME_ONLY=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[DR]${NC} $*"; }
warn() { echo -e "${YELLOW}[DR]${NC} $*"; }
err()  { echo -e "${RED}[DR]${NC} $*" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Restore a DR backup from Google Drive.

Options:
  --list           List available backups on remote
  --download-only  Download but don't extract
  --system-only    Restore only system info (packages, /etc)
  --home-only      Restore only home directory
  --src PATH       rclone source (default: gdrive:backups/dr)
  --help           Show this help

Restore steps:
  1. Lists available backups, you pick one
  2. Downloads archives
  3. Extracts to target locations

For a fresh machine, restore order should be:
  1. Install base Arch (or any Linux)
  2. Install rclone, configure gdrive remote
  3. Run this script with --system-only first (reinstalls packages)
  4. Run this script with --home-only (restores configs + files)
  5. Reboot
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --list)          LIST_ONLY=true; shift ;;
        --download-only) DOWNLOAD_ONLY=true; shift ;;
        --system-only)   SYSTEM_ONLY=true; shift ;;
        --home-only)     HOME_ONLY=true; shift ;;
        --src)           SRC="$2"; shift 2 ;;
        --help)          usage ;;
        *)               err "Unknown option: $1"; usage ;;
    esac
done

# --- List backups ---
list_backups() {
    log "Available backups in ${SRC}:"
    echo ""
    rclone ls "${SRC}/" 2>/dev/null | sort | while read -r size name; do
        human_size=$(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B")
        echo "  ${name}  (${human_size})"
    done
    echo ""
}

if $LIST_ONLY; then
    list_backups
    exit 0
fi

# --- Pick a backup ---
log "Scanning ${SRC} for backups..."
mapfile -t FILES < <(rclone ls "${SRC}/" 2>/dev/null | awk '{print $2}' | sort)

if [[ ${#FILES[@]} -eq 0 ]]; then
    err "No backups found in ${SRC}/"
    exit 1
fi

# Get unique backup dates (supports both legacy .gpg and new .tar.zst)
mapfile -t DATES < <(printf '%s\n' "${FILES[@]}" | sed -E 's/-(home|system)\.tar\.zst(\.gpg)?$//' | sort -u)

echo ""
log "Available backups:"
for i in "${!DATES[@]}"; do
    echo "  [$i] ${DATES[$i]}"
done
echo ""
read -rp "Select backup number [0]: " SELECTION
SELECTION=${SELECTION:-0}
CHOSEN="${DATES[$SELECTION]}"
log "Selected: ${CHOSEN}"

# --- Download ---
mkdir -p "${RESTORE_DIR}"

# Detect whether this backup is legacy GPG-encrypted or plain zst
if rclone lsf "${SRC}/" 2>/dev/null | grep -q "^${CHOSEN}-home.tar.zst.gpg$"; then
    HOME_ARCHIVE="${CHOSEN}-home.tar.zst.gpg"
    SYS_ARCHIVE="${CHOSEN}-system.tar.zst.gpg"
    IS_ENCRYPTED=true
else
    HOME_ARCHIVE="${CHOSEN}-home.tar.zst"
    SYS_ARCHIVE="${CHOSEN}-system.tar.zst"
    IS_ENCRYPTED=false
fi

if ! $HOME_ONLY; then
    log "Downloading system backup..."
    rclone copy "${SRC}/${SYS_ARCHIVE}" "${RESTORE_DIR}/" --progress
fi

if ! $SYSTEM_ONLY; then
    log "Downloading home backup..."
    rclone copy "${SRC}/${HOME_ARCHIVE}" "${RESTORE_DIR}/" --progress
fi

if $DOWNLOAD_ONLY; then
    log "Downloaded to ${RESTORE_DIR}/"
    ls -lh "${RESTORE_DIR}/"
    exit 0
fi

# --- Restore system ---
if ! $HOME_ONLY && [[ -f "${RESTORE_DIR}/${SYS_ARCHIVE}" ]]; then
    echo ""
    log "Extracting system backup..."

    if $IS_ENCRYPTED; then
        warn "Legacy encrypted backup - enter your passphrase:"
        gpg --decrypt "${RESTORE_DIR}/${SYS_ARCHIVE}" 2>/dev/null \
        | zstd -d \
        | tar xf - -C "${RESTORE_DIR}/"
    else
        zstd -d < "${RESTORE_DIR}/${SYS_ARCHIVE}" \
        | tar xf - -C "${RESTORE_DIR}/"
    fi

    # Show what we got
    log "System info restored to ${RESTORE_DIR}/system/"
    ls "${RESTORE_DIR}/system/"

    echo ""
    warn "=== Package Restoration ==="
    PKGCOUNT=$(wc -l < "${RESTORE_DIR}/system/packages.list")
    warn "Found ${PKGCOUNT} packages to restore."
    read -rp "Restore packages now? (y/N): " RESTORE_PKGS
    if [[ "${RESTORE_PKGS}" =~ ^[Yy] ]]; then
        log "Restoring pacman config & mirrors..."
        [[ -f "${RESTORE_DIR}/system/pacman.conf" ]] && sudo cp "${RESTORE_DIR}/system/pacman.conf" /etc/pacman.conf
        [[ -f "${RESTORE_DIR}/system/mirrorlist" ]] && sudo cp "${RESTORE_DIR}/system/mirrorlist" /etc/pacman.d/mirrorlist
        [[ -d "${RESTORE_DIR}/system/hooks" ]] && sudo cp -r "${RESTORE_DIR}/system/hooks" /etc/pacman.d/

        log "Syncing package databases..."
        sudo pacman -Sy

        log "Installing explicit packages..."
        # --needed skips already-installed packages; xargs handles the list as args
        xargs -a "${RESTORE_DIR}/system/packages.list" sudo pacman -S --needed --noconfirm

        if [[ -s "${RESTORE_DIR}/system/packages-foreign.list" ]]; then
            warn "Foreign (AUR) packages need an AUR helper (paru/yay) to reinstall:"
            cat "${RESTORE_DIR}/system/packages-foreign.list" | sed 's/^/  /'
            echo ""
            read -rp "Install foreign packages with paru? (requires paru installed) (y/N): " RESTORE_AUR
            if [[ "${RESTORE_AUR}" =~ ^[Yy] ]]; then
                xargs -a "${RESTORE_DIR}/system/packages-foreign.list" paru -S --needed --noconfirm
            fi
        fi
    fi

    echo ""
    warn "=== /etc Restoration ==="
    warn "Your /etc backup is at: ${RESTORE_DIR}/etc.tar"
    warn "This should be restored selectively. Overwriting /etc wholesale on"
    warn "a new install can break things (different UUIDs, hardware, etc)."
    echo ""
    warn "Recommended: extract and cherry-pick what you need:"
    echo "  mkdir /tmp/etc-backup && tar xf ${RESTORE_DIR}/etc.tar -C /tmp/etc-backup"
    echo "  # Then diff and copy what you need:"
    echo "  diff /tmp/etc-backup/etc/fstab /etc/fstab"

    # Restore flatpaks if present
    if [[ -f "${RESTORE_DIR}/system/flatpaks.list" ]]; then
        echo ""
        read -rp "Restore flatpak apps? (y/N): " RESTORE_FLATPAKS
        if [[ "${RESTORE_FLATPAKS}" =~ ^[Yy] ]]; then
            while read -r app; do
                log "Installing flatpak: ${app}"
                flatpak install -y "$app" 2>/dev/null || warn "Failed: ${app}"
            done < "${RESTORE_DIR}/system/flatpaks.list"
        fi
    fi
fi

# --- Restore home ---
if ! $SYSTEM_ONLY && [[ -f "${RESTORE_DIR}/${HOME_ARCHIVE}" ]]; then
    echo ""
    warn "=== Home Directory Restoration ==="
    warn "This will extract your home directory backup."
    warn "Existing files with the same name WILL be overwritten."
    read -rp "Restore home directory to /home/scott? (y/N): " RESTORE_HOME
    if [[ "${RESTORE_HOME}" =~ ^[Yy] ]]; then
        log "Extracting home directory..."

        if $IS_ENCRYPTED; then
            warn "Legacy encrypted backup - enter your passphrase:"
            gpg --decrypt "${RESTORE_DIR}/${HOME_ARCHIVE}" 2>/dev/null \
            | zstd -d \
            | tar xf - -C /home/
        else
            zstd -d < "${RESTORE_DIR}/${HOME_ARCHIVE}" \
            | tar xf - -C /home/
        fi

        log "Home directory restored!"
    else
        log "Extracting to ${RESTORE_DIR}/home-preview/ instead..."
        mkdir -p "${RESTORE_DIR}/home-preview"
        if $IS_ENCRYPTED; then
            warn "Legacy encrypted backup - enter your passphrase:"
            gpg --decrypt "${RESTORE_DIR}/${HOME_ARCHIVE}" 2>/dev/null \
            | zstd -d \
            | tar xf - -C "${RESTORE_DIR}/home-preview/"
        else
            zstd -d < "${RESTORE_DIR}/${HOME_ARCHIVE}" \
            | tar xf - -C "${RESTORE_DIR}/home-preview/"
        fi
        log "Preview at: ${RESTORE_DIR}/home-preview/"
    fi
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        Restore Complete!             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""
warn "Recommended next steps:"
echo "  1. Review restored configs in ~/.config/"
echo "  2. Reinstall toolchains: rustup, nvm, etc."
echo "  3. Log out and back in (or reboot) for sway/waybar changes"
