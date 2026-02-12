#!/usr/bin/env bash
set -euo pipefail

# Bootstrap a new machine from this dotfiles repo.
# Usage: git clone <repo> ~/dotfiles && cd ~/dotfiles && ./install.sh

echo "=== dotfiles bootstrap ==="

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

# --- Stow all packages ---
echo "Stowing dotfiles..."
cd "$(dirname "$0")"
for pkg in zsh git micro claude; do
  stow --adopt "$pkg" 2>/dev/null || stow "$pkg"
done

# --- Set default shell to zsh ---
if [ "$SHELL" != "$(which zsh)" ]; then
  echo "Setting zsh as default shell..."
  chsh -s "$(which zsh)" || echo "Run: chsh -s \$(which zsh)"
fi

echo ""
echo "=== Done! ==="
echo "Manual steps:"
echo "  1. Update micro vault path: ~/dotfiles/micro/.config/micro/settings.json"
echo "  2. Set up SSH keys: ssh-keygen -t ed25519"
echo "  3. Log out and back in for zsh to take effect"
