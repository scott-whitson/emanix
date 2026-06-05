#!/usr/bin/env bash
# install/04-hyprland.sh — Hyprland compositor + co-located tools
set -euo pipefail
source "$(dirname "$0")/_common.sh"

log "installing Hyprland stack"
need_pkg \
	hyprland \
	hyprlock \
	hypridle \
	hyprpaper \
	xdg-desktop-portal-hyprland \
	hyprpolkitagent \
	hyprland-guiutils
