# --- Personal profile ---

export OBSIDIAN_VAULT="$HOME/gdrive/SEW/Obsidian/Whitsgrove"

# Auto-start ollama if not running
pgrep -x ollama > /dev/null || (ollama serve &>/dev/null &)

# jrnl - leading space prevents history recording
setopt HIST_IGNORE_SPACE
alias j=" jrnl"
alias jrnl=" jrnl"

# --- Google Drive (local sync) ---
# Local copy of Google Drive, synced hourly via cron (rclone bisync)
# rox shortcuts
alias rsu='cd ~/projects/rox && source .venv/bin/activate && rox-sync upgrade'
alias rt='ssh -t minne "cd /opt/rox && source .venv/bin/activate && rox-tui"'

export GDRIVE="$HOME/gdrive"
[ -d "$GDRIVE" ] || mkdir -p "$GDRIVE"
