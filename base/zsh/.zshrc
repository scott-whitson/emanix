# --- Oh My Zsh ---
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"

plugins=(
  git                       # git aliases (gst, gco, gd, etc.)
  zsh-autosuggestions       # ghost-text suggestions from history
  zsh-syntax-highlighting   # colors commands as you type
)

source $ZSH/oh-my-zsh.sh

# --- Theme overrides (after oh-my-zsh loads) ---
PROMPT=""
[[ -n "$SSH_CONNECTION" ]] && PROMPT+="%{$fg[yellow]%}%m%{$reset_color%} "
PROMPT+="%(?::%{$fg_bold[red]%}%1{🔴%} )%{$fg[cyan]%}%c%{$reset_color%}"
PROMPT+=' $(git_prompt_info)'
ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[blue]%}git:(%{$fg[blue]%}"
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[blue]%}) %{$fg[blue]%}."
RPROMPT=

# --- Path ---
export PATH="$HOME/.local/bin:$PATH"
[[ -d /snap/bin ]] && export PATH="/snap/bin:$PATH"

# --- History ---
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS   # no duplicate entries
setopt HIST_FIND_NO_DUPS      # skip dupes when searching
setopt HIST_REDUCE_BLANKS     # trim whitespace
setopt SHARE_HISTORY          # share history across terminals

# --- Git prompt performance (skip untracked files in large repos) ---
DISABLE_UNTRACKED_FILES_DIRTY="true"

# --- Navigation ---
setopt AUTO_CD                # type a directory name to cd into it
setopt AUTO_PUSHD             # cd pushes onto directory stack
setopt PUSHD_IGNORE_DUPS      # no dupes in directory stack
setopt PUSHD_SILENT            # don't print stack after pushd

# --- Completion ---
setopt COMPLETE_ALIASES
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'  # case-insensitive tab completion

# --- Colors ---
if [[ -n "$WSL_DISTRO_NAME" ]]; then
  # Fix WSL ugly background on directories
  LS_COLORS="ow=01;36" && export LS_COLORS
fi
zstyle ':completion:*' list-colors "${(@s.:.)LS_COLORS}"
autoload -Uz compinit
compinit

# --- Aliases ---
# Debian names some tools differently
command -v batcat &>/dev/null && ! command -v bat &>/dev/null && alias bat="batcat"
command -v fdfind &>/dev/null && ! command -v fd &>/dev/null && alias fd="fdfind"
alias ll="ls -lah --color=auto"
alias gs="git status"
alias gd="git diff"
alias gl="git log --oneline -20"
alias ..="cd .."
alias ...="cd ../.."
alias vact="source .venv/bin/activate"
alias lsd="ls -lt --time-style=long-iso | awk '{print \$6, \$7, \$NF}'"
alias dvact="deactivate"
alias theme="theme-switch"
calc() { if [ $# -eq 0 ]; then bc -l; else echo "$*" | bc -l; fi; }

# --- Work laptop sync ---
# See: Obsidian vault → computing/Work Laptop Sync.md
# Host alias "swhitson-11l-1" must resolve (NetBird / tailscale / ssh config).
WORK_HOST="scott@swhitson-11l-1"
WORK_REMOTE_DIR="~/projects"
WORK_LOCAL_DIR="$HOME/work-projects"
WORK_RSYNC_EXCLUDES=(--exclude='node_modules' --exclude='.venv' --exclude='__pycache__' --exclude='.git')

# Pull all projects from work laptop into ~/work-projects
work-pull() {
  rsync -avz --progress "${WORK_RSYNC_EXCLUDES[@]}" \
    "${WORK_HOST}:${WORK_REMOTE_DIR}/" "${WORK_LOCAL_DIR}/"
}

# Push a specific project back to the work laptop.
# Usage: work-push pearl-platform
#        work-push clients/rubber-v2
work-push() {
  if [ -z "$1" ]; then
    echo "Usage: work-push <project-path-relative-to-work-projects>"
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

# --- Functions ---
qt() {
  if [[ -z "$OBSIDIAN_VAULT" ]]; then
    echo "OBSIDIAN_VAULT not set"; return 1
  fi
  local quarter=$(( ($(date +%-m) - 1) / 3 + 1 ))
  local file="$OBSIDIAN_VAULT/Quarterly/$(date +%Y)-Q${quarter}.md"
  if [ -f "$file" ]; then
    hx "$file"
  else
    echo "Quarterly tracker not found: $file"
  fi
}

# --- Tools ---
. "$HOME/.cargo/env"
eval "$(zoxide init zsh)"
export FZF_DEFAULT_COMMAND='fd -H --exclude .git'
# FZF — paths differ between Debian and Arch
for fzf_keys in /usr/share/doc/fzf/examples/key-bindings.zsh /usr/share/fzf/key-bindings.zsh; do
  [[ -f "$fzf_keys" ]] && source "$fzf_keys" && break
done
for fzf_comp in /usr/share/doc/fzf/examples/completion.zsh /usr/share/fzf/completion.zsh; do
  [[ -f "$fzf_comp" ]] && source "$fzf_comp" && break
done

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# --- Profile overrides ---
for f in ~/.zshrc.d/*.zsh(N); do source "$f"; done

# Local binaries
export PATH="$HOME/bin:$PATH"
[ -f ~/.secrets ] && source ~/.secrets
