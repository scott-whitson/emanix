#!/usr/bin/env bash
# install.sh — orchestrator that runs install/*.sh in order.
#
# Usage:
#   ./install.sh <workstation|server>
#
# Each install/*.sh is independently runnable. Re-runs are idempotent
# (pacman --needed, stow -R, systemctl --now etc.). See docs/manual/01-install.md
# (Wave 4) for the script-by-script walkthrough.

set -euo pipefail

PROFILE="${1:-}"
DOTFILES="$(cd "$(dirname "$0")" && pwd)"

# --- Usage ---
if [[ -z "$PROFILE" ]] || [[ ! -d "$DOTFILES/profiles/$PROFILE" ]]; then
    echo "Usage: ./install.sh <profile>"
    echo ""
    echo "Available profiles:"
    for p in "$DOTFILES"/profiles/*/; do
        echo "  $(basename "$p")"
    done
    exit 1
fi

export DOTFILES PROFILE

# --- Source profile vars (OBSIDIAN_VAULT, etc.) ---
PROFILE_CONF="$DOTFILES/profiles/$PROFILE/profile.conf"
if [[ -f "$PROFILE_CONF" ]]; then
    # shellcheck source=/dev/null
    source "$PROFILE_CONF"
fi

echo "=== dotfiles bootstrap (profile: $PROFILE) ==="

# --- Run each install/*.sh in lexical order ---
for script in "$DOTFILES"/install/[0-9][0-9]-*.sh; do
    echo ""
    echo ">>> $(basename "$script")"
    bash "$script"
done

echo ""
echo "=== Done! (profile: $PROFILE) ==="
echo "Manual steps:"
echo "  1. Set up SSH keys: ssh-keygen -t ed25519"
echo "  2. Log out and back in for zsh to take effect"
