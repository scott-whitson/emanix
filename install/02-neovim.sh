#!/usr/bin/env bash
# install/02-neovim.sh — Neovim (latest stable release) for LazyVim
#
# Debian apt caps neovim at 0.10.x; LazyVim tracks latest stable. Fetch the
# official release tarball into ~/.local/opt/nvim and symlink the binary into
# ~/.local/bin (which precedes /usr/bin on PATH, so it shadows the apt nvim
# that 01-core installs as a fallback).
set -euo pipefail
source "$(dirname "$0")/_common.sh"

NVIM_REPO="neovim/neovim"
NVIM_OPT="$HOME/.local/opt/nvim"
NVIM_BIN="$HOME/.local/bin/nvim"

nvim_asset() {
	case "$(uname -m)" in
	x86_64 | amd64) printf 'nvim-linux-x86_64.tar.gz' ;;
	aarch64 | arm64) printf 'nvim-linux-arm64.tar.gz' ;;
	*) die "unsupported architecture for neovim: $(uname -m)" ;;
	esac
}

nvim_version() { "$NVIM_BIN" --version 2>/dev/null | sed -n '1s/^NVIM //p'; }

install_nvim() {
	local asset tag url tmp api_json
	asset="$(nvim_asset)"
	# Fetch the release JSON fully before parsing — piping curl straight into a
	# short-circuiting reader (grep -m1/head) makes curl fail with EPIPE under
	# `set -o pipefail`. A release object has exactly one "tag_name".
	api_json="$(curl -fsSL "https://api.github.com/repos/$NVIM_REPO/releases/latest")" ||
		die "could not fetch latest neovim release info"
	tag="$(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' <<<"$api_json")"
	[[ -n "$tag" ]] || die "could not resolve latest neovim release tag"
	url="https://github.com/$NVIM_REPO/releases/download/$tag/$asset"
	log "installing neovim $tag ($asset)"
	tmp="$(mktemp -d)"
	if ! curl -fsSL "$url" -o "$tmp/nvim.tar.gz"; then
		rm -rf "$tmp"
		die "download failed: $url"
	fi
	tar -xzf "$tmp/nvim.tar.gz" -C "$tmp"
	mkdir -p "$(dirname "$NVIM_OPT")"
	rm -rf "$NVIM_OPT"
	mv "$tmp/${asset%.tar.gz}" "$NVIM_OPT"
	rm -rf "$tmp"
	ln -sfn "$NVIM_OPT/bin/nvim" "$NVIM_BIN"
	log "installed neovim $(nvim_version) -> $NVIM_BIN"
}

# Install unless our managed copy already exists (NVIM_FORCE=1 to upgrade).
if [[ -x "$NVIM_OPT/bin/nvim" ]] && [[ "${NVIM_FORCE:-0}" != "1" ]]; then
	ln -sfn "$NVIM_OPT/bin/nvim" "$NVIM_BIN"
	log "neovim already present: $(nvim_version) (set NVIM_FORCE=1 to upgrade)"
else
	install_nvim
fi
