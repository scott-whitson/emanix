# photo-tools

Photo import pipeline: SD card → laptop staging (`~/downloads/camera/<date>/`) → datacore filesystem archive + Immich for viewing. Designed for "mixed by intent" shooting (default JPG, occasional RAW+JPG).

Spec: `~/docs/superpowers/specs/2026-05-08-photo-workflow-design.md`.

## Install

1. System packages:
   ```bash
   sudo pacman -S darktable perl-image-exiftool
   # immich-go: AUR
   yay -S immich-go-bin       # or download a release binary into ~/.local/bin/
   ```

2. Python deps (already in `~/dotfiles/tools/pyproject.toml`):
   ```bash
   cd ~/dotfiles/tools && uv sync
   ```

3. Configure:
   ```bash
   mkdir -p ~/.config/photo-import
   cp ~/dotfiles/tools/photo-tools/config.example.toml ~/.config/photo-import/config.toml
   cp ~/dotfiles/tools/photo-tools/secrets.example.toml ~/.config/photo-import/secrets.toml
   chmod 600 ~/.config/photo-import/secrets.toml
   $EDITOR ~/.config/photo-import/secrets.toml   # paste Immich API key
   ```

4. Confirm passwordless SSH to datacore:
   ```bash
   ssh datacore true && echo OK
   ```

5. Wrapper script (already done — see `~/.local/bin/photo-import`).

6. Bootstrap the ledger from existing datacore archive (one-time, can take a while):
   ```bash
   photo-import index
   ```

## Usage

```bash
# Insert SD card; automount lands at /run/media/$USER/<label>/
photo-import sd                       # auto-detect
photo-import sd --source /run/media/$USER/3064-3031   # explicit override

# Push staged shoot(s) to datacore + Immich
photo-import publish                  # all staged shoots
photo-import publish 2026-05-08       # specific shoot

# Inspect state
photo-import status

# Keep a shoot past retention (e.g. waiting to edit)
photo-import pin   2026-05-08
photo-import unpin 2026-05-08
```

## Editing RAWs in darktable (optional)

```bash
darktable ~/downloads/camera/2026-05-08/
```

Cancel darktable's first-launch dialog if it offers to import `~/Pictures` — there is no `~/Pictures` directory on this system. Sidecars (`.CR3.xmp`) get rsynced along with the rest when you next run `publish`.

## Architecture

- Laptop holds only "active" shoots (default: 30 days after publish, then auto-cleaned).
- Source of truth: `/srv/data/photo-archive/Pictures/<year>/<YYYY-MM-DD>/` on datacore.
- Immich is the viewing layer; it stores its own copy in `/srv/data/photos/`. Both are inside `/srv/data` and inherit Backblaze coverage.
- Dedup: SHA256 ledger at `~/.local/share/photo-import/imports.sqlite`. Re-inserting the same SD card is a no-op.

## State and config locations

| Path | What |
|---|---|
| `~/downloads/camera/<date>/` | Transient staging (safe to delete; only published files are there) |
| `~/.local/share/photo-import/imports.sqlite` | Hash ledger |
| `~/.local/share/photo-import/photo-import.log` | Rolling log (10 MB rotation) |
| `~/.config/photo-import/config.toml` | Config |
| `~/.config/photo-import/secrets.toml` | Immich API key (mode 600) |

## Legacy

Earlier tooling targeting `~/gdrive/SEW/History/Pictures/` is in `_archive/`. The iCloud / phone-offload playbook from the old README is still available there as `_archive/photo-reconcile` documentation if you need to re-do that flow.

## Tests

```bash
cd ~/dotfiles/tools/photo-tools
uv run --project ~/dotfiles/tools pytest -v
```
