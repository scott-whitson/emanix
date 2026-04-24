#!/usr/bin/env bash
# install/05-desktop.sh — status bar, notifications, launcher, terminal, audio, fonts
set -euo pipefail
source "$(dirname "$0")/_common.sh"
skip_unless_profile workstation

log "installing desktop support packages"
need_pkg \
    waybar mako fuzzel ghostty \
    grim slurp wl-clipboard \
    pipewire wireplumber pipewire-pulse \
    brightnessctl playerctl \
    ttf-jetbrains-mono-nerd
