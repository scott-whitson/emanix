# Opinionated Dotfiles Reorg

**Date:** 2026-04-23
**Status:** Design approved, ready for implementation plan
**Scope:** Restructure `~/dotfiles` into a coherent, opinionated, and documented personal OS inspired by Omarchy. Private repo, personal use, but written public-shaped (docs read as if a stranger could fork them).

## Goal

Turn `~/dotfiles` from a competent multi-profile setup into an opinionated personal operating system with explicit tenets, modular install, a theme system, and topic-based documentation — without overbuilding for an audience that doesn't exist.

Inspiration: Omarchy 3.6 ships Arch + Hyprland + opinionated defaults with a curated install script, a modular `bin/install/` directory, a theme system, and a documented manual at `learn.omarchy.org`. This spec adopts Omarchy's *shape* (modular install, theme switching, topic-based docs, a clear manifesto) without forking it — the soul stays Scott's.

## Audience and publication

- **Private repo.** Not public, no license file, no contribution guide.
- **Public-shaped docs.** Written as if a stranger could read and fork them. The discipline forces the defaults to be justified and the configuration to be self-explanatory.
- **Audience in practice:** future-Scott on a fresh laptop or at 2am on-call.

## Tenets

The manifesto. Each tenet should eliminate at least one decision.

1. **Local-first, data-owned.** Files live on disk first. Cloud is a backup destination, never the source of truth. Three copies (local, gdrive-bisync, USB) with zero trust in any single provider.
2. **Arch + Hyprland, no apologies.** Bleeding-edge is a feature, not a bug. No distro detection, no Ubuntu fallbacks, no Sway remnants. Rolling release matches how the user works.
3. **Terminal-centric, keyboard-driven.** Ghostty + Zellij + Helix + lf. GUI apps are tolerated, not celebrated. Every frequent action has a keybind.
4. **AI-augmented by default.** Claude Code is a first-class tool, not a bolt-on. Custom skills, plugins, and the `agent-skills` project are part of the OS. Tenet that is uniquely Scott's — Omarchy does not have this opinion.
5. **Reversible and recoverable.** `recovery/` directory exists. Any machine is rebuildable from the repo in <1 hour. No snowflake state that only lives on one laptop.
6. **Modular like Framework.** Every piece is swappable. No lock-in to a tool that can't be ripped out in an afternoon.

## Scope

**In scope:**
- Full directory reorg (Section 1)
- Install script rewrite: modular `install/*.sh` + `bin/` helpers (Section 2)
- Theme system with Catppuccin Mocha as the first and only shipped theme (Section 3)
- 8-chapter manual in `docs/manual/` (Section 4)
- Migration in four waves (Section 5)

**Out of scope:**
- Work laptop (Windows + WSL) — constrained by IT, excluded entirely. User cherry-picks files by hand if needed.
- iPhone — not a dotfiles target.
- Multiple shipped themes — the theme *system* is built; only Catppuccin Mocha is delivered. Future themes are copy-and-edit operations, not new code.
- A static docs site (MkDocs, GitHub Pages). Markdown in a private repo is enough.
- Public-facing scaffolding: LICENSE, CONTRIBUTING.md, issue templates.
- GTK-heavy app theming (Firefox, LibreOffice) beyond global GTK theme name.

## Section 1 — Directory Layout

```
~/dotfiles/
├── README.md                 # manifesto + quickstart + link to manual
├── install.sh                # ~50-line orchestrator, sources install/*.sh in order
├── install/                  # NEW — modular install steps
│   ├── _common.sh            # shared helpers (log, need_pkg, stow_pkg)
│   ├── 01-pacman.sh
│   ├── 02-paru.sh
│   ├── 03-system.sh          # locale, hostname, pam_systemd_home fix, timezone
│   ├── 04-hyprland.sh        # workstation only
│   ├── 05-desktop.sh         # waybar, mako, fuzzel, ghostty, fonts, cursor — workstation only
│   ├── 06-tools.sh           # uv + uv sync in tools/ + wrappers to ~/.local/bin
│   ├── 07-claude.sh          # install Claude Code CLI + ensure ~/projects/agent-skills cloned
│   ├── 08-stow-base.sh
│   ├── 09-stow-profile.sh
│   ├── 10-theme.sh           # applies active theme via dot-theme-set
│   └── 11-services.sh        # systemd user units
├── bin/                      # NEW — re-runnable helpers (added to PATH via zshrc.d)
│   ├── dot-restow            # re-stow one package or all
│   ├── dot-theme-set         # apply a specific theme by name
│   ├── dot-theme-toggle      # flip between last-dark and last-light theme (Wave 3)
│   ├── dot-update            # paru -Syu && dot-restow --all
│   └── dot-doctor            # health check
├── base/                     # shared across profiles
│   ├── zsh/  git/  hypr/  waybar/  mako/  fuzzel/  ghostty/
│   ├── btop/ helix/ lf/ mpv/ yt-dlp/ claude/
│   └── paru/ xdg/ systemd/ bin/
│   # Neovim is NOT a base package — see "Neovim (kickstart.nvim)" below
├── profiles/
│   ├── workstation/          # RENAMED from personal
│   └── server/
├── themes/                   # NEW
│   └── catppuccin-mocha/
│       ├── palette.sh        # colors as vars (human reference, single source of truth)
│       ├── hypr.conf
│       ├── waybar.css
│       ├── ghostty.conf
│       ├── mako.conf
│       ├── fuzzel.ini
│       ├── btop.theme
│       ├── gtk.conf
│       ├── wallpaper.jpg
│       ├── README.md         # theme name, origin, any extra font/icon package needs
│       └── post-set.sh       # optional hook (e.g. sed Helix's theme= line, gsettings for GTK)
├── tools/                    # uv project, unchanged
├── recovery/                 # unchanged
├── docs/
│   ├── manual/               # NEW — 8 topic chapters
│   ├── plans/                # existing
│   └── superpowers/          # existing
└── .claude/                  # existing
```

### Deletions

Clean break, not deprecated:
- `profiles/work/` — WSL dies with tenet #2
- `base/windows/`, `sync-windows.sh` — work laptop excluded
- `base/micro/` — unused (wikilink-plugin-only, user moved away)
- `base/qalculate/` — unused (one-time experiment)
- Any remaining Sway/Wofi/Kitty references in README or configs

### Renames

- `profiles/personal/` → `profiles/workstation/` (axis is "has display" vs "headless", not "which of Scott's jobs")

### Neovim (kickstart.nvim)

Neovim is added alongside Helix (both editors live in parallel — tenet #6, no forced switch). The config approach differs from every other app in the repo:

- **Location:** `~/.config/nvim/` as a *separate git repo* (user's fork of `nvim-lua/kickstart.nvim`). Not a stow package in `base/`.
- **Why separate:** kickstart is designed to be forked and edited top-to-bottom. Stowing it would mean a nested git repo inside the dotfiles repo, and fighting kickstart's own upgrade model. A sibling repo keeps both upgradable independently.
- **Theme integration:** `~/.config/nvim/lua/dotfiles-theme.lua` is a symlink managed by `dot-theme-set` (see Section 3). The kickstart fork ends its init with `pcall(require, 'dotfiles-theme')` — opt-in, non-fatal if absent.
- **Installation:** `install/06-tools.sh` ensures `~/.config/nvim/` exists — clones the kickstart upstream (or user's fork if the URL is configured) if the directory is empty.
- **Helix stays.** No forced migration. Both in `$PATH`, user picks per invocation.

## Section 2 — Install Flow

### `install.sh` (orchestrator, ~50 lines)

```bash
#!/usr/bin/env bash
# Usage: ./install.sh <workstation|server>
set -euo pipefail

PROFILE="${1:?usage: ./install.sh <workstation|server>}"
DOTFILES="$(cd "$(dirname "$0")" && pwd)"
export DOTFILES PROFILE

source "$DOTFILES/profiles/$PROFILE/profile.conf"

for script in "$DOTFILES"/install/*.sh; do
    echo ">>> $(basename "$script")"
    bash "$script"
done

echo "Done. Log out and back in for zsh to take effect."
```

### `install/*.sh` contract

- Each script is independently runnable: `bash install/04-hyprland.sh` works standalone.
- Each starts with `set -euo pipefail` and sources `install/_common.sh` for helpers (`log`, `need_pkg`, `stow_pkg`).
- **Idempotent.** Running twice must be safe. Use `pacman -S --needed`, `stow -R` (restow), `systemctl enable --now`.
- Desktop scripts (`04-hyprland.sh`, `05-desktop.sh`) early-exit on `server` profile via `$PROFILE` check.

### Script responsibilities

| # | Script | Purpose |
|---|--------|---------|
| 01 | `pacman.sh` | base-devel, git, stow, zsh, helix, neovim, mirrorlist tweaks |
| 02 | `paru.sh` | bootstrap paru from AUR if missing, apply `paru.conf` cache-redirect policy |
| 03 | `system.sh` | locale, hostname, pam_systemd_home fix, timezone |
| 04 | `hyprland.sh` | hyprland, hyprpaper, xdg-desktop-portal-hyprland *(workstation only)* |
| 05 | `desktop.sh` | waybar, mako, fuzzel, ghostty, fonts, cursor theme *(workstation only)* |
| 06 | `tools.sh` | uv + `uv sync` in `tools/` + wrappers to `~/.local/bin`; clone kickstart.nvim to `~/.config/nvim/` if missing |
| 07 | `claude.sh` | install Claude Code CLI, ensure `~/projects/agent-skills` cloned |
| 08 | `stow-base.sh` | `stow -d base -t ~ --no-folding -R <pkg>` for every base package |
| 09 | `stow-profile.sh` | same, for `profiles/$PROFILE/*` |
| 10 | `theme.sh` | read active theme marker, call `bin/dot-theme-set` to apply |
| 11 | `services.sh` | enable systemd user units (gdrive-bisync timer, etc.) |

### `bin/` helpers

All four are added to PATH via `base/zsh/.zshrc.d/dotfiles.zsh` which prepends `$DOTFILES/bin`.

- **`dot-restow [package|--all]`** — wraps the stow invocations used weekly
- **`dot-theme-set <theme-name>`** — see Section 3
- **`dot-update`** — `paru -Syu && dot-restow --all` (post-`git pull` workflow)
- **`dot-doctor`** — prints green/red checks for:
  - stow symlinks intact
  - `~/gdrive` mounted
  - Tailscale running
  - fonts installed
  - pam_systemd_home fix still applied (per user memory)
  - `~/.local/bin` in PATH
  - `claude` on PATH
  - `~/projects/agent-skills` is a git repo
  - active theme marker present

### Claude Code ordering

`07-claude.sh` runs *before* `08-stow-base.sh` so that when `base/claude/` places `.claude/settings.json` and `.claude/CLAUDE.md` into `~/.claude/`, the Claude Code binary already exists on PATH. First invocation of `claude` then bootstraps plugins from settings.

## Section 3 — Theme System

The most novel mechanism in this reorg. **Design updated 2026-04-24** after inspecting the existing `theme-switch` script; original directory-per-theme model from first-draft spec kept, but dark/light toggle UX preserved at a higher level.

### Model

Each theme is **single-state** (Omarchy-style — one palette per theme directory, no internal dark/light pair). The dark/light toggle that the existing `theme-switch` provides is preserved as a separate mechanism *on top of* the theme system:

- `dot-theme-set <name>` applies a specific theme
- `dot-theme-toggle` (bound to `$mod+SHIFT+t`) flips between the most recent dark and most recent light theme you chose
- Each theme declares its variant (`dark` or `light`) so the toggle command knows which half of its state to update

### State files (in `~/.config/dotfiles/`)

| Path | Purpose |
|---|---|
| `active-theme` | Name of the currently applied theme |
| `last-dark` | Most recent dark theme applied (for toggle) |
| `last-light` | Most recent light theme applied (for toggle) |

`dot-theme-set <name>` updates `active-theme` AND the appropriate `last-<variant>` file, based on the applied theme's declared variant.

### Theme directory anatomy

Each theme is a self-contained directory. Files are pre-rendered; no templating engine (YAGNI, tenet #6).

```
themes/catppuccin-mocha/
├── variant             # single word: "dark" or "light"
├── palette.sh          # colors as shell vars — human reference, single source of truth
├── hypr.conf           # col.active_border, col.inactive_border, decoration
├── hyprlock.conf       # full hyprlock screen config tuned to this theme
├── waybar.css          # CSS used by base waybar style.css symlink
├── ghostty.conf        # palette = … (Ghostty native syntax)
├── mako.conf           # background-color, text-color, border-color block
├── fuzzel.ini          # [colors] section
├── btop.theme          # btop native format
├── nvim.lua            # require'd by kickstart init if present (pcall-guarded)
├── helix-theme         # one word: the name of the upstream Helix theme (e.g. "catppuccin_mocha")
├── obsidian-theme      # one word: the Obsidian theme name (e.g. "obsidian" for dark)
├── gtk.conf            # GTK theme name, icon theme, cursor theme name, color-scheme preference
├── wallpaper.jpg       # (or .png)
├── README.md           # theme origin, extra font/icon packages required
└── post-set.sh         # optional hook for app-specific tweaks (runs last)
```

### `dot-theme-set <name>` behavior

1. Validate `themes/<name>/` exists; refuse unknown names.
2. Read variant from `themes/<name>/variant` (must be `dark` or `light`).
3. Write markers in `~/.config/dotfiles/`:
   - `active-theme` = `<name>`
   - `last-<variant>` = `<name>` (e.g. `last-dark` if this is a dark theme)
4. Symlink theme files into the locations apps read:
   - `themes/<name>/hypr.conf` → `~/.config/hypr/theme.conf`
   - `themes/<name>/hyprlock.conf` → `~/.config/hypr/hyprlock.conf`
   - `themes/<name>/waybar.css` → `~/.config/waybar/style.css`
   - `themes/<name>/ghostty.conf` → `~/.config/ghostty/theme.conf`
   - `themes/<name>/fuzzel.ini` → `~/.config/fuzzel/fuzzel.ini`
   - `themes/<name>/mako.conf` → `~/.config/mako/config`
   - `themes/<name>/btop.theme` → `~/.config/btop/themes/active.theme`
   - `themes/<name>/nvim.lua` → `~/.config/nvim/lua/dotfiles-theme.lua` *(skipped if `~/.config/nvim/lua/` does not exist)*
   - `themes/<name>/wallpaper.jpg` → `~/.config/dotfiles/wallpaper`
5. Non-symlink integration:
   - Sed-rewrite `~/.config/helix/config.toml` `theme = "…"` line to the value in `themes/<name>/helix-theme` (preserves existing behavior from `theme-switch`)
   - JSON-patch Obsidian's `<vault>/.obsidian/appearance.json` `"theme"` field to the value in `themes/<name>/obsidian-theme` (preserves existing behavior, conditional on `$OBSIDIAN_VAULT` being set in profile.conf)
   - Run `gsettings` to set `color-scheme` and `gtk-theme` from `themes/<name>/gtk.conf`
6. Run `themes/<name>/post-set.sh` if present (theme-specific tweaks not handled generically above).
7. Reload running apps (best-effort, non-fatal):
   - `hyprctl reload`
   - `pkill -SIGUSR2 waybar`
   - `pkill -SIGUSR2 ghostty` (ghostty picks up theme.conf on SIGUSR2)
   - `makoctl reload`
   - `pkill -SIGUSR1 hx` / `pkill -SIGUSR1 helix` (helix reloads config on SIGUSR1)
   - Restart fragpaper via its launch wrapper (fragpaper has no live reload — kill + relaunch with new wallpaper)

### `dot-theme-toggle` behavior

The hotkey companion. Preserves the existing `$mod+SHIFT+t` quick-toggle UX.

1. Read `~/.config/dotfiles/active-theme`; look up its variant from `themes/<active>/variant`.
2. If variant is `dark` → read `~/.config/dotfiles/last-light`; if non-empty and the theme still exists, apply it via `dot-theme-set`.
3. If variant is `light` → same with `last-dark`.
4. Graceful fallback if the counterpart state file is empty or stale: find the first theme of the opposite variant in `themes/*/variant` and apply that; warn the user to pick a preferred counterpart by running `dot-theme-set <name>` once.

### Base config participation

Each themable app's base config ends with a theme include, keeping theme-free content in `base/` and theme-specific content in `themes/`:

- `base/hypr/.config/hypr/hyprland.conf` — includes `source = ~/.config/hypr/theme.conf`
- `base/ghostty/.config/ghostty/config` — includes `config-file = theme.conf`
- `base/mako/.config/mako/config` — already IS the theme file (symlinked in place by `dot-theme-set`)
- `base/waybar/style.css` — already IS the theme file (symlinked in place)
- `base/fuzzel/fuzzel.ini` — already IS the theme file (symlinked in place)
- `base/btop/.config/btop/btop.conf` — `color_theme = "active"` (reads `~/.config/btop/themes/active.theme`)

**Helix** is integrated via sed-rewrite of `config.toml` (no include mechanism), not symlink. Integration preserved from existing `theme-switch`.

**Obsidian** is integrated via JSON-patch to the vault's `appearance.json` (live file watcher picks up the change). Preserved from existing `theme-switch`.

**Fragpaper** (wallpaper daemon) has no live reload — killed and relaunched per theme change. Preserved from existing `theme-switch`.

### Base config participation

Each themable app's base config ends with a theme include, keeping theme-free content in `base/` and theme-specific content in `themes/`:

- `base/hypr/.config/hypr/hyprland.conf` — last line: `source = ~/.config/hypr/theme.conf`
- `base/waybar/.config/waybar/style.css` — last line: `@import url("theme.css");`
- `base/ghostty/.config/ghostty/config` — contains: `config-file = theme`
- `base/mako/.config/mako/config` — `include = ~/.config/mako/theme.conf`
- `base/fuzzel/.config/fuzzel/fuzzel.ini` — `[include]` directive pointing at `theme.ini`
- `base/btop/.config/btop/btop.conf` — `color_theme = "active"`

**Neovim integration:** the user's kickstart fork at `~/.config/nvim/` ends its `init.lua` with `pcall(require, 'dotfiles-theme')` (injected in Wave 2). The `dotfiles-theme.lua` file placed by `dot-theme-set` typically contains one line: `vim.cmd.colorscheme('catppuccin-mocha')` (or equivalent per theme). Requires the theme's colorscheme plugin to be installed by the kickstart config. If the file is absent, kickstart falls back to its default colorscheme — non-fatal by design.

### Server profile

`install/10-theme.sh` is a no-op on server. `dot-theme-set` on a headless box only applies btop + ghostty if present; other surfaces silently skip when target directories don't exist.

### Themes shipped at launch

Wave 3 ships **two themes** (one of each variant, so the toggle works out of the box):

- `themes/catppuccin-mocha/` — dark, variant=dark
- `themes/catppuccin-latte/` — light, variant=light

The user's prior dark palette (Tokyo Night) and prior light palette (daltonized-Claude-Code) are preserved in git history. If re-wanted later, they can be re-extracted as new themes.

### Retirement of `theme-switch`

The existing `base/bin/.local/bin/theme-switch` script is **deleted** in Wave 3 — its logic is absorbed and generalized into `bin/dot-theme-set` + `bin/dot-theme-toggle`. The `$mod+SHIFT+t` Hyprland keybind is rewired from `theme-switch` to `dot-theme-toggle`.

### Extension

Adding a second theme later: copy `themes/catppuccin-mocha/` → `themes/<new>/`, hand-edit each file (including the `variant` file), done. No code changes to `dot-theme-set`.

### Not in v1

- GTK-heavy app theming (Firefox, LibreOffice) — boutique problems, defer until needed
- Cursor theme switching via theme system — cursor set once in `05-desktop.sh`; themes may override via gsettings in `post-set.sh`
- A `dot-theme-list` command — `ls themes/` is sufficient

## Section 4 — Manual Chapters

Eight files in `docs/manual/`. Each owns one concern completely so the README stays tight.

| # | File | What's in it |
|---|------|--------------|
| 01 | `install.md` | Fresh Arch → running workstation. Script-by-script walkthrough of `install/*.sh`. What each step does, what to check if it fails. References `dot-doctor`. |
| 02 | `keybindings.md` | Every binding: Hyprland (window/workspace/launcher), Zellij, editors (Helix links upstream; Neovim links to user's kickstart fork + notes on custom bindings), Claude Code. Cheat-sheet-shaped. |
| 03 | `theming.md` | How the theme system works (Section 3 made permanent), how to add a new theme, what each surface controls, when to edit `base/` vs `themes/`. |
| 04 | `tools.md` | The `tools/` uv project: `yt_transcript`, `web_extract`, `news`. How to add a new tool (`pyproject.toml` entry + wrapper in `base/bin/`). |
| 05 | `claude-code.md` | Tenet #4 made concrete. Settings philosophy, active plugins + why, the `agent-skills` project, the custom `sew` plugin, hook conventions, how to author a new skill. |
| 06 | `recovery.md` | Dead-laptop → functional in <1 hour. DR backup (`dr_backup.sh`), Ventoy USB when built, Google Drive bisync recovery, what's NOT in the repo (SSH keys, `.gitconfig.local`, secrets). |
| 07 | `philosophy.md` | The 6 tenets, each with 1-2 paragraphs of reasoning and concrete consequences. The "why" document. |
| 08 | `roll-your-own.md` | Fork guide for the hypothetical stranger. What's Scott-specific (Obsidian vault paths, gdrive-bisync cron, Tailscale), what's generalizable (install structure, theme system, modular script pattern). Which tenets a stranger would likely rewrite. |

### README.md after the reorg

- Manifesto (link to Ch. 7)
- 6-line quickstart
- Table linking to each manual chapter
- Status line (private repo, Arch + Hyprland, last updated)

No inline keybinding tables, no 30-line install instructions. README is the front door.

## Section 5 — Migration Sequencing

Four waves, each independently mergeable. Order chosen so each wave leaves the machine in a working state.

### Wave 1 — Cleanup

Low risk. Frees the workspace.

- Delete `profiles/work/`, `base/windows/`, `base/micro/`, `base/qalculate/`, `sync-windows.sh`, Sway/Wofi/Kitty remnants
- Rename `profiles/personal/` → `profiles/workstation/`
- Stopgap update of existing README to reflect Arch/Hyprland/Ghostty reality (will be replaced in Wave 4)
- Commit. Machine keeps working; dead weight is gone.

**Est. effort:** 30 min.

### Wave 2 — Install modularization

Medium risk. Test carefully.

- Create `install/` dir with 11 scripts + `_common.sh`; port logic from current monolithic `install.sh`
- Rewrite `install.sh` as the orchestrator
- Create `bin/` with four helpers; add `$DOTFILES/bin` to PATH via new `base/zsh/.zshrc.d/dotfiles.zsh`
- Clone kickstart.nvim (or user fork) to `~/.config/nvim/` as its own git repo; add the `pcall(require, 'dotfiles-theme')` line at the end of its `init.lua`
- Test by running individual `install/*.sh` scripts on live machine — each should be a no-op (idempotence test)
- Commit. Next fresh install would go through the new flow.

**Est. effort:** half a day, plus whatever time the user spends initially learning kickstart.

### Wave 3 — Theme system

New capability, additive only.

- Create `themes/catppuccin-mocha/` with all per-app snippets
- Add theme include directives to base configs (hypr, waybar, ghostty, mako, fuzzel, btop)
- Run `dot-theme-set catppuccin-mocha` on live machine; verify every surface
- Commit. Theme switching works (once more themes are added).

**Est. effort:** a full day. Most time is in per-surface tuning.

### Wave 4 — Docs overhaul

Pure writing. Zero risk.

- Write all 8 manual chapters in `docs/manual/`
- Rewrite README as the tight front door
- Commit. System is now opinionated *and documented*.

**Est. effort:** 2-3 focused sessions.

### Why this order

- Wave 1 first: a clean workspace makes everything else easier to review.
- Wave 2 before Wave 3: `install/10-theme.sh` depends on the modular install layout existing.
- Wave 4 last: accurate docs require the system to be in final shape.

## Open items / deferred decisions

- Exact Claude Code install method (npm global, curl script, AUR package if available) — decide in Wave 2 implementation plan.
- Which Hyprland wallpaper daemon to standardize on (`hyprpaper` vs `swww`) — `dot-theme-set` reload command differs; decide in Wave 3.
- Whether `dot-doctor` output uses color (`tput` vs plain text) — taste call, not blocking.
- Kickstart.nvim fork strategy: clone upstream directly vs fork on GitHub first. Fork is cleaner for tenet #5 (reproducible), but adds an account setup step. Decide in Wave 2 implementation plan.
- Which colorscheme plugin the Neovim config pulls in for Catppuccin (`catppuccin/nvim` is canonical). Confirm in Wave 3 when the theme's `nvim.lua` is written.
- Second theme: deferred indefinitely. Add when there is an actual mood/lighting reason.

## References

- Omarchy 3.6 — shape inspiration (`bin/install/*.sh`, theme system, topic-based docs)
- Existing spec: `2026-04-18-arch-dr-design.md` — DR flow this spec depends on (recovery chapter pulls from it)
- User memory: tenets #1 and #6 derived from data-ownership and hardware-modularity preferences
