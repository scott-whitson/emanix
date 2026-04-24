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

## 2. Arch + Hyprland, no apologies

Bleeding-edge is a feature, not a bug. Rolling release matches how you work.

**What this eliminates:**
- Distro detection in `install.sh` (it's Arch-only now)
- Ubuntu/Debian fallback code (deleted in Wave 2)
- Sway/Wofi/Kitty legacy (deleted in Wave 1)
- Compromise package selections that worked across both (just pick the best Arch package)

**Concrete consequences:**
- `install.sh` is 49 lines. If it were distro-agnostic, it would be 200+.
- `01-pacman.sh` can list `helix`, `neovim`, `rclone`, `uv` without worrying whether a given Debian version ships them

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

Claude Code is a first-class tool, not a bolt-on. Custom skills, plugins, and the `agent-skills` project are part of the OS.

**What this eliminates:**
- Treating AI-assisted workflows as an afterthought to configure per-project
- Re-learning your Claude plugin layout on a fresh machine

**Concrete consequences:**
- `base/claude/.claude/settings.json` ships with the dotfiles
- `install/07-claude.sh` is a dedicated step (not folded into `06-tools.sh`)
- See [Chapter 05 — Claude Code](05-claude-code.md) for the concrete setup

**This is the tenet most specific to this user.** A fork would either adopt a similar AI-augmented workflow or delete `base/claude/` and retire this tenet.

## 5. Reversible and recoverable

`recovery/` directory exists. Any machine is rebuildable from the repo in <1 hour. No snowflake state that only lives on one laptop.

**What this eliminates:**
- "I'll just tweak this live and remember to commit later" (the source of all snowflakes)
- Fear of reinstalling when the current install gets weird
- The laptop being a single point of failure

**Concrete consequences:**
- `./install.sh workstation` is idempotent — run it after any manual tweak to re-base
- `dot-doctor` exists to catch drift (17 checks, last verified 2026-04-24)
- `dr_backup.sh` runs on a systemd timer

## 6. Modular like Framework

Every piece is swappable. No lock-in to a tool that can't be ripped out in an afternoon.

**What this eliminates:**
- Tools that require data migration to remove (proprietary note-taking apps, etc.)
- Workflows that only work if a specific combination of apps is installed
- Plugin systems that assume everything

**Concrete consequences:**
- The theme system ([Chapter 03](03-theming.md)) is directory-per-theme — remove a theme by deleting a directory
- `bin/dot-*` helpers each do one thing; `dot-update` composes `paru -Syu` + `dot-restow --all` rather than baking them together
- Kickstart.nvim is a separate repo, not a stow package — so you can ditch it without disturbing the dotfiles

## What this document is *not*

Not a roadmap. Not a prediction. The tenets describe how decisions are made now. They could change; if they do, rewrite them here.

Tenet edits require a concrete reason: "this tenet led me astray in situation X" or "this tenet no longer matches how I work." Without that, tenet drift is just aesthetic preference.
