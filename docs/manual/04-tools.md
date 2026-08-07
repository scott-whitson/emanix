# Chapter 04 — Tools

Three flavors of user-space tooling in this repo:

1. **`tools/`** — subdirectory-per-tool: Rust binary, Python projects, shell scripts.
2. **`base/bin/`** — small wrapper scripts that live on `$HOME/.local/bin` via stow.
3. **`bin/dot-*`** — re-runnable dotfiles helpers on `$DOTFILES/bin` via zshrc.d.

## tools/

### window-picker

A small Rust binary that renders a window picker overlay for Hyprland. Built by `install/06-tools.sh`. Binary path: `~/dotfiles/tools/window-picker/target/release/window-picker`.

### cheatsheet — mpv dependency

`hypr-cheatsheet` renders to an `mpv` window (forced float, mpv title `hypr-cheatsheet`). install/05-desktop.sh includes `mpv` as a desktop package. If you swap mpv for another viewer, update:

- `base/bin/.local/bin/hypr-cheatsheet`
- `base/hypr/.config/hypr/hyprland.conf` `windowrule` entries
- `install/05-desktop.sh`

(Weather imagery used to render through mpv too; it now renders natively inside Emacs — see "Emacs surfaces" below.)

### Emacs surfaces

The weather (`$mod + n`), OpenRouter cost (`$mod + u`), and pi (`$mod + p`) popups are elisp commands in `modules/home-manager/emacs/lisp/` (`scott/weather-frame`, `scott/openrouter-cost-frame`, `scott/pi-frame`), invoked from Hyprland via `emacsclient -e` against the Emacs daemon. ERT tests live in `modules/home-manager/emacs/test/`.

### fragpaper

GPU shader wallpaper renderer for Wayland. `install/06-tools.sh` uses `~/projects/fragpaper` on datacore, but on runtime desktops it caches the checkout under `~/.local/share/fragpaper` instead of creating `~/projects`. It builds a release binary and installs it to `~/.local/opt/fragpaper/bin/fragpaper`. Fragpaper runs as a user systemd service (`fragpaper.service`) started automatically from Hyprland; on runtime-only hosts like zord it is just an installed product and does not need a project checkout unless you are actively debugging it. `fragpaper-launch` reads shaders from the best available checkout (`~/.local/share/fragpaper` on runtime desktops, `~/projects/fragpaper` on datacore/dev machines) and falls back to `cargo run --release` if the installed binary is missing.

Runtime launcher:

```bash
~/.local/bin/fragpaper-launch
```

Override env if needed:

```bash
FRAGPAPER_BIN=~/.local/opt/fragpaper/bin/fragpaper
FRAGPAPER_SRC=~/.local/share/fragpaper   # runtime desktops
FRAGPAPER_SRC=~/projects/fragpaper       # datacore/dev machines
FRAGPAPER_SHADERS_DIR=$FRAGPAPER_SRC/shaders
```

### syncthing

Syncthing is the local file-sync layer for your docs vault. The install flow brings up the user service and `install/13-docs-sync.sh` pairs the docs folder with datacore. The synced docs tree lives at `~/docs`, which is what Obsidian opens. The canonical setup shares that folder from datacore to runtime desktops; the runtime desktop only needs the synced files, not a project checkout.

Useful paths:

- Config/state: `~/.local/state/syncthing/`
- Synced docs folder: `~/docs`
- Obsidian vault: `~/docs/vault`

## base/bin/ — stowed wrappers

Every file in `base/bin/.local/bin/` is symlinked to `~/.local/bin/<name>` by `install/08-stow-base.sh`. (Populate this table from the Step 1 inspection. Expected contents as of now — double-check against actual):

| Wrapper | Purpose |
|---|---|
| `fragpaper-launch` | Launches fragpaper with the active theme's BG_COLOR + PALETTE |
| `hypr-brightness` | Adjusts laptop brightness with brightnessctl/light/sysfs fallbacks; bound to F2/F3 and XF86 brightness keys |
| `hypr-calc` | Quick calculator popup (bound to `$mod + c`) |
| `hypr-cheatsheet` | Fuzzel viewer for Hyprland keybindings; sources from `~/docs/vault/Whitsgrove/Hyprland Cheatsheet.md` (bound to `$mod + Shift + /`) |
| `hypr-rename-workspace` | Fuzzel prompt → `hyprctl dispatch renameworkspace <id> "<id> <label>"` (bound to `$mod + r`) |
| `hypr-wifi` | WiFi connection helper in Ghostty (bound to `$mod + i`) |
| `firefox` | Wrapper that prefers installed Firefox, then Firefox ESR, then Flatpak Firefox |
| `obsidian` | Wrapper that prefers installed Obsidian, then `/opt/Obsidian`, then Flatpak Obsidian |
| `trackpad-toggle` | Toggle trackpad on/off |
| `window-picker` | Calls the Rust binary at `tools/window-picker/target/release/` |

## bin/dot-* — repo-level helpers

These live at `$DOTFILES/bin/` and are on PATH via `base/zsh/.zshrc.d/dotfiles.zsh` (which prepends `$DOTFILES/bin`). They are NOT stowed — they live in the repo and ride along with your clone.

| Helper | Purpose |
|---|---|
| `dot-bootstrap` | Datacore-first sync + full `./install.sh` bootstrap |
| `dot-context` | Print host, repo path, branch, and key symlink state for quick troubleshooting |
| `dot-restow <pkg\|--all>` | Re-stow one package or all packages from `base/` |
| `dot-theme-set <name>` | Apply a theme (see [Chapter 03](03-theming.md)) |
| `dot-theme-toggle` | Flip between last-dark and last-light (Chapter 03) |
| `dot-update` | `apt update && apt full-upgrade -y && dot-restow --all` — weekly housekeeping |
| `dot-repair <script\|--all>` | Rerun one or more `install/*.sh` scripts without re-cloning repo |
| `dot-doctor` | 17-check health scan: stow links, services, fonts, PATH, pi, active theme |

Fresh clone note: use `./bootstrap.sh` and `./repair.sh` from repo root before shell dotfiles load `$DOTFILES/bin` onto PATH.

## Adding a new tool

- **Small shell script:** drop it in `base/bin/.local/bin/<name>`, `chmod +x`, commit. It'll land in `~/.local/bin/` on next stow.
- **Dotfiles-specific re-runnable helper:** add it to `bin/`, `chmod +x`, commit. No stow needed — it's on PATH via `$DOTFILES/bin`.

## Why three flavors

- `tools/` is for things substantial enough to have their own build system (Cargo projects, Python projects with external deps). These could in principle be separate projects; keeping them here means one-clone recovery.
- `base/bin/` is for small user-facing wrappers that should be on `~/.local/bin/` like any other user script. These are what you type at the shell.
- `bin/dot-*` is for helpers that operate on the dotfiles system itself (stow, update, health). They live in the repo because they only make sense with the repo checked out.

## AI Tooling

The [pi coding agent](https://github.com/earendil-works/pi-coding-agent) is a first-class tool, installed by `install/07-pi.sh` via `npm install -g --prefix ~/.local @earendil-works/pi-coding-agent`. It requires Node/npm from apt.

### What ships in dotfiles

| Item | Stow source | Runtime target |
|---|---|---|
| Agent config | `base/pi/.pi/agent/AGENTS.md` | `~/.pi/agent/AGENTS.md` |
| Custom extensions | `base/pi/.pi/agent/extensions/` | `~/.pi/agent/extensions/` |
| Skills | `base/pi/.pi/agent/skills/` | `~/.pi/agent/skills/` |

Shipped skills:

- **`vaultkeeper`** — Obsidian vault maintenance: find missing connections, enrich thin notes, propose changes as diffs. Invoked with `/vaultkeeper "topic"` or `/vaultkeeper random 5`.

### Commit discipline

- Changes to `base/pi/` → commit in this dotfiles repo.
- Skills live in both `~/.pi/agent/skills/` and `base/pi/.pi/agent/skills/` — sync changes to `base/pi/` and commit.
- Engram memory is external — no `.mv2` files in the repo.

### Forking

The `base/pi/` package and the AI-augmented workflow are the most user-specific piece of this system. A forker will either adopt a similar setup or delete the package (see [Chapter 06 — Roll Your Own](06-roll-your-own.md)).
