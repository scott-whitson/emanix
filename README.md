# dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/) and a multi-profile system. One shared base config, with profile-specific overrides for different machines. Supports both Debian/Ubuntu (WSL) and Arch Linux (native).

## Quick Start

```bash
git clone git@github.com:scottwhitson/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh <profile>
```

The install script detects your distro (`apt` vs `pacman`), installs system packages and developer tools, stows the base config, then layers the chosen profile on top.

## Structure

```
~/dotfiles/
├── install.sh              # bootstrap script: ./install.sh <profile>
├── base/                   # shared config, applied to every machine
│   ├── zsh/.zshrc          # Oh My Zsh, aliases, tools; sources ~/.zshrc.d/*.zsh
│   ├── git/.gitconfig      # core git settings; includes ~/.gitconfig.local
│   ├── micro/              # keybindings (wikilink plugin)
│   ├── claude/             # Claude Code settings (full plugin set)
│   ├── sway/               # Sway compositor (Arch only)
│   ├── waybar/             # status bar config + theme (Arch only)
│   ├── wofi/               # app launcher config + theme (Arch only)
│   ├── mako/               # notification daemon (Arch only)
│   ├── kitty/              # terminal emulator (Arch only)
│   └── windows/            # Windows-side configs (GlazeWM, etc.) — see below
└── profiles/
    ├── personal/           # WSL / personal machine
    ├── arch-personal/      # Arch Linux / personal laptop
    ├── work/               # work machine
    └── server/             # headless / remote server
```

**Base** is stowed first with `--no-folding`, so directories like `~/.zshrc.d/` and `~/.claude/` are real directories (not symlinks). Profile packages then add or replace files inside those same directories.

Desktop packages (`sway`, `waybar`, `wofi`, `mako`, `kitty`) are only stowed on Arch.

## Profiles

| Profile | Distro | What it adds |
|---------|--------|-------------|
| `personal` | Debian/WSL | Personal git identity, Obsidian vault path, ollama, jrnl, Google Drive via drvfs |
| `arch-personal` | Arch | Personal git identity, Obsidian vault path, ollama, jrnl, Google Drive via rclone |
| `work` | Debian/WSL | Work git identity, work Obsidian vault path |
| `server` | Any | Server git identity, trimmed Claude Code plugin set (no playwright, frontend-design, rust-analyzer) |

Each profile can include:
- `profile.conf` -- variables sourced by `install.sh` (e.g. `OBSIDIAN_VAULT` for micro wikilink)
- `git/.gitconfig.local` -- profile-specific `[user]` identity
- `zsh/.zshrc.d/<profile>.zsh` -- shell config sourced after base `.zshrc`
- `claude/.claude/settings.json` -- override base Claude settings

## Distro Support

The install script auto-detects the distro via `/etc/os-release`:

| | Debian/Ubuntu/WSL | Arch/EndeavourOS/Manjaro |
|---|---|---|
| **Package manager** | apt | pacman |
| **Dev tools** | Installed via curl scripts | Installed via pacman (zoxide, micro, zellij, rustup, uv) |
| **Desktop** | N/A (WSL uses Windows WM) | Sway + Waybar + Wofi + Mako + Kitty |
| **Nerd Font** | N/A | ttf-jetbrains-mono-nerd via pacman |

## Sway Desktop (Arch)

The desktop environment is configured across five base packages with a cohesive dark theme (Tokyo Night-inspired):

| Component | Config | Purpose |
|-----------|--------|---------|
| **Sway** | `base/sway/` | Wayland compositor — tiling, keybindings, swayidle/swaylock |
| **Waybar** | `base/waybar/` | Status bar — workspaces, clock, battery, network, audio, cpu/memory |
| **Wofi** | `base/wofi/` | App launcher |
| **Mako** | `base/mako/` | Notifications |
| **Kitty** | `base/kitty/` | Terminal emulator |

Key bindings (vim-style):

| Binding | Action |
|---------|--------|
| `Super + H/J/K/L` | Focus left/down/up/right |
| `Super + Shift + H/J/K/L` | Move window |
| `Super + R` | Enter resize mode (H/J/K/L to resize) |
| `Super + 1-9` | Switch workspace |
| `Super + Shift + 1-9` | Move window to workspace |
| `Super + A/S` | Previous/next workspace |
| `Super + Return` | Kitty terminal |
| `Super + D` | Wofi launcher |
| `Super + W` | Firefox |
| `Super + F` | Fullscreen |
| `Super + Shift + Q` | Close window |
| `Super + Shift + Space` | Toggle floating |
| `Super + -` | Show scratchpad |
| `Super + Escape` | Lock screen |
| `Print` | Screenshot region to clipboard |

## Adding a New Profile

1. Create `profiles/<name>/`
2. Add a `profile.conf` (set `OBSIDIAN_VAULT` if using micro wikilinks, or leave empty)
3. Add any stow packages you need (e.g. `git/.gitconfig.local`, `zsh/.zshrc.d/<name>.zsh`)
4. Run `./install.sh <name>`

The directory layout inside a profile mirrors `$HOME`, same as base packages.

## Common Operations

```bash
# Re-stow base after editing
cd ~/dotfiles && stow -d base -t ~ --no-folding -R zsh

# Re-stow a profile package
cd ~/dotfiles && stow -d profiles/personal -t ~ --no-folding -R zsh

# Unstow a package
cd ~/dotfiles && stow -d base -t ~ --no-folding -D zsh
```

## Windows Configs

Windows-side configs (GlazeWM, AutoHotkey, etc.) live in `base/windows/` but can't be stowed since they target `C:\Users\scott`, not `~`. Use the sync script instead:

```bash
./sync-windows.sh
```

This copies configs to the Windows home directory. Reload GlazeWM after syncing with `lwin+shift+r`.

## Manual Steps

- **SSH keys**: `ssh-keygen -t ed25519` -- never committed to git
- **Oh My Zsh**: installed automatically by `install.sh`
- **Default shell**: `install.sh` runs `chsh -s $(which zsh)`; log out and back in to take effect
- **rclone** (Arch): run `rclone config` to set up a `gdrive` remote for Google Drive
