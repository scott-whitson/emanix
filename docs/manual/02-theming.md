# Chapter 02 — Theming

The theme system is Omarchy-style (directory-per-theme) plus a dark/light toggle layer. Applying a theme is `dot-theme-set <name>`; flipping between dark and light is the separate `dot-theme-toggle`. Neither is bound to a key under EWM — see the omissions list below.

## Commands

```bash
dot-theme-set <name>      # apply a specific theme
dot-theme-toggle          # flip between last-dark and last-light
dot-theme-set             # (no arg) prints usage + lists available themes
```

## Shipped themes

```
themes/
├── catppuccin-mocha/     # dark  — soft, the daily default
├── catppuccin-latte/     # light — soft
├── high-contrast-dark/   # dark  — 16.16:1
└── high-contrast-light/  # light — 16.87:1
```

`dot-theme-toggle` flips dark↔light within the last-used theme of each
variant, so it stays a two-way toggle even with four themes. Choosing high
contrast is an explicit `dot-theme-set`.

The high-contrast pair exists for accessibility (visual snow syndrome), not
aesthetics. Every accent slot clears WCAG AAA (7:1) against its base;
`tests/contrast-check.py` enforces that. Catppuccin is exempt by name — it is
knowingly soft, and 14 of Latte's 18 accent slots fail WCAG AA (4.5:1) against
its base.

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
├── variant              # "dark" or "light" — single word
├── colors.toml          # the palette; [ui] [ansi] [palette] sections
├── palette.sh           # colors as shell vars (reference only; not consumed)
├── emacs-theme          # Emacs theme to load, e.g. "catppuccin", "modus-vivendi"
├── btop.theme           # btop theme → ~/.config/btop/themes/active.theme
├── gtk.conf             # GTK_THEME + COLOR_SCHEME (sourced by dot-theme-set)
├── pi-agent-theme.json  # generated from colors.toml by bin/gen-pi-theme.py
└── README.md            # theme origin, contrast figures
```

`post-set.sh` (optional hook run at the end of `dot-theme-set`, if present and
executable) is part of the anatomy `dot-theme-set` supports, but no shipped
theme currently has one.

**These files are generated, not hand-written.** `bin/gen-theme-dir.py`
renders them from the palette in `lib/themes.nix`, which is the single source
of truth for colour (26 slots per palette). To change a colour, edit the
palette and re-run the generator — do not edit these files directly.

`ghostty.conf` is **not** here: ghostty configs are rendered by Nix into
`~/.config/ghostty/themes/<name>.conf`, and `dot-theme-set` symlinks one of
those to `~/.config/ghostty/theme.conf`. Home Manager deliberately does not
declare `theme.conf` — two owners for that path meant every rebuild silently
reverted the active theme.

Only ghostty and btop are themed by symlinking a rendered config into place.
Everything else uses a different mechanism per app: Emacs (including the EWM
top bar) is themed by calling `scott/theme-set` in the running daemon; pi's
agent theme is regenerated from `colors.toml` on every switch; zellij and
Claude Code follow the terminal's own ANSI palette rather than reading
anything theme-specific; GTK goes through `gsettings`; and Firefox chrome is
rendered by Nix from `config.eminix.theme` at build time. That is **not** the
same mechanism as ghostty: ghostty pre-renders all four palettes into
`~/.config/ghostty/themes/`, and the runtime switcher picks one of them.
Firefox renders exactly one palette into the generated `userChrome.css`, and
the runtime switcher (`dot-theme-set`) never picks — it has no way to touch
Firefox at all. Running `dot-theme-set` never changes Firefox, on restart or
ever; only editing `eminix.theme` in `host config` and rebuilding
does. "Themed by file symlink" was never a complete description even for the
two apps it did cover, and it undercounts what the system now reaches.

## How `dot-theme-set <name>` works

1. Validates `themes/<name>/` exists; refuses unknown names.
2. Reads `variant` (must be `dark` or `light`).
3. Writes `~/.config/dotfiles/active-theme` = `<name>` and `last-<variant>` = `<name>`.
4. Symlinks `~/.config/ghostty/themes/<name>.conf` → `~/.config/ghostty/theme.conf`,
   and `btop.theme` → `~/.config/btop/themes/active.theme`.
5. Symlinks `available/eminix-<variant>.kdl` → `active/theme.kdl` in
   `~/.local/share/dotfiles/zellij-themes/`. Both definitions are named
   `eminix`, so zellij's `theme` line never changes.
6. Regenerates `pi-agent-theme.json` from `colors.toml` and points pi's
   `settings.json` at it.
7. Writes Claude Code's `theme` key to `dark-ansi`/`light-ansi`.
8. Sources `gtk.conf` and runs `gsettings` for `color-scheme` and `gtk-theme`.
9. Runs `themes/<name>/post-set.sh` if present and executable.
10. Calls `(scott/theme-set "<name>")` in the running Emacs daemon, resolving
    `emacsclient` from `PATH`. Emacs maps the name via `themes/<name>/emacs-theme`.
11. Signals ghostty (`SIGUSR2`) to reload.

zellij and Claude Code are themed by **terminal ANSI colours**, not by hex, so
they follow whichever terminal renders them — including over ssh, where that
terminal belongs to the client. Only the dark/light axis is written for them.

**A note on the zellij theme files, so nobody "simplifies" them back.** Both
`eminix-dark.kdl` and `eminix-light.kdl` use zellij's verbose per-declaration
format — `text_unselected`, `ribbon_selected`, and so on, each spelling out
`base`/`background`/`emphasis_0`–`emphasis_3` as ANSI indices — rather than
zellij's shorter bare `fg`/`bg`/`black`/`white`/… palette format. That
shorthand has no way to set `theme_hue`, which then defaults to `Dark`; `impl
From<Palette> for Styling` in zellij's `zellij-utils/src/data.rs` derives the
background from `palette.black`, so a light theme written in the bare format
still renders its unselected rows on black. This was got wrong twice during
development. Both definitions here are instead modelled on zellij's own
bundled `assets/themes/ansi.kdl` (a 16-ANSI-colour per-declaration theme),
with the light variant exchanging the greyscale ends (indices `0↔15`,
`7↔8`).

## How `dot-theme-toggle` works

1. Reads `active-theme`, looks up its variant.
2. Applies the theme named in `last-<opposite-variant>` via `dot-theme-set`.
3. If `last-<opposite>` is empty (first-ever toggle to that variant): falls back to the first theme in `themes/*/` with the opposite variant, warns on stderr.

The first toggle after a fresh install uses the fallback path. Every subsequent toggle reads the markers cleanly.

## Adding a new theme

Themes are generated from `lib/themes.nix`, so adding one is two steps:

1. Add a palette to `palettes` in `lib/themes.nix` (26 slots; copy an existing
   one as the shape).
2. Render its directory and check contrast:

```bash
cd ~/dotfiles
PAL=$(mktemp)
nix eval --json --impure --expr 'let t = import ./lib/themes.nix { pkgs = import <nixpkgs> {}; };
  in builtins.mapAttrs (n: p: p // { ansi = t.ansiSlots p; }) t.palettes' > "$PAL"
bin/gen-theme-dir.py <new-theme> themes/<new-theme> themes/catppuccin-mocha/btop.theme < "$PAL"
echo <emacs-theme-name> > themes/<new-theme>/emacs-theme
python3 tests/contrast-check.py < "$PAL"
```

Then rebuild (so Nix renders its ghostty config) and apply:

```bash
sudo nixos-rebuild switch --flake .#<host>
dot-theme-set <new-theme>
```

No code changes needed — `dot-theme-set` discovers themes via `ls themes/`,
and Emacs resolves the theme through `themes/<name>/emacs-theme`.

## The Helix drift caveat (resolved 2026-08-07)

Helix used to be themed by sed-rewriting `~/.config/helix/config.toml`. Because
that path was a stow symlink, sed followed it and dirtied the repo copy, so
every `dot-theme-toggle` away from the committed default left a modified line in
`git status`.

Helix is retired and every trace of it is gone — the module, `base/helix/`, the
`themes/*/helix-theme` files and the sed block itself. That sed-into-a-symlink
defect is gone, but `dot-theme-set` still writes into the repo in two places:
it regenerates `themes/<name>/pi-agent-theme.json` from `colors.toml` on every
switch (see the script), and it rewrites `~/.claude/settings.json`, an
out-of-store symlink into the checkout, per `claude.nix`. Both leave a clean
`git status` today only because their output is deterministic — every switch
reproduces the same bytes for a given theme, not new ones — so there is
nothing to commit. That is incidental, not structural: a change to either
generator that makes its output non-deterministic would dirty the tree on
every switch with no warning. Kept here because the symptom (a mysteriously
dirty repo after toggling themes) is memorable enough to be worth recognising
if it ever recurs.

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

- **Firefox page content.** Chrome is themed; page colours are left as
  authored. Forcing the palette onto content is one pref
  (`browser.display.document_color_use = 2` in `firefox.nix`) and is the
  bigger accessibility lever, but it breaks sites that hardcode colours
  without honouring `forced-colors`. Deliberately not enabled — see
  `docs/superpowers/specs/2026-08-09-theming-high-contrast-design.md`.
- LibreOffice / Electron apps
- Cursor theme (set once, not swapped per theme)
- Per-theme fonts (all shipped themes use JetBrains Mono Nerd Font)
- **No keybinding for `dot-theme-toggle`.** The Hyprland-era `$mod+Shift+T`
  went with Hyprland; nothing is bound under EWM.

These are explicit omissions, not oversights. Add them per-theme via `post-set.sh` if you want.
