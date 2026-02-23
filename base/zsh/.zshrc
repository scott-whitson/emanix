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
alias ll="ls -lah --color=auto"
alias gs="git status"
alias gd="git diff"
alias gl="git log --oneline -20"
alias ..="cd .."
alias ...="cd ../.."
alias vact="source .venv/bin/activate"
alias dvact="deactivate"
calc() { if [ $# -eq 0 ]; then bc -l; else echo "$*" | bc -l; fi; }

# --- Functions ---
qt() {
  if [[ -z "$OBSIDIAN_VAULT" ]]; then
    echo "OBSIDIAN_VAULT not set"; return 1
  fi
  local quarter=$(( ($(date +%-m) - 1) / 3 + 1 ))
  local file="$OBSIDIAN_VAULT/Quarterly Notes/$(date +%Y)-Q${quarter}.md"
  if [ -f "$file" ]; then
    hx "$file"
  else
    echo "Quarterly tracker not found: $file"
  fi
}

# --- Tools ---
. "$HOME/.cargo/env"
eval "$(zoxide init zsh)"
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
