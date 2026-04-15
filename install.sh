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

# --- Detect distro ---
detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
      arch|endeavouros|manjaro) echo "arch" ;;
      ubuntu|debian|pop|linuxmint) echo "debian" ;;
      *) echo "$ID" ;;
    esac
  else
    echo "unknown"
  fi
}

DISTRO=$(detect_distro)
echo "=== dotfiles bootstrap (profile: $PROFILE, distro: $DISTRO) ==="

# --- System packages ---
case "$DISTRO" in
  debian)
    sudo apt-get update -qq
    sudo apt-get install -y zsh stow git curl wget unzip fzf fd-find ripgrep bat
    ;;
  arch)
    sudo pacman -Syu --noconfirm --needed \
      zsh stow git curl wget unzip fzf rsync openssh gnupg \
      zoxide micro zellij rustup uv rclone base-devel \
      noto-fonts noto-fonts-emoji
    ;;
  *)
    echo "Unsupported distro: $DISTRO"
    echo "Install manually: zsh stow git curl wget unzip fzf"
    exit 1
    ;;
esac

# --- Detect environment ---
IS_WSL=false
[[ -f /proc/version ]] && grep -qi microsoft /proc/version && IS_WSL=true
IS_DESKTOP=false
[[ "$PROFILE" != "server" ]] && IS_DESKTOP=true

# --- Desktop packages (native Linux with display server) ---
if [[ "$IS_DESKTOP" == "true" ]]; then
  case "$DISTRO" in
    debian)
      sudo apt-get install -y \
        sway swayidle swaylock xdg-desktop-portal-wlr \
        waybar wofi mako-notifier kitty \
        grim slurp wl-clipboard \
        pipewire wireplumber pipewire-pulse \
        polkit-gnome brightnessctl playerctl \
        fonts-jetbrains-mono rclone
      ;;
    arch)
      sudo pacman -S --noconfirm --needed \
        hyprland hyprlock hypridle xdg-desktop-portal-hyprland \
        waybar mako ghostty fuzzel hyprpaper \
        grim slurp wl-clipboard \
        pipewire wireplumber pipewire-pulse \
        polkit-gnome brightnessctl playerctl \
        ttf-jetbrains-mono-nerd rclone
      ;;
  esac
fi

# --- Oh My Zsh ---
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "Installing Oh My Zsh..."
  RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# --- Zsh plugins ---
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] || \
  git clone https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] || \
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# --- Rust ---
if [[ "$DISTRO" == "arch" ]]; then
  # rustup installed via pacman, just need a toolchain
  if ! rustc --version &>/dev/null; then
    echo "Initializing Rust stable toolchain..."
    rustup default stable
  fi
else
  if ! command -v rustc &>/dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    . "$HOME/.cargo/env"
  fi
fi

# --- uv (Debian only — Arch gets it via pacman) ---
if [[ "$DISTRO" != "arch" ]] && ! command -v uv &>/dev/null; then
  echo "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# --- zoxide (Debian only — Arch gets it via pacman) ---
if [[ "$DISTRO" != "arch" ]] && ! command -v zoxide &>/dev/null; then
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

# --- micro editor (Debian only — Arch gets it via pacman) ---
if [[ "$DISTRO" != "arch" ]] && ! command -v micro &>/dev/null; then
  echo "Installing micro..."
  curl https://getmic.ro | bash
  sudo mv micro /usr/local/bin/
fi

# --- micro wikilink plugin ---
MICRO_PLUGINS="$HOME/.config/micro/plug"
if [ ! -d "$MICRO_PLUGINS/wikilink" ]; then
  mkdir -p "$MICRO_PLUGINS"
  git clone https://github.com/scott-whitson/micro-wikilink.git "$MICRO_PLUGINS/wikilink"
fi

# --- zellij (Debian only — Arch gets it via pacman) ---
if [[ "$DISTRO" != "arch" ]] && ! command -v zellij &>/dev/null; then
  echo "Installing zellij..."
  curl -L https://github.com/zellij-org/zellij/releases/latest/download/zellij-x86_64-unknown-linux-musl.tar.gz | tar xz -C /tmp
  sudo mv /tmp/zellij /usr/local/bin/
fi

# --- Helix editor ---
if ! command -v hx &>/dev/null; then
  echo "Installing Helix..."
  case "$DISTRO" in
    arch)
      sudo pacman -S --noconfirm --needed helix
      ;;
    debian)
      sudo snap install helix --classic
      ;;
  esac
fi

# --- Claude Code ---
if ! command -v claude &>/dev/null; then
  echo "Installing Claude Code..."
  npm install -g @anthropic-ai/claude-code
fi

# --- Build window-picker (Hyprland overlay tool, native Rust binary) ---
if [[ "$IS_DESKTOP" == "true" && "$DISTRO" == "arch" ]]; then
  WP_BIN="$DOTFILES_DIR/tools/window-picker/target/release/window-picker"
  if [[ ! -x "$WP_BIN" ]]; then
    echo "Building window-picker..."
    (cd "$DOTFILES_DIR/tools/window-picker" && cargo build --release)
  fi
fi

# --- Stow base packages ---
# --no-folding ensures directories are real (not symlinks), so profile
# packages can add files to the same directories (e.g. ~/.zshrc.d/)
echo "Stowing base packages..."
cd "$DOTFILES_DIR"
for pkg in base/*/; do
  pkg_name="$(basename "$pkg")"
  # Skip windows — synced separately via sync-windows.sh
  [[ "$pkg_name" == "windows" ]] && continue
  # Skip desktop packages when there's no display server (WSL, server)
  case "$pkg_name" in hypr|waybar|mako|ghostty|fuzzel) [[ "$IS_DESKTOP" != "true" ]] && continue ;; esac
  stow -d base -t "$HOME" --no-folding --adopt "$pkg_name" 2>/dev/null || stow -d base -t "$HOME" --no-folding "$pkg_name"
done
# --adopt resolves conflicts by pulling existing files into the repo;
# restore the repo's versions so our dotfiles win over defaults (e.g. Oh My Zsh)
git checkout -- base/

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
