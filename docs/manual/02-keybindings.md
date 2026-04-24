# Chapter 02 — Keybindings

All system-level bindings. `$mod` is Super (Windows key) on this machine.

---

## Hyprland

### Window management

| Binding | Action |
|---|---|
| `$mod + h/j/k/l` | Move focus left / down / up / right |
| `$mod + Shift + h/j/k/l` | Move window left / down / up / right |
| `$mod + Ctrl + h/j/k/l` | Resize active window (repeatable) |
| `$mod + mouse1 (drag)` | Move floating window |
| `$mod + mouse2 (drag)` | Resize floating window |
| `$mod + Shift + q` | Close active window |
| `$mod + Shift + Space` | Toggle floating |
| `$mod + f` | Fullscreen |
| `$mod + v` | Preselect split below (dwindle) |
| `$mod + b` | Preselect split right (dwindle) |
| `$mod + Tab` | Window picker (`~/.local/bin/window-picker`) |

### Workspaces

| Binding | Action |
|---|---|
| `$mod + 1..9` | Switch to workspace 1–9 |
| `$mod + Shift + 1..9` | Move window to workspace 1–9 (silent) |
| `$mod + s` | Next workspace on monitor |
| `$mod + a` | Previous workspace on monitor |
| `$mod + Shift + -` | Move window to special workspace (scratchpad) |
| `$mod + -` | Toggle special workspace |

### Launchers

| Binding | Action |
|---|---|
| `$mod + Return` | Terminal (`$term`) |
| `$mod + d` | App launcher (`$menu`) |
| `$mod + w` | Firefox |
| `$mod + Alt + p` | Firefox private window |
| `$mod + e` | File manager (`lf` in terminal) |
| `$mod + o` | Obsidian |
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

## Claude Code

- In session: `/help` lists session commands (`/plan`, `/resume`, `/review`, `/clear`, `/compact`, etc.). These are Claude Code built-ins, not dotfiles config.
- Hooks: configured in `base/claude/.claude/settings.json`. See [Chapter 05 — Claude Code](05-claude-code.md).
