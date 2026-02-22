#!/usr/bin/env bash
set -euo pipefail

# Syncs Windows-side config files from dotfiles to the Windows user directory.
# Usage: ./sync-windows.sh
#
# This is separate from install.sh because stow targets ~ (WSL home),
# but these configs live under /mnt/c/Users/<user>/.

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
WIN_SRC="$DOTFILES_DIR/base/windows"
WIN_HOME="/mnt/c/Users/scott"

if [ ! -d "$WIN_HOME" ]; then
  echo "Windows home not found at $WIN_HOME — skipping."
  exit 0
fi

if [ ! -d "$WIN_SRC" ]; then
  echo "No windows configs found at $WIN_SRC — nothing to sync."
  exit 0
fi

echo "Syncing Windows configs to $WIN_HOME..."

# Copy .glzr/ (GlazeWM config)
if [ -d "$WIN_SRC/.glzr" ]; then
  mkdir -p "$WIN_HOME/.glzr"
  cp -rv "$WIN_SRC/.glzr/." "$WIN_HOME/.glzr/"
fi

echo "Done. Reload GlazeWM config with lwin+shift+r."
