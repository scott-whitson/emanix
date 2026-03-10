#!/bin/bash
# Launch Sway as a nested compositor inside WSLg.
# WSLg provides the Wayland socket; Sway runs in its own window.

export XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir
export WAYLAND_DISPLAY=wayland-0
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=sway

export WLR_NO_HARDWARE_CURSORS=1
export WLR_WL_APP_ID=SwayWM

exec sway -c ~/.config/sway/config-wsl 2>/dev/null
