# dotfiles — the ioshi stack

Scott Whitson's personal machine, as a Nix flake. NixOS + Emacs/EWM, organized
around **ioshi**: a three-concern architecture the machine is actually reasoned
about in.

- **i — intelligence interface** (`ioshi/i-intelligence/`): Emacs, EWM, the pi
  agent, theming, and the user workspace.
- **os — operating system** (`ioshi/os-system/`): the NixOS substrate (base, desktop).
- **hi — hardware / internet** (`ioshi/hi-hardware/`): per-machine hardware, disko
  disk layouts, and the shared network/session layer.

**eminix** (em·in·ix — Emacs + Linux + NixOS, a nod to minix) is the name of the
*distribution* only — `profiles/eminix.nix`, the common core every host shares.
It is never a hostname. Hosts are assembled from a role profile plus that core
by `lib/mkHost`.

## Layout

```
ioshi/{i-intelligence,os-system,hi-hardware}   # the three concerns
profiles/eminix.nix                            # the distribution's common core (os + net + secrets)
profiles/roles/{workstation,server,wsl}.nix    # per-shape config layered on top
lib/{mkHost.nix,themes.nix}                    # host composer + theme lib
hosts/{rafik,datacore,whistle}                 # thin per-host anchors
secrets/                                        # agenix-encrypted (openrouter auth)
docs/ioshi/                                     # install runbook + deploy checklist
```

- **rafik** — ThinkPad T14 Gen 5 AMD, daily driver (role `workstation`).
- **datacore** — HP 15-ef2013dx, headless home server (role `server`); superseded
  the Debian-era `zord-old` on the same physical box.
- **whistle** — work laptop, NixOS-WSL (role `wsl`).

## Build / deploy

Validate any host without root:

```bash
nix flake check
nix build .#nixosConfigurations.rafik.config.system.build.toplevel
```

Apply on a machine:

```bash
sudo nixos-rebuild switch --flake .#rafik      # or .#datacore / .#whistle
```

Fresh install (bare metal): build the **eminix installer ISO** on rafik with
`bin/eminix-iso` (see [`docs/ioshi/eminix-install.md`](docs/ioshi/eminix-install.md))
— boot → `sudo fresh-eminix-install <host>`. The rafik v1 rollout checklist is in
[`docs/ioshi/history/`](docs/ioshi/history/).

## Path conventions

- **`~/dotfiles`** — this flake, on every machine (matches `scott.dotfiles.path`;
  liveElisp symlinks `~/.config/emacs` into it).
- **`~/projects` on datacore** — canonical source trees.
- **`~/docs`** — Syncthing mirror for the vault / personal docs.

## Notes

- Secrets are managed with **agenix** (`secrets/`); hosts decrypt with their SSH
  host key. See the deploy checklist for inserting the real OpenRouter keys.
- The former **Debian + Hyprland** setup is fully retired: no host runs Debian,
  and `hyprland.nix`, `mako.nix` and `fuzzel.nix` are deleted — EWM is the sole
  compositor now. GNU stow is retired too; nothing symlinks into `~/.local/bin`,
  and the wrapper scripts in `bin/` reach PATH via `ioshi/i-intelligence/zsh.nix`.
- Older Debian-era guides under `docs/manual/` are kept for history, marked with
  supersede banners where relevant.
