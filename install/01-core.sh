#!/usr/bin/env bash
# install/01-core.sh — core Debian packages
set -euo pipefail
source "$(dirname "$0")/_common.sh"

log "refreshing apt package lists"
sudo apt update

install_font_fallback() {
	local font_dir="$HOME/.local/share/fonts/JetBrainsMonoNerd"
	local tmp extract_dir
	tmp="$(mktemp -d)"
	extract_dir="$tmp/extract"
	mkdir -p "$font_dir" "$extract_dir"
	log "downloading JetBrains Mono Nerd Font fallback"
	curl -fsSL -o "$tmp/JetBrainsMono.tar.xz" \
		https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz
	tar -xJf "$tmp/JetBrainsMono.tar.xz" -C "$extract_dir"
	find "$extract_dir" -type f -name '*.ttf' -exec cp -f {} "$font_dir"/ \;
	if [[ -z "$(find "$font_dir" -maxdepth 1 -type f -name '*.ttf' -print -quit)" ]]; then
		warn "JetBrains Mono Nerd Font archive yielded no TTFs"
	fi
	rm -rf "$tmp"
	fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true
}

install_uv() {
	if command -v uv >/dev/null 2>&1; then
		log "uv already on PATH"
		return 0
	fi
	if apt-cache show uv >/dev/null 2>&1; then
		need_pkg uv
		return 0
	fi
	log "uv not in apt; installing official binary"
	curl -fsSL https://astral.sh/uv/install.sh | sh
}

install_jetbrains_mono() {
	local candidate
	candidate="$(apt-cache policy fonts-jetbrains-mono 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
	if [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
		if need_pkg fonts-jetbrains-mono; then
			return 0
		fi
		warn "apt fonts-jetbrains-mono failed; falling back to Nerd Font"
	fi
	install_font_fallback
}

log "installing core Debian packages"
need_pkg \
	build-essential cargo rustc pkg-config \
	libgtk-4-dev libadwaita-1-dev blueprint-compiler libnotify-bin \
	git stow zsh \
	curl wget unzip rsync openssh-client gnupg \
	nodejs npm \
	fzf zoxide rclone \
	hx neovim qalc \
	fontconfig fonts-noto fonts-noto-color-emoji fonts-dejavu-core

install_uv
install_jetbrains_mono

log "Rust toolchain comes from apt packages"
if ! command -v cargo &>/dev/null; then
	warn "cargo missing after apt install"
fi
