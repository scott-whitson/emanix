# Multi-Profile Dotfiles Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reorganize flat stow packages into base + profile layers so dotfiles can be deployed to personal, work, and server machines with a single command.

**Architecture:** Base stow packages provide shared config. Profile stow packages overlay system-specific files into `~/.zshrc.d/`, `~/.gitconfig.local`, etc. An install script takes a profile name and stows the right combination.

**Tech Stack:** GNU Stow, zsh, git includes

---

### Task 1: Commit pending .zshrc changes

The working tree has uncommitted additions (ollama, jrnl, fzf). Commit these before restructuring so nothing is lost.

**Files:**
- Modify: `zsh/.zshrc` (already modified, just needs committing)

**Step 1: Stage and commit**

```bash
git add zsh/.zshrc
git commit -m "Add ollama auto-start, jrnl aliases, and fzf integration"
```

**Step 2: Verify clean working tree**

Run: `git status`
Expected: nothing to commit, working tree clean

---

### Task 2: Unstow old packages

Remove all current symlinks so we can reorganize without conflicts.

**Files:**
- Affects: `~/.zshrc`, `~/.gitconfig`, `~/.config/micro/settings.json`, `~/.config/micro/bindings.json`, `~/.claude/settings.json`

**Step 1: Unstow all packages**

```bash
cd ~/dotfiles
stow -D zsh
stow -D git
stow -D micro
stow -D claude
```

**Step 2: Verify symlinks are gone**

Run: `ls -la ~/.zshrc ~/.gitconfig ~/.config/micro/settings.json ~/.config/micro/bindings.json ~/.claude/settings.json 2>&1`
Expected: "No such file or directory" for each

---

### Task 3: Create base/zsh with split .zshrc

Move .zshrc into base/, strip profile-specific lines, add the .zshrc.d sourcing loop.

**Files:**
- Create: `base/zsh/.zshrc`
- Create: `base/zsh/.zshrc.d/.gitkeep`
- Delete (later, Task 9): `zsh/.zshrc`

**Step 1: Create directory structure**

```bash
mkdir -p base/zsh/.zshrc.d
touch base/zsh/.zshrc.d/.gitkeep
```

**Step 2: Write base .zshrc**

Create `base/zsh/.zshrc` with the following content. This is the current .zshrc with these removals:
- Ollama auto-start (line 13-14) → personal profile
- jrnl aliases + HIST_IGNORE_SPACE (lines 62-65) → personal profile
- fzf sourcing (lines 84-86) → personal profile
- Google Drive mount (lines 88-90) → personal profile
- qt() hardcoded path → replaced with $OBSIDIAN_VAULT variable

```zsh
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
PROMPT="%(?::%{$fg_bold[red]%}%1{🔴%} )%{$fg[cyan]%}%c%{$reset_color%}"
PROMPT+=' $(git_prompt_info)'
ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[blue]%}git:(%{$fg[blue]%}"
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[blue]%}) %{$fg[blue]%}."
RPROMPT='%F{245}%D{%I:%M$([ $(date +%H) -ge 12 ] && echo ".")}%f'

# --- Path ---
export PATH="$HOME/.local/bin:$PATH"

# --- History ---
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS   # no duplicate entries
setopt HIST_FIND_NO_DUPS      # skip dupes when searching
setopt HIST_REDUCE_BLANKS     # trim whitespace
setopt SHARE_HISTORY          # share history across terminals

# --- Git prompt performance (skip untracked files on /mnt/ paths) ---
DISABLE_UNTRACKED_FILES_DIRTY="true"

# --- Navigation ---
setopt AUTO_CD                # type a directory name to cd into it
setopt AUTO_PUSHD             # cd pushes onto directory stack
setopt PUSHD_IGNORE_DUPS      # no dupes in directory stack
setopt PUSHD_SILENT            # don't print stack after pushd

# --- Completion ---
setopt COMPLETE_ALIASES
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'  # case-insensitive tab completion

# --- Colors (fix WSL ugly background on directories) ---
LS_COLORS="ow=01;36" && export LS_COLORS
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
  local file="$OBSIDIAN_VAULT/Quarterly/$(date +%Y)-Q${quarter}.md"
  if [ -f "$file" ]; then
    micro "$file"
  else
    echo "Quarterly tracker not found: $file"
  fi
}

# --- Tools ---
. "$HOME/.cargo/env"
eval "$(zoxide init zsh)"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# --- Profile overrides ---
for f in ~/.zshrc.d/*.zsh(N); do source "$f"; done
```

Note: `(N)` is a zsh glob qualifier that suppresses errors when no files match.

**Step 3: Verify**

Run: `diff <(cat base/zsh/.zshrc) /dev/null | head -5`
Expected: file exists and has content

**Step 4: Commit**

```bash
git add base/zsh/
git commit -m "Add base zsh config with profile sourcing"
```

---

### Task 4: Create base/git with include directive

**Files:**
- Create: `base/git/.gitconfig`
- Delete (later, Task 9): `git/.gitconfig`

**Step 1: Write base .gitconfig**

Create `base/git/.gitconfig`:

```ini
[core]
	autocrlf = input
[include]
	path = ~/.gitconfig.local
```

**Step 2: Commit**

```bash
git add base/git/
git commit -m "Add base git config with local include"
```

---

### Task 5: Create base/micro and base/claude

**Files:**
- Create: `base/micro/.config/micro/bindings.json` (copy from current)
- Create: `base/claude/.claude/settings.json` (copy from current)
- Delete (later, Task 9): `micro/`, `claude/`

**Step 1: Create directories and copy files**

```bash
mkdir -p base/micro/.config/micro
cp micro/.config/micro/bindings.json base/micro/.config/micro/bindings.json

mkdir -p base/claude/.claude
cp claude/.claude/settings.json base/claude/.claude/settings.json
```

Note: micro `settings.json` is NOT included in base — it gets templated by install.sh per profile.

**Step 2: Commit**

```bash
git add base/micro/ base/claude/
git commit -m "Add base micro and claude configs"
```

---

### Task 6: Create personal profile

**Files:**
- Create: `profiles/personal/profile.conf`
- Create: `profiles/personal/zsh/.zshrc.d/personal.zsh`
- Create: `profiles/personal/git/.gitconfig.local`

**Step 1: Create directory structure**

```bash
mkdir -p profiles/personal/zsh/.zshrc.d
mkdir -p profiles/personal/git
```

**Step 2: Write profile.conf**

Create `profiles/personal/profile.conf`:

```bash
OBSIDIAN_VAULT="/mnt/h/My Drive/SEW/Obsidian/Whitsgrove"
```

**Step 3: Write personal.zsh**

Create `profiles/personal/zsh/.zshrc.d/personal.zsh`:

```zsh
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
```

**Step 4: Write .gitconfig.local**

Create `profiles/personal/git/.gitconfig.local`:

```ini
[user]
	name = Scott Whitson
	email = scott@whitsoninterfacesystems.com
```

**Step 5: Commit**

```bash
git add profiles/personal/
git commit -m "Add personal profile (ollama, jrnl, fzf, Google Drive)"
```

---

### Task 7: Create work and server profiles

**Files:**
- Create: `profiles/work/profile.conf`
- Create: `profiles/work/zsh/.zshrc.d/work.zsh`
- Create: `profiles/work/git/.gitconfig.local`
- Create: `profiles/server/profile.conf`
- Create: `profiles/server/zsh/.zshrc.d/server.zsh`
- Create: `profiles/server/git/.gitconfig.local`
- Create: `profiles/server/claude/.claude/settings.json`

**Step 1: Create work profile**

```bash
mkdir -p profiles/work/zsh/.zshrc.d
mkdir -p profiles/work/git
```

Create `profiles/work/profile.conf`:

```bash
OBSIDIAN_VAULT=""  # TODO: set work vault path
```

Create `profiles/work/zsh/.zshrc.d/work.zsh`:

```zsh
# --- Work profile ---

# export OBSIDIAN_VAULT="/path/to/work/vault"  # TODO: set when ready
```

Create `profiles/work/git/.gitconfig.local`:

```ini
[user]
	name = Scott Whitson
	email = TODO@work-domain.com
```

**Step 2: Create server profile**

```bash
mkdir -p profiles/server/zsh/.zshrc.d
mkdir -p profiles/server/git
mkdir -p profiles/server/claude/.claude
```

Create `profiles/server/zsh/.zshrc.d/server.zsh`:

```zsh
# --- Server profile ---
# Add server-specific config here
```

Create `profiles/server/git/.gitconfig.local`:

```ini
[user]
	name = Scott Whitson
	email = scott@whitsoninterfacesystems.com
```

Create `profiles/server/claude/.claude/settings.json` (trimmed — no playwright, frontend-design, rust-analyzer-lsp):

```json
{
  "enabledPlugins": {
    "context7@claude-plugins-official": true,
    "serena@claude-plugins-official": true,
    "superpowers@claude-plugins-official": true,
    "code-review@claude-plugins-official": true,
    "code-simplifier@claude-plugins-official": true,
    "feature-dev@claude-plugins-official": true,
    "claude-md-management@claude-plugins-official": true,
    "mind@memvid": true
  },
  "alwaysThinkingEnabled": true
}
```

**Step 3: Commit**

```bash
git add profiles/work/ profiles/server/
git commit -m "Add work and server profiles"
```

---

### Task 8: Rewrite install.sh

Replace the current install script with one that accepts a profile argument.

**Files:**
- Modify: `install.sh`

**Step 1: Write new install.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-}"
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "$PROFILE" ]] || [[ ! -d "$DOTFILES_DIR/profiles/$PROFILE" ]]; then
  echo "Usage: ./install.sh <profile>"
  echo ""
  echo "Available profiles:"
  for p in "$DOTFILES_DIR"/profiles/*/; do
    echo "  $(basename "$p")"
  done
  exit 1
fi

PROFILE_DIR="$DOTFILES_DIR/profiles/$PROFILE"
echo "=== dotfiles bootstrap (profile: $PROFILE) ==="

# --- System packages ---
sudo apt-get update -qq
sudo apt-get install -y zsh stow git curl wget unzip

# --- Oh My Zsh ---
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "Installing Oh My Zsh..."
  RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# --- Zsh plugins ---
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] || \
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] || \
  git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# --- Rust ---
if ! command -v rustc &>/dev/null; then
  echo "Installing Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  . "$HOME/.cargo/env"
fi

# --- uv (Python package manager) ---
if ! command -v uv &>/dev/null; then
  echo "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# --- zoxide ---
if ! command -v zoxide &>/dev/null; then
  echo "Installing zoxide..."
  curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
fi

# --- nvm + Node ---
export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
  echo "Installing nvm..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  . "$NVM_DIR/nvm.sh"
  nvm install --lts
fi

# --- micro editor ---
if ! command -v micro &>/dev/null; then
  echo "Installing micro..."
  curl https://getmic.ro | bash
  sudo mv micro /usr/local/bin/
fi

# --- micro wikilink plugin ---
MICRO_PLUGINS="$HOME/.config/micro/plug"
if [ ! -d "$MICRO_PLUGINS/wikilink" ]; then
  mkdir -p "$MICRO_PLUGINS"
  git clone https://github.com/obedm503/micro-wikilink "$MICRO_PLUGINS/wikilink"
fi

# --- Claude Code ---
if ! command -v claude &>/dev/null; then
  echo "Installing Claude Code..."
  npm install -g @anthropic-ai/claude-code
fi

# --- Stow base packages ---
echo "Stowing base packages..."
cd "$DOTFILES_DIR"
for pkg in base/*/; do
  pkg_name="$(basename "$pkg")"
  # Skip if profile overrides this package
  if [ -d "$PROFILE_DIR/$pkg_name" ]; then
    echo "  Skipping base/$pkg_name (overridden by profile)"
    continue
  fi
  stow -d base --adopt "$pkg_name" 2>/dev/null || stow -d base "$pkg_name"
done

# --- Stow profile packages ---
echo "Stowing profile packages..."
for pkg in "$PROFILE_DIR"/*/; do
  pkg_name="$(basename "$pkg")"
  stow -d "$PROFILE_DIR" --adopt "$pkg_name" 2>/dev/null || stow -d "$PROFILE_DIR" "$pkg_name"
done

# --- Template micro settings ---
if [ -f "$PROFILE_DIR/profile.conf" ]; then
  source "$PROFILE_DIR/profile.conf"
fi
if [[ -n "${OBSIDIAN_VAULT:-}" ]]; then
  echo "Configuring micro wikilink vault..."
  mkdir -p "$HOME/.config/micro"
  cat > "$HOME/.config/micro/settings.json" <<MICEOF
{
    "wikilink.vault": "$OBSIDIAN_VAULT"
}
MICEOF
fi

# --- Set default shell to zsh ---
if [ "$SHELL" != "$(which zsh)" ]; then
  echo "Setting zsh as default shell..."
  chsh -s "$(which zsh)" || echo "Run: chsh -s \$(which zsh)"
fi

echo ""
echo "=== Done! (profile: $PROFILE) ==="
echo "Manual steps:"
echo "  1. Set up SSH keys: ssh-keygen -t ed25519"
echo "  2. Log out and back in for zsh to take effect"
```

**Step 2: Commit**

```bash
git add install.sh
git commit -m "Rewrite install.sh to support profile-based setup"
```

---

### Task 9: Remove old flat directories

Remove the original flat stow package directories now that everything is in base/ and profiles/.

**Files:**
- Delete: `zsh/`
- Delete: `git/`
- Delete: `micro/`
- Delete: `claude/`

**Step 1: Remove old directories**

```bash
git rm -r zsh/ git/ micro/ claude/
```

**Step 2: Commit**

```bash
git commit -m "Remove old flat stow directories (replaced by base + profiles)"
```

---

### Task 10: Stow new structure on this machine and verify

Apply the new personal profile on the current machine and verify everything works.

**Step 1: Stow base packages**

```bash
cd ~/dotfiles
for pkg in base/*/; do
  pkg_name="$(basename "$pkg")"
  # Skip claude since server would override, but personal doesn't — stow it
  stow -d base "$pkg_name"
done
```

**Step 2: Stow personal profile**

```bash
stow -d profiles/personal zsh
stow -d profiles/personal git
```

**Step 3: Template micro settings**

```bash
source profiles/personal/profile.conf
mkdir -p ~/.config/micro
cat > ~/.config/micro/settings.json <<EOF
{
    "wikilink.vault": "$OBSIDIAN_VAULT"
}
EOF
```

**Step 4: Verify symlinks**

Run: `ls -la ~/.zshrc ~/.gitconfig ~/.config/micro/bindings.json ~/.claude/settings.json ~/.zshrc.d/ ~/.gitconfig.local`

Expected:
- `~/.zshrc` → `dotfiles/base/zsh/.zshrc`
- `~/.gitconfig` → `dotfiles/base/git/.gitconfig`
- `~/.config/micro/bindings.json` → `dotfiles/base/micro/.config/micro/bindings.json`
- `~/.claude/settings.json` → `dotfiles/base/claude/.claude/settings.json`
- `~/.zshrc.d/personal.zsh` → `dotfiles/profiles/personal/zsh/.zshrc.d/personal.zsh`
- `~/.gitconfig.local` → `dotfiles/profiles/personal/git/.gitconfig.local`
- `~/.config/micro/settings.json` → real file (not symlink, templated)

**Step 5: Verify shell loads cleanly**

Run: `zsh -c 'source ~/.zshrc && echo "OK: shell loaded"'`
Expected: "OK: shell loaded" with no errors

**Step 6: Verify git identity**

Run: `git config user.email`
Expected: `scott@whitsoninterfacesystems.com`

**Step 7: Commit verification notes (if any fixes were needed)**

---

### Task 11: Update README.md

Update the README to document the new profile system.

**Files:**
- Modify: `README.md`

**Step 1: Rewrite README**

Update to document:
- The base + profiles structure
- How to bootstrap a new machine: `git clone ... && ./install.sh <profile>`
- Available profiles and what each includes
- How to add a new profile
- How to add/modify config for a specific machine

**Step 2: Commit**

```bash
git add README.md
git commit -m "Update README for multi-profile setup"
```
