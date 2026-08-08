# Chapter 06 — Nix Architecture

> **Status:** Done. This chapter used to be the Debian→NixOS migration plan; the
> migration completed 2026-08-07 (see `docs/superpowers/specs/2026-08-07-eminix-convergence-design.md`
> for the as-built decision record). What follows describes the system as it
> actually runs today, not a plan for one.

## eminix is a distribution, not a machine

`profiles/eminix.nix` is the **common core**: everything true of every host
regardless of shape (base OS settings, Tailscale, SSH, agenix secrets). It is
never a hostname — `eminix` names the platform, full stop.

## Roles supply the shape

`profiles/roles/` holds one file per machine shape, layered on top of the core:

```
profiles/
  eminix.nix              common core: os base + net + secrets
  roles/
    workstation.nix        desktop + EWM + Ollama — the daily-driver shape
    server.nix              headless — the home-server shape
    wsl.nix                 NixOS-WSL, no hardware layer — the work-laptop shape
```

## mkHost composes a host

`lib/mkHost.nix` takes `{ hostName, role, hardware ? null, extraModules ? [] }`
and produces a `nixosSystem`: the eminix core, the named role, Home Manager,
agenix, and (if given) a hardware module and disko layout. Every host goes
through this one path — there is no hand-assembled special case.

## The three hosts

| Host | Role | Hardware |
| --- | --- | --- |
| `rafik` | `workstation` | ThinkPad T14 Gen 5 AMD — daily driver |
| `datacore` | `server` | HP 15-ef2013dx — headless home server |
| `whistle` | `wsl` | Work laptop, NixOS-WSL |

Declared in `flake.nix`'s `nixosConfigurations`, one entry per host, each a call
to `mkHost`. Disk layout for `rafik` and `datacore` comes from
`ioshi/hi-hardware/disko/<host>.nix`; `whistle` has no hardware layer at all.

## What replaced Debian + stow

- **No Debian anywhere.** Every host is NixOS; `nixos-rebuild switch --flake .#<host>`
  is the only apply path.
- **No GNU stow.** Home Manager owns `~/.config/*` declaratively. `base/`,
  `bin/dot-restow` and `bin/dot-sync` are gone.
- **Wrapper scripts live in `bin/`** at the repo root, on `PATH` via
  `ioshi/i-intelligence/zsh.nix` — nothing symlinks into `~/.local/bin`.
- **EWM replaced Hyprland.** Emacs is the Wayland compositor; `hyprland.nix`,
  `mako.nix` and `fuzzel.nix` are deleted.

## Verifying a host builds

```bash
nix build --no-link .#nixosConfigurations.rafik.config.system.build.toplevel
nix build --no-link .#nixosConfigurations.datacore.config.system.build.toplevel
nix build --no-link .#nixosConfigurations.whistle.config.system.build.toplevel
```

No root required — this only evaluates and builds the closure.
