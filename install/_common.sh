#!/usr/bin/env bash
# install/_common.sh — shared helpers for install/*.sh scripts
# Not executable directly; sourced by numbered scripts.

set -euo pipefail

# --- Required env (set by install.sh orchestrator) ---
: "${DOTFILES:?DOTFILES must be set (orchestrator sets this)}"
: "${PROFILE:?PROFILE must be set (orchestrator sets this)}"

# --- Log helpers ---
log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(basename "${BASH_SOURCE[1]:-install}")" "$*"; }
warn() { printf '\033[1;33m[%s]\033[0m %s\n' "$(basename "${BASH_SOURCE[1]:-install}")" "$*" >&2; }
die()  { printf '\033[1;31m[%s]\033[0m %s\n' "$(basename "${BASH_SOURCE[1]:-install}")" "$*" >&2; exit 1; }

# --- Profile guards ---
# Return success if current PROFILE is one of the given names.
profile_is() {
    local p
    for p in "$@"; do
        [[ "$PROFILE" == "$p" ]] && return 0
    done
    return 1
}

# Exit the calling script early if PROFILE is NOT in the given list.
skip_unless_profile() {
    if ! profile_is "$@"; then
        log "skipping on profile=$PROFILE (this script only runs on: $*)"
        exit 0
    fi
}

# --- Package helpers ---
# Install pacman packages idempotently. Accepts a list.
need_pkg() {
    [[ $# -gt 0 ]] || return 0
    sudo pacman -S --noconfirm --needed "$@"
}

# Install from AUR via paru. Accepts a list.
need_aur() {
    [[ $# -gt 0 ]] || return 0
    paru -S --noconfirm --needed "$@"
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
# Args: <url> <dest> [<branch>]
clone_if_missing() {
    local url="$1" dest="$2" branch="${3:-}"
    if [[ -d "$dest" ]] && [[ -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
        log "clone_if_missing: $dest already populated, skipping"
        return 0
    fi
    log "cloning $url -> $dest"
    if [[ -n "$branch" ]]; then
        git clone --branch "$branch" "$url" "$dest"
    else
        git clone "$url" "$dest"
    fi
}
