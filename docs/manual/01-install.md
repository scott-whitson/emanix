# Chapter 01 — Install

From a clean Debian Testing install to a running desktop in about an hour. The installer is a numbered orchestrator (`install.sh`) that runs scripts in lexical order. Each script is independently runnable and idempotent; re-running `./install.sh` is safe.

## Prerequisites

- Clean Debian install with sudo access and a working internet connection
- Know your hostname and timezone
- Datacore bootstrap portal reachable from the machine

## Bootstrap

Preferred blank-machine flow:

```bash
./ventoy/bootstrap.sh \
  --datacore-url https://datacore.example \
  --device-name fjord \
  --role desktop
```

That flow phones home to datacore, opens verification URL, gets a short-lived bootstrap token, installs SSH trust bundle, joins Headscale, fetches dotfiles, and then hands off to repo `./bootstrap.sh`.

Existing installed machine can still use direct clone:

```bash
git clone scott@datacore:~/projects/dotfiles ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

The repo orchestrator exports `DOTFILES`, then runs every `install/NN-*.sh` in lexical order.
Git-based fetches try datacore mirror first, then fall back to upstream if mirror missing.

### Host path convention

Use these paths consistently:

- `~/projects/<name>` on datacore: canonical projects
- `~/lab/<name>` on non-canonical developer machines: editable mirrors you can experiment in
- runtime-only products on zord: install to system/user locations, not `~/projects`

Fragpaper on zord is the example of a runtime-only product: it should run as a service and does not require a `~/projects/fragpaper` checkout unless you are deliberately developing it there.

## fjord sample run

Use this as a clean reinstall exercise on `fjord`.

1. Boot Debian, mount Ventoy USB, and start datacore bootstrap:

   ```bash
   ./ventoy/bootstrap.sh \
     --datacore-url https://datacore.example \
     --device-name fjord \
     --role desktop
   ```

2. Open datacore verification URL, sign in, and approve device.

3. Let script install SSH trust, join Headscale, fetch dotfiles, and run repo bootstrap.

4. Verify install:

   ```bash
   dot-doctor
   ```

If you already have a working clone, skip Ventoy and just `cd ~/dotfiles` before `./bootstrap.sh`.

## Host classes

The installer branches by host class:

- `server` — canonical projects host; includes IB Gateway
- `workstation` — Hyprland + desktop apps + user services

## What each script does

| # | Script | Purpose | Interactive? |
|---|---|---|---|
| 01 | `01-core.sh` | Installs core Debian packages: build-essential, cargo, rustc, pkg-config, libgtk-4-dev, libadwaita-1-dev, libgtk4-layer-shell-dev, blueprint-compiler, libnotify-bin, git, stow, zsh, curl/wget/unzip/rsync/openssh-client/gnupg, jq, nodejs, npm, fzf, zoxide, rclone, hx, neovim, qalc, syncthing, Noto fonts. Then installs `uv` from apt if available, else the official binary installer; installs JetBrains Mono from apt if available, else a Nerd Font fallback in `~/.local/share/fonts/`. | sudo password |
| 03 | `03-system.sh` | Installs Oh My Zsh (non-interactive, keeps existing `.zshrc`), clones zsh-autosuggestions and zsh-syntax-highlighting plugins, sets zsh as the default shell via `chsh`, and warns if `pam_systemd_home` auth is active anywhere under `/etc/pam.d/`. | `chsh` may prompt |
| 04 | `04-hyprland.sh` | Workstation-only. Installs the Hyprland compositor stack: hyprland, hyprlock, hypridle, hyprpaper, xdg-desktop-portal-hyprland, hyprpolkitagent. `hyprland-guiutils` is best-effort when available. | sudo password |
| 05 | `05-desktop.sh` | Workstation-only. Installs desktop support packages: Firefox ESR, Obsidian, waybar, mako-notifier, fuzzel, ghostty (via Debian repo fallback if needed), grim/slurp/wl-clipboard, PipeWire + WirePlumber + pipewire-pulse, brightnessctl, playerctl, mpv, ffmpeg + libavcodec-extra + gstreamer1.0-libav, Syncthing, plus a backlight udev trigger + root service so brightness keys work without root. `mpv` is required by the weather and cheatsheet popups. | sudo password |
| 06 | `06-tools.sh` | Runs `uv sync` on `tools/`, builds `window-picker` after installing the GTK layer-shell dev dependency, checks Node/npm from apt, and handles fragpaper as a product cache: server keeps `~/projects/fragpaper`, workstations use `~/.local/share/fragpaper` and avoid `~/projects`. It also clones kickstart.nvim to `~/.config/nvim` if missing. Appends the theme opt-in line to `init.lua` (idempotent). | None |
| 07 | `07-pi.sh` | Installs the pi coding agent via `npm install -g --prefix ~/.local @earendil-works/pi-coding-agent`. Uses system Node/npm from apt. | None |
| 08 | `08-stow-base.sh` | Stows every package under `base/*/` into `$HOME` using `--adopt`; auto-stashes any existing `base/` edits, then restores them after stow so install can continue. | None |
| 10 | `10-theme.sh` | Applies the active theme via `bin/dot-theme-set`. On first run defaults to `catppuccin-mocha`; on re-install re-applies whatever `~/.config/dotfiles/active-theme` records. | None |
| 11 | `11-services.sh` | Runs `systemctl --user daemon-reload` then enables and starts every `*.timer` and `*.service` found in `~/.config/systemd/user/`. Server-only IB units are skipped on workstations. | None |
| 12 | `12-ibgateway.sh` | Server-only. Installs IB Gateway + IBC into `/opt`, writes per-user config templates, and prints next steps on the server; skips on workstations. | sudo for `/opt` writes |

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

The orchestrator prints this at the end; listed here for completeness:

1. Log out and back in for zsh to take effect
2. Reboot, then run `dot-doctor`

## What the orchestrator does NOT do

- Disk partitioning / bootloader / encryption — see [Chapter 06 — Recovery](06-recovery.md)
- SSH trust bootstrap is handled by Ventoy (it generates and registers the machine key during enrollment)
- Tailscale enrollment inside repo install (`sudo tailscale up`); Ventoy bootstrap handles enrollment before handing off
- Kickstart.nvim fork selection — defaults to upstream `nvim-lua/kickstart.nvim`; if you fork on your own GitHub, edit `install/06-tools.sh`'s `KICKSTART_URL`
