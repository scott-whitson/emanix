#!/usr/bin/env bash
# install/04-hyprland.sh — Hyprland compositor + co-located tools (workstation only)
set -euo pipefail
source "$(dirname "$0")/_common.sh"
skip_unless_profile workstation

log "installing Hyprland stack"
need_pkg \
    hyprland \
    hyprlock \
    hypridle \
    hyprpaper \
    xdg-desktop-portal-hyprland \
    polkit-gnome
