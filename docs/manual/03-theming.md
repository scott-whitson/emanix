# Chapter 03 — Theming

The theme system is Omarchy-style (directory-per-theme) plus a dark/light toggle layer. Applying a theme is one command; switching between dark and light is one hotkey.

## Commands

```bash
dot-theme-set <name>      # apply a specific theme
dot-theme-toggle          # flip between last-dark and last-light (bound to $mod+Shift+T)
dot-theme-set             # (no arg) prints usage + lists available themes
```

## Shipped themes

```
themes/
├── catppuccin-mocha/     # dark
└── catppuccin-latte/     # light
```

## State files

Three files in `~/.config/dotfiles/`:

| File | Contents |
| --- | --- |
| `active-theme` | Currently applied theme (used by `install/10-theme.sh` on re-install) |
| `last-dark` | Most recent dark theme (source of truth for `dot-theme-toggle` when flipping to dark) |
| `last-light` | Most recent light theme |

## Theme directory anatomy

Each theme is a self-contained directory. All files are pre-rendered; there's no templating step.

```
themes/catppuccin-mocha/
├── variant            # "dark" or "light" — single word
├── colors.toml        # the palette, single source of truth for pi-agent-theme.json
├── palette.sh         # colors as shell vars (reference only; not consumed)
├── ghostty.conf       # terminal palette → ~/.config/ghostty/theme.conf
├── btop.theme         # btop theme → ~/.config/btop/themes/active.theme
├── gtk.conf           # GTK_THEME + COLOR_SCHEME (sourced by dot-theme-set, applied via gsettings)
├── pi-agent-theme.json # generated from colors.toml by bin/gen-pi-theme.py
├── README.md          # theme origin, extra font/plugin requirements
└── post-set.sh        # optional hook run at the end of dot-theme-set
```

Only two apps are themed by file symlink now — ghostty and btop. Emacs (including
the EWM top bar) is themed by `scott/theme-set` in the running daemon, not by a
file here. Targets retired on 2026-08-08 because nothing was installed to read
them: `hypr.conf`, `hyprlock.conf`, `mako.conf`, `fuzzel.ini`, `nvim.lua`,
`obsidian-theme` and `fragpaper.conf`.

## How `dot-theme-set <name>` works

1. Validates `themes/<name>/` exists; refuses unknown names.
2. Reads `variant` (must be `dark` or `light`).
3. Writes `~/.config/dotfiles/active-theme` = `<name>` and `last-<variant>` = `<name>`.
4. Symlinks `ghostty.conf` and `btop.theme` into place (see anatomy above).
5. Regenerates `pi-agent-theme.json` from `colors.toml` and points pi's `settings.json` at it.
6. Sources `gtk.conf` and runs `gsettings` for `color-scheme` and `gtk-theme`.
7. Tells the running Emacs daemon to switch catppuccin flavor via `scott/theme-set` — this is what themes EWM and its top bar.
8. Runs `themes/<name>/post-set.sh` if present and executable.
9. Signals ghostty (`SIGUSR2`) to reload.

## How `dot-theme-toggle` works

1. Reads `active-theme`, looks up its variant.
2. Applies the theme named in `last-<opposite-variant>` via `dot-theme-set`.
3. If `last-<opposite>` is empty (first-ever toggle to that variant): falls back to the first theme in `themes/*/` with the opposite variant, warns on stderr.

The first toggle after a fresh install uses the fallback path. Every subsequent toggle reads the markers cleanly.

## Adding a new theme

```bash
cp -r ~/dotfiles/themes/catppuccin-mocha ~/dotfiles/themes/<new-theme>
```

Then edit each file in the new directory:

1. `variant` — `dark` or `light`
2. `colors.toml` — the palette; `pi-agent-theme.json` is regenerated from it
3. `palette.sh` — the same palette as shell vars (for humans)
4. `ghostty.conf` and `btop.theme` — replace color values with the new palette
5. `gtk.conf` — GTK preferences
6. `README.md` — describe the theme

Then apply:

```bash
dot-theme-set <new-theme>
```

No code changes needed. `dot-theme-set` discovers themes dynamically via `ls themes/`.

## The Helix drift caveat (resolved 2026-08-07)

Helix used to be themed by sed-rewriting `~/.config/helix/config.toml`. Because
that path was a stow symlink, sed followed it and dirtied the repo copy, so
every `dot-theme-toggle` away from the committed default left a modified line in
`git status`.

Helix is retired and every trace of it is gone — the module, `base/helix/`, the
`themes/*/helix-theme` files and the sed block itself. `dot-theme-set` no longer
writes into the repo at all, so theme toggling always leaves a clean working
tree. Kept here because the symptom (a mysteriously dirty repo after toggling
themes) is memorable enough to be worth recognising if it ever recurs.

## Wallpaper (fragpaper retired 2026-08-08)

There is no wallpaper layer. EWM is the desktop and paints its own background;
nothing in the theme system sets it.

Fragpaper — a GPU shader wallpaper generator — used to fill this role under
Hyprland. It was retired along with its `themes/*/fragpaper.conf` files, the
`bin/fragpaper-*` launchers and `ioshi/i-intelligence/fragpaper.nix`. By the time
it was removed it had already stopped running anywhere: on the T14 the user unit
was `not-found`, no process was alive, and there was no source checkout.

EWM does expose a `Background` layer through layer-shell (`compositor/src/render.rs`),
so a wallpaper client could be reintroduced later. Its absence is a preference,
not a limitation.

## Not handled by the theme system (yet)

- Firefox / web content colors (would need userstyles or a per-site extension)
- LibreOffice / Electron apps other than Obsidian
- Cursor theme (set once, not swapped per theme)
- Per-theme fonts (the shipped themes all use JetBrains Mono Nerd Font)

These are explicit omissions, not oversights. Add them per-theme via `post-set.sh` if you want.
