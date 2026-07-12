# install/profiles/wsl.sh — WSL profile
# Debian under Windows: core userland only, no UI stack.

PROFILE_NAME="wsl"
PROFILE_DESCRIPTION="Debian WSL profile"
export PROFILE_ENABLE_FRAGPAPER=0
export PROFILE_ENABLE_WINDOW_PICKER=0
# Uniformity: stow the full base set here too. Desktop configs (hypr/waybar/…)
# are harmless dangling files on WSL; systemd is needed for the dot-sync timer;
# pi config is shared across machines. Nothing skipped.
export PROFILE_BASE_STOW_SKIP=""
# Work box: no personal GitHub credential, authors no config — dot-sync only
# consumes (pull + restow), never commits/pushes. install.sh sets the marker.
export PROFILE_SYNC_PULL_ONLY=1
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
)
