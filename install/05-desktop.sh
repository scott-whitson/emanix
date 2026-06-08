#!/usr/bin/env bash
# install/05-desktop.sh — status bar, notifications, launcher, terminal, audio
set -euo pipefail
source "$(dirname "$0")/_common.sh"

if is_server; then
	log "skipping workstation desktop packages on server host"
	exit 0
fi

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
	candidate="$(apt-cache show ghostty 2>/dev/null >/dev/null && apt-cache policy ghostty 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
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
	tag="$(curl -fsSL https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest | awk -F'"' '/"tag_name":/ {print $4; exit}')"
	if [[ -z "$tag" ]]; then
		die "could not resolve latest Obsidian release tag"
	fi
	version="${tag#v}"
	deb_url="https://github.com/obsidianmd/obsidian-releases/releases/download/$tag/obsidian_${version}_amd64.deb"
	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' RETURN
	log "downloading Obsidian $version"
	curl -fL --progress-bar "$deb_url" -o "$tmp/obsidian.deb"
	log "installing Obsidian"
	sudo apt install -y "$tmp/obsidian.deb"
}

install_backlight_permissions() {
	local rule=/etc/udev/rules.d/90-backlight-permissions.rules
	local service=/etc/systemd/system/dot-backlight-permissions.service
	local tmp_rule tmp_service
	tmp_rule="$(mktemp)"
	tmp_service="$(mktemp)"
	cat >"$tmp_rule" <<'EOF'
# Trigger the root service whenever a backlight device appears.
ACTION=="add", SUBSYSTEM=="backlight", TAG+="systemd", ENV{SYSTEMD_WANTS}="dot-backlight-permissions.service"
EOF
	cat >"$tmp_service" <<'EOF'
[Unit]
Description=Set writable backlight permissions for brightness keys
ConditionPathExistsGlob=/sys/class/backlight/*/brightness

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -lc 'for f in /sys/class/backlight/*/brightness; do [ -e "$f" ] || continue; chgrp video "$f" && chmod g+w "$f"; done'
EOF
	if [[ ! -f "$rule" ]] || ! cmp -s "$tmp_rule" "$rule"; then
		log "installing backlight udev trigger rule"
		sudo install -D -m 0644 "$tmp_rule" "$rule"
	fi
	if [[ ! -f "$service" ]] || ! cmp -s "$tmp_service" "$service"; then
		log "installing backlight permission service"
		sudo install -D -m 0644 "$tmp_service" "$service"
	fi
	rm -f "$tmp_rule" "$tmp_service"
	sudo systemctl daemon-reload
	sudo udevadm control --reload-rules
	sudo udevadm trigger --subsystem-match=backlight || true
	sudo systemctl start dot-backlight-permissions.service || true
}

ensure_video_group() {
	if id -nG "$USER" | tr ' ' '\n' | grep -qx video; then
		return 0
	fi
	log "adding $USER to the video group for backlight access"
	sudo usermod -aG video "$USER"
	warn "video group membership will take effect after you log out and back in"
}

log "installing desktop support packages"
need_pkg \
	firefox-esr \
	waybar mako-notifier fuzzel \
	grim slurp wl-clipboard \
	pipewire wireplumber pipewire-pulse \
	brightnessctl playerctl \
	ffmpeg libavcodec-extra gstreamer1.0-libav \
	syncthing \
	fonts-noto fonts-noto-color-emoji

install_backlight_permissions
ensure_video_group
install_ghostty
install_obsidian
