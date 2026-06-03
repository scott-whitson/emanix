# Chapter 01 — Install

From a clean Debian Testing install to a running Hyprland desktop in about an hour. The installer is a ~30-line orchestrator (`install.sh`) that runs numbered scripts in lexical order. Each script is independently runnable and idempotent; re-running `./install.sh` is safe.

## Prerequisites

- Clean Debian install with sudo access and a working internet connection
- Know your hostname and timezone
- SSH access back to `datacore`

## Bootstrap

```bash
git clone scott@datacore:~/projects/dotfiles ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

That’s it. The orchestrator exports `DOTFILES`, then runs every `install/NN-*.sh` in lexical order.
Git-based fetches try datacore mirror first, then fall back to upstream if mirror missing.

## What each script does

| # | Script | Purpose | Interactive? |
|---|---|---|---|
| 01 | `01-core.sh` | Installs core Debian packages: build-essential, cargo, rustc, pkg-config, libgtk-4-dev, libadwaita-1-dev, blueprint-compiler, libnotify-bin, git, stow, zsh, curl/wget/unzip/rsync/openssh-client/gnupg, fzf, zoxide, rclone, hx, neovim, qalc, Noto fonts. Then installs `uv` from apt if available, else the official binary installer; installs JetBrains Mono from apt if available, else a Nerd Font fallback in `~/.local/share/fonts/`. | sudo password |
| 03 | `03-system.sh` | Installs Oh My Zsh (non-interactive, keeps existing `.zshrc`), clones zsh-autosuggestions and zsh-syntax-highlighting plugins, sets zsh as the default shell via `chsh`, and warns if `pam_systemd_home` auth is active anywhere under `/etc/pam.d/`. | `chsh` may prompt |
| 04 | `04-hyprland.sh` | Installs Hyprland compositor stack: hyprland, hyprlock, hypridle, hyprpaper, xdg-desktop-portal-hyprland, hyprpolkitagent. | sudo password |
| 05 | `05-desktop.sh` | Installs desktop support packages: Firefox ESR, Obsidian, waybar, mako-notifier, fuzzel, ghostty (via Debian repo fallback if needed), grim/slurp/wl-clipboard, PipeWire + WirePlumber + pipewire-pulse, brightnessctl, playerctl. | sudo password |
| 06 | `06-tools.sh` | Runs `uv sync` on `tools/`, builds `window-picker`, checks Node/npm from apt, clones fragpaper, and clones kickstart.nvim to `~/.config/nvim` if missing. Appends the theme opt-in line to `init.lua` (idempotent). | None |
| 07 | `07-pi.sh` | Installs pi coding agent via `npm install -g --prefix ~/.local @earendil-works/pi-coding-agent`. Uses system Node/npm from apt. | None |
| 08 | `08-stow-base.sh` | Stows every package under `base/*/` into `$HOME` using `--adopt`; auto-stashes any existing `base/` edits, then restores them after stow so install can continue. | None |
| 10 | `10-theme.sh` | Applies the active theme via `bin/dot-theme-set`. On first run defaults to `catppuccin-mocha`; on re-install re-applies whatever `~/.config/dotfiles/active-theme` records. | None |
| 11 | `11-services.sh` | Runs `systemctl --user daemon-reload` then enables and starts every `*.timer` and `*.service` found in `~/.config/systemd/user/`. | None |
| 12 | `12-ibgateway.sh` | Datacore-only. Installs IB Gateway + IBC into `/opt`, writes per-user config templates, and prints next steps on datacore; skips on fjord and other non-gateway hosts. | sudo for `/opt` writes |

## Idempotence

Re-running `./install.sh` is safe. Every package install uses `--needed`, every git clone checks for an existing populated directory, every stow uses `-R` (restow), every systemd enable uses `--now`. The orchestrator is designed so a fresh install and a re-install follow the same path. The one exception is the `--adopt` + `git checkout` dance in `08-stow-base.sh` — commit or stash any uncommitted edits to `base/` before re-running the orchestrator.

## Interactive gotchas

- Sudo prompts multiple times. Run `sudo -v` in a second terminal to warm the cache.
- `03-system.sh` will warn (but not fix) if `pam_systemd_home` auth is active anywhere under `/etc/pam.d/`. Fix it manually before proceeding: comment out the offending line, then verify with `sudo true`.
- Non-TTY agent contexts cannot drive sudo — the full orchestrator fails early in such environments.

## Failure recovery

Each `install/*.sh` is independently runnable after fixing a problem:

```bash
# Re-run a single script after fixing an issue:
DOTFILES=~/dotfiles bash ~/dotfiles/install/NN-name.sh

# Or use repo helpers from repo root:
#   ./repair.sh 05-desktop
#   ./repair.sh --all
#   ./bootstrap.sh

# Or re-run the whole orchestrator (always safe):
./install.sh
```

## First-run manual steps

The orchestrator prints these at the end; listed here for completeness:

1. Set up SSH keys: `ssh-keygen -t ed25519`
2. Log out and back in for zsh to take effect

## What the orchestrator does NOT do

- Disk partitioning / bootloader / encryption — see [Chapter 06 — Recovery](06-recovery.md)
- SSH keygen (explicit manual step — never committed)
- Tailscale enrollment (`sudo tailscale up` after install)
- Kickstart.nvim fork selection — defaults to upstream `nvim-lua/kickstart.nvim`; if you fork on your own GitHub, edit `install/06-tools.sh`'s `KICKSTART_URL`
