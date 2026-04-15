# Auto-start Hyprland on TTY1 login (bare Arch, no display manager).
# Only runs for login shells; no effect in tmux, SSH, or nested terminals.
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = "1" ]; then
  exec start-hyprland
fi
