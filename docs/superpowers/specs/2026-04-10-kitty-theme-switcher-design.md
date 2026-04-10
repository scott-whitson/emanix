# Kitty Theme Switcher Design

**Date:** 2026-04-10
**Motivation:** White-on-dark terminal text is unreadable outdoors in sunlight. Need a quick way to toggle between dark (indoor) and light (outdoor, high-contrast) kitty themes.

## Scope

- Kitty terminal theme switching only (dark/light)
- Live reload without restarting kitty
- Shell command + sway keybind triggers
- Future: waybar/sway/wofi/mako/fragpaper can be added later

## Themes

### Dark: Tokyo Night (current)

```
foreground              #c0caf5
background              #1a1b26
background_opacity      0.85

color0  #15161e    color8  #414868
color1  #f7768e    color9  #f7768e
color2  #9ece6a    color10 #9ece6a
color3  #e0af68    color11 #e0af68
color4  #7aa2f7    color12 #7aa2f7
color5  #bb9af7    color13 #bb9af7
color6  #7dcfff    color14 #7dcfff
color7  #a9b1d6    color15 #c0caf5

cursor                  #c0caf5
cursor_text_color       #1a1b26
selection_foreground    #c0caf5
selection_background    #33467c
url_color               #73daca
active_tab_foreground   #15161e
active_tab_background   #7aa2f7
inactive_tab_foreground #565f89
inactive_tab_background #1a1b26
active_border_color     #7aa2f7
inactive_border_color   #414868
```

### Light: Zenbones Light

> Note: url_color, active/inactive_border_color are not in the upstream Zenbones theme. Values below are chosen from the Zenbones palette for consistency.

```
foreground              #2C363C
background              #F0EDEC
background_opacity      1.0

color0  #F0EDEC    color8  #CFC1BA
color1  #A8334C    color9  #94253E
color2  #4F6C31    color10 #3F5A22
color3  #944927    color11 #803D1C
color4  #286486    color12 #1D5573
color5  #88507D    color13 #7B3B70
color6  #3B8992    color14 #2B747C
color7  #2C363C    color15 #4F5E68

cursor                  #2C363C
cursor_text_color       #F0EDEC
selection_foreground    #2C363C
selection_background    #CBD9E3
url_color               #286486
active_tab_foreground   #2C363C
active_tab_background   #DEB9D6
inactive_tab_foreground #2C363C
inactive_tab_background #D6CDC9
active_border_color     #286486
inactive_border_color   #CFC1BA
```

## File Structure

```
base/kitty/.config/kitty/
  kitty.conf              # Non-color settings + `include theme.conf`
  theme.conf              # Symlink -> dark.conf or light.conf (stowed to ~/.config/kitty/)
  dark.conf               # Tokyo Night colors
  light.conf              # Zenbones Light colors

base/scripts/.local/bin/
  theme-switch            # The switcher script (stowed to ~/.local/bin/)
```

## kitty.conf Changes

Remove all hardcoded color lines from `kitty.conf`. Add at the top:

```
include theme.conf
```

All non-color settings (font, padding, scrollback, bell, performance) remain in `kitty.conf`.

## theme-switch Script

```bash
#!/usr/bin/env bash
# Usage: theme-switch [dark|light]
# No argument: toggles between dark and light

THEME_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kitty"
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/theme-current"

current() {
    cat "$STATE_FILE" 2>/dev/null || echo "dark"
}

if [ -z "$1" ]; then
    # Toggle
    if [ "$(current)" = "dark" ]; then
        target="light"
    else
        target="dark"
    fi
else
    target="$1"
fi

if [ "$target" != "dark" ] && [ "$target" != "light" ]; then
    echo "Usage: theme-switch [dark|light]"
    exit 1
fi

# Swap the symlink
ln -sf "$target.conf" "$THEME_DIR/theme.conf"

# Persist state
mkdir -p "$(dirname "$STATE_FILE")"
echo "$target" > "$STATE_FILE"

# Live reload all kitty instances
killall -SIGUSR1 kitty 2>/dev/null

echo "Switched to $target theme"
```

## Sway Keybind

Add to `config-common`:

```
bindsym $mod+Shift+t exec theme-switch
```

This toggles between dark and light.

## Shell Alias

Add to `.zshrc`:

```bash
alias theme='theme-switch'
```

So `theme light`, `theme dark`, or just `theme` to toggle.

## Stow Considerations

- `dark.conf` and `light.conf` are real files in the stow package, stowed to `~/.config/kitty/`
- `theme.conf` is NOT in the stow package - it is created and managed by `theme-switch`
- `theme-switch` creates `~/.config/kitty/theme.conf` as a relative symlink (`dark.conf` or `light.conf`), which resolves correctly since the target files are stowed into the same directory
- On a fresh machine after stowing, run `theme-switch dark` (or just `theme-switch`) to initialize `theme.conf`

## Reload Mechanism

`killall -SIGUSR1 kitty` causes all kitty instances to re-read their config, including the `include theme.conf` directive. This picks up the new symlink target and applies colors live. No `allow_remote_control` setting needed.

## Default State

- Default theme: dark (Tokyo Night)
- On fresh stow, `theme.conf` symlinks to `dark.conf`
- State file at `~/.local/state/theme-current` tracks the active theme
