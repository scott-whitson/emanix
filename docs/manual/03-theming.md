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
|---|---|
| `active-theme` | Currently applied theme (used by `install/10-theme.sh` on re-install) |
| `last-dark` | Most recent dark theme (source of truth for `dot-theme-toggle` when flipping to dark) |
| `last-light` | Most recent light theme |

## Theme directory anatomy

Each theme is a self-contained directory. All files are pre-rendered; there's no templating step.

```
themes/catppuccin-mocha/
├── variant            # "dark" or "light" — single word
├── palette.sh         # colors as shell vars (reference only; not consumed)
├── hypr.conf          # border colors → symlinked to ~/.config/hypr/theme.conf
├── hyprlock.conf      # full hyprlock screen → ~/.config/hypr/hyprlock.conf
├── ghostty.conf       # terminal palette → ~/.config/ghostty/theme.conf
├── waybar.css         # status bar styles → ~/.config/waybar/style.css
├── mako.conf          # notification colors → ~/.config/mako/config
├── fuzzel.ini         # launcher colors → ~/.config/fuzzel/fuzzel.ini
├── btop.theme         # btop theme → ~/.config/btop/themes/active.theme
├── nvim.lua           # `vim.cmd.colorscheme('…')` → ~/.config/nvim/lua/dotfiles-theme.lua
├── helix-theme        # one word: Helix theme name (sed-rewrites config.toml)
├── obsidian-theme     # one word: Obsidian theme name (JSON-patches appearance.json)
├── gtk.conf           # GTK_THEME + COLOR_SCHEME (sourced by dot-theme-set, applied via gsettings)
├── fragpaper.conf     # BG_COLOR + PALETTE for fragpaper wallpaper daemon
├── README.md          # theme origin, extra font/plugin requirements
└── post-set.sh        # optional hook run at the end of dot-theme-set
```

## How `dot-theme-set <name>` works

1. Validates `themes/<name>/` exists; refuses unknown names.
2. Reads `variant` (must be `dark` or `light`).
3. Writes `~/.config/dotfiles/active-theme` = `<name>` and `last-<variant>` = `<name>`.
4. Symlinks each per-app file into its target location (see anatomy table above).
5. Sed-rewrites the `theme = "..."` line in `~/.config/helix/config.toml` to the value in `helix-theme`.
6. If `$OBSIDIAN_VAULT` is set in the active profile's `profile.conf`, JSON-patches the vault's `.obsidian/appearance.json` with the value in `obsidian-theme`.
7. Sources `gtk.conf` and runs `gsettings` for `color-scheme` and `gtk-theme`.
8. Kills + relaunches fragpaper via `fragpaper-launch` (which reads the new `active-theme` marker).
9. Runs `themes/<name>/post-set.sh` if present and executable.
10. Sends reload signals: `hyprctl reload`, `SIGUSR2` to waybar/ghostty, `makoctl reload`, `SIGUSR1` to helix.

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
2. `palette.sh` — the new palette as shell vars (for humans)
3. All the per-app files — replace color values with the new palette
4. `helix-theme` — Helix upstream theme name (or a custom one if you ship it with kickstart)
5. `obsidian-theme` — Obsidian theme name
6. `gtk.conf` — GTK preferences
7. `fragpaper.conf` — fragpaper bg color + palette hint
8. `README.md` — describe the theme

Then apply:

```bash
dot-theme-set <new-theme>
```

No code changes needed. `dot-theme-set` discovers themes dynamically via `ls themes/`.

## The Helix drift caveat

`dot-theme-set` sed-rewrites `~/.config/helix/config.toml`. Because that file is a stow symlink, sed follows it and modifies `base/helix/.config/helix/config.toml` in the repo.

**Consequence:** every time you `dot-theme-toggle` away from your committed default, `git status` shows one modified line in that file. Toggling back cleans the working tree.

The committed default is currently `catppuccin_mocha`. Drift appears when you're in light mode; disappears when you flip back to dark.

If this ever annoys you enough, three escape hatches:

1. Commit the current drift (sets the new value as the default)
2. `git checkout -- base/helix/.config/helix/config.toml` to revert
3. Switch Helix to a colorscheme management plugin that can source an include file — not shipped here.

## Fragpaper integration

Fragpaper is a GPU shader wallpaper generator (not a static image). Each theme provides `BG_COLOR` and `PALETTE` (`dark` or `light`) via `fragpaper.conf`. `fragpaper-launch` reads the active theme and passes them to the installed fragpaper binary.

If fragpaper isn't installed, theme switching still works — fragpaper relaunch is `|| true` guarded and the rest of the system doesn't care.

## Not handled by the theme system (yet)

- Firefox / web content colors (would need userstyles or a per-site extension)
- LibreOffice / Electron apps other than Obsidian
- Cursor theme (set once, not swapped per theme)
- Per-theme fonts (the shipped themes all use JetBrains Mono Nerd Font)

These are explicit omissions, not oversights. Add them per-theme via `post-set.sh` if you want.
