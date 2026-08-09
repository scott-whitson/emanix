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

| Host | Role | Hardware | Status |
| --- | --- | --- | --- |
| `rafik` | `workstation` | ThinkPad T14 Gen 5 AMD — daily driver | **live** |
| `whistle` | `wsl` | Work laptop, NixOS-WSL | **live** |
| `datacore` | `server` | HP 15-ef2013dx — headless home server | **not yet cut over** |

`datacore`'s entry is a *target*, not a running system. The machine is still
Debian 13 with a standalone Home Manager profile frozen at 2026-07-20, and the
flake has no `homeConfigurations` output, so that profile cannot be rebuilt from
this repo at all. The cutover plan is to build it on the HP that `zord-old` used
to run — see `docs/superpowers/specs/2026-08-05-datacore-nixos-design.md`.

Declared in `flake.nix`'s `nixosConfigurations`, one entry per host, each a call
to `mkHost`. Disk layout for `rafik` and `datacore` comes from
`ioshi/hi-hardware/disko/<host>.nix`; `whistle` has no hardware layer at all.

## What replaced Debian + stow

- **NixOS on every host that has been cut over.** `nixos-rebuild switch --flake .#<host>`
  is the only apply path. **`datacore` is the exception and is still Debian 13** —
  see the host table above. Do not assume otherwise: an earlier draft of this
  chapter claimed every host was NixOS, and that false premise led to a config
  change that would have handed datacore a symlink to a secret it cannot decrypt.
- **No GNU stow.** Home Manager owns `~/.config/*` declaratively. `base/`,
  `bin/dot-restow` and `bin/dot-sync` are gone.
- **Wrapper scripts live in `bin/`** at the repo root, on `PATH` via
  `ioshi/i-intelligence/zsh.nix` — nothing symlinks into `~/.local/bin`.
- **EWM replaced Hyprland.** Emacs is the Wayland compositor; `hyprland.nix`,
  `mako.nix` and `fuzzel.nix` are deleted.

## The `scott.*` options that shape a host

Declared in `ioshi/i-intelligence/theme.nix`. The ones that decide behaviour:

| Option | Set by | Purpose |
| --- | --- | --- |
| `scott.role` | `lib/mkHost.nix`, from the same argument that picks the role profile | `workstation` / `server` / `wsl`. Modules branch on this rather than re-deriving host shape |
| `scott.gui` | the role profile | Gates GUI packages, cursor theme, ghostty, firefox, fragpaper-era Wayland tools |
| `scott.ewm.enable` | the role profile | True: Emacs *is* the compositor (system-owned EWM build). False: the pgtk Emacs runs as a user daemon via `emacs-daemon.nix` |
| `scott.pi.enable` | the role profile | Whether this host gets the OpenRouter credential symlinked from agenix. False on `server`: datacore holds `~/.pi/agent` only as a Syncthing peer and does not run pi — but it **is** an `openrouter-auth.age` recipient regardless (the secret decrypts at every activation via the common core), so `false` here only means no symlink, not no recipient |
| `scott.ibgateway.enable` | per-host | IB Gateway. True on `rafik` only — see [Chapter 03](03-tools.md#ib-gateway) |

`scott.role` replaced `scott.dotfiles.profile` on 2026-08-08. That option encoded
the same fact in a second vocabulary (`desktop` for what the role calls
`workstation`) and was hand-written in each role file — exactly the duplication
the role structure exists to remove.

## Home Manager will not clobber files it does not own

`home-manager.backupFileExtension = "hm-bak"` is set in `flake.nix`. Without it,
activation *aborts* the moment any real file sits where HM wants to write —
which kills the whole switch over one file. With it, the intruder is renamed to
`<file>.hm-bak` and activation continues.

This is not theoretical: `rafik`'s switch on 2026-08-08 failed outright because
Firefox had already written `~/.mozilla/firefox/profiles.ini`. It matters most
for the datacore cutover, where Debian-era files will sit at HM-owned paths.

## Verifying a host builds

```bash
nix build --no-link .#nixosConfigurations.rafik.config.system.build.toplevel
nix build --no-link .#nixosConfigurations.datacore.config.system.build.toplevel
nix build --no-link .#nixosConfigurations.whistle.config.system.build.toplevel
```

No root required — this only evaluates and builds the closure.
