# Chapter 07 — Philosophy

Six tenets. Each should eliminate at least one decision. The goal is not to be comprehensive — it's to be *decided*.

## 1. Local-first, data-owned

Files live on disk first. Cloud is a backup destination, never the source of truth. Three copies (local, gdrive-bisync, USB-when-built) with zero trust in any single provider.

**What this eliminates:**
- The temptation to cloud-sync dotfiles via Dropbox/iCloud/syncthing-only
- Schemes that treat your machine as a cache of the cloud
- Dependencies on a provider remaining in business

**Concrete consequences:**
- `~/gdrive` is a mounted partition with rclone bisync every 15 minutes, not a streamed-on-demand mount
- `dr_backup.sh` treats the backup as a point-in-time copy, not a live sync

## 2. Debian + Hyprland, no apologies

Stable base, modern desktop. Debian Testing gives you current Hyprland and still keeps the machine boring enough to trust.

**What this eliminates:**
- Distro detection in `install.sh` (it targets Debian now)
- Legacy package-manager paths are gone from the install flow
- Compromise package selections that try to cover two distros at once
- Rolling-release anxiety before a work session

**Concrete consequences:**
- `install.sh` stays short because the distro choice is already made
- `01-core.sh` is the Debian bootstrap step
- `hx`, `rclone`, `uv`, `waybar`, and `hyprland` are installed from Debian packages where available

## 3. Terminal-centric, keyboard-driven

Ghostty + Zellij + Helix/Neovim + lf. GUI apps are tolerated, not celebrated. Every frequent action has a keybind.

**What this eliminates:**
- "Which GUI menu is this option in?"
- Needing a mouse for any day-to-day task
- File-browser-clicking as a workflow

**Concrete consequences:**
- `fuzzel` (keyboard launcher) is in base/, not a mouse-driven app menu
- Helix + kickstart-Neovim are both installed; GUI editors are not

## 4. AI-augmented by default

pi coding agent is a first-class tool, not a bolt-on. Custom skills and extensions are part of the OS.

**What this eliminates:**
- Treating AI-assisted workflows as an afterthought to configure per-project
- Re-learning your agent layout on a fresh machine

**Concrete consequences:**
- `base/pi/.pi/agent/AGENTS.md` ships with the dotfiles
- `install/07-pi.sh` is a dedicated step (not folded into `06-tools.sh`)
- See [Chapter 05 — AI Tooling](05-ai-tooling.md) for the concrete setup

**This is the tenet most specific to this user.** A fork would either adopt a similar AI-augmented workflow or delete `base/pi/` and retire this tenet.

## 5. Reversible and recoverable

Fresh Debian reinstall path is enough: join Headscale, clone dotfiles from datacore, run `./bootstrap.sh`, and verify with `dot-doctor`. No snowflake state that only lives on one laptop.

**What this eliminates:**
- "I'll just tweak this live and remember to commit later" (the source of all snowflakes)
- Fear of reinstalling when the current install gets weird
- The laptop being a single point of failure

**Concrete consequences:**
- `./install.sh` is idempotent — run it after any manual tweak to re-base
- `dot-doctor` exists to catch drift (17 checks, Debian port verified 2026-06-01)
- `dr_backup.sh` runs on a systemd timer

## 6. Modular like Framework

Every piece is swappable. No lock-in to a tool that can't be ripped out in an afternoon.

**What this eliminates:**
- Tools that require data migration to remove (proprietary note-taking apps, etc.)
- Workflows that only work if a specific combination of apps is installed
- Plugin systems that assume everything

**Concrete consequences:**
- The theme system ([Chapter 03](03-theming.md)) is directory-per-theme — remove a theme by deleting a directory
- `bin/dot-*` helpers each do one thing; `dot-update` composes `apt full-upgrade` + `dot-restow --all` rather than baking them together
- Kickstart.nvim is a separate repo, not a stow package — so you can ditch it without disturbing the dotfiles

## What this document is *not*

Not a roadmap. Not a prediction. The tenets describe how decisions are made now. They could change; if they do, rewrite them here.

Tenet edits require a concrete reason: "this tenet led me astray in situation X" or "this tenet no longer matches how I work." Without that, tenet drift is just aesthetic preference.
