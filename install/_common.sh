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

git_clone_into() {
	local url="$1" dest="$2" branch="${3:-}" rc=0
	if [[ -n "$branch" ]]; then
		if git clone --branch "$branch" "$url" "$dest"; then
			:
		else
			rc=$?
		fi
	else
		if git clone "$url" "$dest"; then
			:
		else
			rc=$?
		fi
	fi
	if [[ "$rc" -ne 0 ]] && [[ -d "$dest" ]] && ! git -C "$dest" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		rm -rf "$dest"
	fi
	return "$rc"
}

clone_if_missing() {
	local url="$1" dest="$2" branch="${3:-}" repo_name mirror_url
	if [[ -d "$dest" ]]; then
		if git -C "$dest" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
			if [[ -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
				log "clone_if_missing: $dest already populated, skipping"
				return 0
			fi
		elif [[ -e "$dest/.git" ]]; then
			warn "clone_if_missing: $dest has broken git metadata; removing and retrying"
			rm -rf "$dest"
		elif [[ -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
			warn "clone_if_missing: $dest exists and is not a git repo; refusing to reuse it"
			return 1
		fi
	fi

	repo_name="$(repo_name_from_url "$url")"
	if [[ -n "$DATACORE_GIT_ROOT" ]] && [[ "$url" != *"datacore:"* ]] && [[ "$url" != *"datacore."* ]]; then
		mirror_url="${DATACORE_GIT_ROOT%/}/$repo_name"
		log "trying datacore mirror $mirror_url -> $dest"
		if git_clone_into "$mirror_url" "$dest" "$branch"; then
			return 0
		fi
		warn "datacore mirror unavailable for $repo_name; clearing partial clone and falling back to $url"
		rm -rf "$dest"
	fi

	log "cloning $url -> $dest"
	git_clone_into "$url" "$dest" "$branch"
}

# --- Profile helpers ---
profile_manifest_path() {
	local profile="$1"
	printf '%s/install/profiles/%s.sh' "$DOTFILES" "$profile"
}

is_wsl() {
	[[ -n "${WSL_DISTRO_NAME:-}" ]] && return 0
	[[ -r /proc/version ]] && grep -qi microsoft /proc/version
}

default_dotfiles_profile() {
	if is_wsl; then
		printf '%s' wsl
		return 0
	fi

	case "${HOSTNAME%%.*}" in
	datacore)
		printf '%s' server
		;;
	*)
		printf '%s' desktop
		;;
	esac
}

load_profile_manifest() {
	local profile="$1" manifest
	manifest="$(profile_manifest_path "$profile")"
	if [[ ! -f "$manifest" ]]; then
		die "unknown dotfiles profile: $profile"
	fi
	unset PROFILE_NAME PROFILE_DESCRIPTION PROFILE_SCRIPTS
	declare -ga PROFILE_SCRIPTS=()
	source "$manifest"
	if [[ ${#PROFILE_SCRIPTS[@]} -eq 0 ]]; then
		die "profile '$profile' did not define PROFILE_SCRIPTS"
	fi
}
