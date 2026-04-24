#!/usr/bin/env bash
# install/02-paru.sh — bootstrap paru from AUR if missing
set -euo pipefail
source "$(dirname "$0")/_common.sh"

if command -v paru &>/dev/null; then
    log "paru already installed ($(paru --version | head -1)); skipping bootstrap"
    exit 0
fi

log "bootstrapping paru from AUR"
need_pkg base-devel git

# Clone + build in a throwaway temp dir
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git clone https://aur.archlinux.org/paru.git "$tmp/paru"
(
    cd "$tmp/paru"
    makepkg -si --noconfirm
)

log "paru bootstrapped: $(paru --version | head -1)"
