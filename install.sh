#!/usr/bin/env bash
# install.sh — orchestrator that runs install/*.sh in order.
#
# Usage:
#   ./install.sh
#
# Each install/*.sh is independently runnable. Re-runs are idempotent
# (apt --no-install-recommends, stow -R, systemctl --now etc.). See docs/manual/01-install.md
# for the script-by-script walkthrough.

set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
export DOTFILES

echo "=== dotfiles bootstrap ==="

# --- Run each install/*.sh in lexical order ---
for script in "$DOTFILES"/install/[0-9][0-9]-*.sh; do
	echo ""
	echo ">>> $(basename "$script")"
	bash "$script"
done

echo ""
echo "=== Done! ==="
echo "Manual steps:"
echo "  1. Set up SSH keys: ssh-keygen -t ed25519"
echo "  2. Log out and back in for zsh to take effect"
