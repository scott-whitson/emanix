# Chapter 04 — Philosophy

Seven tenets. Each should eliminate at least one decision. The goal is not to be comprehensive — it's to be *decided*.

## 1. Local-first, data-owned

Files live on disk first. Cloud is a backup destination, never the source of truth. Three copies (local, gdrive-bisync, USB-when-built) with zero trust in any single provider.

**What this eliminates:**

- The temptation to cloud-sync dotfiles via Dropbox/iCloud/syncthing-only
- Schemes that treat your machine as a cache of the cloud
- Dependencies on a provider remaining in business

**Concrete consequences:**

- `~/gdrive` is a mounted partition with rclone bisync every 15 minutes, not a streamed-on-demand mount
- `systemd.services.backrest` on datacore (`hosts/datacore/configuration.nix`) runs restic scheduled backups to B2, a point-in-time copy, not a live sync

## 2. NixOS + EWM, no apologies

Declarative base, Emacs-as-desktop. NixOS gives every host the same reproducible
closure; EWM makes Emacs the compositor instead of running a separate window
manager next to it. (Debian + Hyprland was tenet 2 until the 2026-08-07 eminix
convergence retired both.)

**What this eliminates:**

- Distro detection anywhere — the flake is the OS, on every host
- Package drift between machines (`apt upgrade` entropy)
- A separate window-manager config surface alongside the editor
- "Which Debian package has this" package-hunting before a work session

**Concrete consequences:**

- `nixos-rebuild switch --flake .#<host>` is the only apply path
- `profiles/eminix.nix` + `profiles/roles/*.nix` are the bootstrap step — there is no `install.sh`
- `rclone`, `uv`, and the EWM/Emacs build come from nixpkgs (+ the emacs-overlay), not a distro repo

## 3. Terminal-centric, keyboard-driven

Ghostty + Zellij + Emacs + lf. GUI apps are tolerated, not celebrated. Every frequent action has a keybind.

**What this eliminates:**

- "Which GUI menu is this option in?"
- Needing a mouse for any day-to-day task
- File-browser-clicking as a workflow

**Concrete consequences:**

- EWM's own app launcher (`s-d`) is the launcher — no separate keyboard-launcher package
- Emacs is the editor (Helix retired 2026-08-07); other GUI editors are not installed

## 4. AI-augmented by default

pi coding agent is a first-class tool, not a bolt-on. Custom skills and extensions are part of the OS.

**What this eliminates:**

- Treating AI-assisted workflows as an afterthought to configure per-project
- Re-learning your agent layout on a fresh machine

**Concrete consequences:**

- `ioshi/i-intelligence/pi/agent/AGENTS.md` ships with the dotfiles
- `ioshi/i-intelligence/pi.nix` is a dedicated Home Manager module, not folded into a general packages list
- See [Chapter 03 — Tools](03-tools.md#ai-tooling) for the concrete setup

**This is the tenet most specific to this user.** A fork would either adopt a similar AI-augmented workflow or delete `ioshi/i-intelligence/pi.nix` + `ioshi/i-intelligence/pi/` and retire this tenet.

## 5. Reversible and recoverable

Fresh install path is enough: install NixOS, clone the flake, run `nixos-rebuild switch --flake .#<host>`, and verify with `dot-doctor`. No snowflake state that only lives on one laptop.

**What this eliminates:**

- "I'll just tweak this live and remember to commit later" (the source of all snowflakes)
- Fear of reinstalling when the current install gets weird
- The laptop being a single point of failure

**Concrete consequences:**

- `nixos-rebuild switch --flake .#<host>` is idempotent — run it after any manual tweak to re-base
- `dot-doctor` exists to catch drift (21 checks)
- `installer/fresh-eminix-install` (run from the NixOS live ISO) and `installer/eminix-firstboot` (one-time post-install setup: tailnet join, Syncthing pairing, dotfiles clone) cover the recovery path end to end
- `systemd.services.backrest` on datacore runs on its own systemd unit, independent of the laptop

## 6. Modular like Framework

Every piece is swappable. No lock-in to a tool that can't be ripped out in an afternoon.

**What this eliminates:**

- Tools that require data migration to remove (proprietary note-taking apps, etc.)
- Workflows that only work if a specific combination of apps is installed
- Plugin systems that assume everything

**Concrete consequences:**

- The theme system ([Chapter 03](02-theming.md)) is directory-per-theme — remove a theme by deleting a directory
- `bin/dot-*` helpers each do one thing rather than baking several together
- Neovim/kickstart was ripped out entirely (retired in favor of Emacs) without disturbing anything else — proof the modularity holds

## 7. Clear ownership — dotfiles vs datacore-config vs runtime state

The system is split into three layers with hard boundaries. Every file belongs in exactly one place.

**Layer 1: `~/projects/dotfiles`** — Canonical portable user config. Put things here if they should travel with you across machines.

Owns:

- Shell, editor, terminal config
- Shared theme assets
- Pi themes, skills, prompt templates, portable settings
- User-level helper scripts

Rule of thumb: if you'd want the same file on laptop and datacore, it belongs in dotfiles.

**Layer 2: `~/projects/datacore-config`** — Datacore-only application overlay. NixOS (`hosts/datacore/configuration.nix` + the `ioshi/` modules) now owns the substrate — disko/partitioning, sshd, tailscale, native syncthing, and the backrest service are declared there, not in this layer. `datacore-config` owns what sits above the substrate: the Docker Compose app stacks and their host-specific values.

Owns:

- Docker Compose stack definitions and deployment for the ~22 app containers
- `srv/data` layout for those stacks
- Host-specific environment/config values the compose stacks need
- Migration/runbook docs for the app layer
- Validation that dotfiles landed correctly on this host

Where the exact boundary is unclear for a given file (e.g. a script that touches both a systemd unit and a compose stack), default to: if `nixos-rebuild switch` produces or manages it, it belongs in the flake, not here.

**Layer 3: Runtime state** — Generated output, not source. Produced by bootstrap or sync steps, not hand-maintained.

Examples:

- `~/.pi/agent` after Home Manager activation
- System service state, Docker container state
- Syncthing database/state
- IB Gateway runtime files, Honcho runtime data on datacore

**Recovery order for a fresh datacore install:**

1. Install NixOS, join the tailnet, restore host identity and SSH access.
2. Clone the flake and run `nixos-rebuild switch --flake .#datacore` — this brings up disko-managed storage, sshd, tailscale, syncthing, and backrest, and pulls in dotfiles (Layer 1) via Home Manager.
3. Clone or sync `~/projects/datacore-config`.
4. Bring up the Docker Compose app stacks from `datacore-config`.
5. Verify Pi runtime assets are present under `~/.pi/agent`.
6. Verify Pi starts cleanly and theme/skill validation passes.
7. Verify the app stacks and sync clients are healthy.

**Short version:**

- Author portable config in **dotfiles**.
- Author datacore's app-stack config in **datacore-config**.
- Treat `~/.pi/agent` and other live service state as **generated output**.

## What this document is *not*

Not a roadmap. Not a prediction. The tenets describe how decisions are made now. They could change; if they do, rewrite them here.

Tenet edits require a concrete reason: "this tenet led me astray in situation X" or "this tenet no longer matches how I work." Without that, tenet drift is just aesthetic preference.
