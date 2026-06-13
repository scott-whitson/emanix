# install/profiles/wsl.sh — WSL profile
# Debian under Windows: core userland only, no UI stack.

PROFILE_NAME="wsl"
PROFILE_DESCRIPTION="Debian WSL profile"
export PROFILE_ENABLE_FRAGPAPER=0
export PROFILE_ENABLE_WINDOW_PICKER=0
export PROFILE_BASE_STOW_SKIP="ib systemd pi"
export PROFILE_SERVICE_SKIP_PREFIXES=""
# shellcheck disable=SC2034
PROFILE_SCRIPTS=(
	01-core
	03-system
	06-tools
	07-pi
	08-stow-base
	10-theme
)
