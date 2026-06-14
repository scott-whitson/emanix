#!/usr/bin/env bash
# install/09-zk.sh — zk (zk-org) notebook CLI + Helix markdown LSP backend
#
# zk powers two things in this setup:
#   - the Helix markdown language server (base/helix languages.toml: roots = [".zk"])
#     -> [[wikilink]] completion, go-to-note, dead-link diagnostics
#   - the vaultkeeper pi skill (zk list/index graph queries)
#
# Installs the latest release binary to ~/.local/bin (idempotent) and indexes
# the active Obsidian vault if it already contains a .zk notebook. It does NOT
# create .zk — the vault config lives in the synced vault, not in dotfiles.
set -euo pipefail
source "$(dirname "$0")/_common.sh"

ZK_BIN="$HOME/.local/bin/zk"
ZK_REPO="zk-org/zk"

zk_arch() {
	case "$(dpkg --print-architecture 2>/dev/null || uname -m)" in
	amd64 | x86_64) printf 'amd64' ;;
	arm64 | aarch64) printf 'arm64' ;;
	*) die "unsupported architecture for zk: $(uname -m)" ;;
	esac
}

install_zk() {
	local arch tag url tmp api_json
	arch="$(zk_arch)"
	# Fetch the release JSON fully before parsing — piping curl straight into a
	# short-circuiting reader (grep -m1/head) makes curl fail with EPIPE under
	# `set -o pipefail`. A release object has exactly one "tag_name".
	api_json="$(curl -fsSL "https://api.github.com/repos/$ZK_REPO/releases/latest")" ||
		die "could not fetch latest zk release info"
	tag="$(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' <<<"$api_json")"
	[[ -n "$tag" ]] || die "could not resolve latest zk release tag"
	url="https://github.com/$ZK_REPO/releases/download/$tag/zk-$tag-linux-$arch.tar.gz"
	log "installing zk $tag ($arch)"
	tmp="$(mktemp -d)"
	if ! curl -fsSL "$url" -o "$tmp/zk.tar.gz"; then
		rm -rf "$tmp"
		die "download failed: $url"
	fi
	tar -xzf "$tmp/zk.tar.gz" -C "$tmp"
	install -m 0755 "$tmp/zk" "$ZK_BIN"
	rm -rf "$tmp"
	log "installed $("$ZK_BIN" --version)"
}

# Install unless already present (set ZK_FORCE=1 to upgrade to latest).
if [[ -x "$ZK_BIN" ]] && [[ "${ZK_FORCE:-0}" != "1" ]]; then
	log "zk already present: $("$ZK_BIN" --version) (set ZK_FORCE=1 to upgrade)"
else
	install_zk
fi

# Resolve the active vault the same way workstation.zsh does: WSL -> OneDrive
# docs, otherwise the Whitsgrove vault. An exported OBSIDIAN_VAULT wins.
vault="${OBSIDIAN_VAULT:-}"
if [[ -z "$vault" ]]; then
	if is_wsl; then
		vault="/mnt/c/Users/swhitson.CENTRALDATA/OneDrive - Central Data Systems, Inc/docs"
	else
		vault="$HOME/docs/vault/Whitsgrove"
	fi
fi

if [[ -d "$vault/.zk" ]]; then
	log "indexing zk notebook: $vault"
	"$ZK_BIN" index --notebook-dir "$vault" || warn "zk index failed for $vault"
else
	warn "no .zk notebook at '$vault'; skipping index (run 'zk init' there to enable the LSP)"
fi
