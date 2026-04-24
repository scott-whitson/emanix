# Chapter 01 — Install

From an Arch live USB to a running workstation in about an hour. The installer is a ~50-line orchestrator (`install.sh`) that runs 11 modular scripts in order. Each script is independently runnable and idempotent; re-running `./install.sh workstation` is safe.

## Prerequisites

- A clean Arch Linux install with sudo access and a working internet connection
- You know your hostname and timezone
- Optional: an Anthropic API key for the `07-claude.sh` step (can be skipped on first pass)

## Bootstrap

```bash
git clone git@github.com:scott-whitson/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh workstation
```

That's it. The orchestrator exports `DOTFILES` and `PROFILE`, sources `profiles/workstation/profile.conf` if present, then runs every `install/NN-*.sh` in lexical order.

Scripts tagged **workstation only** exit early on other profiles via `skip_unless_profile workstation` — safe to run but a no-op.

## What each script does

| # | Script | Purpose | Interactive? |
|---|--------|---------|---|
| 01 | `01-pacman.sh` | Installs core pacman packages: base-devel, git, stow, zsh, curl/wget/rsync/openssh/gnupg, fzf, zoxide, rclone, rustup, uv, helix, neovim, Noto fonts, JetBrains Mono Nerd font. Initialises rustup stable toolchain if missing. | sudo password |
| 02 | `02-paru.sh` | Bootstraps the paru AUR helper if not already on PATH. Builds from a temp clone of `aur.archlinux.org/paru.git` via `makepkg -si`. No-op if paru is already installed. | sudo password (first run only) |
| 03 | `03-system.sh` | Installs Oh My Zsh (non-interactive, keeps existing .zshrc), clones zsh-autosuggestions and zsh-syntax-highlighting plugins, sets zsh as the default shell via `chsh`, and warns if `pam_systemd_home` auth is active in `/etc/pam.d/system-auth`. | `chsh` may prompt for password |
| 04 | `04-hyprland.sh` | Installs the Hyprland compositor stack: hyprland, hyprlock, hypridle, hyprpaper, xdg-desktop-portal-hyprland, polkit-gnome. **Workstation only** — exits early on other profiles. | sudo password |
| 05 | `05-desktop.sh` | Installs desktop support packages: waybar, mako, fuzzel, ghostty, grim/slurp/wl-clipboard (screenshots), pipewire + wireplumber + pipewire-pulse (audio), brightnessctl, playerctl. **Workstation only.** | sudo password |
| 06 | `06-tools.sh` | Runs `uv sync` on `tools/`, builds the `window-picker` Rust binary (workstation only), installs nvm + Node LTS, and clones kickstart.nvim to `~/.config/nvim` if missing. Appends a theme opt-in line to `nvim/init.lua` (idempotent). | None (all automated) |
| 07 | `07-claude.sh` | Installs the Claude Code CLI via `npm install -g @anthropic-ai/claude-code`. Re-sources nvm so Node is on PATH even when run standalone. Warns if `~/projects/agent-skills` is missing (clone is manual — URL is user-specific). | None |
| 08 | `08-stow-base.sh` | Stows every package under `base/*/` into `$HOME` using `--adopt` + `git checkout -- base/` to absorb and then restore any pre-existing files (e.g. Oh My Zsh's default `.zshrc`). Skips desktop packages (hypr, waybar, mako, ghostty, fuzzel) on non-workstation profiles. | None |
| 09 | `09-stow-profile.sh` | Stows every package under `profiles/$PROFILE/*/` into `$HOME` using `-R` (restow). On conflict with a base package it unstows the base version and retries. | None |
| 10 | `10-theme.sh` | Applies the active theme via `bin/dot-theme-set`. On first run defaults to `catppuccin-mocha`; on re-install re-applies whatever `~/.config/dotfiles/active-theme` records. **Workstation only.** | None |
| 11 | `11-services.sh` | Runs `systemctl --user daemon-reload` then enables and starts every `*.timer` and `*.service` found in `~/.config/systemd/user/` (stowed by step 08). No-op if the unit directory doesn't exist yet. | None |

## Profile guard

Scripts 04, 05, and 10 are workstation-only. On a `server` profile they print a skip message and exit 0. Scripts 01–03 and 06–09 and 11 run on all profiles.

## Idempotence

Re-running `./install.sh workstation` is safe. Every package install uses `--needed`, every git clone checks for an existing populated directory, every stow uses `-R` (restow), every systemd enable uses `--now`. The orchestrator is designed so a fresh install and a re-install follow the same path. The one exception is the `--adopt` + `git checkout` dance in `08-stow-base.sh` — always commit or stash any uncommitted edits to `base/` before re-running the orchestrator.

## Interactive gotchas

- Sudo prompts multiple times (orchestrator does not cache credentials across scripts). Run `sudo -v` in a second terminal to warm the cache, or set `NOPASSWD` for pacman in `/etc/sudoers`.
- `03-system.sh` will warn (but not fix) if `pam_systemd_home` auth is active in `/etc/pam.d/system-auth`. Fix it manually before proceeding: comment out the offending line, then verify with `sudo true`.
- Non-TTY agent contexts cannot drive sudo — the full orchestrator fails early in such environments. See `docs/superpowers/plans/2026-04-24-dotfiles-reorg-wave-2-install-modularization.md` Task 14 notes.

## Failure recovery

Each `install/*.sh` is independently runnable after fixing a problem:

```bash
# Re-run a single script after fixing an issue:
DOTFILES=~/dotfiles PROFILE=workstation bash ~/dotfiles/install/NN-name.sh

# Or re-run the whole orchestrator (always safe):
./install.sh workstation
```

## First-run manual steps

The orchestrator prints these at the end; listed here for completeness:

1. Set up SSH keys: `ssh-keygen -t ed25519`
2. Log out and back in for zsh to take effect
3. If `~/projects/agent-skills` is missing, clone it manually (repo URL is user-specific — see [Chapter 05](05-claude-code.md))

## What the orchestrator does NOT do

- Disk partitioning / bootloader / encryption — see [Chapter 06 — Recovery](06-recovery.md)
- SSH keygen (explicit manual step — never committed)
- Initial rclone bisync for `~/gdrive` (one-time `--resync` run)
- Tailscale enrollment (`sudo tailscale up` after install)
- Kickstart.nvim fork selection — defaults to upstream `nvim-lua/kickstart.nvim`; if you fork on your own GitHub, edit `install/06-tools.sh`'s `KICKSTART_URL` variable
