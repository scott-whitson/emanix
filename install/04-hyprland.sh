#!/usr/bin/env bash
# install/04-hyprland.sh — Hyprland compositor + co-located tools
set -euo pipefail
source "$(dirname "$0")/_common.sh"

if is_server; then
	log "skipping Hyprland stack on server host"
	exit 0
fi

install_if_available() {
	local pkg="$1"
	if apt-cache show "$pkg" >/dev/null 2>&1; then
		need_pkg "$pkg"
	else
		warn "skipping $pkg; not available in configured apt sources"
	fi
}

log "installing Hyprland stack"
need_pkg \
	hyprland \
	hyprlock \
	hypridle \
	hyprpaper \
	xdg-desktop-portal-hyprland \
	hyprpolkitagent
install_if_available hyprland-guiutils
