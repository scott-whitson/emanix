# --- Personal profile ---

export OBSIDIAN_VAULT="/mnt/h/My Drive/SEW/Obsidian/Whitsgrove"

# Auto-start ollama if not running
pgrep -x ollama > /dev/null || (ollama serve &>/dev/null &)

# jrnl - leading space prevents history recording
setopt HIST_IGNORE_SPACE
alias j=" jrnl"
alias jrnl=" jrnl"

# --- fzf ---
source /usr/share/doc/fzf/examples/key-bindings.zsh
source /usr/share/doc/fzf/examples/completion.zsh

# --- Google Drive mount ---
[ -d /mnt/h ] || sudo mkdir -p /mnt/h
mountpoint -q /mnt/h || sudo mount -t drvfs H: /mnt/h 2>/dev/null
