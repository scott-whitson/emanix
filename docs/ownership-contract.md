# Repo Ownership Contract

This document defines what belongs in `~/projects/dotfiles`, what belongs in `~/projects/datacore-config`, and what should only exist as generated runtime state.

## Goal

Keep one source of truth for portable user config, one place for datacore-specific host setup, and one place for installed runtime state.

## Layer 1: `~/projects/dotfiles`

**Canonical portable user config.**

Put things here if they should travel with Scott across machines.

### Owns

- shell config
- editor config
- terminal config
- shared theme assets
- Pi themes
- Pi skills
- Pi prompt templates
- Pi settings that should be consistent on laptop and datacore
- user-level helper scripts

### Rule of thumb

If you would want the same file on the laptop and on datacore, it belongs in dotfiles.

### Pi-specific examples

- `base/pi/.pi/agent/settings.json`
- `base/pi/.pi/agent/themes/*.json`
- `base/pi/.pi/agent/skills/*`
- `base/pi/.pi/agent/extensions/*` when the extension is user-portable

## Layer 2: `~/projects/datacore-config`

**Datacore-only machine overlay and bootstrap orchestration.**

Put things here if they depend on the host, the Debian install, the network layout, local services, storage, or recovery workflow.

### Owns

- Debian reinstall/bootstrap steps
- system packages for datacore
- systemd units
- `/etc/fstab` and mount setup
- `/srv/data` and related server storage layout
- Docker stack deployment and runtime state management
- datacore-only services
- host-specific environment values
- migration/runbook docs
- glue that invokes dotfiles bootstrap on datacore
- validation steps that confirm dotfiles landed correctly on this host

### Rule of thumb

If the file exists because of datacore hardware or datacore services, it belongs here.

### Important distinction

`datacore-config` should **not** become the second copy of portable dotfiles content.

Instead, it should:
- call the dotfiles bootstrap,
- set datacore-specific environment and paths,
- ensure the machine gets the right runtime services,
- validate that Pi assets and other user config were installed,
- and document the restore order.

## Layer 3: runtime state

**Generated output, not source.**

These should be produced by bootstrap or sync steps, not hand-maintained.

### Examples

- `~/.pi/agent` after bootstrap/stow
- system service state
- Docker container state
- Syncthing database/state
- IB Gateway runtime files
- Honcho runtime data on datacore

## Practical ownership table

| Item | Canonical home | Why |
|---|---|---|
| Pi themes | `~/projects/dotfiles` | portable user preference |
| Pi skills | `~/projects/dotfiles` | portable behavior package |
| Pi settings | `~/projects/dotfiles` | portable runtime config |
| Pi bootstrap wiring | `~/projects/datacore-config` | host-specific install order and recovery |
| Pi runtime verification | `~/projects/datacore-config` | confirms the portable assets landed on datacore |
| Theme installation target | generated runtime state | should land in `~/.pi/agent` |
| Datacore systemd units | `~/projects/datacore-config` | machine-only services |
| `/srv/data` layout | `~/projects/datacore-config` | datacore storage model |
| Docker stack compose files | `~/projects/datacore-config` | datacore services |
| Laptop shell/editor config | `~/projects/dotfiles` | portable across machines |
| Debian reinstall runbook | `~/projects/datacore-config` | datacore-specific recovery |

## Recovery order for a fresh datacore Debian install

1. Install Debian and basic networking.
2. Restore datacore host identity and SSH access.
3. Bring up the datacore storage and system services from `datacore-config`.
4. Clone or sync `~/projects/dotfiles`.
5. Run the dotfiles bootstrap so user config is installed.
6. Verify Pi runtime assets are present under `~/.pi/agent`.
7. Verify Pi starts cleanly and theme/skill validation passes.
8. Bring up datacore services and sync clients.

## Short version

- **Author portable config in dotfiles.**
- **Author datacore-specific bootstrap in datacore-config.**
- **Treat `~/.pi/agent` and other live service state as generated output.**

## Note on the Pi fix

The Pi themes and the vaultkeeper skill live in `dotfiles` because they are portable user config.
`datacore-config` should only validate that the assets were installed correctly on this machine.
