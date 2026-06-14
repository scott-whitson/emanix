# install/profiles/server.sh — datacore/server profile
# Canonical headless Debian server with datacore-only runtime services.

PROFILE_NAME="server"
PROFILE_DESCRIPTION="Datacore server profile"
export PROFILE_ENABLE_FRAGPAPER=1
export PROFILE_ENABLE_WINDOW_PICKER=1
export PROFILE_FRAGPAPER_SRC="$HOME/projects/fragpaper"
export PROFILE_BASE_STOW_SKIP=""
export PROFILE_SERVICE_SKIP_PREFIXES=""
# shellcheck disable=SC2034
PROFILE_SCRIPTS=(
	01-core
	02-neovim
	03-system
	06-tools
	07-pi
	08-stow-base
	09-zk
	10-theme
	11-services
	12-ibgateway
	13-docs-sync
)
