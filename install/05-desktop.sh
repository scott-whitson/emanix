#!/usr/bin/env bash
# install/05-desktop.sh — status bar, notifications, launcher, terminal, audio
set -euo pipefail
source "$(dirname "$0")/_common.sh"

ensure_griffo_repo() {
	local keyring=/etc/apt/trusted.gpg.d/debian.griffo.io.gpg
	local list=/etc/apt/sources.list.d/debian.griffo.io.list
	if grep -Rqs 'debian.griffo.io/apt' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
		return 0
	fi
	local codename
	codename="${VERSION_CODENAME:-}"
	if [[ -z "$codename" ]] && [[ -r /etc/os-release ]]; then
		# shellcheck disable=SC1091
		source /etc/os-release
		codename="${VERSION_CODENAME:-}"
	fi
	log "adding griffo apt repo for ghostty"
	curl -fsSL https://debian.griffo.io/EA0F721D231FDD3A0A17B9AC7808B4DD62C41256.asc | sudo gpg --dearmor --yes -o "$keyring"
	echo "deb https://debian.griffo.io/apt ${codename:-forky} main" | sudo tee "$list" >/dev/null
	sudo apt update
}

install_ghostty() {
	local candidate
	candidate="$(apt-cache policy ghostty 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
	if [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
		need_pkg ghostty
		return 0
	fi
	ensure_griffo_repo
	need_pkg ghostty
}

log "installing desktop support packages"
need_pkg \
	waybar mako-notifier fuzzel \
	grim slurp wl-clipboard \
	pipewire wireplumber pipewire-pulse \
	brightnessctl playerctl \
	fonts-noto fonts-noto-color-emoji

install_ghostty
