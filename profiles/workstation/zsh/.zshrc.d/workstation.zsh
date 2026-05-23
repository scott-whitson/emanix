# --- Personal profile ---

export OBSIDIAN_VAULT="$HOME/vault/Whitsgrove"

# Auto-start ollama if not running
pgrep -x ollama > /dev/null || (ollama serve &>/dev/null &)

# jrnl - leading space prevents history recording
setopt HIST_IGNORE_SPACE
alias j=" jrnl"
alias jrnl=" jrnl"

# Google Drive local sync retired 2026-05-06 — datacore (Immich + Nextcloud) is now canonical.
# gdrive remote retained only as encrypted restic backup target.

# --- Work laptop sync ---
# See: Obsidian vault → computing/Work Laptop Sync.md
# Host alias "swhitson-11l-1" must resolve (NetBird / tailscale / ssh config).
WORK_HOST="scott@swhitson-11l-1"
WORK_REMOTE_DIR="~/projects"
WORK_LOCAL_DIR="$HOME/projects/work"
WORK_RSYNC_EXCLUDES=(--exclude='node_modules' --exclude='.venv' --exclude='__pycache__' --exclude='.git')

# Pull all projects from work laptop into ~/projects/work
work-pull() {
  rsync -avz --progress "${WORK_RSYNC_EXCLUDES[@]}" \
    "${WORK_HOST}:${WORK_REMOTE_DIR}/" "${WORK_LOCAL_DIR}/"
}

# Push a specific project back to the work laptop.
# Usage: work-push pearl-platform
#        work-push clients/rubber-v2
work-push() {
  if [ -z "$1" ]; then
    echo "Usage: work-push <project-path-relative-to-projects/work>"
    return 1
  fi
  local project="$1"
  if [ ! -d "${WORK_LOCAL_DIR}/${project}" ]; then
    echo "Not found: ${WORK_LOCAL_DIR}/${project}"
    return 1
  fi
  rsync -avz --progress \
    "${WORK_LOCAL_DIR}/${project}/" \
    "${WORK_HOST}:${WORK_REMOTE_DIR}/${project}/"
}
