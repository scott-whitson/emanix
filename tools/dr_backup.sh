#!/usr/bin/env bash
set -euo pipefail

# DR Backup — compressed backup to Google Drive
# Usage: ~/dotfiles/tools/dr_backup.sh [--dry-run] [--no-upload] [--dest gdrive:path]

BACKUP_DATE=$(date +%Y-%m-%d)
HOSTNAME=$(uname -n)
BACKUP_NAME="dr-${HOSTNAME}-${BACKUP_DATE}"
TMPDIR="${TMPDIR:-/tmp}"
STAGING="${TMPDIR}/${BACKUP_NAME}"
DEST="gdrive:backups/dr"
DRY_RUN=false
NO_UPLOAD=false

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

Create a compressed backup and upload to Google Drive.

Options:
  --dry-run      Show what would be backed up without doing it
  --no-upload    Create backup locally but don't upload
  --dest PATH    rclone destination (default: gdrive:backups/dr)
  --help         Show this help

What gets backed up:
  HOME: dotfiles, projects, downloads, .config, .claude, .gemini,
        .oh-my-zsh, .local, snap, and all dotfiles in home root
        (.zshrc, .gitconfig, etc.)
  SYSTEM: /etc, package list, pacman config & mirrors, systemd user units

What gets skipped:
  gdrive, .steam, .cache, .rustup, .nvm, .npm, .cargo, .factorio,
  node_modules, .venv, __pycache__, target, .gradle, .next,
  projects/rox/data, projects/work/clients, .git/objects (keeps
  .git/config and refs)
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)   DRY_RUN=true; shift ;;
        --no-upload) NO_UPLOAD=true; shift ;;
        --dest)      DEST="$2"; shift 2 ;;
        --help)      usage ;;
        *)           err "Unknown option: $1"; usage ;;
    esac
done

# --- Preflight checks ---
for cmd in tar zstd rclone; do
    if ! command -v "$cmd" &>/dev/null; then
        err "Required command not found: $cmd"
        exit 1
    fi
done

# --- Collect system info ---
collect_system_info() {
    log "Collecting system info..."
    mkdir -p "${STAGING}/system"

    # Package list (explicitly installed — omits deps pulled in automatically)
    pacman -Qqe > "${STAGING}/system/packages.list"
    log "  Saved package list ($(wc -l < "${STAGING}/system/packages.list") explicit packages)"

    # Foreign packages (AUR / manually built — not in sync repos)
    pacman -Qqem > "${STAGING}/system/packages-foreign.list" 2>/dev/null || true

    # Pacman config & mirrors
    cp /etc/pacman.conf "${STAGING}/system/" 2>/dev/null || true
    cp /etc/pacman.d/mirrorlist "${STAGING}/system/" 2>/dev/null || true
    [[ -d /etc/pacman.d/hooks ]] && cp -r /etc/pacman.d/hooks "${STAGING}/system/" 2>/dev/null || true

    # Key system configs
    for f in /etc/fstab /etc/hostname /etc/hosts /etc/locale.gen /etc/default/grub; do
        [[ -f "$f" ]] && cp "$f" "${STAGING}/system/" 2>/dev/null || true
    done

    # Flatpak list if available
    if command -v flatpak &>/dev/null; then
        flatpak list --app --columns=application > "${STAGING}/system/flatpaks.list" 2>/dev/null || true
    fi

    # Snap list if available
    if command -v snap &>/dev/null; then
        snap list 2>/dev/null > "${STAGING}/system/snaps.list" || true
    fi

    # Systemd user units
    if [[ -d ~/.config/systemd/user ]]; then
        mkdir -p "${STAGING}/system/systemd-user"
        cp -r ~/.config/systemd/user/* "${STAGING}/system/systemd-user/" 2>/dev/null || true
    fi

    # Crontab (if cron is installed — Arch default is systemd timers)
    command -v crontab &>/dev/null && crontab -l > "${STAGING}/system/crontab" 2>/dev/null || true

    # LUKS header backup (only if root is on a LUKS-encrypted block device)
    ROOT_SRC="$(findmnt -n -o SOURCE /)"
    CRYPT_BACKING=""
    if [[ "$ROOT_SRC" == /dev/mapper/* ]]; then
        # Follow the mapper → find the underlying block device
        CRYPT_BACKING="$(cryptsetup status "$(basename "$ROOT_SRC")" 2>/dev/null \
            | awk '/device:/{print $2}')"
    fi
    if [[ -n "$CRYPT_BACKING" ]] && cryptsetup isLuks "$CRYPT_BACKING" 2>/dev/null; then
        log "  Root is on LUKS ($CRYPT_BACKING) — capturing header..."
        if sudo -n true 2>/dev/null; then
            sudo cryptsetup luksHeaderBackup "$CRYPT_BACKING" \
                --header-backup-file "${STAGING}/system/luks-header.img" 2>/dev/null \
                && log "  LUKS header saved ($(du -sh "${STAGING}/system/luks-header.img" | cut -f1))" \
                || warn "  LUKS header backup failed"
        else
            warn "  sudo required for LUKS header backup — skipped"
        fi
    else
        log "  Root is not on LUKS — skipping header backup"
    fi

    log "  System info collected"
}

# --- Home directory excludes ---
HOME_EXCLUDES=(
    # Already on Google Drive or redownloadable
    "gdrive"
    ".steam"
    ".cache"
    ".rustup"
    ".nvm"
    ".npm"
    ".cargo"
    ".factorio"

    # Build artifacts / caches
    "node_modules"
    ".venv"
    "__pycache__"
    ".tox"
    "target"          # Rust build dir
    ".gradle"
    ".next"           # Next.js build cache

    # Large regenerable data
    ".local/share/Trash"
    ".local/share/Steam"
    "projects/rox/data"      # Lives on minne server
    "projects/work/clients"  # Client data lives on work SharePoint — never in personal backup

    # Temp / lock files
    "*.swp"
    "*.swo"
    ".DS_Store"
)

build_exclude_args() {
    local args=()
    for pattern in "${HOME_EXCLUDES[@]}"; do
        args+=("--exclude=${pattern}")
    done
    echo "${args[@]}"
}

# --- Dry run ---
if $DRY_RUN; then
    log "DRY RUN — showing what would be backed up"
    echo ""
    warn "Home directory contents (with excludes applied):"
    exclude_args=$(build_exclude_args)
    # shellcheck disable=SC2086
    du -sh --exclude='.git/objects' $exclude_args /home/scott/ 2>/dev/null || true
    echo ""
    warn "System info that would be collected:"
    echo "  - Explicit package list (pacman -Qqe)"
    echo "  - Foreign/AUR package list (pacman -Qqem)"
    echo "  - Pacman config, mirrorlist, hooks"
    echo "  - System configs (fstab, hostname, hosts, locale, grub)"
    echo "  - Flatpak list (if present)"
    echo "  - Systemd user units"
    echo "  - Crontab (if cron installed)"
    echo ""
    warn "Would upload to: ${DEST}/${BACKUP_NAME}-home.tar.zst and -system.tar.zst"
    exit 0
fi

# --- /etc backup ---
backup_etc() {
    log "Backing up /etc..."
    if sudo -n true 2>/dev/null; then
        sudo tar cf "${STAGING}/etc.tar" \
            --exclude='*.pacnew' \
            --exclude='*.pacsave' \
            /etc/ 2>/dev/null
        log "  /etc saved ($(du -sh "${STAGING}/etc.tar" | cut -f1))"
    else
        warn "sudo not available without password prompt — backing up readable /etc files only"
        tar cf "${STAGING}/etc.tar" \
            --exclude='*.pacnew' \
            --exclude='*.pacsave' \
            --ignore-failed-read \
            /etc/ 2>/dev/null || true
        log "  /etc saved (partial, $(du -sh "${STAGING}/etc.tar" | cut -f1))"
    fi
}

# --- Main backup ---
main() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     DR Backup — ${BACKUP_DATE}        ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo ""

    # Staging
    rm -rf "${STAGING}"
    mkdir -p "${STAGING}"

    # System info
    collect_system_info

    # /etc
    backup_etc

    # Home directory tar + compress (streamed)
    log "Creating compressed backup of home directory..."

    ARCHIVE="${STAGING}/${BACKUP_NAME}-home.tar.zst"

    exclude_args=$(build_exclude_args)
    # shellcheck disable=SC2086
    tar cf - \
        --exclude='.git/objects' \
        $exclude_args \
        -C /home scott \
    | zstd -T0 -9 -o "${ARCHIVE}"

    HOME_SIZE=$(du -sh "${ARCHIVE}" | cut -f1)
    log "Home backup created: ${HOME_SIZE}"

    # System archive
    log "Compressing system info..."
    SYSARCHIVE="${STAGING}/${BACKUP_NAME}-system.tar.zst"
    tar cf - -C "${STAGING}" system etc.tar \
    | zstd -T0 -9 -o "${SYSARCHIVE}"

    SYS_SIZE=$(du -sh "${SYSARCHIVE}" | cut -f1)
    log "System backup created: ${SYS_SIZE}"

    # Clean up staging dirs
    rm -rf "${STAGING}/system" "${STAGING}/etc.tar"

    # Upload
    if $NO_UPLOAD; then
        warn "Skipping upload (--no-upload)"
        log "Backup files in: ${STAGING}/"
        ls -lh "${STAGING}/"
    else
        log "Uploading to ${DEST}..."
        rclone mkdir "${DEST}" 2>/dev/null || true

        rclone copy "${ARCHIVE}" "${DEST}/" --progress
        rclone copy "${SYSARCHIVE}" "${DEST}/" --progress

        log "Upload complete!"

        # Verify
        log "Verifying upload..."
        rclone ls "${DEST}/" 2>/dev/null | grep "${BACKUP_NAME}" && log "Verified on remote" || warn "Could not verify"

        # Clean up local staging
        rm -rf "${STAGING}"
        log "Local staging cleaned up"
    fi

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          Backup Complete!            ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC} Home:   ${HOME_SIZE}                       ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC} System: ${SYS_SIZE}                       ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC} Dest:   ${DEST}/  ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""
    warn "To restore, see: ~/dotfiles/tools/dr_restore.sh"
}

main
