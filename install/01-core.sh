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

install_zellij() {
	if command -v zellij >/dev/null 2>&1; then
		log "zellij already on PATH"
		return 0
	fi

	if apt-cache show zellij >/dev/null 2>&1; then
		need_pkg zellij
		return 0
	fi

	local arch target tag release_json asset_url tmp
	arch="$(dpkg --print-architecture)"
	case "$arch" in
	amd64) target="x86_64-unknown-linux-musl" ;;
	arm64) target="aarch64-unknown-linux-musl" ;;
	*)
		warn "zellij binary install unsupported on architecture $arch"
		return 0
		;;
	esac

	release_json="$(mktemp)"
	trap 'rm -f "$release_json"' RETURN
	curl -fsSL https://api.github.com/repos/zellij-org/zellij/releases/latest -o "$release_json"
	tag="$(
		python3 - "$release_json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(data["tag_name"])
PY
	)"
	asset_url="$(
		python3 - "$release_json" "$target" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
target = sys.argv[2]
preferred = [f"zellij-no-web-{target}.tar.gz", f"zellij-{target}.tar.gz"]
for want in preferred:
    for asset in data.get("assets", []):
        if asset.get("name") == want:
            print(asset["browser_download_url"])
            raise SystemExit(0)
raise SystemExit(1)
PY
	)"
	if [[ -z "$asset_url" ]]; then
		warn "could not resolve zellij release asset for $target"
		return 0
	fi

	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp" "$release_json"' RETURN
	log "installing zellij $tag ($target)"
	curl -fL "$asset_url" -o "$tmp/zellij.tar.gz"
	tar -xzf "$tmp/zellij.tar.gz" -C "$tmp"
	install -d -m 0755 "$HOME/.local/bin"
	install -m 0755 "$tmp/zellij" "$HOME/.local/bin/zellij"
}

log "installing core Debian packages"
need_pkg \
	build-essential cargo rustc pkg-config \
	libgtk-4-dev libadwaita-1-dev libgtk4-layer-shell-dev blueprint-compiler libnotify-bin \
	git stow zsh \
	curl wget unzip rsync openssh-client gnupg jq \
	nodejs npm \
	fzf zoxide rclone \
	hx neovim qalc \
	syncthing \
	fontconfig fonts-noto fonts-noto-color-emoji fonts-dejavu-core

install_uv
install_jetbrains_mono
install_zellij

log "Rust toolchain comes from apt packages"
if ! command -v cargo &>/dev/null; then
	warn "cargo missing after apt install"
fi
