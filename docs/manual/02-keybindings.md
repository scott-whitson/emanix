# Chapter 02 — Keybindings

eminix runs **EWM** — Emacs *is* the Wayland compositor. There is no separate
window manager or status bar: windowing, workspaces, and the top bar all live in
Emacs. `Super` (a.k.a. `s-`, the Windows key) is the compositor modifier; `C-c` /
`C-x` are Emacs prefixes. Text editing is **modal (Meow)**.

Two routing rules worth knowing:

- **`Super` (`s-`) keys are intercepted by the compositor** — they work from any
  window, including a focused terminal or browser.
- **`C-c` / `C-x` are ordinary Emacs bindings** — they only register when a
  native Emacs buffer has focus, not from a Wayland surface (terminal). That is
  why the global assistant is on `s-i`, not a `C-c` prefix.

> Hyprland (`ioshi/i-intelligence/hyprland.nix`) still exists as an optional /
> legacy module for non-EWM use; its bindings are not documented here.

---

## EWM (compositor — `Super` keys)

### Frame slots (workspaces)

| Binding | Action |
| --- | --- |
| `s-1` … `s-9` | Go to / create slot 1–9 on the current output strip (keyed by number — `s-3` never conjures 1 and 2) |
| `s-0` | Go to / create slot 10 |
| `s-r` | Rename the current slot (shows in the top bar) |
| `s-q` | Close the current slot (mirrors Hyprland's `killactive`) |
| `s-t` | New frame after the current one |

Slots are generic — no app is tied to a number. Names are session-local; set them with `s-r`.

### Focus & movement

| Binding | Action |
| --- | --- |
| `s-←/→/↑/↓` | Move focus between frames |
| `s-Shift-←/→` | Move the current frame within the output strip |
| `s-Ctrl-←/→` | Move the current frame to another output |
| `s-Ctrl-↑/↓` | Move the buffer up / down (`buf-move`) |
| `s-Tab` / `s-Shift-Tab` | Cycle surface buffers (next / previous) |
| `s-f` | Toggle fullscreen for the focused surface |

### Launchers & assistant

| Binding | Action |
| --- | --- |
| `s-d` | App launcher (`ewm-launch-app`) |
| `s-w` | Firefox |
| `s-i` | Ask **elisa** — the local config-aware assistant; works from any slot |

### Session & clipboard

| Binding | Action |
| --- | --- |
| `s-l` | Lock session (`swaylock`) |
| `s-c` / `s-v` | Copy / paste (`kill-ring-save` / `yank`) |

The top bar — clock, battery, volume/wifi/cpu/ram/gpu, and the slot list — is
rendered in the Emacs tab-bar (`scott-modeline.el`, `scott-ewm.el`), not a
separate bar. Compositor bindings live in EWM's `ewm-mode-map`; the eminix
additions are in the `with-eval-after-load 'ewm` block of `init.el`.

---

## Emacs — modal editing (Meow)

Editing is **select-then-act** (Kakoune-style): build a selection, then one key
acts on it. Enter insert with `i` / `a`; `ESC` returns to normal.

| Key | Action |
| --- | --- |
| `h j k l` | Move (also starts a selection); `H J K L` extend it |
| `w` / `x` | Mark word / select line (press again, or a digit, to extend) |
| `d` / `s` / `c` | Delete / cut / change the selection |
| `y` / `p` | Copy / paste |
| `u` | Undo (`U` = undo within selection) |
| `f` / `t` | Find / till char forward; `F` = avy 2-char jump anywhere |
| `, . [ ]` | Inner / bounds / beginning / end of the thing at point |
| `Q` / `X` | Go to line |
| `SPC` | Leader (`SPC ?` = full meow cheatsheet) |

Config: `meow-normal-define-key` in `init.el`. **`C-c d` is Dirvish, not a line
delete** — to delete lines use `x` (select, repeat to extend) then `d`.

---

## Emacs — commands (`C-c` / `C-x`)

Work when a native Emacs buffer is focused.

| Binding | Action |
| --- | --- |
| `C-c i i` | Ask elisa (full set: `i` ask / `r` reindex / `m` toggle model / `n` ask notes). `s-i` is the global shortcut for ask. |
| `C-c q` | Open the current-quarter tracker note |
| `C-c d` | Dirvish (file manager) |
| `C-c f` | `consult-ripgrep` (search project) |
| `C-s` | `consult-line` (search buffer) |
| `C-x b` | `consult-buffer` (switch buffer) |
| `M-y` | `consult-yank-pop` |
| `C-.` | `embark-act` |
| `C-x g` | `magit-status` |
| `C-c n f` / `n i` / `n c` | org-roam find / insert / capture |
| `C-c a` | org-agenda |
| `C-c p` | Pi: open Pi in Ghostty (`~/.local/bin/pi` fallback if PATH is missing it) |
| `C-c C-c` | Confirm / finish (Org, Pi, etc.) |

Fuller personal reference is in the vault notes *Emacs Shortcuts*, *Emacs Command
Map*, and *Meow* (`~/docs/org`, reachable via `C-c n f`).

---

## Theme

Theming is driven from Emacs (`dot-theme-set`, light/dark). See
[Chapter 03 — Theming](03-theming.md).

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

`pi` from the shell; skills under `~/.pi/agent/skills/`. In Emacs, **elisa** (the
local RAG assistant) is `s-i` (ask from anywhere) or `C-c i` (full command set).
