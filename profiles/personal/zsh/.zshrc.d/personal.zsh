# --- Personal profile ---

export OBSIDIAN_VAULT="$HOME/gdrive/SEW/Obsidian/Whitsgrove"

# Auto-start ollama if not running
pgrep -x ollama > /dev/null || (ollama serve &>/dev/null &)

# jrnl - leading space prevents history recording
setopt HIST_IGNORE_SPACE
alias j=" jrnl"
alias jrnl=" jrnl"

# --- Google Drive (rclone) ---
# Requires one-time setup: rclone config (add a "gdrive" remote for Google Drive)
GDRIVE_MOUNT="$HOME/gdrive"
[ -d "$GDRIVE_MOUNT" ] || mkdir -p "$GDRIVE_MOUNT"
mountpoint -q "$GDRIVE_MOUNT" || rclone mount gdrive: "$GDRIVE_MOUNT" --daemon --vfs-cache-mode full 2>/dev/null
