#!/usr/bin/env bash
# install/09-stow-profile.sh — stow profiles/$PROFILE/* packages
set -euo pipefail
source "$(dirname "$0")/_common.sh"

PROFILE_DIR="$DOTFILES/profiles/$PROFILE"
if [[ ! -d "$PROFILE_DIR" ]]; then
    die "profile directory not found: $PROFILE_DIR"
fi

# Write the active-profile marker so dot-restow can find the profile without
# falling back to symlink inference.
mkdir -p "$HOME/.config/dotfiles"
echo "$PROFILE" > "$HOME/.config/dotfiles/active-profile"
log "active-profile marker written: $PROFILE"

log "stowing $PROFILE_DIR/* packages"
cd "$DOTFILES"

for pkg_path in "$PROFILE_DIR"/*/; do
    pkg_name="$(basename "$pkg_path")"
    # Profile packages add to base directories (e.g. zsh adds to ~/.zshrc.d/)
    # If conflict with base, unstow base's version and retry
    if ! stow -d "$PROFILE_DIR" -t "$HOME" --no-folding -R "$pkg_name" 2>/dev/null; then
        log "conflict stowing profile pkg $pkg_name; unstowing base/$pkg_name and retrying"
        stow -d base -t "$HOME" --no-folding -D "$pkg_name" 2>/dev/null || true
        stow -d "$PROFILE_DIR" -t "$HOME" --no-folding -R "$pkg_name"
    fi
done
