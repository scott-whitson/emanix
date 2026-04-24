# dotfiles

Scott Whitson's personal Linux setup. Arch + Hyprland. Opinionated, documented, reversible.

This is a private repo built for one user, but written as if a stranger could fork it. See [`docs/manual/08-roll-your-own.md`](docs/manual/08-roll-your-own.md) if you're that stranger.

## Quickstart

```bash
git clone git@github.com:scott-whitson/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh workstation
```

On first install, that's the full path from fresh Arch to a running Hyprland workstation with Catppuccin Mocha applied. Subsequent runs are idempotent no-ops.

## Philosophy

Six tenets. Read [`docs/manual/07-philosophy.md`](docs/manual/07-philosophy.md) for the expanded version:

1. Local-first, data-owned
2. Arch + Hyprland, no apologies
3. Terminal-centric, keyboard-driven
4. AI-augmented by default (Claude Code is a first-class tool)
5. Reversible and recoverable
6. Modular like Framework

## Manual

| Chapter | Topic |
|---|---|
| [01 — Install](docs/manual/01-install.md) | Fresh Arch → running workstation |
| [02 — Keybindings](docs/manual/02-keybindings.md) | Every binding, by surface |
| [03 — Theming](docs/manual/03-theming.md) | Theme system + `dot-theme-set` + `dot-theme-toggle` |
| [04 — Tools](docs/manual/04-tools.md) | `tools/` uv project + `bin/dot-*` helpers |
| [05 — Claude Code](docs/manual/05-claude-code.md) | Plugins, skills, agent-skills |
| [06 — Recovery](docs/manual/06-recovery.md) | Dead laptop → functional in <1 hour |
| [07 — Philosophy](docs/manual/07-philosophy.md) | The 6 tenets, expanded |
| [08 — Roll Your Own](docs/manual/08-roll-your-own.md) | Fork guide |

## Structure

```
~/dotfiles/
├── install.sh               # ~50-line orchestrator
├── install/                 # modular NN-<name>.sh scripts
├── bin/                     # dot-* helpers (on $PATH via zshrc.d)
├── base/                    # stow packages for every profile
├── profiles/                # workstation + server
├── themes/                  # catppuccin-mocha + catppuccin-latte
├── tools/                   # uv project + Rust window-picker
├── recovery/                # disaster-recovery runbook
├── docs/                    # this manual + specs + plans
└── .claude/                 # Claude Code skills/plugins specific to this repo
```

## Status

- **Last reorg:** Wave 4 docs overhaul, 2026-04-24
- **Active theme:** catppuccin-mocha (toggle with `$mod+Shift+T`)
- **Health check:** `dot-doctor` (17 checks)
- **License:** none — private repo
