# Chapter 04 — Tools

Three flavors of user-space tooling in this repo:

1. **`tools/`** — a uv Python project with CLI utilities (`yt_transcript`, `web_extract`, `news`) plus a Rust binary (`window-picker`).
2. **`base/bin/`** — small wrapper scripts that live on `$HOME/.local/bin` via stow.
3. **`bin/dot-*`** — re-runnable dotfiles helpers on `$DOTFILES/bin` via zshrc.d.

## tools/

A uv-managed Python project. `pyproject.toml` declares entry points; `uv sync` (run by `install/06-tools.sh`) creates a project venv and wires the entry points.

### yt_transcript

Extracts YouTube transcripts. No API key.

```bash
yt_transcript "https://www.youtube.com/watch?v=VIDEO_ID"
yt_transcript "VIDEO_ID" --timestamps
yt_transcript "VIDEO_ID" -o transcript.md
yt_transcript "VIDEO_ID" -l es -l en
```

Accepts full URLs, `youtu.be` short links, or bare video IDs.

### web_extract

Pulls clean article text from a URL, stripping ads/nav/boilerplate.

```bash
web_extract "https://example.com/article"
web_extract "https://example.com/article" -o article.md
web_extract "https://example.com/article" -f text
web_extract "https://example.com/article" --precision
```

### news

Tech news briefing. Pulls from Hacker News, Reddit, and Lobsters via RSS / public APIs.

```bash
news            # all sources
news hn
news reddit
news lobsters
news -n 5       # limit items per feed
```

Default subreddits live in `REDDIT_SUBS` in `tools/news.py`.

### window-picker

A small Rust binary that renders a window picker overlay for Hyprland. Built by `install/06-tools.sh`. Binary path: `~/dotfiles/tools/window-picker/target/release/window-picker`.

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

## base/bin/ — stowed wrappers

Every file in `base/bin/.local/bin/` is symlinked to `~/.local/bin/<name>` by `install/08-stow-base.sh`. (Populate this table from the Step 1 inspection. Expected contents as of now — double-check against actual):

| Wrapper | Purpose |
|---|---|
| `fragpaper-launch` | Launches fragpaper with the active theme's BG_COLOR + PALETTE |
| `hypr-brightness` | Adjusts laptop brightness with brightnessctl/light/sysfs fallbacks; bound to F2/F3 and XF86 brightness keys |
| `hypr-cheatsheet` | Fuzzel viewer for Hyprland keybindings; sources from `~/docs/vault/Whitsgrove/Hyprland Cheatsheet.md` (bound to `$mod + Shift + /`) |
| `hypr-rename-workspace` | Fuzzel prompt → `hyprctl dispatch renameworkspace <id> "<id> <label>"` (bound to `$mod + r`) |
| `helix` | Wrapper that prefers `hx` on Debian but still supports a native `helix` binary |
| `firefox` | Wrapper that prefers installed Firefox, then Firefox ESR, then Flatpak Firefox |
| `obsidian` | Wrapper that prefers installed Obsidian, then `/opt/Obsidian`, then Flatpak Obsidian |
| `news` | Calls the uv-managed `news` entry point |
| `trackpad-toggle` | Toggle trackpad on/off |
| `web_extract` | Calls the uv-managed `web_extract` entry point |
| `window-picker` | Calls the Rust binary at `tools/window-picker/target/release/` |
| `yt_transcript` | Calls the uv-managed entry point |

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

- **Python CLI that should ship with the dotfiles:** add it to `tools/`, declare an entry point in `pyproject.toml`, add a wrapper in `base/bin/.local/bin/<name>` that calls it. Run `install/06-tools.sh` (or just `uv sync` in `tools/`) to wire the venv.
- **Small shell script:** drop it in `base/bin/.local/bin/<name>`, `chmod +x`, commit. It'll land in `~/.local/bin/` on next stow.
- **Dotfiles-specific re-runnable helper:** add it to `bin/`, `chmod +x`, commit. No stow needed — it's on PATH via `$DOTFILES/bin`.

## Why three flavors

- `tools/` is for things substantial enough to have dependencies (uv-managed Python, Cargo-managed Rust). These could in principle be separate projects; keeping them here means one-clone recovery.
- `base/bin/` is for small user-facing wrappers that should be on `~/.local/bin/` like any other user script. These are what you type at the shell.
- `bin/dot-*` is for helpers that operate on the dotfiles system itself (stow, update, health). They live in the repo because they only make sense with the repo checked out.
