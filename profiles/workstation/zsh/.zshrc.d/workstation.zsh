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
