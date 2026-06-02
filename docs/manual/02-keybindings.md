# Chapter 02 — Keybindings

All system-level bindings. `$mod` is Super (Windows key) on this machine.

---

## Hyprland

Active layout: **master** (configured in `base/hypr/.config/hypr/hyprland.conf` via `layout = master` + a `master { … }` block — left-oriented, `mfact = 0.55`).

> **Live reference:** `$mod + Shift + /` pops a searchable fuzzel viewer (`hypr-cheatsheet`) sourced from `~/docs/vault/Whitsgrove/Hyprland Cheatsheet.md`. Edits to that file are picked up on the next popup. The tables below are the canonical reference; the vault file is the daily-use index.

### Window management

| Binding | Action |
|---|---|
| `$mod + h/j/k/l` | Move focus left / down / up / right |
| `$mod + Shift + h/j/k/l` | Move window left / down / up / right |
| `$mod + Ctrl + h` / `$mod + Ctrl + l` | Shrink / grow master area (`mfact ±0.05`, repeatable) |
| `$mod + Ctrl + j/k` | Resize active window vertically (repeatable) |
| `$mod + mouse1 (drag)` | Move floating window |
| `$mod + mouse2 (drag)` | Resize floating window |
| `$mod + Shift + q` | Close active window |
| `$mod + Shift + Space` | Toggle floating |
| `$mod + f` | Fullscreen |
| `$mod + Tab` | Window picker (`~/.local/bin/window-picker`) |

### Master layout

| Binding | Action |
|---|---|
| `$mod + m` | Jump to/from the master window |
| `$mod + Shift + Return` | Promote focused window to master (`swapwithmaster`) |
| `$mod + y` | Cycle orientation (left → top → right → bottom → center) |

### Workspaces

| Binding | Action |
|---|---|
| `$mod + 1..9` | Switch to workspace 1–9 |
| `$mod + Shift + 1..9` | Move window to workspace 1–9 (silent) |
| `$mod + s` | Next workspace on monitor |
| `$mod + a` | Previous workspace on monitor |
| `$mod + r` | Rename current workspace (`hypr-rename-workspace`; fuzzel prompt, empty input clears) |
| `$mod + Shift + -` | Move window to special workspace (scratchpad) |
| `$mod + -` | Toggle special workspace |

Workspace names render in waybar's `hyprland/workspaces` module via `"format": "{name}"`. Renames are session-local (lost on Hyprland exit).

### Launchers

| Binding | Action |
|---|---|
| `$mod + Return` | Terminal (`$term`) |
| `$mod + d` | App launcher (`$menu`) |
| `$mod + w` | Firefox |
| `$mod + Alt + p` | Firefox private window |
| `$mod + e` | File manager (`thunar`) |
| `$mod + o` | Obsidian |
| `$mod + Shift + /` | Keybindings cheatsheet popup (`hypr-cheatsheet`; reads `~/docs/vault/Whitsgrove/Hyprland Cheatsheet.md`) |
| `$mod + Escape` | Lock screen (`hyprlock`) |
| `Print` | Screenshot region → clipboard (`grim` + `slurp`) |
| `Shift + Print` | Screenshot region → `~/downloads/screenshot-YYYYMMDD-HHMMSS.png` |
| `Ctrl + Print` | Screenshot full screen → clipboard |
| `$mod + F1` | Push-to-talk toggle (`push-to-talk.sh toggle`) |
| `F1` | Push-to-talk toggle (bare, without mod) |

### Theme

| Binding | Action |
|---|---|
| `$mod + Shift + T` | `dot-theme-toggle` — flip between last-dark and last-light theme |

See [Chapter 03 — Theming](03-theming.md).

### System / other

| Binding | Action |
|---|---|
| `$mod + Shift + e` | Exit Hyprland |
| `$mod + Shift + r` | Reload Hyprland config (`hyprctl reload`) |
| `$mod + Shift + m` | Toggle trackpad (`trackpad-toggle`) |
| `$mod + Ctrl + p` | Cycle fragpaper wallpaper (`pkill -USR1 fragpaper`) |

---

## Ghostty

Ghostty uses built-in defaults. No `keybind` overrides in `base/ghostty/.config/ghostty/config`. See [Ghostty docs](https://ghostty.org/docs/) for the stock set.

---

## Helix

Defaults. No overrides in `base/helix/.config/helix/config.toml`. Use `:help` inside Helix or the [upstream docs](https://docs.helix-editor.com/).

---

## Neovim (kickstart)

Kickstart defaults plus any customization in `~/.config/nvim/lua/custom/`. Not documented here — that fork is a separate repo.

---

## Zellij

Defaults. No `~/.config/zellij/` config shipped in dotfiles. If you add one, document bindings here.

---

## AI tooling

No AI-tool-specific keybindings ship here. Use `pi` from shell; skills live under `~/.pi/agent/skills/`.
