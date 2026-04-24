#!/usr/bin/env bash
# install/01-pacman.sh — core pacman packages (cross-profile)
set -euo pipefail
source "$(dirname "$0")/_common.sh"

log "installing core pacman packages"
need_pkg \
    base-devel git stow zsh \
    curl wget unzip rsync openssh gnupg \
    fzf zoxide rclone \
    rustup uv \
    helix neovim \
    noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd

log "initializing rustup stable toolchain if needed"
if ! rustc --version &>/dev/null; then
    rustup default stable
fi
