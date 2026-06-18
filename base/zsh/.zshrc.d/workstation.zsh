# --- Personal profile ---

# Vault location is machine-specific:
#   work-laptop WSL (Debian/Ubuntu)  -> OneDrive `docs` (synced by OneDrive)
#   personal desktops                -> Whitsgrove vault (synced by Syncthing)
# Detect WSL via /proc/version (kernel-level "microsoft" marker) rather than
# $WSL_DISTRO_NAME, which isn't reliably exported to every shell.
if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
  export OBSIDIAN_VAULT="/mnt/c/Users/swhitson.CENTRALDATA/OneDrive - Central Data Systems, Inc/docs"
else
  export OBSIDIAN_VAULT="$HOME/docs/vault/Whitsgrove"
fi

# Auto-start ollama if not running
pgrep -x ollama > /dev/null || (ollama serve &>/dev/null &)


# Google Drive local sync retired 2026-05-06 — datacore (Immich + Nextcloud) is now canonical.
# gdrive remote retained only as encrypted restic backup target.

# --- Work laptop sync ---
# See: Obsidian vault → computing/Work Laptop Sync.md
# Host alias "swhitson-11l" must resolve (NetBird / tailscale / ssh config).
WORK_HOST="scott@swhitson-11l"
WORK_REMOTE_DIR="~/projects"
WORK_LOCAL_DIR="$HOME/work"
WORK_RSYNC_EXCLUDES=(--exclude='node_modules' --exclude='.venv' --exclude='__pycache__' --exclude='.git' --exclude='clients')

# Mirror all projects from the work laptop into ~/work.
work-pull() {
  rsync -avz --progress "${WORK_RSYNC_EXCLUDES[@]}" \
    "${WORK_HOST}:${WORK_REMOTE_DIR}/" "${WORK_LOCAL_DIR}/"
}

# Push a specific project back to the work laptop.
# Usage: work-push pearl-platform
#        work-push cd-connect
# `clients/` is intentionally blocked and stays outside this workflow.
work-push() {
  if [ -z "$1" ]; then
    echo "Usage: work-push <project-path-relative-to-work>"
    return 1
  fi
  local project="$1"
  if [[ "$project" == clients || "$project" == clients/* ]]; then
    echo "Blocked by exclude policy: clients"
    return 1
  fi
  if [ ! -d "${WORK_LOCAL_DIR}/${project}" ]; then
    echo "Not found: ${WORK_LOCAL_DIR}/${project}"
    return 1
  fi
  rsync -avz --progress \
    "${WORK_LOCAL_DIR}/${project}/" \
    "${WORK_HOST}:${WORK_REMOTE_DIR}/${project}/"
}
