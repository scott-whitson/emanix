#!/usr/bin/env bash
# install/_common.sh — shared helpers for install/*.sh scripts
# Not executable directly; sourced by numbered scripts.

set -euo pipefail

# --- Required env (set by install.sh orchestrator) ---
: "${DOTFILES:?DOTFILES must be set (orchestrator sets this)}"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
DATACORE_GIT_ROOT="${DATACORE_GIT_ROOT:-scott@datacore:~/projects}"

# --- Log helpers ---
log() { printf '\033[1;34m[%s]\033[0m %s\n' "$(basename "${BASH_SOURCE[1]:-install}")" "$*"; }
warn() { printf '\033[1;33m[%s]\033[0m %s\n' "$(basename "${BASH_SOURCE[1]:-install}")" "$*" >&2; }
die() {
	printf '\033[1;31m[%s]\033[0m %s\n' "$(basename "${BASH_SOURCE[1]:-install}")" "$*" >&2
	exit 1
}

# --- Package helpers ---
# Install apt packages idempotently. Accepts a list.
need_pkg() {
	[[ $# -gt 0 ]] || return 0
	sudo apt install -y --no-install-recommends "$@"
}

# --- Stow helper ---
# Restow a package. Args: <stow-dir> <pkg-name>
# Uses --no-folding so directories stay real (profile packages can add to them).
stow_pkg() {
	local stow_dir="$1" pkg="$2"
	stow -d "$stow_dir" -t "$HOME" --no-folding -R "$pkg"
}

# --- Clone helper ---
# Clone a git repo if the target directory is missing OR empty.
# Tries datacore mirror first, then upstream URL.
# Args: <url> <dest> [<branch>]
repo_name_from_url() {
	local url="${1%/}"
	local name="${url##*/}"
	printf '%s' "${name%.git}"
}

clone_if_missing() {
	local url="$1" dest="$2" branch="${3:-}" repo_name mirror_url
	if [[ -d "$dest" ]] && [[ -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
		log "clone_if_missing: $dest already populated, skipping"
		return 0
	fi

	repo_name="$(repo_name_from_url "$url")"
	if [[ -n "$DATACORE_GIT_ROOT" ]] && [[ "$url" != *"datacore:"* ]] && [[ "$url" != *"datacore."* ]]; then
		mirror_url="${DATACORE_GIT_ROOT%/}/$repo_name"
		log "trying datacore mirror $mirror_url -> $dest"
		if [[ -n "$branch" ]]; then
			if git clone --branch "$branch" "$mirror_url" "$dest"; then
				return 0
			fi
		else
			if git clone "$mirror_url" "$dest"; then
				return 0
			fi
		fi
		warn "datacore mirror unavailable for $repo_name; falling back to $url"
	fi

	log "cloning $url -> $dest"
	if [[ -n "$branch" ]]; then
		git clone --branch "$branch" "$url" "$dest"
	else
		git clone "$url" "$dest"
	fi
}
