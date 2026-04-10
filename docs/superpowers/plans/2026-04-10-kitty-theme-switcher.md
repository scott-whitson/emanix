# Kitty Theme Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Toggle kitty between Tokyo Night (dark) and Zenbones Light (light) with a shell command and sway keybind, with live reload.

**Architecture:** Extract kitty colors into separate theme files, add an `include` directive, and use a shell script to swap a symlink and signal kitty to reload. State persisted to `~/.local/state/theme-current`.

**Tech Stack:** Bash, kitty config, sway config, zsh

**Spec:** `docs/superpowers/specs/2026-04-10-kitty-theme-switcher-design.md`

---

### Task 1: Create dark.conf theme file

**Files:**
- Create: `base/kitty/.config/kitty/dark.conf`

- [ ] **Step 1: Create `dark.conf` with Tokyo Night colors**

```bash
# File: base/kitty/.config/kitty/dark.conf
# Tokyo Night color scheme

foreground #c0caf5
background #1a1b26
background_opacity 0.85

# Black
color0  #15161e
color8  #414868

# Red
color1  #f7768e
color9  #f7768e

# Green
color2  #9ece6a
color10 #9ece6a

# Yellow
color3  #e0af68
color11 #e0af68

# Blue
color4  #7aa2f7
color12 #7aa2f7

# Magenta
color5  #bb9af7
color13 #bb9af7

# Cyan
color6  #7dcfff
color14 #7dcfff

# White
color7  #a9b1d6
color15 #c0caf5

# Cursor
cursor #c0caf5
cursor_text_color #1a1b26

# Selection
selection_foreground #c0caf5
selection_background #33467c

# URL
url_color #73daca

# Tab bar
active_tab_foreground   #15161e
active_tab_background   #7aa2f7
inactive_tab_foreground #565f89
inactive_tab_background #1a1b26

# Window border
active_border_color #7aa2f7
inactive_border_color #414868
```

- [ ] **Step 2: Commit**

```bash
git add base/kitty/.config/kitty/dark.conf
git commit -m "Add Tokyo Night dark theme file for kitty"
```

---

### Task 2: Create light.conf theme file

**Files:**
- Create: `base/kitty/.config/kitty/light.conf`

- [ ] **Step 1: Create `light.conf` with Zenbones Light colors**

```bash
# File: base/kitty/.config/kitty/light.conf
# Zenbones Light color scheme

foreground #2C363C
background #F0EDEC
background_opacity 1.0

# Black
color0  #F0EDEC
color8  #CFC1BA

# Red
color1  #A8334C
color9  #94253E

# Green
color2  #4F6C31
color10 #3F5A22

# Yellow
color3  #944927
color11 #803D1C

# Blue
color4  #286486
color12 #1D5573

# Magenta
color5  #88507D
color13 #7B3B70

# Cyan
color6  #3B8992
color14 #2B747C

# White
color7  #2C363C
color15 #4F5E68

# Cursor
cursor #2C363C
cursor_text_color #F0EDEC

# Selection
selection_foreground #2C363C
selection_background #CBD9E3

# URL
url_color #286486

# Tab bar
active_tab_foreground   #2C363C
active_tab_background   #DEB9D6
inactive_tab_foreground #2C363C
inactive_tab_background #D6CDC9

# Window border
active_border_color #286486
inactive_border_color #CFC1BA
```

- [ ] **Step 2: Commit**

```bash
git add base/kitty/.config/kitty/light.conf
git commit -m "Add Zenbones Light theme file for kitty"
```

---

### Task 3: Refactor kitty.conf to use include

**Files:**
- Modify: `base/kitty/.config/kitty/kitty.conf` (remove lines 1-71, add include)

The current `kitty.conf` has colors hardcoded on lines 1-71. Remove all color lines and add `include theme.conf` at the top. Keep all non-color settings (font, window, scrollback, bell, performance).

- [ ] **Step 1: Replace kitty.conf contents**

New `kitty.conf`:

```bash
# -----------------------------------------------
# Kitty Configuration
# -----------------------------------------------

# --- Theme (swapped by theme-switch script) ---
include theme.conf

# --- Font ---
font_family JetBrainsMono Nerd Font
font_size 11.0

# --- Cursor ---
cursor_shape beam
cursor_blink_interval 0

# --- URL ---
url_style curly
detect_urls yes

# --- Window ---
window_padding_width 6
confirm_os_window_close 0
hide_window_decorations yes

# --- Scrollback ---
scrollback_lines 10000

# --- Bell ---
enable_audio_bell no
visual_bell_duration 0

# --- Performance ---
repaint_delay 6
input_delay 1
sync_to_monitor yes
```

- [ ] **Step 2: Verify the file looks correct**

```bash
cat base/kitty/.config/kitty/kitty.conf
```

Confirm: no color values remain, `include theme.conf` is present, all non-color settings are preserved.

- [ ] **Step 3: Commit**

```bash
git add base/kitty/.config/kitty/kitty.conf
git commit -m "Refactor kitty.conf: extract colors to includable theme file"
```

---

### Task 4: Create the theme-switch script

**Files:**
- Create: `base/bin/bin/theme-switch`

This goes in the existing `base/bin/bin/` stow package, which stows to `~/bin/`. The user's `.zshrc` already has `$HOME/bin` on PATH (line 138).

- [ ] **Step 1: Create the script**

```bash
#!/usr/bin/env bash
# theme-switch — toggle kitty between dark and light themes
# Usage: theme-switch [dark|light]
#   No argument toggles between dark and light.

set -euo pipefail

KITTY_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kitty"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_FILE="$STATE_DIR/theme-current"

current_theme() {
    cat "$STATE_FILE" 2>/dev/null || echo "dark"
}

target="${1:-}"

if [ -z "$target" ]; then
    if [ "$(current_theme)" = "dark" ]; then
        target="light"
    else
        target="dark"
    fi
fi

if [ "$target" != "dark" ] && [ "$target" != "light" ]; then
    echo "Usage: theme-switch [dark|light]" >&2
    exit 1
fi

# Swap the symlink (relative so it resolves within ~/.config/kitty/)
ln -sf "$target.conf" "$KITTY_CONFIG_DIR/theme.conf"

# Persist state
mkdir -p "$STATE_DIR"
echo "$target" > "$STATE_FILE"

# Live reload all kitty instances
killall -SIGUSR1 kitty 2>/dev/null || true

echo "Switched to $target theme"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x base/bin/bin/theme-switch
```

- [ ] **Step 3: Commit**

```bash
git add base/bin/bin/theme-switch
git commit -m "Add theme-switch script for kitty dark/light toggle"
```

---

### Task 5: Add sway keybind and zsh alias

**Files:**
- Modify: `base/sway/.config/sway/config-common:100` (add keybind after session section)
- Modify: `base/zsh/.zshrc:69` (add alias in aliases section)

- [ ] **Step 1: Add sway keybind**

Add after line 101 (`bindsym $mod+Shift+r reload`) in `config-common`:

```
bindsym $mod+Shift+t exec theme-switch
```

- [ ] **Step 2: Add zsh alias**

Add after line 69 (`alias rescue-gnome=...`) in `.zshrc`:

```bash
alias theme="theme-switch"
```

- [ ] **Step 3: Commit**

```bash
git add base/sway/.config/sway/config-common base/zsh/.zshrc
git commit -m "Add sway keybind (mod+shift+t) and zsh alias for theme switching"
```

---

### Task 6: Deploy and test

- [ ] **Step 1: Restow kitty and bin packages**

```bash
cd ~/dotfiles && stow -R -d base -t ~ kitty bin
```

- [ ] **Step 2: Initialize theme.conf for the first time**

```bash
theme-switch dark
```

Verify: `ls -la ~/.config/kitty/theme.conf` shows a symlink to `dark.conf`.

- [ ] **Step 3: Test dark theme loads**

```bash
killall -SIGUSR1 kitty
```

Kitty should still look the same (Tokyo Night).

- [ ] **Step 4: Switch to light theme**

```bash
theme-switch light
```

Kitty should immediately switch to Zenbones Light — light background, dark text, no transparency.

- [ ] **Step 5: Toggle back**

```bash
theme-switch
```

Should toggle back to dark (Tokyo Night, with transparency).

- [ ] **Step 6: Restow sway and zsh, reload sway**

```bash
cd ~/dotfiles && stow -R -d base -t ~ sway zsh
swaymsg reload
```

- [ ] **Step 7: Test sway keybind**

Press `Super+Shift+T`. Kitty should toggle themes.

- [ ] **Step 8: Commit any fixes if needed, then final commit**

```bash
git add -A
git commit -m "Kitty theme switcher: dark (Tokyo Night) / light (Zenbones Light)"
```
