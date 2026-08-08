# Chapter 04 — Tools

Two flavors of user-space tooling in this repo:

1. **`tools/`** — subdirectory-per-tool: Rust binary, Python projects, shell scripts.
2. **`bin/`** — both the user-facing wrapper scripts (`firefox`, `fragpaper-*`, `news`, `obsidian`, `pi`, `trackpad-toggle`, `window-picker`) and the re-runnable `dot-*` dotfiles helpers, all on PATH via `ioshi/i-intelligence/zsh.nix` (`export PATH="$DOTFILES/bin:$PATH"`). Nothing here is stowed — they live in the repo and ride along with the checkout.

## tools/

### window-picker

A small Rust binary that renders a window picker overlay by shelling out to `hyprctl`. Written for Hyprland; EWM replaced Hyprland as the compositor and this tool was never ported, so it is currently vestigial — kept here as source, not wired into any host. Binary path if built: `~/dotfiles/tools/window-picker/target/release/window-picker`.

### cheatsheet — mpv dependency

`hypr-cheatsheet` was removed along with the other Hyprland-era `hypr-*` wrappers (EWM replaced Hyprland; they shelled out to `hyprctl`). This subsection is stale and pending removal/replacement by whatever EWM cheatsheet mechanism succeeds it.

(Weather imagery used to render through mpv too; it now renders natively inside Emacs — see "Emacs surfaces" below.)

### Emacs surfaces

The weather (`$mod + n`), OpenRouter cost (`$mod + u`), and pi (`$mod + p`) popups are elisp commands in `ioshi/i-intelligence/emacs/lisp/` (`scott/weather-frame`, `scott/openrouter-cost-frame`, `scott/pi-frame`), invoked from EWM via `emacsclient -e` against the Emacs daemon. (The elisp itself still comments these as "Hyprland entry point" — a leftover from before EWM replaced it; the mechanism, `emacsclient -e`, didn't change.) ERT tests live in `ioshi/i-intelligence/emacs/test/`.

### fragpaper

GPU shader wallpaper renderer for Wayland. `~/projects/fragpaper` is canonical on datacore; on runtime desktops the checkout is cached under `~/.local/share/fragpaper` instead of creating `~/projects`. It builds a release binary and installs it to `~/.local/opt/fragpaper/bin/fragpaper`. Fragpaper runs as a user systemd service (`fragpaper.service`, ported into `ioshi/i-intelligence/fragpaper.nix` during the stow retirement); on runtime-only hosts like `rafik` it is just an installed product and does not need a project checkout unless you are actively debugging it. `fragpaper-launch` reads shaders from the best available checkout (`~/.local/share/fragpaper` on runtime desktops, `~/projects/fragpaper` on datacore/dev machines) and falls back to `cargo run --release` if the installed binary is missing.

Runtime launcher:

```bash
fragpaper-launch   # bin/fragpaper-launch, on PATH via $DOTFILES/bin
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

## bin/ — user-facing wrappers

`base/bin/.local/bin/` (the stow-deployed wrapper directory) was retired; these scripts now live directly in `bin/` and reach PATH via `ioshi/i-intelligence/zsh.nix`'s `export PATH="$DOTFILES/bin:$PATH"` — no stow, no symlink into `~/.local/bin`. The five Hyprland-era `hypr-*` wrappers (`hypr-brightness`, `hypr-calc`, `hypr-cheatsheet`, `hypr-rename-workspace`, `hypr-wifi`) were deleted outright: they shelled out to `hyprctl`, which EWM replaced.

| Wrapper | Purpose |
|---|---|
| `fragpaper-launch` | Launches fragpaper with the active theme's BG_COLOR + PALETTE |
| `fragpaper-ctl` | fragpaper control helper |
| `fragpaper-playlist` | fragpaper playlist helper |
| `firefox` | Wrapper that prefers installed Firefox, then Firefox ESR, then Flatpak Firefox |
| `obsidian` | Wrapper that prefers installed Obsidian, then `/opt/Obsidian`, then Flatpak Obsidian |
| `news` | News helper |
| `pi` | Pi coding agent launcher |
| `trackpad-toggle` | Toggle trackpad on/off |
| `window-picker` | Calls the Rust binary at `tools/window-picker/target/release/` |

## bin/dot-* — repo-level helpers

Also in `bin/`, on PATH the same way. They are NOT stowed — they live in the repo and ride along with your clone.

| Helper | Purpose |
|---|---|
| `dot-bootstrap` | Pull latest dotfiles, then run the install path for the current profile |
| `dot-context` | Print host, repo path, branch, and key symlink state for quick troubleshooting |
| `dot-theme-set <name>` | Apply a theme (see [Chapter 03](03-theming.md)) |
| `dot-theme-toggle` | Flip between last-dark and last-light (Chapter 03) |
| `dot-update` | **Stale — flag for cleanup.** Its script still reads `apt update && apt full-upgrade -y` then calls `bin/dot-sync`, both Debian/stow-era; `dot-sync` no longer exists in `bin/`, so this command currently fails on every NixOS host. |
| `dot-repair <script\|--all>` | Rerun one or more install scripts without re-cloning the repo |
| `dot-doctor` | 20-check health scan: PATH, services, fonts, pi, active theme, Nix/Emacs/org-roam state |

Fresh clone note: use `./bootstrap.sh` and `./repair.sh` from repo root before shell dotfiles load `$DOTFILES/bin` onto PATH.

## Adding a new tool

- **User-facing wrapper script:** drop it in `bin/`, `chmod +x`, commit. No stow, no HM module needed — it's on PATH via `$DOTFILES/bin`.
- **Dotfiles-specific re-runnable helper:** same — add it to `bin/`, `chmod +x`, commit.

## Why two flavors

- `tools/` is for things substantial enough to have their own build system (Cargo projects, Python projects with external deps). These could in principle be separate projects; keeping them here means one-clone recovery.
- `bin/` covers both small user-facing wrappers (what you type at the shell) and helpers that operate on the dotfiles system itself (stow, update, health). They live in the repo because they only make sense with the repo checked out.

## AI Tooling

The [pi coding agent](https://github.com/earendil-works/pi-coding-agent) is a first-class tool, installed by `install/07-pi.sh` via `npm install -g --prefix ~/.local @earendil-works/pi-coding-agent`. It requires Node/npm from apt.

### What ships in dotfiles

| Item | Repo source | Runtime target |
|---|---|---|
| Agent config | `ioshi/i-intelligence/pi/agent/AGENTS.md` | `~/.pi/agent/AGENTS.md` (Home Manager `home.file`, via `ioshi/i-intelligence/pi.nix`) |
| Custom extensions | `ioshi/i-intelligence/pi/agent/extensions/` | `~/.pi/agent/extensions/` |
| Skills | `ioshi/i-intelligence/pi/agent/skills/` | `~/.pi/agent/skills/` |

`~/.pi/agent` is otherwise a Syncthing-synced folder between machines — only
`AGENTS.md` and `auth.json` (an agenix secret, symlinked out-of-store) are
Home-Manager-managed; `settings.json` is seeded once then left to pi's own
runtime writes.

Shipped skills:

- **`vaultkeeper`** — Obsidian vault maintenance: find missing connections, enrich thin notes, propose changes as diffs. Invoked with `/vaultkeeper "topic"` or `/vaultkeeper random 5`.

### Commit discipline

- Changes to `ioshi/i-intelligence/pi/` → commit in this dotfiles repo.
- Skills live in both `~/.pi/agent/skills/` and `ioshi/i-intelligence/pi/agent/skills/` — sync changes to the repo copy and commit.
- Engram memory is external — no `.mv2` files in the repo.

### Forking

The `ioshi/i-intelligence/pi.nix` module (and `ioshi/i-intelligence/pi/`) and the AI-augmented workflow are the most user-specific piece of this system. A forker will either adopt a similar setup or delete them (see [Chapter 06 — Roll Your Own](06-roll-your-own.md)).
