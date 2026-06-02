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

install_obsidian() {
	local arch tag version deb_url tmp
	if [[ -x /usr/bin/obsidian ]] || [[ -x /opt/Obsidian/obsidian ]]; then
		return 0
	fi
	arch="$(dpkg --print-architecture)"
	if [[ "$arch" != amd64 ]]; then
		warn "Obsidian official DEB only ships for amd64; skipping on $arch"
		return 0
	fi
	tag="$(curl -fsSI https://github.com/obsidianmd/obsidian-releases/releases/latest | tr -d '\r' | awk -F/ '/^location:/I {print $NF; exit}')"
	version="${tag#v}"
	deb_url="https://github.com/obsidianmd/obsidian-releases/releases/download/$tag/obsidian_${version}_amd64.deb"
	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' RETURN
	log "downloading Obsidian $version"
	curl -fL --progress-bar "$deb_url" -o "$tmp/obsidian.deb"
	log "installing Obsidian"
	sudo apt install -y "$tmp/obsidian.deb"
}

log "installing desktop support packages"
need_pkg \
	firefox-esr \
	waybar mako-notifier fuzzel \
	grim slurp wl-clipboard \
	pipewire wireplumber pipewire-pulse \
	brightnessctl playerctl \
	fonts-noto fonts-noto-color-emoji

install_ghostty
install_obsidian
