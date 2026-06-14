# install/profiles/desktop.sh — workstation profile
# Full desktop Debian install with Hyprland and desktop services.

PROFILE_NAME="desktop"
PROFILE_DESCRIPTION="Debian workstation profile"
export PROFILE_ENABLE_FRAGPAPER=1
export PROFILE_ENABLE_WINDOW_PICKER=1
export PROFILE_FRAGPAPER_SRC="$HOME/.local/share/fragpaper"
export PROFILE_BASE_STOW_SKIP=""
export PROFILE_SERVICE_SKIP_PREFIXES="ib minne-ib"
# shellcheck disable=SC2034
PROFILE_SCRIPTS=(
	01-core
	02-neovim
	03-system
	04-hyprland
	05-desktop
	06-tools
	07-pi
	08-stow-base
	09-zk
	10-theme
	11-services
	13-docs-sync
)
