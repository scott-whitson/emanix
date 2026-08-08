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
├── palette.sh         # colors as shell vars (reference only; not consumed)
├── hypr.conf          # border colors → symlinked to ~/.config/hypr/theme.conf
├── hyprlock.conf      # full hyprlock screen → ~/.config/hypr/hyprlock.conf
├── ghostty.conf       # terminal palette → ~/.config/ghostty/theme.conf
├── tab-bar.el         # EWM tab-bar styling + status rendering
├── mako.conf          # notification colors → ~/.config/mako/config
├── fuzzel.ini         # launcher colors → ~/.config/fuzzel/fuzzel.ini
├── btop.theme         # btop theme → ~/.config/btop/themes/active.theme
├── nvim.lua           # `vim.cmd.colorscheme('…')` → ~/.config/nvim/lua/dotfiles-theme.lua
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
4. Symlinks each per-app file into its target location (see anatomy table above). The EWM top bar is refreshed from the running Emacs daemon; it is not a separate CSS-driven status bar.
5. If `$OBSIDIAN_VAULT` is set in the active profile's `profile.conf`, JSON-patches the vault's `.obsidian/appearance.json` with the value in `obsidian-theme`.
6. Sources `gtk.conf` and runs `gsettings` for `color-scheme` and `gtk-theme`.
7. Restarts the `fragpaper.service` user unit so the wallpaper picks up the new `active-theme` marker (with a fallback to `fragpaper-launch` if the service is unavailable).
8. Runs `themes/<name>/post-set.sh` if present and executable.
9. Sends reload signals: `hyprctl reload`, `makoctl reload`. EWM bar state is refreshed in the running Emacs daemon.

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
4. `obsidian-theme` — Obsidian theme name
5. `gtk.conf` — GTK preferences
6. `fragpaper.conf` — fragpaper bg color + palette hint
7. `README.md` — describe the theme

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

## Fragpaper integration

Fragpaper is a GPU shader wallpaper generator (not a static image). Each theme provides `BG_COLOR` and `PALETTE` (`dark` or `light`) via `fragpaper.conf`. `fragpaper.service` is a Home Manager systemd user service defined in `ioshi/i-intelligence/fragpaper.nix`, gated on `scott.gui` and wanted by `graphical-session.target` — it starts automatically on any GUI host, no Hyprland involved. `fragpaper-launch` reads the active theme and passes it to the installed fragpaper binary, reading shader files from the best available checkout (`~/.local/share/fragpaper` on runtime desktops, `~/projects/fragpaper` on datacore/dev machines). The EWM top bar is updated from the running Emacs daemon, not through a separate status-bar CSS file.

If fragpaper isn't installed, theme switching still works — fragpaper relaunch is `|| true` guarded and the rest of the system doesn't care.

## Not handled by the theme system (yet)

- Firefox / web content colors (would need userstyles or a per-site extension)
- LibreOffice / Electron apps other than Obsidian
- Cursor theme (set once, not swapped per theme)
- Per-theme fonts (the shipped themes all use JetBrains Mono Nerd Font)

These are explicit omissions, not oversights. Add them per-theme via `post-set.sh` if you want.
