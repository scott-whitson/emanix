#!/usr/bin/env bash
# install/08-stow-base.sh — stow every base/* package (skip desktop pkgs on server)
set -euo pipefail
source "$(dirname "$0")/_common.sh"

log "stowing base/* packages"
cd "$DOTFILES"

for pkg_path in base/*/; do
    pkg_name="$(basename "$pkg_path")"

    # Skip desktop packages on headless/server
    if ! profile_is workstation; then
        case "$pkg_name" in
            hypr|waybar|mako|ghostty|fuzzel) continue ;;
        esac
    fi

    # --adopt absorbs existing files at $HOME so stow can succeed on fresh
    # installs (Oh My Zsh drops a default .zshrc, etc.); the git checkout
    # below restores the repo's intended content.
    stow -d base -t "$HOME" --no-folding --adopt "$pkg_name" 2>/dev/null \
        || stow -d base -t "$HOME" --no-folding "$pkg_name"
done

# WARNING: this reverts ALL uncommitted changes in base/, including intentional
# edits. Always commit or stash base/ edits before running install.sh; the
# orchestrator preflight doesn't check (but dot-doctor should be able to flag
# the risk on demand in future).
git checkout -- base/
