# eminix — a NixOS distribution

**eminix** (em·in·ix — **Em**acs + L**in**ux + N**ix**OS, a nod to minix) is an
opinionated NixOS distribution where *Emacs is the desktop*. It is organized
around **ioshi**, a three-concern architecture:

- **i — intelligence interface** (`ioshi/i-intelligence/`): Emacs, EWM, the pi
  agent, theming, and the user workspace. Mostly Home Manager modules, but see
  the note below — `ewm.nix` and `ollama.nix` are NixOS modules.
- **os — operating system** (`ioshi/os-system/`): the NixOS substrate
  (base, desktop, server).
- **hi — hardware / internet** (`ioshi/hi-hardware/`): hardware abstraction and
  the shared network layer (Tailscale).

The three concerns are **descriptive, not enforced**. They say what a piece of
config *is about*, not which module system delivers it — so `i-intelligence/`
legitimately holds both Home Manager and NixOS modules (EWM is an intelligence
concern that happens to need a system-level compositor service), and
`hi-hardware/` is thin because the distribution needs little hardware
abstraction, not because it is unfinished. Nothing checks the boundary and
nothing is meant to; if you are deciding where a file goes, ask what it is
about, not how it is wired.

This repository is the *distribution*. It is generic: it does not hard-code any
user's username, SSH keys, email, secrets, or hostnames. Personal configuration
(hosts, secrets, home-manager user config) lives in a consuming flake (e.g. a
personal dotfiles repo) that imports eminix and calls `lib.mkHost`.

## Layout

```
ioshi/{i-intelligence,os-system,hi-hardware}   # the three concerns
profiles/eminix.nix                            # the distribution's common core (os + net)
profiles/roles/{workstation,server,wsl}.nix    # per-shape config layered on top
lib/{mkHost.nix,themes.nix}                    # host composer + theme lib
installer/                                     # installer ISO + scripts
checks/                                        # fixtures for the flake's eval checks
```

## Using it from a consuming flake

```nix
{
  inputs.eminix.url = "path:/path/to/eminix";
  outputs = { self, eminix, ... }: {
    nixosConfigurations.myhost = eminix.lib.mkHost {
      hostName = "myhost";
      role = "workstation";   # workstation | server | wsl
      username = "alice";
      hardware = ./myhost-hardware.nix;         # optional
      extraModules = [ ./myhost-system.nix ];   # NixOS modules: secrets, keys
      homeModules = [ ./alice-home.nix ];       # Home Manager modules for alice
    };
  };
}
```

Use `homeModules` for the user's Home Manager config rather than reaching into
`home-manager.users.alice` from `extraModules` — `mkHost` already knows the
username, and spelling it again in the consumer is how the two drift apart.

`mkHost` composes the distribution core + role profile + Home Manager wiring
for the given username. Everything personal arrives via `hardware` /
`extraModules` from the consuming flake.

## The installer ISO

```bash
nix build .#nixosConfigurations.installer.config.system.build.isoImage
```

or, from a consuming flake that overrides the ISO to carry its own keys:

```bash
nix build .#nixosConfigurations.installer.config.system.build.isoImage
```

Boot → `sudo fresh-eminix-install <host>`. See
[`docs/ioshi/eminix-install.md`](docs/ioshi/eminix-install.md).

## Themes

The Catppuccin palette is defined once in `lib/themes.nix` and consumed by
every component (Emacs, EWM, Ghostty, TUIs) so colors never drift. Consuming
flakes set `eminix.theme` per host.

## Validation

```bash
nix flake check
```
