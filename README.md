# dotfiles — the ioshi stack

Scott Whitson's personal machine, as a Nix flake. NixOS + Emacs/EWM, organized
around **ioshi**: a three-concern architecture the machine is actually reasoned
about in.

- **i — intelligence interface** (`ioshi/i-intelligence/`): Emacs, EWM, the pi
  agent, theming, and the user workspace.
- **os — operating system** (`ioshi/os-system/`): the NixOS substrate (base, desktop).
- **hi — hardware / internet** (`ioshi/hi-hardware/`): per-machine hardware, disko
  disk layouts, and the shared network/session layer.

**eminix** is the composed platform (em·in·ix — Emacs + Linux + NixOS, a nod to
minix): the daily driver. Hosts are assembled from the layers by `lib/mkHost`.

## Layout

```
ioshi/{i-intelligence,os-system,hi-hardware}   # the three concerns
profiles/eminix.nix                            # the platform = os + i + shared net
lib/{mkHost.nix,themes.nix}                    # host composer + theme lib
hosts/{eminix,zord-old,datacore}               # thin per-host anchors
secrets/                                        # agenix-encrypted (openrouter auth)
base/                                           # non-Nix assets consumed by modules (pi, etc.)
docs/ioshi/                                     # install runbook + deploy checklist
```

- **eminix** — ThinkPad T14 Gen 5 AMD, daily driver.
- **zord-old** — HP 15-ef2013dx, backup running the same stack.

## Build / deploy

Validate any host without root:

```bash
nix flake check
nix build .#nixosConfigurations.eminix.config.system.build.toplevel
```

Apply on a machine:

```bash
sudo nixos-rebuild switch --flake .#eminix     # or .#zord-old
```

Fresh install (bare metal): follow [`docs/ioshi/eminix-install.md`](docs/ioshi/eminix-install.md)
— disko + `nixos-install`, on-device from a Ventoy NixOS ISO. Outstanding manual
steps for the current rollout are in
[`docs/ioshi/deploy-checklist.md`](docs/ioshi/deploy-checklist.md).

## Path conventions

- **`~/dotfiles`** — this flake, on every machine (matches `scott.dotfiles.path`;
  liveElisp symlinks `~/.config/emacs` into it).
- **`~/projects` on datacore** — canonical source trees.
- **`~/docs`** — Syncthing mirror for the vault / personal docs.

## Notes

- Secrets are managed with **agenix** (`secrets/`); hosts decrypt with their SSH
  host key. See the deploy checklist for inserting the real OpenRouter keys.
- The former **Debian + Hyprland** setup is being retired. The Debian install/
  bootstrap tooling has been removed; still legacy and unimported on the EWM hosts
  are the Hyprland/fuzzel/mako modules (`ioshi/i-intelligence/{hyprland,fuzzel,mako}.nix`)
  and the `bin/dot-*` theming helpers. The old desktop bar code has been archived
  and is no longer part of the active path.
- Older Debian-era guides under `docs/manual/` are kept for history with supersede
  banners where relevant.
