# Dotfiles Reorg — Wave 3: Theme System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire the existing dark/light `theme-switch` script in favor of an Omarchy-style directory-per-theme system. Ship two themes at launch (`catppuccin-mocha` + `catppuccin-latte`). Preserve the dark/light quick-toggle UX via a new `dot-theme-toggle` command bound to `$mod+SHIFT+t`.

**Architecture:** Each theme lives as a self-contained directory under `themes/<name>/` containing pre-rendered per-app config files plus a `variant` marker (`dark` or `light`) and a `fragpaper.conf` (bg color + palette hint). The real `bin/dot-theme-set` replaces the Wave 2 stub: it validates the theme, writes markers (`active-theme` + `last-<variant>`), symlinks each per-app file into `~/.config/…`, sed-rewrites Helix's `config.toml`, JSON-patches Obsidian's `appearance.json`, runs `gsettings`, relaunches fragpaper, and sends reload signals to running apps. `bin/dot-theme-toggle` reads the active theme's variant and flips to the counterpart via `last-<other-variant>`. `install/10-theme.sh` grows from stub into a real theme applier. The `$mod+SHIFT+t` Hyprland keybind rewires from `theme-switch` → `dot-theme-toggle`.

**Tech Stack:** Bash, GNU Stow, sed, Python 3 (Obsidian JSON patch, preserved from existing), gsettings, hyprctl, makoctl, pkill signals.

**Spec:** `docs/superpowers/specs/2026-04-23-dotfiles-opinionated-reorg-design.md` (Section 3, updated 2026-04-24)

**Scope note:** Wave 3 ships 2 themes (catppuccin-mocha + catppuccin-latte) so the toggle works out of the box. The user's prior Tokyo Night dark + daltonized light palettes are preserved in git history (commits `fc99ab3`, `a151838`, etc.) and can be extracted as additional themes post-Wave-3 if missed. Adding a new theme is a copy-and-edit operation, no code changes.

---

## Pre-plan checklist

Before starting Task 1:

- [ ] HEAD is on `main` at the latest commit (`53aaabc` or later).
- [ ] `cd ~/dotfiles && git status` — working tree clean.
- [ ] `command -v theme-switch` returns a path — the existing script is live on the current machine.
- [ ] `~/.config/nvim/init.lua` contains `pcall(require, 'dotfiles-theme')` (Wave 2 should have injected this).
- [ ] `~/.config/dotfiles/` directory may or may not exist; will be created by `dot-theme-set` on first run.

### ⚠️ LIVE-MACHINE IMPACT WARNING

Tasks 14-15 run `dot-theme-set` live against your workstation. Expect:
- All terminal colors switch (Ghostty reloads via SIGUSR2)
- Hyprland border colors change (reload)
- Waybar restyles (SIGUSR2)
- Mako notifications restyle (makoctl reload)
- Fragpaper gets killed and relaunched with new palette
- Helix running instances reload config on SIGUSR1
- Obsidian vault theme changes (if vault present)
- GTK apps (Firefox in particular) pick up new color-scheme preference

None of this is destructive — each change is reversible by running `dot-theme-set <other>` or `dot-theme-toggle`. But visually it'll be jarring. Consider having a spare terminal open to react if anything fails.

---

## File Structure

**New files created by this plan:**

| Path | Purpose |
|---|---|
| `themes/catppuccin-mocha/variant` | Contains `dark` |
| `themes/catppuccin-mocha/palette.sh` | Catppuccin Mocha palette as shell vars (human reference) |
| `themes/catppuccin-mocha/hypr.conf` | Hyprland border colors ($col_active, $col_inactive) |
| `themes/catppuccin-mocha/hyprlock.conf` | Full hyprlock screen (Catppuccin Mocha) |
| `themes/catppuccin-mocha/ghostty.conf` | 16-color palette + bg/fg |
| `themes/catppuccin-mocha/waybar.css` | Status bar styles |
| `themes/catppuccin-mocha/mako.conf` | Notification colors |
| `themes/catppuccin-mocha/fuzzel.ini` | Launcher colors |
| `themes/catppuccin-mocha/btop.theme` | btop theme |
| `themes/catppuccin-mocha/nvim.lua` | `vim.cmd.colorscheme('catppuccin-mocha')` |
| `themes/catppuccin-mocha/helix-theme` | Contains `catppuccin_mocha` |
| `themes/catppuccin-mocha/obsidian-theme` | Contains `obsidian` (default dark) |
| `themes/catppuccin-mocha/gtk.conf` | GTK theme + gsettings color-scheme=prefer-dark |
| `themes/catppuccin-mocha/fragpaper.conf` | `BG_COLOR=#1e1e2e`, `PALETTE=dark` |
| `themes/catppuccin-mocha/README.md` | Theme description, plugin requirements |
| `themes/catppuccin-mocha/post-set.sh` | Optional hook (empty/absent initially) |
| `themes/catppuccin-latte/*` | Light variant (16 files, same structure) |
| `bin/dot-theme-toggle` | New: flip between last-dark and last-light |

**Files MODIFIED by this plan:**

| Path | Change |
|---|---|
| `bin/dot-theme-set` | Replace Wave 2 stub with real directory-per-theme implementation |
| `base/bin/.local/bin/fragpaper-launch` | Read from `~/.config/dotfiles/active-theme` + `fragpaper.conf` |
| `base/hypr/.config/hypr/hyprland.conf` | Rewire `$mod SHIFT t` binding to `dot-theme-toggle`; change `source = ~/.config/hypr/colors/theme.conf` → `source = ~/.config/hypr/theme.conf` |
| `base/ghostty/.config/ghostty/config` | Change `config-file = theme.conf` path context if needed |
| `base/btop/.config/btop/btop.conf` | Set `color_theme = "active"` so btop reads from `themes/active.theme` (a symlink to active theme's btop.theme) |
| `install/10-theme.sh` | Replace Wave 2 stub — actually invoke `dot-theme-set` when active-theme marker is present |
| `bin/dot-doctor` | Add theme-related checks (active-theme marker exists, symlinks intact) |

**Files DELETED by this plan:**

| Path | Why |
|---|---|
| `base/hypr/.config/hypr/colors/dark.conf` | Content moved to `themes/*/hypr.conf` |
| `base/hypr/.config/hypr/colors/light.conf` | Same |
| `base/hypr/.config/hypr/colors/theme.conf` (if a tracked symlink) | No longer needed; new active symlink lives at `~/.config/hypr/theme.conf` |
| `base/hypr/.config/hypr/hyprlock-dark.conf` | Content moved to `themes/catppuccin-mocha/hyprlock.conf` |
| `base/hypr/.config/hypr/hyprlock-light.conf` | Content moved to `themes/catppuccin-latte/hyprlock.conf` |
| `base/ghostty/.config/ghostty/dark.conf` | Content moved to `themes/catppuccin-mocha/ghostty.conf` |
| `base/ghostty/.config/ghostty/light.conf` | Content moved to `themes/catppuccin-latte/ghostty.conf` |
| `base/ghostty/.config/ghostty/theme.conf` (if tracked symlink) | Now a live symlink created by `dot-theme-set` |
| `base/waybar/.config/waybar/dark.css` | Content moved to `themes/catppuccin-mocha/waybar.css` |
| `base/waybar/.config/waybar/light.css` | Content moved to `themes/catppuccin-latte/waybar.css` |
| `base/waybar/.config/waybar/style.css` (if tracked symlink) | Now a live symlink |
| `base/mako/.config/mako/dark` | Content moved to `themes/catppuccin-mocha/mako.conf` |
| `base/mako/.config/mako/light` | Content moved to `themes/catppuccin-latte/mako.conf` |
| `base/fuzzel/.config/fuzzel/dark.ini` | Content moved to `themes/catppuccin-mocha/fuzzel.ini` |
| `base/fuzzel/.config/fuzzel/light.ini` | Content moved to `themes/catppuccin-latte/fuzzel.ini` |
| `base/bin/.local/bin/theme-switch` | Replaced by `bin/dot-theme-set` + `bin/dot-theme-toggle` |

---

## Reference: Catppuccin palette values

Authoritative source: https://catppuccin.com/palette. Reproduced here for plan self-containment.

### Catppuccin Mocha (dark)

```
Rosewater #f5e0dc   Flamingo  #f2cdcd   Pink      #f5c2e7
Mauve     #cba6f7   Red       #f38ba8   Maroon    #eba0ac
Peach     #fab387   Yellow    #f9e2af   Green     #a6e3a1
Teal      #94e2d5   Sky       #89dceb   Sapphire  #74c7ec
Blue      #89b4fa   Lavender  #b4befe
Text      #cdd6f4   Subtext1  #bac2de   Subtext0  #a6adc8
Overlay2  #9399b2   Overlay1  #7f849c   Overlay0  #6c7086
Surface2  #585b70   Surface1  #45475a   Surface0  #313244
Base      #1e1e2e   Mantle    #181825   Crust     #11111b
```

### Catppuccin Latte (light)

```
Rosewater #dc8a78   Flamingo  #dd7878   Pink      #ea76cb
Mauve     #8839ef   Red       #d20f39   Maroon    #e64553
Peach     #fe640b   Yellow    #df8e1d   Green     #40a02b
Teal      #179299   Sky       #04a5e5   Sapphire  #209fb5
Blue      #1e66f5   Lavender  #7287fd
Text      #4c4f69   Subtext1  #5c5f77   Subtext0  #6c6f85
Overlay2  #7c7f93   Overlay1  #8c8fa1   Overlay0  #9ca0b0
Surface2  #acb0be   Surface1  #bcc0cc   Surface0  #ccd0da
Base      #eff1f5   Mantle    #e6e9ef   Crust     #dce0e8
```

---

## Task 1: Create `themes/catppuccin-mocha/` metadata files

**Files:**
- Create: `themes/catppuccin-mocha/variant`
- Create: `themes/catppuccin-mocha/palette.sh`
- Create: `themes/catppuccin-mocha/helix-theme`
- Create: `themes/catppuccin-mocha/obsidian-theme`
- Create: `themes/catppuccin-mocha/nvim.lua`
- Create: `themes/catppuccin-mocha/gtk.conf`
- Create: `themes/catppuccin-mocha/fragpaper.conf`
- Create: `themes/catppuccin-mocha/README.md`

These are the short files. Visual configs come in Task 2.

- [ ] **Step 1: `themes/catppuccin-mocha/variant`**

```
dark
```

(single word, no trailing newline required but acceptable)

- [ ] **Step 2: `themes/catppuccin-mocha/palette.sh`**

```bash
# Catppuccin Mocha palette — human reference (not consumed by dot-theme-set)
# Source: https://catppuccin.com/palette
export CATPPUCCIN_ROSEWATER="#f5e0dc"
export CATPPUCCIN_FLAMINGO="#f2cdcd"
export CATPPUCCIN_PINK="#f5c2e7"
export CATPPUCCIN_MAUVE="#cba6f7"
export CATPPUCCIN_RED="#f38ba8"
export CATPPUCCIN_MAROON="#eba0ac"
export CATPPUCCIN_PEACH="#fab387"
export CATPPUCCIN_YELLOW="#f9e2af"
export CATPPUCCIN_GREEN="#a6e3a1"
export CATPPUCCIN_TEAL="#94e2d5"
export CATPPUCCIN_SKY="#89dceb"
export CATPPUCCIN_SAPPHIRE="#74c7ec"
export CATPPUCCIN_BLUE="#89b4fa"
export CATPPUCCIN_LAVENDER="#b4befe"
export CATPPUCCIN_TEXT="#cdd6f4"
export CATPPUCCIN_SUBTEXT1="#bac2de"
export CATPPUCCIN_SUBTEXT0="#a6adc8"
export CATPPUCCIN_OVERLAY2="#9399b2"
export CATPPUCCIN_OVERLAY1="#7f849c"
export CATPPUCCIN_OVERLAY0="#6c7086"
export CATPPUCCIN_SURFACE2="#585b70"
export CATPPUCCIN_SURFACE1="#45475a"
export CATPPUCCIN_SURFACE0="#313244"
export CATPPUCCIN_BASE="#1e1e2e"
export CATPPUCCIN_MANTLE="#181825"
export CATPPUCCIN_CRUST="#11111b"
```

- [ ] **Step 3: `themes/catppuccin-mocha/helix-theme`**

```
catppuccin_mocha
```

(Helix ships this theme upstream — no plugin install required.)

- [ ] **Step 4: `themes/catppuccin-mocha/obsidian-theme`**

```
obsidian
```

(Keeping existing behavior — "obsidian" is Obsidian's default dark. User can install the community Catppuccin Obsidian theme later if desired, then edit this file to the new name.)

- [ ] **Step 5: `themes/catppuccin-mocha/nvim.lua`**

```lua
-- Catppuccin Mocha for Neovim
-- Requires the `catppuccin/nvim` plugin installed in your kickstart fork.
-- If plugin is missing, pcall in init.lua silently falls back to kickstart default.
vim.cmd.colorscheme('catppuccin-mocha')
```

- [ ] **Step 6: `themes/catppuccin-mocha/gtk.conf`**

```bash
# GTK + system color-scheme for Catppuccin Mocha
# Consumed by dot-theme-set via `source` — exports key=value vars.
GTK_THEME="Adwaita-dark"
COLOR_SCHEME="prefer-dark"
```

- [ ] **Step 7: `themes/catppuccin-mocha/fragpaper.conf`**

```bash
# Fragpaper args for this theme. Consumed by fragpaper-launch.
BG_COLOR="#1e1e2e"
PALETTE="dark"
```

- [ ] **Step 8: `themes/catppuccin-mocha/README.md`**

```markdown
# Catppuccin Mocha (dark)

The dark half of the Catppuccin palette. Variant: **dark**.

## Activate

    dot-theme-set catppuccin-mocha

## Optional enhancements

- **Neovim:** install the `catppuccin/nvim` plugin in your kickstart fork for
  colors to apply. Add to `~/.config/nvim/lua/custom/plugins/catppuccin.lua`:
  ```lua
  return {
    { 'catppuccin/nvim', name = 'catppuccin', priority = 1000 },
  }
  ```
- **Obsidian:** install the community "Catppuccin" theme and edit
  `themes/catppuccin-mocha/obsidian-theme` to `Catppuccin`. Otherwise ships
  with Obsidian's default dark theme.
- **GTK apps:** `gtk.conf` sets `Adwaita-dark` by default. Replace with
  `catppuccin-mocha-mauve-standard` (or similar) if you've installed a GTK
  Catppuccin theme package from AUR.

Source: https://catppuccin.com/palette
```

- [ ] **Step 9: Verify directory state**

```bash
ls ~/dotfiles/themes/catppuccin-mocha/
wc -l ~/dotfiles/themes/catppuccin-mocha/*
```

Expected: 8 files, each between 1 and ~30 lines.

- [ ] **Step 10: Commit**

```bash
cd ~/dotfiles && git add themes/catppuccin-mocha/
git commit -m "$(cat <<'EOF'
themes: add catppuccin-mocha metadata files

Foundation for the directory-per-theme system (Wave 3). Includes
variant marker, palette reference, nvim/helix/obsidian/gtk hooks,
fragpaper args, README. Visual config files (hypr/ghostty/waybar/
mako/fuzzel/btop) land in Task 2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Create `themes/catppuccin-mocha/` visual configs

**Files:**
- Create: `themes/catppuccin-mocha/hypr.conf`
- Create: `themes/catppuccin-mocha/hyprlock.conf`
- Create: `themes/catppuccin-mocha/ghostty.conf`
- Create: `themes/catppuccin-mocha/waybar.css`
- Create: `themes/catppuccin-mocha/mako.conf`
- Create: `themes/catppuccin-mocha/fuzzel.ini`
- Create: `themes/catppuccin-mocha/btop.theme`

Strategy: for smaller files (hypr.conf, mako.conf, fuzzel.ini, ghostty.conf), provide full verbatim content. For larger files (waybar.css, hyprlock.conf, btop.theme), port the structure of the existing `base/<app>/dark*` file and substitute Catppuccin Mocha palette values.

- [ ] **Step 1: `themes/catppuccin-mocha/hypr.conf`**

```
# Catppuccin Mocha — Hyprland border colors.
# Active = Blue (#89b4fa); inactive = transparent (matches user's no-visible-inactive-border preference).
$col_active = rgb(89b4fa)
$col_inactive = rgba(00000000)
```

- [ ] **Step 2: `themes/catppuccin-mocha/hyprlock.conf`**

Read the existing `base/hypr/.config/hypr/hyprlock-dark.conf`:

```bash
cat ~/dotfiles/base/hypr/.config/hypr/hyprlock-dark.conf
```

Port its structure to `themes/catppuccin-mocha/hyprlock.conf`, substituting any color values with Catppuccin Mocha equivalents:
- Background dominant → `rgba(1e1e2ee6)` (Base with e6 alpha, ~90% opacity)
- Text color → `rgb(cdd6f4)` (Text)
- Accent / input field border → `rgb(89b4fa)` (Blue)
- Error / wrong password → `rgb(f38ba8)` (Red)
- Any muted / subtle colors → `rgb(a6adc8)` (Subtext0)

Preserve layout (positions, fonts, shapes). Only substitute colors.

If the existing hyprlock-dark.conf has references to $col_active / $col_inactive, replace those with direct hex values (this file is standalone, not sourced).

- [ ] **Step 3: `themes/catppuccin-mocha/ghostty.conf`**

```
# Catppuccin Mocha — Ghostty terminal
# Source: https://github.com/catppuccin/ghostty

background = #1e1e2e
foreground = #cdd6f4
background-opacity = 1.0

cursor-color = #f5e0dc
cursor-text = #1e1e2e

selection-background = #585b70
selection-foreground = #cdd6f4

# Normal palette (0-7)
palette = 0=#45475a
palette = 1=#f38ba8
palette = 2=#a6e3a1
palette = 3=#f9e2af
palette = 4=#89b4fa
palette = 5=#f5c2e7
palette = 6=#94e2d5
palette = 7=#bac2de

# Bright palette (8-15)
palette = 8=#585b70
palette = 9=#f38ba8
palette = 10=#a6e3a1
palette = 11=#f9e2af
palette = 12=#89b4fa
palette = 13=#f5c2e7
palette = 14=#94e2d5
palette = 15=#a6adc8
```

- [ ] **Step 4: `themes/catppuccin-mocha/waybar.css`**

Read the existing `base/waybar/.config/waybar/dark.css`:

```bash
cat ~/dotfiles/base/waybar/.config/waybar/dark.css
```

Port its structure to `themes/catppuccin-mocha/waybar.css`, substituting color hex values with Catppuccin Mocha equivalents. Common substitutions:
- Window / module background → `#1e1e2e` (Base) or `#181825` (Mantle) for nested bg
- Text color → `#cdd6f4` (Text)
- Accent highlights (active workspace) → `#89b4fa` (Blue)
- Muted text / inactive → `#a6adc8` (Subtext0) or `#6c7086` (Overlay0)
- Warning / battery-low → `#f9e2af` (Yellow) or `#fab387` (Peach)
- Critical / error → `#f38ba8` (Red)
- Success / success indicator → `#a6e3a1` (Green)
- Borders → `#45475a` (Surface1) or transparent

Preserve all CSS selector structure, properties (padding, border-radius, transitions), layout. Only substitute colors.

- [ ] **Step 5: `themes/catppuccin-mocha/mako.conf`**

Read the existing `base/mako/.config/mako/dark`:

```bash
cat ~/dotfiles/base/mako/.config/mako/dark
```

Port its structure to `themes/catppuccin-mocha/mako.conf`:
- background-color → `#1e1e2e` (Base)
- text-color → `#cdd6f4` (Text)
- border-color → `#89b4fa` (Blue)
- progress-color → `#89b4fa`
- Preserve timeouts, positions, widths, and any app-specific rules (you already removed the kitty rule in Wave 1)

If the source file has sections like `[urgency=critical]`, preserve those with red Catppuccin values:
- critical bg → `#1e1e2e`
- critical border → `#f38ba8` (Red)
- critical text → `#f38ba8`

- [ ] **Step 6: `themes/catppuccin-mocha/fuzzel.ini`**

Read the existing `base/fuzzel/.config/fuzzel/dark.ini`:

```bash
cat ~/dotfiles/base/fuzzel/.config/fuzzel/dark.ini
```

Port its structure, substituting `[colors]` section with Catppuccin Mocha:

```ini
[colors]
background=1e1e2eff
text=cdd6f4ff
match=f38ba8ff
selection=45475aff
selection-text=cdd6f4ff
selection-match=f38ba8ff
border=89b4faff
```

(Fuzzel uses 8-char hex including alpha; `ff` = opaque.)

Preserve all other sections (font, lines, width, prompt, dpi-aware, etc.) verbatim.

- [ ] **Step 7: `themes/catppuccin-mocha/btop.theme`**

Use the upstream Catppuccin Mocha btop theme. Quick fetch:

```bash
curl -sSL https://raw.githubusercontent.com/catppuccin/btop/main/themes/catppuccin_mocha.theme \
    -o ~/dotfiles/themes/catppuccin-mocha/btop.theme
```

If the curl fails, fall back to a minimal handwritten btop theme — but try curl first since the upstream is authoritative and maintained.

- [ ] **Step 8: Verify all 7 files created + syntax-check what can be syntax-checked**

```bash
ls -la ~/dotfiles/themes/catppuccin-mocha/*.conf ~/dotfiles/themes/catppuccin-mocha/*.css ~/dotfiles/themes/catppuccin-mocha/*.ini ~/dotfiles/themes/catppuccin-mocha/*.theme
wc -l ~/dotfiles/themes/catppuccin-mocha/{hypr,hyprlock,ghostty,mako}.conf ~/dotfiles/themes/catppuccin-mocha/waybar.css ~/dotfiles/themes/catppuccin-mocha/fuzzel.ini ~/dotfiles/themes/catppuccin-mocha/btop.theme
```

Expected: 7 files listed, each non-empty. Spot-check color values:

```bash
grep -E '#[0-9a-f]{6}' ~/dotfiles/themes/catppuccin-mocha/ghostty.conf | head -5
```

Expected: lines with Catppuccin Mocha hex values (`#cdd6f4`, `#89b4fa`, `#1e1e2e`, etc.).

- [ ] **Step 9: Commit**

```bash
cd ~/dotfiles && git add themes/catppuccin-mocha/
git commit -m "$(cat <<'EOF'
themes: add catppuccin-mocha visual configs

hypr.conf (border colors), hyprlock.conf (lock screen), ghostty.conf
(terminal palette), waybar.css (status bar), mako.conf (notifications),
fuzzel.ini (launcher), btop.theme (system monitor).

Ports structure from existing base/<app>/dark* files, substituting
palette hex values for Catppuccin Mocha. Preserves user's transparent-
inactive-border preference in hypr.conf.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Create `themes/catppuccin-latte/` metadata files

**Files:** mirror of Task 1 for the light variant.

The structure is identical to Task 1's. Substitute:
- `variant` → `light`
- `palette.sh` → Latte palette values (see Reference section at top of plan)
- `helix-theme` → `catppuccin_latte` (Helix ships this upstream)
- `obsidian-theme` → `moonstone` (Obsidian's default light)
- `nvim.lua` → `vim.cmd.colorscheme('catppuccin-latte')`
- `gtk.conf` → `GTK_THEME="Adwaita"`, `COLOR_SCHEME="prefer-light"`
- `fragpaper.conf` → `BG_COLOR="#eff1f5"`, `PALETTE="light"`
- `README.md` → light-variant wording; same plugin notes but point at latte equivalents

- [ ] **Step 1: Write `themes/catppuccin-latte/variant`**

```
light
```

- [ ] **Step 2: Write `themes/catppuccin-latte/palette.sh`**

Same structure as mocha's palette.sh, using Catppuccin Latte values:

```bash
# Catppuccin Latte palette — human reference
# Source: https://catppuccin.com/palette
export CATPPUCCIN_ROSEWATER="#dc8a78"
export CATPPUCCIN_FLAMINGO="#dd7878"
export CATPPUCCIN_PINK="#ea76cb"
export CATPPUCCIN_MAUVE="#8839ef"
export CATPPUCCIN_RED="#d20f39"
export CATPPUCCIN_MAROON="#e64553"
export CATPPUCCIN_PEACH="#fe640b"
export CATPPUCCIN_YELLOW="#df8e1d"
export CATPPUCCIN_GREEN="#40a02b"
export CATPPUCCIN_TEAL="#179299"
export CATPPUCCIN_SKY="#04a5e5"
export CATPPUCCIN_SAPPHIRE="#209fb5"
export CATPPUCCIN_BLUE="#1e66f5"
export CATPPUCCIN_LAVENDER="#7287fd"
export CATPPUCCIN_TEXT="#4c4f69"
export CATPPUCCIN_SUBTEXT1="#5c5f77"
export CATPPUCCIN_SUBTEXT0="#6c6f85"
export CATPPUCCIN_OVERLAY2="#7c7f93"
export CATPPUCCIN_OVERLAY1="#8c8fa1"
export CATPPUCCIN_OVERLAY0="#9ca0b0"
export CATPPUCCIN_SURFACE2="#acb0be"
export CATPPUCCIN_SURFACE1="#bcc0cc"
export CATPPUCCIN_SURFACE0="#ccd0da"
export CATPPUCCIN_BASE="#eff1f5"
export CATPPUCCIN_MANTLE="#e6e9ef"
export CATPPUCCIN_CRUST="#dce0e8"
```

- [ ] **Step 3: Write `themes/catppuccin-latte/helix-theme`**

```
catppuccin_latte
```

- [ ] **Step 4: Write `themes/catppuccin-latte/obsidian-theme`**

```
moonstone
```

- [ ] **Step 5: Write `themes/catppuccin-latte/nvim.lua`**

```lua
-- Catppuccin Latte for Neovim
vim.cmd.colorscheme('catppuccin-latte')
```

- [ ] **Step 6: Write `themes/catppuccin-latte/gtk.conf`**

```bash
GTK_THEME="Adwaita"
COLOR_SCHEME="prefer-light"
```

- [ ] **Step 7: Write `themes/catppuccin-latte/fragpaper.conf`**

```bash
BG_COLOR="#eff1f5"
PALETTE="light"
```

- [ ] **Step 8: Write `themes/catppuccin-latte/README.md`**

Same structure as mocha's README. Substitute "Mocha" → "Latte", "dark" → "light", color-scheme preferences. Plugin notes point at `catppuccin-latte` for nvim.

- [ ] **Step 9: Commit**

```bash
cd ~/dotfiles && git add themes/catppuccin-latte/
git commit -m "$(cat <<'EOF'
themes: add catppuccin-latte metadata files

Light variant. Mirrors catppuccin-mocha's structure with Latte palette.
Helix theme = catppuccin_latte (upstream), Obsidian = moonstone (default
light), GTK = Adwaita + prefer-light, fragpaper palette = light.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Create `themes/catppuccin-latte/` visual configs

**Files:** mirror of Task 2 for the light variant.

- [ ] **Step 1: `themes/catppuccin-latte/hypr.conf`**

```
# Catppuccin Latte — Hyprland border colors.
# Active = Blue (#1e66f5); inactive = transparent.
$col_active = rgb(1e66f5)
$col_inactive = rgba(00000000)
```

- [ ] **Step 2: `themes/catppuccin-latte/hyprlock.conf`**

Read `base/hypr/.config/hypr/hyprlock-light.conf` and port structure with Latte colors:
- Background → `rgba(eff1f5e6)` (Base, ~90% opacity)
- Text → `rgb(4c4f69)` (Text)
- Accent / border → `rgb(1e66f5)` (Blue)
- Error → `rgb(d20f39)` (Red)
- Muted → `rgb(6c6f85)` (Subtext0)

- [ ] **Step 3: `themes/catppuccin-latte/ghostty.conf`**

```
# Catppuccin Latte — Ghostty terminal

background = #eff1f5
foreground = #4c4f69
background-opacity = 1.0

cursor-color = #dc8a78
cursor-text = #eff1f5

selection-background = #acb0be
selection-foreground = #4c4f69

# Normal palette (0-7)
palette = 0=#5c5f77
palette = 1=#d20f39
palette = 2=#40a02b
palette = 3=#df8e1d
palette = 4=#1e66f5
palette = 5=#ea76cb
palette = 6=#179299
palette = 7=#acb0be

# Bright palette (8-15)
palette = 8=#6c6f85
palette = 9=#d20f39
palette = 10=#40a02b
palette = 11=#df8e1d
palette = 12=#1e66f5
palette = 13=#ea76cb
palette = 14=#179299
palette = 15=#bcc0cc
```

- [ ] **Step 4: `themes/catppuccin-latte/waybar.css`**

Port `base/waybar/.config/waybar/light.css` with Latte palette substitutions:
- bg → `#eff1f5` (Base) or `#e6e9ef` (Mantle)
- text → `#4c4f69` (Text)
- accent → `#1e66f5` (Blue)
- muted → `#6c6f85` / `#9ca0b0`
- warning → `#df8e1d` (Yellow)
- critical → `#d20f39` (Red)
- success → `#40a02b` (Green)

- [ ] **Step 5: `themes/catppuccin-latte/mako.conf`**

Port `base/mako/.config/mako/light`:
- bg → `#eff1f5`
- text → `#4c4f69`
- border → `#1e66f5`
- critical border → `#d20f39`

- [ ] **Step 6: `themes/catppuccin-latte/fuzzel.ini`**

Port `base/fuzzel/.config/fuzzel/light.ini` `[colors]` section:

```ini
[colors]
background=eff1f5ff
text=4c4f69ff
match=d20f39ff
selection=acb0beff
selection-text=4c4f69ff
selection-match=d20f39ff
border=1e66f5ff
```

- [ ] **Step 7: `themes/catppuccin-latte/btop.theme`**

```bash
curl -sSL https://raw.githubusercontent.com/catppuccin/btop/main/themes/catppuccin_latte.theme \
    -o ~/dotfiles/themes/catppuccin-latte/btop.theme
```

- [ ] **Step 8: Verify + commit**

```bash
ls ~/dotfiles/themes/catppuccin-latte/
wc -l ~/dotfiles/themes/catppuccin-latte/*
```

```bash
cd ~/dotfiles && git add themes/catppuccin-latte/
git commit -m "$(cat <<'EOF'
themes: add catppuccin-latte visual configs

Light variant per-app files: hypr.conf, hyprlock.conf, ghostty.conf,
waybar.css, mako.conf, fuzzel.ini, btop.theme. Ports structure from
existing base/<app>/light* files with Latte palette values.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Update `fragpaper-launch` to read from new theme marker

**Files:**
- Modify: `base/bin/.local/bin/fragpaper-launch`

The existing fragpaper-launch reads from `$XDG_STATE_HOME/theme-current` (set by the old theme-switch). Rewrite it to read from `~/.config/dotfiles/active-theme` and source the active theme's `fragpaper.conf`.

- [ ] **Step 1: Rewrite `fragpaper-launch`**

```bash
#!/usr/bin/env bash
# fragpaper-launch — launches fragpaper with the current theme's bg + palette.
# Reads ~/.config/dotfiles/active-theme, then sources
# ~/dotfiles/themes/<active>/fragpaper.conf for BG_COLOR and PALETTE.
# Falls back to Catppuccin Mocha defaults if no active theme is set.

set -u

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
ACTIVE_THEME_FILE="$HOME/.config/dotfiles/active-theme"

BG_COLOR="#1e1e2e"
PALETTE="dark"

if [[ -f "$ACTIVE_THEME_FILE" ]]; then
    active=$(<"$ACTIVE_THEME_FILE")
    conf="$DOTFILES/themes/$active/fragpaper.conf"
    if [[ -f "$conf" ]]; then
        # shellcheck source=/dev/null
        . "$conf"
    fi
fi

FRAGPAPER="$HOME/projects/fragpaper/target/release/fragpaper"
SHADERS_DIR="$HOME/projects/wallpaper-gen/shaders"

exec env RUST_LOG=info "$FRAGPAPER" \
    --bg-color "$BG_COLOR" \
    --palette "$PALETTE" \
    "$SHADERS_DIR/attractors.vert" \
    "$SHADERS_DIR/attractors.frag"
```

- [ ] **Step 2: Syntax-check and commit**

```bash
bash -n ~/dotfiles/base/bin/.local/bin/fragpaper-launch && echo OK
cd ~/dotfiles && git add base/bin/.local/bin/fragpaper-launch
git commit -m "$(cat <<'EOF'
fragpaper-launch: read from ~/.config/dotfiles/active-theme

Migrate off the old theme-current state file (set by soon-deleted
theme-switch). Sources $DOTFILES/themes/<active>/fragpaper.conf for
BG_COLOR and PALETTE. Catppuccin Mocha defaults as fallback when no
active theme is set.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Adjust base config hooks for new symlink locations

**Files:**
- Modify: `base/hypr/.config/hypr/hyprland.conf` (two changes: theme source path + keybind)
- Modify: `base/btop/.config/btop/btop.conf` (color_theme setting)

These edits prepare base configs for the new symlink targets. Keybind rewire is included here since it's a one-liner in the same file.

- [ ] **Step 1: Update hyprland.conf — theme source path**

Current line 13: `source = ~/.config/hypr/colors/theme.conf`

Change to: `source = ~/.config/hypr/theme.conf` (new dot-theme-set target).

Also current line 177: `bind = $mod SHIFT, t, exec, ~/.local/bin/theme-switch`

Change to: `bind = $mod SHIFT, t, exec, dot-theme-toggle`

(Note: `dot-theme-toggle` is on PATH via `$DOTFILES/bin` prepended in zshrc.d — but Hyprland's bind exec doesn't go through zsh. Use full path to be safe.)

Revised binding: `bind = $mod SHIFT, t, exec, ~/dotfiles/bin/dot-theme-toggle`

- [ ] **Step 2: Update btop.conf to use active theme**

Check current `base/btop/.config/btop/btop.conf` for the `color_theme` line:

```bash
grep -n 'color_theme' ~/dotfiles/base/btop/.config/btop/btop.conf
```

If it exists, ensure it's set to `"active"` (quoted, without .theme extension — btop adds it). Example:

```
color_theme = "active"
```

If the setting isn't present, add it in the appropriate section.

- [ ] **Step 3: Verify, live-restow, commit**

```bash
bash -n /dev/null && echo OK  # just a formality; hyprland.conf isn't bash
grep -n 'source\|theme-switch\|dot-theme-toggle' ~/dotfiles/base/hypr/.config/hypr/hyprland.conf
```

Expected: the updated source line + updated bind line.

Restow to update live symlinks:

```bash
cd ~/dotfiles && stow -d base -t ~ --no-folding -R hypr btop
```

```bash
cd ~/dotfiles && git add base/hypr/.config/hypr/hyprland.conf base/btop/.config/btop/btop.conf
git commit -m "$(cat <<'EOF'
base: adjust hypr + btop hooks for new theme symlink locations

- hyprland.conf: source = ~/.config/hypr/theme.conf (was colors/theme.conf)
- hyprland.conf: $mod+SHIFT+t binds dot-theme-toggle (was theme-switch)
- btop.conf: color_theme = "active" (reads ~/.config/btop/themes/active.theme
  which dot-theme-set symlinks to the active theme's btop.theme)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Delete old per-app dark/light files from `base/`

**Files:** delete, as listed in File Structure. After this commit, themes live ONLY in `themes/`.

- [ ] **Step 1: List what's going away**

```bash
ls ~/dotfiles/base/hypr/.config/hypr/colors/*.conf 2>/dev/null
ls ~/dotfiles/base/hypr/.config/hypr/hyprlock-*.conf 2>/dev/null
ls ~/dotfiles/base/ghostty/.config/ghostty/{dark,light,theme}.conf 2>/dev/null
ls ~/dotfiles/base/waybar/.config/waybar/{dark,light,style}.css 2>/dev/null
ls ~/dotfiles/base/mako/.config/mako/{dark,light,config} 2>/dev/null
ls ~/dotfiles/base/fuzzel/.config/fuzzel/{dark,light,fuzzel}.ini 2>/dev/null
```

Note which files are tracked (in git) vs symlinks (may exist but be untracked). We only delete TRACKED files.

For files that are symlinks at repo level (not common but possible), inspect manually:

```bash
find ~/dotfiles/base -type l
```

- [ ] **Step 2: Unstow the affected packages from `$HOME` first**

Before deleting, unstow so `~/.config/*` symlinks vanish cleanly:

```bash
cd ~/dotfiles && stow -d base -t ~ --no-folding -D hypr ghostty waybar mako fuzzel
```

This clears `~/.config/hypr/colors/`, `~/.config/ghostty/theme.conf`, `~/.config/waybar/style.css`, `~/.config/mako/config`, and `~/.config/fuzzel/fuzzel.ini` from pointing into `base/`.

- [ ] **Step 3: Delete the files**

```bash
cd ~/dotfiles
rm -f base/hypr/.config/hypr/colors/dark.conf base/hypr/.config/hypr/colors/light.conf
# If colors/theme.conf is a tracked symlink, remove it too
rm -f base/hypr/.config/hypr/colors/theme.conf 2>/dev/null
rmdir base/hypr/.config/hypr/colors 2>/dev/null || true
rm -f base/hypr/.config/hypr/hyprlock-dark.conf base/hypr/.config/hypr/hyprlock-light.conf
rm -f base/hypr/.config/hypr/hyprlock.conf 2>/dev/null

rm -f base/ghostty/.config/ghostty/dark.conf base/ghostty/.config/ghostty/light.conf
rm -f base/ghostty/.config/ghostty/theme.conf 2>/dev/null

rm -f base/waybar/.config/waybar/dark.css base/waybar/.config/waybar/light.css
rm -f base/waybar/.config/waybar/style.css 2>/dev/null

rm -f base/mako/.config/mako/dark base/mako/.config/mako/light
rm -f base/mako/.config/mako/config 2>/dev/null

rm -f base/fuzzel/.config/fuzzel/dark.ini base/fuzzel/.config/fuzzel/light.ini
rm -f base/fuzzel/.config/fuzzel/fuzzel.ini 2>/dev/null
```

- [ ] **Step 4: Re-stow the base packages to refresh `~/.config/`**

```bash
cd ~/dotfiles && stow -d base -t ~ --no-folding -R hypr ghostty waybar mako fuzzel
```

After this, `~/.config/hypr/`, `~/.config/ghostty/`, etc. will have whatever base files remain (no theme-specific ones). When `dot-theme-set` runs next, it'll create the `theme.conf`/`style.css`/etc. symlinks pointing at themes/.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add -A base/hypr/ base/ghostty/ base/waybar/ base/mako/ base/fuzzel/
git commit -m "$(cat <<'EOF'
base: delete per-app dark/light theme files (moved to themes/)

Content relocated to themes/catppuccin-mocha/ and themes/catppuccin-
latte/ in Tasks 1-4. Deletions cover hypr/colors/*, hyprlock-*.conf,
ghostty/{dark,light,theme}.conf, waybar/{dark,light,style}.css,
mako/{dark,light,config}, fuzzel/{dark,light,fuzzel}.ini.

Tokyo Night dark + daltonized light content is preserved in git
history (commits fc99ab3, a151838, etc.); can be re-extracted as
additional themes if desired.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Write `bin/dot-theme-set` (real implementation)

**Files:**
- Modify: `bin/dot-theme-set` (replace Wave 2 stub with full implementation)

This is the core of Wave 3. Replace the stub with the real directory-per-theme implementation.

- [ ] **Step 1: Write the new `bin/dot-theme-set`**

Use the `Write` tool to replace the file entirely:

```bash
#!/usr/bin/env bash
# bin/dot-theme-set — apply a theme from $DOTFILES/themes/<name>/
#
# Usage: dot-theme-set <theme-name>
#
# Validates the theme, writes state markers, symlinks per-app files into
# ~/.config/<app>/, sed-rewrites Helix, JSON-patches Obsidian, runs
# gsettings, relaunches fragpaper, reloads running apps.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
STATE_DIR="$HOME/.config/dotfiles"
THEME_NAME="${1:-}"

if [[ -z "$THEME_NAME" ]]; then
    echo "Usage: dot-theme-set <theme-name>"
    echo ""
    echo "Available themes:"
    for d in "$DOTFILES"/themes/*/; do
        n=$(basename "$d")
        v=$(cat "$d/variant" 2>/dev/null || echo "?")
        printf "  %-20s (%s)\n" "$n" "$v"
    done
    exit 1
fi

THEME_DIR="$DOTFILES/themes/$THEME_NAME"
if [[ ! -d "$THEME_DIR" ]]; then
    echo "dot-theme-set: unknown theme '$THEME_NAME'" >&2
    echo "  Available: $(ls "$DOTFILES"/themes/ | tr '\n' ' ')" >&2
    exit 1
fi

# --- Read variant ---
VARIANT_FILE="$THEME_DIR/variant"
if [[ ! -f "$VARIANT_FILE" ]]; then
    echo "dot-theme-set: $THEME_NAME is missing a 'variant' file" >&2
    exit 1
fi
VARIANT=$(tr -d '[:space:]' < "$VARIANT_FILE")
if [[ "$VARIANT" != "dark" ]] && [[ "$VARIANT" != "light" ]]; then
    echo "dot-theme-set: variant must be 'dark' or 'light', got '$VARIANT'" >&2
    exit 1
fi

# --- Write state markers ---
mkdir -p "$STATE_DIR"
echo "$THEME_NAME" > "$STATE_DIR/active-theme"
echo "$THEME_NAME" > "$STATE_DIR/last-$VARIANT"

# --- Symlink per-app files (idempotent: ln -sf) ---
link_if_present() {
    local src="$1" dst="$2"
    if [[ -f "$src" ]]; then
        mkdir -p "$(dirname "$dst")"
        ln -sfn "$src" "$dst"
    fi
}

link_if_present "$THEME_DIR/hypr.conf"      "$HOME/.config/hypr/theme.conf"
link_if_present "$THEME_DIR/hyprlock.conf"  "$HOME/.config/hypr/hyprlock.conf"
link_if_present "$THEME_DIR/waybar.css"     "$HOME/.config/waybar/style.css"
link_if_present "$THEME_DIR/ghostty.conf"   "$HOME/.config/ghostty/theme.conf"
link_if_present "$THEME_DIR/fuzzel.ini"     "$HOME/.config/fuzzel/fuzzel.ini"
link_if_present "$THEME_DIR/mako.conf"      "$HOME/.config/mako/config"
link_if_present "$THEME_DIR/btop.theme"     "$HOME/.config/btop/themes/active.theme"
link_if_present "$THEME_DIR/nvim.lua"       "$HOME/.config/nvim/lua/dotfiles-theme.lua"

# --- Helix: sed-rewrite config.toml's theme = "..." line ---
helix_cfg="$HOME/.config/helix/config.toml"
helix_theme_file="$THEME_DIR/helix-theme"
if [[ -f "$helix_cfg" ]] && [[ -f "$helix_theme_file" ]]; then
    helix_theme=$(tr -d '[:space:]' < "$helix_theme_file")
    # sed -i through a symlink breaks the link; edit the real file instead.
    real_cfg=$(readlink -f "$helix_cfg")
    sed -i -E "s|^theme = \".*\"|theme = \"$helix_theme\"|" "$real_cfg"
fi

# --- Obsidian: JSON-patch vault appearance.json (best-effort) ---
obsidian_theme_file="$THEME_DIR/obsidian-theme"
if [[ -n "${OBSIDIAN_VAULT:-}" ]] && [[ -f "$obsidian_theme_file" ]]; then
    obsidian_theme=$(tr -d '[:space:]' < "$obsidian_theme_file")
    appearance="$OBSIDIAN_VAULT/.obsidian/appearance.json"
    if [[ -f "$appearance" ]]; then
        python3 - "$appearance" "$obsidian_theme" <<'PY' || true
import json, sys, os, tempfile
path, theme = sys.argv[1], sys.argv[2]
with open(path) as f: data = json.load(f)
data["theme"] = theme
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, "w") as f: json.dump(data, f, indent=2)
os.replace(tmp, path)
PY
    fi
fi

# --- GTK + system color-scheme via gsettings ---
gtk_conf="$THEME_DIR/gtk.conf"
if [[ -f "$gtk_conf" ]]; then
    # shellcheck source=/dev/null
    . "$gtk_conf"
    gsettings set org.gnome.desktop.interface color-scheme "${COLOR_SCHEME:-default}" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme    "${GTK_THEME:-Adwaita}"   2>/dev/null || true
fi

# --- Relaunch fragpaper (it has no live reload) ---
if pgrep -x fragpaper &>/dev/null; then
    pkill -TERM -x fragpaper 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x fragpaper &>/dev/null || break
        sleep 0.1
    done
fi
# fragpaper-launch reads active-theme + fragpaper.conf now (Task 5)
setsid -f bash -c '~/.local/bin/fragpaper-launch > /tmp/fragpaper-debug.log 2>&1' &>/dev/null || true

# --- Run theme-specific post-set hook if present ---
if [[ -x "$THEME_DIR/post-set.sh" ]]; then
    bash "$THEME_DIR/post-set.sh" || true
fi

# --- Reload running apps (best-effort) ---
command -v hyprctl  &>/dev/null && hyprctl reload &>/dev/null || true
command -v makoctl  &>/dev/null && makoctl reload 2>/dev/null || true
pkill -SIGUSR2 waybar   2>/dev/null || true
pkill -SIGUSR2 ghostty  2>/dev/null || true
pkill -SIGUSR1 -x hx    2>/dev/null || true
pkill -SIGUSR1 -x helix 2>/dev/null || true

echo "Switched to $THEME_NAME ($VARIANT)"
```

- [ ] **Step 2: Make executable + syntax-check**

```bash
chmod +x ~/dotfiles/bin/dot-theme-set
bash -n ~/dotfiles/bin/dot-theme-set && echo OK
```

- [ ] **Step 3: Test usage message (NO actual application)**

```bash
dot-theme-set
```

Expected: prints usage + lists available themes (`catppuccin-mocha (dark)`, `catppuccin-latte (light)`). Exits 1.

Do NOT test with a theme name yet — that's Task 14.

- [ ] **Step 4: Commit**

```bash
cd ~/dotfiles && git add bin/dot-theme-set
git commit -m "$(cat <<'EOF'
bin/dot-theme-set: replace Wave 2 stub with real implementation

Validates the theme, reads variant, writes active-theme + last-<variant>
markers, symlinks per-app files into ~/.config/*, sed-rewrites Helix,
JSON-patches Obsidian if $OBSIDIAN_VAULT set, gsettings for GTK/color-
scheme, relaunches fragpaper, reloads hyprctl/waybar/ghostty/mako/helix.

Absorbs logic from retiring base/bin/theme-switch, generalized from
dark/light toggle to arbitrary named themes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Write `bin/dot-theme-toggle` (new)

**Files:**
- Create: `bin/dot-theme-toggle`

The hotkey companion. Reads active theme's variant, applies the counterpart-variant's last-used theme.

- [ ] **Step 1: Write `bin/dot-theme-toggle`**

```bash
#!/usr/bin/env bash
# bin/dot-theme-toggle — flip between the last-applied dark and last-applied
# light theme. Bound to $mod+SHIFT+t in Hyprland.
#
# Reads ~/.config/dotfiles/active-theme, looks up its variant, then applies
# ~/.config/dotfiles/last-<other-variant>. Falls back to first theme of the
# opposite variant if the counterpart marker is empty or stale.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
STATE_DIR="$HOME/.config/dotfiles"
ACTIVE_FILE="$STATE_DIR/active-theme"

if [[ ! -f "$ACTIVE_FILE" ]]; then
    echo "dot-theme-toggle: no active theme. Run 'dot-theme-set <name>' first." >&2
    exit 1
fi

active=$(<"$ACTIVE_FILE")
active_variant_file="$DOTFILES/themes/$active/variant"
if [[ ! -f "$active_variant_file" ]]; then
    echo "dot-theme-toggle: active theme '$active' is missing or invalid." >&2
    exit 1
fi
active_variant=$(tr -d '[:space:]' < "$active_variant_file")

# Determine the counterpart variant
case "$active_variant" in
    dark)  other_variant="light" ;;
    light) other_variant="dark"  ;;
    *)
        echo "dot-theme-toggle: unexpected variant '$active_variant' for theme '$active'" >&2
        exit 1
        ;;
esac

# Try counterpart marker first
counterpart_file="$STATE_DIR/last-$other_variant"
target=""
if [[ -f "$counterpart_file" ]]; then
    candidate=$(<"$counterpart_file")
    if [[ -n "$candidate" ]] && [[ -d "$DOTFILES/themes/$candidate" ]]; then
        target="$candidate"
    fi
fi

# Fallback: find first theme of the opposite variant
if [[ -z "$target" ]]; then
    for d in "$DOTFILES"/themes/*/; do
        n=$(basename "$d")
        v=$(tr -d '[:space:]' < "$d/variant" 2>/dev/null || echo "")
        if [[ "$v" == "$other_variant" ]]; then
            target="$n"
            echo "dot-theme-toggle: no saved $other_variant preference; falling back to '$target'" >&2
            echo "  (run 'dot-theme-set <name>' once to set a preferred $other_variant theme)" >&2
            break
        fi
    done
fi

if [[ -z "$target" ]]; then
    echo "dot-theme-toggle: no $other_variant theme found in $DOTFILES/themes/" >&2
    exit 1
fi

exec "$DOTFILES/bin/dot-theme-set" "$target"
```

- [ ] **Step 2: chmod + syntax-check**

```bash
chmod +x ~/dotfiles/bin/dot-theme-toggle
bash -n ~/dotfiles/bin/dot-theme-toggle && echo OK
```

- [ ] **Step 3: Commit**

```bash
cd ~/dotfiles && git add bin/dot-theme-toggle
git commit -m "$(cat <<'EOF'
bin/dot-theme-toggle: new — flip between last-dark and last-light

Reads ~/.config/dotfiles/active-theme's variant, applies the counterpart's
last-<other-variant> marker via dot-theme-set. Fallback: picks the first
theme of the opposite variant in themes/*/ with a warning.

Bound to $mod+SHIFT+t in Hyprland (rewired in Task 6 from theme-switch).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Rewrite `install/10-theme.sh` (real, not stub)

**Files:**
- Modify: `install/10-theme.sh` (replace Wave 2 stub)

- [ ] **Step 1: Write the new `install/10-theme.sh`**

```bash
#!/usr/bin/env bash
# install/10-theme.sh — apply active theme via dot-theme-set
set -euo pipefail
source "$(dirname "$0")/_common.sh"
skip_unless_profile workstation

ACTIVE_THEME_FILE="$HOME/.config/dotfiles/active-theme"
DEFAULT_THEME="catppuccin-mocha"

# First run: no active-theme marker. Apply the default.
if [[ ! -f "$ACTIVE_THEME_FILE" ]]; then
    log "no active theme set; applying default ($DEFAULT_THEME)"
    "$DOTFILES/bin/dot-theme-set" "$DEFAULT_THEME"
    exit 0
fi

# Re-install: re-apply whatever the active marker says.
active=$(<"$ACTIVE_THEME_FILE")
if [[ -d "$DOTFILES/themes/$active" ]]; then
    log "re-applying active theme: $active"
    "$DOTFILES/bin/dot-theme-set" "$active"
else
    warn "active-theme marker says '$active' but themes/$active/ not found"
    warn "applying default ($DEFAULT_THEME) instead"
    "$DOTFILES/bin/dot-theme-set" "$DEFAULT_THEME"
fi
```

- [ ] **Step 2: Syntax-check + commit**

```bash
bash -n ~/dotfiles/install/10-theme.sh && echo OK
cd ~/dotfiles && git add install/10-theme.sh
git commit -m "$(cat <<'EOF'
install/10-theme.sh: replace Wave 2 stub with real theme applier

First run: apply catppuccin-mocha as default. Re-install: re-apply
whatever ~/.config/dotfiles/active-theme says. Falls back to default
if the marker points at a missing theme.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Retire `base/bin/.local/bin/theme-switch`

**Files:**
- Delete: `base/bin/.local/bin/theme-switch`

All its logic has been absorbed. Delete and unstow.

- [ ] **Step 1: Unstow the bin package (to clear the live symlink)**

```bash
cd ~/dotfiles && stow -d base -t ~ --no-folding -D bin
```

This removes `~/.local/bin/theme-switch` (along with all other base/bin/ wrappers temporarily).

- [ ] **Step 2: Delete the file**

```bash
rm ~/dotfiles/base/bin/.local/bin/theme-switch
```

- [ ] **Step 3: Re-stow base/bin to restore the other wrappers**

```bash
cd ~/dotfiles && stow -d base -t ~ --no-folding -R bin
```

Other wrappers (fragpaper-launch, trackpad-toggle, news, web_extract, yt_transcript, window-picker) are re-symlinked. `theme-switch` is gone.

- [ ] **Step 4: Verify `theme-switch` is no longer on PATH**

```bash
command -v theme-switch && echo "STILL ON PATH — investigate" || echo "removed"
ls -la ~/.local/bin/theme-switch 2>&1 | head -2
```

Expected: "removed"; the `ls` reports "No such file or directory."

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add -A base/bin/
git commit -m "$(cat <<'EOF'
base/bin: retire theme-switch (absorbed into dot-theme-set)

Logic generalized from dark/light toggle into dot-theme-set +
dot-theme-toggle. $mod+SHIFT+t keybind was rewired to dot-theme-toggle
in Task 6.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Add theme checks to `bin/dot-doctor`

**Files:**
- Modify: `bin/dot-doctor`

Add checks that verify the theme system is functioning.

- [ ] **Step 1: Add three new `check` lines before the final `echo ""` in `bin/dot-doctor`**

Use `Edit` tool to insert:

```bash
check "active theme marker present"    "[[ -f \"\$HOME/.config/dotfiles/active-theme\" ]]"
check "active theme directory exists"  "[[ -d \"\$DOTFILES/themes/\$(cat \"\$HOME/.config/dotfiles/active-theme\" 2>/dev/null)\" ]]"
check "~/.config/hypr/theme.conf is live symlink" "[[ -L \"\$HOME/.config/hypr/theme.conf\" ]] && [[ -e \"\$HOME/.config/hypr/theme.conf\" ]]"
```

Position: immediately before the `echo ""` that precedes the pass/fail summary.

- [ ] **Step 2: Syntax-check**

```bash
bash -n ~/dotfiles/bin/dot-doctor && echo OK
```

- [ ] **Step 3: Run dot-doctor. Expect the three new checks to FAIL (no active theme applied yet)**

```bash
zsh -ic '~/dotfiles/bin/dot-doctor' 2>&1 | tail -25
```

Expected: 3 new red-X lines for the new checks. Everything else still green. That's correct — Wave 3 hasn't applied a theme yet; these will turn green in Task 14.

- [ ] **Step 4: Commit**

```bash
cd ~/dotfiles && git add bin/dot-doctor
git commit -m "$(cat <<'EOF'
bin/dot-doctor: add theme-system health checks

Three new checks:
- active theme marker present (~/.config/dotfiles/active-theme)
- active theme directory exists under $DOTFILES/themes/
- ~/.config/hypr/theme.conf is a live symlink

All three will fail until Task 14 applies a theme. That's expected.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Add Catppuccin Neovim plugin config (optional, graceful)

**Files:**
- Create: `~/.config/nvim/lua/custom/plugins/catppuccin.lua` (in the user's kickstart fork — NOT in the dotfiles repo)

The kickstart.nvim fork at `~/.config/nvim/` is its own git repo. The theme symlinks nvim.lua already run `vim.cmd.colorscheme('catppuccin-mocha')`, but without the `catppuccin/nvim` plugin, that call silently fails and kickstart uses its default colorscheme.

This task installs the plugin config in the kickstart fork so the color scheme actually applies. The user can choose whether to commit this to their fork or leave it uncommitted.

- [ ] **Step 1: Check kickstart's plugin loading convention**

```bash
ls ~/.config/nvim/lua/ 2>/dev/null
grep -n 'custom' ~/.config/nvim/init.lua | head -5
```

Kickstart typically loads plugins from `lua/custom/plugins/` via `{ import = 'custom.plugins' }` in the lazy.nvim spec. Confirm by reading the init.lua section.

- [ ] **Step 2: Write `~/.config/nvim/lua/custom/plugins/catppuccin.lua`**

```bash
mkdir -p ~/.config/nvim/lua/custom/plugins
cat > ~/.config/nvim/lua/custom/plugins/catppuccin.lua <<'EOF'
-- Catppuccin Neovim theme plugin.
-- The colorscheme is set by ~/.config/nvim/lua/dotfiles-theme.lua,
-- which is symlinked by `dot-theme-set` to the active theme's nvim.lua.
return {
  {
    'catppuccin/nvim',
    name = 'catppuccin',
    priority = 1000,  -- load early so colorscheme can apply at startup
    lazy = false,
  },
}
EOF
```

- [ ] **Step 3: Smoke-test nvim**

```bash
nvim --headless '+Lazy! sync' '+qall' 2>&1 | tail -5
```

Lazy.nvim will fetch the catppuccin plugin and install it on this command. Expected: installation log lines, no errors.

Then verify:

```bash
nvim --headless '+lua print(pcall(require, "catppuccin"))' '+qall' 2>&1
```

Expected: `true  table: 0x...` (the pcall succeeded and returned the module).

- [ ] **Step 4: No commit (in the dotfiles repo)**

This task modifies `~/.config/nvim/`, which is a separate git repo. Whether to commit there is the user's call. Do NOT commit anything in the dotfiles repo for this task.

Report which files were created in the kickstart fork so the user can commit them there if desired.

---

## Task 14: Live-apply `catppuccin-mocha` and verify every surface

**Files:** no repo changes. Live validation.

### Preflight

```bash
cd ~/dotfiles && git status --porcelain && echo PREFLIGHT_OK
```

Expected: `PREFLIGHT_OK` with nothing above it. If dirty, address before continuing.

- [ ] **Step 1: Apply catppuccin-mocha**

```bash
dot-theme-set catppuccin-mocha
```

Expected terminal output: `Switched to catppuccin-mocha (dark)`. Visual changes:
- Hyprland border colors shift to Blue (active) / transparent (inactive)
- Waybar restyles to Mocha palette
- Ghostty terminal colors update (you see this immediately)
- Mako future notifications will use new colors
- Fragpaper kills + relaunches (brief flash)

- [ ] **Step 2: Verify state markers written**

```bash
cat ~/.config/dotfiles/active-theme
cat ~/.config/dotfiles/last-dark
[[ -f ~/.config/dotfiles/last-light ]] && cat ~/.config/dotfiles/last-light || echo "(no last-light yet — expected)"
```

Expected: both `active-theme` and `last-dark` say `catppuccin-mocha`. `last-light` should not exist yet.

- [ ] **Step 3: Verify symlinks created**

```bash
ls -la ~/.config/hypr/theme.conf
ls -la ~/.config/ghostty/theme.conf
ls -la ~/.config/waybar/style.css
ls -la ~/.config/mako/config
ls -la ~/.config/fuzzel/fuzzel.ini
ls -la ~/.config/btop/themes/active.theme
ls -la ~/.config/nvim/lua/dotfiles-theme.lua
```

Expected: each is a symlink pointing into `~/dotfiles/themes/catppuccin-mocha/`.

- [ ] **Step 4: Verify Helix sed-rewrite**

```bash
grep -n '^theme' ~/.config/helix/config.toml
```

Expected: `theme = "catppuccin_mocha"`.

- [ ] **Step 5: Verify GTK color-scheme**

```bash
gsettings get org.gnome.desktop.interface color-scheme
gsettings get org.gnome.desktop.interface gtk-theme
```

Expected: `'prefer-dark'` and `'Adwaita-dark'`.

- [ ] **Step 6: Verify dot-doctor is now fully green**

```bash
zsh -ic '~/dotfiles/bin/dot-doctor' 2>&1 | tail -6
```

Expected: "All checks passed" (14 checks passing, or 17 if Task 12's new checks are counted).

- [ ] **Step 7: Open Ghostty and confirm colors are Mocha**

Visual confirmation only — the user should eyeball.

- [ ] **Step 8: No commit**

---

## Task 15: Toggle to `catppuccin-latte` via `dot-theme-toggle`

**Files:** no repo changes. Live validation of toggle UX.

- [ ] **Step 1: Invoke the toggle**

```bash
dot-theme-toggle
```

Expected: "dot-theme-toggle: no saved light preference; falling back to 'catppuccin-latte'" (warning) → "Switched to catppuccin-latte (light)".

Note: this is the fallback path fires first time, because `last-light` was never set. Subsequent toggles skip the fallback.

- [ ] **Step 2: Verify markers updated**

```bash
cat ~/.config/dotfiles/active-theme   # should be catppuccin-latte
cat ~/.config/dotfiles/last-dark      # should still be catppuccin-mocha
cat ~/.config/dotfiles/last-light     # should be catppuccin-latte
```

- [ ] **Step 3: Toggle back**

```bash
dot-theme-toggle
```

Expected: clean "Switched to catppuccin-mocha (dark)" (no fallback warning now).

- [ ] **Step 4: Toggle once more — latte**

```bash
dot-theme-toggle
```

Expected: "Switched to catppuccin-latte (light)".

- [ ] **Step 5: Test the Hyprland keybind**

Press `$mod+SHIFT+t`. Visual verification: the desktop should switch themes on the hotkey.

- [ ] **Step 6: No commit**

---

## Task 16: Final verification

**Files:** read-only.

- [ ] **Step 1: `git log` shows all Wave 3 commits**

```bash
cd ~/dotfiles && git log --oneline 53aaabc..HEAD
```

Expected: ~12 Wave 3 commits (tasks 1-12; tasks 13-15 are live-only, no commits).

- [ ] **Step 2: All theme directories have the required files**

```bash
for t in catppuccin-mocha catppuccin-latte; do
    echo "=== $t ==="
    ls ~/dotfiles/themes/$t/
done
```

Expected for each: variant, palette.sh, hypr.conf, hyprlock.conf, ghostty.conf, waybar.css, mako.conf, fuzzel.ini, btop.theme, nvim.lua, helix-theme, obsidian-theme, gtk.conf, fragpaper.conf, README.md.

- [ ] **Step 3: `dot-theme-set` and `dot-theme-toggle` are executable, syntax-clean**

```bash
for f in ~/dotfiles/bin/dot-theme-set ~/dotfiles/bin/dot-theme-toggle; do
    [[ -x "$f" ]] || echo "NOT executable: $f"
    bash -n "$f" || echo "SYNTAX FAIL: $f"
done
echo DONE
```

- [ ] **Step 4: theme-switch is gone**

```bash
command -v theme-switch && echo "STILL ON PATH" || echo "removed"
```

- [ ] **Step 5: dot-doctor 17/17 green**

```bash
zsh -ic '~/dotfiles/bin/dot-doctor' 2>&1 | tail -3
```

Expected: "All checks passed."

- [ ] **Step 6: Working tree clean**

```bash
cd ~/dotfiles && git status
```

Expected: "nothing to commit, working tree clean" (the `~/.config/nvim/` changes from Task 13 are in a *different* repo, not this one).

---

## Rollback

If any task introduces breakage:

```bash
cd ~/dotfiles && git log --oneline -20
git reset --hard <last-known-good-sha>   # e.g. 53aaabc (Wave 3 spec update)
./install.sh workstation                  # re-stow, re-apply theme
```

Because Wave 3 mostly adds new files (themes/, bin/dot-theme-toggle) and modifies existing scripts additively, reverts are clean. The risky commit is Task 7 (deletes base/*/dark* files) — if you revert past it, those files come back and the old theme-switch (if not already deleted) would start working again.

---

## Out of scope for Wave 3

- Additional themes beyond catppuccin-mocha + catppuccin-latte (add post-Wave-3 as copy-and-edit)
- Catppuccin community theme for Obsidian (user-installable; plan ships with built-in "obsidian"/"moonstone")
- GTK Catppuccin theme package (user-installable; plan ships with Adwaita-dark/Adwaita)
- Cursor theme swap per theme (deferred)
- `dot-theme-list` helper (use `ls themes/`)
- Neovim theme preview / cycle commands (deferred)
- Fuzzel-based theme picker UI (deferred)
- Docs manual chapter on theming (Wave 4)
