# dotfiles

Scott Whitson's personal Linux setup. Debian + Hyprland. Opinionated, documented, reversible.

This is a private repo built for one user, but written as if a stranger could fork it. See [`docs/manual/08-roll-your-own.md`](docs/manual/08-roll-your-own.md) if you're that stranger.

## Quickstart

```bash
git clone scott@datacore:~/projects/dotfiles ~/dotfiles
cd ~/dotfiles
./install.sh
```

Fresh install path: Debian Testing → recover root access → join Headscale → `ssh datacore` → run `./install.sh` → Hyprland + tools.
Git-based fetches try datacore mirror first, then upstream fallback.

## Philosophy

Six tenets. Read [`docs/manual/07-philosophy.md`](docs/manual/07-philosophy.md) for the expanded version:

1. Local-first, data-owned
2. Debian + Hyprland, no apologies
3. Terminal-centric, keyboard-driven
4. AI-augmented by default (pi coding agent)
5. Reversible and recoverable
6. Modular like Framework

## Manual

| Chapter | Topic |
|---|---|
| [01 — Install](docs/manual/01-install.md) | Fresh Debian Testing → running workstation |
| [02 — Keybindings](docs/manual/02-keybindings.md) | Every binding, by surface |
| [03 — Theming](docs/manual/03-theming.md) | Theme system + `dot-theme-set` + `dot-theme-toggle` |
| [04 — Tools](docs/manual/04-tools.md) | `tools/` uv project + `bin/dot-*` helpers |
| [05 — AI Tooling](docs/manual/05-ai-tooling.md) | pi coding agent + skills |
| [06 — Recovery](docs/manual/06-recovery.md) | Archived recovery notes |
| [07 — Philosophy](docs/manual/07-philosophy.md) | The 6 tenets, expanded |
| [08 — Roll Your Own](docs/manual/08-roll-your-own.md) | Fork guide |

## Structure

```
~/dotfiles/
├── install.sh               # ~30-line orchestrator
├── install/                 # modular NN-<name>.sh scripts
├── bin/                     # dot-* helpers (on $PATH via zshrc.d)
├── base/                    # stow packages
├── themes/                  # catppuccin-mocha + catppuccin-latte
├── tools/                   # uv project + Rust window-picker
├── recovery/                # disaster-recovery runbook
└── docs/                    # manual + specs + plans
```

## Status

- **Last reorg:** Debian port + recovery cleanup, 2026-06-01
- **Active theme:** catppuccin-mocha (toggle with `$mod+Shift+T`)
- **Health check:** `dot-doctor`
- **IB Gateway:** datacore-only; manual restart because relogin can trigger MFA
- **Firefox + Obsidian:** first-class desktop apps; install flow should bring them up on a fresh Debian box
- **License:** none — private repo
