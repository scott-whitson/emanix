# Chapter 01 — Keybindings

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

> Hyprland is fully retired — `hyprland.nix`, `mako.nix` and `fuzzel.nix` were
> deleted when EWM replaced it. There is no non-EWM desktop path anymore.

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
additions are in the `with-eval-after-load 'ewm` block of `config.el`.

---

## Config layout: a loader, a config, and a fallback

`~/.config/emacs/` holds three top-level files. The split is a safety boundary,
not organisation:

| File | Role |
| --- | --- |
| `init.el` | 38-line loader. Loads `config.el` inside a `condition-case`. Must never break, so it is rarely edited. |
| `config.el` | All actual configuration. Free to be edited and to break. |
| `fallback.el` | Minimum viable desktop, loaded only when `config.el` fails. |

**Why the loader is a separate file.** A signal raised inside a `load`ed file
propagates to its caller, so `init.el` catches two failures that no guard
*inside* the config could:

- a **read-time** failure such as an unbalanced paren — nothing in `config.el`
  runs, so nothing in it can catch anything;
- a **load-time** failure such as a `require` that signals.

Both happened on 2026-08-10 and both presented identically — no top bar, `s-d`
dead, no window navigation — because Emacs is the compositor here. EWM itself
survived both, since it starts from `--eval` on the command line, which Emacs
processes after init.

**How to tell you are in the fallback.** The tab bar shows a red
`⚠ CONFIG FAILED` item at the far left. For the reason:

```bash
emacsclient -e 'scott/init-error'
```

`nil` is a healthy boot. Anything else is the error that aborted `config.el`.

**What the fallback restores:** the top bar (`scott/modeline-mode`), the
launcher (`C-c o`), the `scott/ewm-*` slot commands and a theme. Not completion,
meow, magit, org or apheleia — recoverable by fixing `config.el`, and not the
desktop.

**Editing caution.** `config.el` is an out-of-store symlink into the checkout
(`liveElisp`), so an edit is live on the next Emacs start with no rebuild. That
is why the guard is a runtime one: both 2026-08-10 incidents were uncommitted
live edits, which no build-time or pre-commit check would have caught.

**Testing it:** `./tests/init-guard.sh` reproduces both faults against a temp
copy and asserts the desktop survives each, plus that a healthy config is
unaffected.

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

Config: `meow-normal-define-key` in `config.el`. **`C-c d` is Dirvish, not a line
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
| `C-c p` | Pi: open Pi in Ghostty (`~/dotfiles/bin/pi` fallback if PATH is missing it) |
| `C-c C-c` | Confirm / finish (Org, Pi, etc.) |

Fuller personal reference is in the vault notes *Emacs Shortcuts*, *Emacs Command
Map*, and *Meow* (`~/docs/org`, reachable via `C-c n f`).

---

## Emacs — code navigation and LSP

Added 2026-08-07. Emacs 30 ships nearly all of this: `project.el`, `xref`,
`eglot` and `flymake` are built in. Only `nix-ts-mode`, `apheleia` and the
tree-sitter grammars come from Nix (`ioshi/i-intelligence/emacs/packages.nix`).

**Navigation — stock bindings, no config needed:**

| Binding | Action |
| --- | --- |
| `C-x p f` | Find file in project |
| `C-x p p` / `C-x p b` | Switch project / project buffers |
| `M-.` / `M-,` | Jump to definition / jump back |
| `M-?` | Find references |

With eglot attached, `M-.` is a semantic jump rather than a guess.

**Diagnostics and refactoring — `C-c e`** (flymake ships no bindings of its own):

| Binding | Action |
| --- | --- |
| `C-c e n` / `C-c e p` | Next / previous diagnostic |
| `C-c e l` | List all diagnostics (`consult-flymake`) |
| `C-c e r` | `eglot-rename` — rename across the project |
| `C-c e a` | `eglot-code-actions` |
| `C-c e =` | Format buffer now |

**Automatic behaviour:** eglot attaches on `.nix` (nixd) and `.py`
(basedpyright); apheleia formats on save — `nixpkgs-fmt` for Nix, `ruff` for
Python. `nixpkgs-fmt` is this repo's own `nix fmt` formatter, so a save from
Emacs and `nix fmt` produce identical bytes.

Check the mode line for `EGLOT` to confirm the server attached; `M-x
eglot-events-buffer` shows the handshake if it did not.

---

## Theme

Theming is driven from Emacs (`dot-theme-set`, light/dark). See
[Chapter 02 — Theming](02-theming.md).

---

## Ghostty

Ghostty uses built-in defaults. No `keybind` overrides in the generated config
(`ioshi/i-intelligence/ghostty.nix`, written to `~/.config/ghostty/config`). See
[Ghostty docs](https://ghostty.org/docs/) for the stock set.

---

## Neovim (retired)

Neovim/kickstart is gone — Emacs is the sole editor (see [Chapter 04 — Philosophy](04-philosophy.md#3-terminal-centric-keyboard-driven)).
`base/nvim` was deleted along with the rest of `base/`.

---

## Zellij

A config **is** shipped, at `ioshi/i-intelligence/zellij/` (`config.kdl` +
`layouts/`), deployed via `mkOutOfStoreSymlink`. It clears the stock keybinds
(`clear-defaults=true`) and remaps pane/focus movement onto `h j k l` inside
each mode rather than using Zellij's defaults — see `config.kdl` for the full
map. Plugins `zellaude` and `zellij-forgot` are wired in under `plugins/`.

---

## AI tooling

`pi` from the shell; skills under `~/.pi/agent/skills/`. In Emacs, **elisa** (the
local RAG assistant) is `s-i` (ask from anywhere) or `C-c i` (full command set).
