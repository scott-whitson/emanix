# Emanix — a NixOS distribution

**Emanix** (em·a·nix — **Em**acs + **Nix**OS) is an opinionated NixOS
distribution where *Emacs is the desktop*. It is organized around **ioshi**, a
three-concern architecture:

- **i — intelligence interface** (`ioshi/i-intelligence/`): Emacs, EWM,
  theming, and the user workspace. Mostly Home Manager modules, but see the
  note below — `ewm.nix` is a NixOS module.
- **os — operating system** (`ioshi/os-system/`): the NixOS substrate
  (base, firstboot).
- **hi — hardware / internet**: absent here, and deliberately. Which drivers a
  machine needs, how its disks are laid out, and what network it joins are
  facts about *a* machine, not about the distribution. That concern belongs to
  the consuming flake, which is the only thing that can know it.

The three concerns are **descriptive, not enforced**. They say what a piece of
config *is about*, not which module system delivers it — so `i-intelligence/`
legitimately holds both Home Manager and NixOS modules (EWM is an intelligence
concern that happens to need a system-level compositor service). Nothing checks
the boundary and nothing is meant to; if you are deciding where a file goes, ask
what it is about, not how it is wired.

This repository is the *distribution*. It is generic: it does not hard-code any
user's username, SSH keys, email, secrets, or hostnames. Personal configuration
(hosts, secrets, home-manager user config) lives in a consuming flake (e.g. a
personal dotfiles repo) that imports Emanix and calls `lib.mkHost`.

## Layout

```
emanix.nix                                     # the distribution — one profile, imported by mkHost
ioshi/{i-intelligence,os-system}               # the two concerns the distro owns
lib/{mkHost.nix,themes.nix}                    # host composer + theme lib
installer/                                     # installer ISO + scripts
checks/                                        # fixtures for the flake's eval checks
```

### There are no roles

There used to be `profiles/roles/{workstation,server,wsl}.nix`, selected by
`mkHost`'s `role` argument. They were deleted on 2026-08-30.

By the end they differed in almost nothing: which `os-system` file they imported
and whether they set `emanix.gui`. What they carried was not distribution policy
but **host shape** — whether a machine has speakers, a touchpad, a printer, a
bootloader. A distribution should know *how* to enable those; it should not
decide *which* machines want them, because it cannot know. That decision now sits
with the consuming flake, which does.

So Emanix ships **one shape**. A consumer composes the rest through
`extraModules`, and imports `nixosModules.ewm` if it wants the compositor —
explicitly, rather than inheriting it from a role it did not choose.

`role` survives as an *argument to `mkHost`* and as metadata on
`emanix.role`. It selects nothing; it is a label the distro records
(`zsh.nix` exports `EMANIX_ROLE`) and the consumer interprets.

## Using it from a consuming flake

```nix
{
  inputs.emanix.url = "path:/path/to/emanix";
  outputs = { self, emanix, ... }: {
    nixosConfigurations.myhost = emanix.lib.mkHost {
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

`mkHost` composes the distribution core + Home Manager wiring for the given
username. Everything personal arrives via `hardware` / `extraModules` from the
consuming flake.

## The installer ISO

```bash
nix build .#nixosConfigurations.installer.config.system.build.isoImage
```

or, from a consuming flake that overrides the ISO to carry its own keys:

```bash
nix build .#nixosConfigurations.installer.config.system.build.isoImage
```

Boot → `sudo fresh-emanix-install <host>`. See
[`docs/ioshi/emanix-install.md`](docs/ioshi/emanix-install.md).

## Themes

The Catppuccin palette is defined once in `lib/themes.nix` and consumed by
every component (Emacs, EWM, Ghostty, TUIs) so colors never drift. Consuming
flakes set `emanix.theme` per host.

## Validation

```bash
nix flake check
```
