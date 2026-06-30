# dotfiles

Scott Whitson's personal Linux setup. Debian + Hyprland. Opinionated, documented, reversible.

This is a private repo built for one user, but written as if a stranger could fork it. See [`docs/manual/06-roll-your-own.md`](docs/manual/06-roll-your-own.md) if you're that stranger.

## Path conventions

- **`~/projects` on datacore** — canonical source trees
- **`~/docs` on every synced machine** — Syncthing mirror for vault / personal docs
- **`~/projects/datacore-config` on datacore** — machine-specific bootstrap, service wiring, and runtime overlay for this host
- **`~/lab` on secondary dev machines** — non-canonical editable mirrors; `dot-bootstrap` creates the root `~/lab` directory for you so you have one consistent place to put them
- **Installed products** — runtime-only deployments on machines like zord; no project checkout required unless you are actively developing that product

Top-level `/home/scott` should stay sparse: docs, projects, and dotfiles/runtime config only. Anything transient should be archived or moved into a service-owned tree.

## Quickstart

Existing Debian box:

```bash
git clone scott@datacore:~/projects/dotfiles ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

Fresh box or reinstall:

```bash
./ventoy/bootstrap.sh --datacore-url https://datacore.example --device-name fjord --role desktop
```

That flow phones home to datacore, gets a short-lived bootstrap token, installs SSH trust, joins Headscale, transfers dotfiles, and hands off to `./bootstrap.sh`.
When it finishes, reboot and run `dot-doctor`.
For a datacore reinstall, follow `~/projects/datacore-config/RECOVERY.md` after the dotfiles bootstrap.
Git-based fetches still try datacore mirror first, then upstream if mirror missing.

## Philosophy

Seven tenets. Read [`docs/manual/05-philosophy.md`](docs/manual/05-philosophy.md) for the expanded version:

1. Local-first, data-owned
2. Debian + Hyprland, no apologies
3. Terminal-centric, keyboard-driven
4. AI-augmented by default (pi coding agent)
5. Reversible and recoverable
6. Modular like Framework
7. Clear ownership — dotfiles vs datacore-config vs runtime state

## Manual

| Chapter | Topic |
|---|---|
| [01 — Install](docs/manual/01-install.md) | Fresh Debian Testing → running workstation |
| [02 — Keybindings](docs/manual/02-keybindings.md) | Every binding, by surface |
| [03 — Theming](docs/manual/03-theming.md) | Theme system + `dot-theme-set` + `dot-theme-toggle` |
| [04 — Tools](docs/manual/04-tools.md) | `tools/` uv project + `bin/dot-*` helpers, plus AI tooling |
| [05 — Philosophy](docs/manual/05-philosophy.md) | 7 tenets + ownership model |
| [06 — Roll Your Own](docs/manual/06-roll-your-own.md) | Fork guide |

## Structure

```
~/dotfiles/
├── bootstrap.sh             # fresh-clone entrypoint
├── repair.sh                # rerun install scripts
├── ventoy/                  # USB bootstrap kit
├── install.sh               # ~30-line orchestrator
├── install/                 # modular NN-<name>.sh scripts
├── bin/                     # dot-* helpers (on $PATH via zshrc.d)
├── base/                    # stow packages
├── themes/                  # catppuccin-mocha + catppuccin-latte
├── tools/                   # uv project + Rust window-picker
└── docs/                    # manual
```

## Status

- **Last reorg:** docs consolidation, 2026-06-30
- **Active theme:** catppuccin-mocha (toggle with `$mod+Shift+T`)
- **Health check:** `dot-doctor`
- **IB Gateway:** datacore-only; manual restart because relogin can trigger MFA
- **Firefox + Obsidian:** first-class desktop apps; install flow brings them up on a fresh Debian box
- **Bootstrap helpers:** `bootstrap.sh` / `repair.sh` for fresh-clone flow; `dot-bootstrap` / `dot-repair` for shell PATH flow
- **Pi assets:** canonical Pi themes/skills/settings live under `base/pi/`; datacore validates them during bootstrap
- **Installed products:** fragpaper runs as a user service on zord; it is treated as a runtime product, not a project checkout
- **Lab checkouts:** use `~/lab/<name>` for intentionally non-canonical mirrors you want to edit on secondary machines
- **Ventoy kit:** `ventoy/bootstrap.sh` for datacore enrollment + dotfiles bootstrap on blank machines
- **License:** none — private repo
