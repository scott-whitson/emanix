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
sudo apt-get install -y zsh stow git curl wget unzip fzf

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
else
  . "$NVM_DIR/nvm.sh"
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

# --- zellij ---
if ! command -v zellij &>/dev/null; then
  echo "Installing zellij..."
  curl -L https://github.com/zellij-org/zellij/releases/latest/download/zellij-x86_64-unknown-linux-musl.tar.gz | tar xz -C /tmp
  sudo mv /tmp/zellij /usr/local/bin/
fi

# --- Claude Code ---
if ! command -v claude &>/dev/null; then
  echo "Installing Claude Code..."
  npm install -g @anthropic-ai/claude-code
fi

# --- Stow base packages ---
# --no-folding ensures directories are real (not symlinks), so profile
# packages can add files to the same directories (e.g. ~/.zshrc.d/)
echo "Stowing base packages..."
cd "$DOTFILES_DIR"
for pkg in base/*/; do
  pkg_name="$(basename "$pkg")"
  stow -d base -t "$HOME" --no-folding --adopt "$pkg_name" 2>/dev/null || stow -d base -t "$HOME" --no-folding "$pkg_name"
done

# --- Stow profile packages ---
# Profile packages add to base directories (e.g. personal/zsh adds to ~/.zshrc.d/)
# If a profile package conflicts with base (same file), unstow base first and retry
echo "Stowing profile packages..."
for pkg in "$PROFILE_DIR"/*/; do
  pkg_name="$(basename "$pkg")"
  if ! stow -d "$PROFILE_DIR" -t "$HOME" --no-folding "$pkg_name" 2>/dev/null; then
    # Conflict with base — unstow base version and retry
    stow -d base -t "$HOME" --no-folding -D "$pkg_name" 2>/dev/null || true
    stow -d "$PROFILE_DIR" -t "$HOME" --no-folding "$pkg_name"
  fi
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
