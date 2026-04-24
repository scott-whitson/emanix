# dotfiles

> **Status (2026-04-23):** mid-reorg. This README is a stopgap — a proper manual at `docs/manual/` is planned in Wave 4 of the reorg. See `docs/superpowers/specs/2026-04-23-dotfiles-opinionated-reorg-design.md`.

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/) and a multi-profile system. One shared base config, with profile-specific overrides for different machines.

## Quick Start

```bash
git clone git@github.com:scottwhitson/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh workstation
```

The install script detects your distro, installs system packages and developer tools, stows the base config, then layers the chosen profile on top.

## Structure

```
~/dotfiles/
├── install.sh              # bootstrap script: ./install.sh <profile>
├── base/                   # shared config, applied to every machine
│   ├── zsh/.zshrc          # Oh My Zsh, aliases, tools; sources ~/.zshrc.d/*.zsh
│   ├── git/.gitconfig      # core git settings; includes ~/.gitconfig.local
│   ├── hypr/               # Hyprland compositor (desktop only)
│   ├── waybar/             # status bar config + theme (desktop only)
│   ├── fuzzel/             # app launcher config (desktop only)
│   ├── mako/               # notification daemon (desktop only)
│   ├── ghostty/            # terminal emulator (desktop only)
│   ├── btop/               # system monitor
│   ├── helix/              # text editor
│   ├── lf/                 # terminal file manager
│   ├── mpv/                # media player
│   ├── yt-dlp/             # video downloader
│   ├── claude/             # Claude Code settings (full plugin set)
│   ├── paru/               # AUR helper config
│   ├── xdg/                # XDG base dir overrides
│   ├── systemd/            # user systemd units
│   ├── bin/                # personal scripts (~/.local/bin)
│   └── zsh/                # shell config
└── profiles/
    ├── workstation/        # this Arch laptop (personal)
    └── server/             # headless / remote server
```

**Base** is stowed first with `--no-folding`, so directories like `~/.zshrc.d/` and `~/.claude/` are real directories (not symlinks). Profile packages then add or replace files inside those same directories.

Desktop packages (`hypr`, `waybar`, `fuzzel`, `mako`, `ghostty`) are skipped on server profiles (no display server).

## Profiles

| Profile | Machine | What it adds |
|---------|---------|-------------|
| `workstation` | This Arch laptop | Personal git identity, Obsidian vault path, Google Drive bisync, custom zsh fragments |
| `server` | Headless Arch server | Server git identity, trimmed Claude Code plugin set |

Each profile can include:
- `profile.conf` -- variables sourced by `install.sh` (e.g. `OBSIDIAN_VAULT` for micro wikilink)
- `git/.gitconfig.local` -- profile-specific `[user]` identity
- `zsh/.zshrc.d/<profile>.zsh` -- shell config sourced after base `.zshrc`
- `claude/.claude/settings.json` -- override base Claude settings

## Hyprland Desktop

The desktop environment is configured across five base packages:

| Component | Config | Purpose |
|-----------|--------|---------|
| **Hyprland** | `base/hypr/` | Wayland compositor — tiling, keybindings, hyprpaper, hyprlock |
| **Waybar** | `base/waybar/` | Status bar |
| **Fuzzel** | `base/fuzzel/` | App launcher |
| **Mako** | `base/mako/` | Notifications |
| **Ghostty** | `base/ghostty/` | Terminal emulator |

See `~/.config/hypr/hyprland.conf` for the current keybindings. A full keybinding reference will land in `docs/manual/02-keybindings.md` in Wave 4 of the reorg.

## Adding a New Profile

1. Create `profiles/<name>/`
2. Add a `profile.conf` (set `OBSIDIAN_VAULT` if using micro wikilinks, or leave empty)
3. Add any stow packages you need (e.g. `git/.gitconfig.local`, `zsh/.zshrc.d/<name>.zsh`)
4. Run `./install.sh workstation` (or `./install.sh server` for a headless machine)

The directory layout inside a profile mirrors `$HOME`, same as base packages.

## Common Operations

```bash
# Re-stow base after editing
cd ~/dotfiles && stow -d base -t ~ --no-folding -R zsh

# Re-stow a profile package
cd ~/dotfiles && stow -d profiles/workstation -t ~ --no-folding -R zsh

# Unstow a package
cd ~/dotfiles && stow -d base -t ~ --no-folding -D zsh
```

## Manual Steps

- **SSH keys**: `ssh-keygen -t ed25519` -- never committed to git
- **Oh My Zsh**: installed automatically by `install.sh`
- **Default shell**: `install.sh` runs `chsh -s $(which zsh)`; log out and back in to take effect
- **Google Drive**: `~/gdrive` is a dedicated ext4 partition (`/dev/nvme0n1p8`) mounted via fstab, synced bidirectionally with Google Drive every 15 minutes using `rclone bisync`. Run `rclone config` to set up the `gdrive` remote, then `rclone bisync ~/gdrive gdrive: --resync` for the initial sync. The sync script is at `~/dotfiles/tools/gdrive_sync.sh` and runs via cron. Native Google Docs are skipped (`--drive-skip-gdocs`).
