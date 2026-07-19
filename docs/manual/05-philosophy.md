# Chapter 05 — Philosophy

Seven tenets. Each should eliminate at least one decision. The goal is not to be comprehensive — it's to be *decided*.

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
- `hx`, `rclone`, `uv`, and `hyprland` are installed from Debian packages where available

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
- See [Chapter 04 — Tools](04-tools.md#ai-tooling) for the concrete setup

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

## 7. Clear ownership — dotfiles vs datacore-config vs runtime state

The system is split into three layers with hard boundaries. Every file belongs in exactly one place.

**Layer 1: `~/projects/dotfiles`** — Canonical portable user config. Put things here if they should travel with you across machines.

Owns:

- Shell, editor, terminal config
- Shared theme assets
- Pi themes, skills, prompt templates, portable settings
- User-level helper scripts

Rule of thumb: if you'd want the same file on laptop and datacore, it belongs in dotfiles.

**Layer 2: `~/projects/datacore-config`** — Datacore-only machine overlay and bootstrap orchestration. Put things here if they depend on the host, the Debian install, the network layout, local services, or recovery workflow.

Owns:

- Debian reinstall/bootstrap steps
- System packages for datacore
- Systemd units, `fstab`, mount setup, `srv/data` layout
- Docker stack deployment and runtime state
- Host-specific environment values
- Migration/runbook docs
- Validation that dotfiles landed correctly on this host

**Layer 3: Runtime state** — Generated output, not source. Produced by bootstrap or sync steps, not hand-maintained.

Examples:

- `~/.pi/agent` after bootstrap/stow
- System service state, Docker container state
- Syncthing database/state
- IB Gateway runtime files, Honcho runtime data on datacore

**Recovery order for a fresh Debian install:**

1. Install Debian and basic networking.
2. Restore host identity and SSH access.
3. Bring up storage and system services from `datacore-config`.
4. Clone or sync `~/projects/dotfiles`.
5. Run the dotfiles bootstrap.
6. Verify Pi runtime assets are present under `~/.pi/agent`.
7. Verify Pi starts cleanly and theme/skill validation passes.
8. Bring up datacore services and sync clients.

**Short version:**

- Author portable config in **dotfiles**.
- Author datacore-specific bootstrap in **datacore-config**.
- Treat `~/.pi/agent` and other live service state as **generated output**.

## What this document is *not*

Not a roadmap. Not a prediction. The tenets describe how decisions are made now. They could change; if they do, rewrite them here.

Tenet edits require a concrete reason: "this tenet led me astray in situation X" or "this tenet no longer matches how I work." Without that, tenet drift is just aesthetic preference.
