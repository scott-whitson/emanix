# Emanix — a NixOS distribution

**Emanix** (em·a·nix — **Em**acs + **Nix**OS) is an opinionated NixOS
distribution where *Emacs is the desktop*.

**The manual is [emanix.net](https://emanix.net)** — philosophy, architecture,
keybindings, theming, installation, and every `emanix.*` option. This README is
the contract for consuming the flake. Dated design records live in
[`docs/`](docs/) and are history, not instructions.

The claim the distribution makes is narrow and testable: **any Emanix machine
can be rebuilt from the configuration alone. If it is not in the flake, it does
not exist.**

## What it ships

One shape: a base system, Emacs as the desktop, the EWM compositor, a shell, a
terminal, a theme system, and the first-boot convention. A consuming flake
supplies everything Emanix cannot know — which machines exist, what hardware
they have, how their disks are laid out, which network they join, which secrets
they hold, and the user's Home Manager configuration.

Emanix does not hard-code a username, an SSH key, an email address, a secret, or
a hostname. Personal configuration lives in the consuming flake (a personal
dotfiles repo, for example), which imports Emanix and calls `lib.mkHost`.

One thing is deliberately *not* consumer-supplied, and is named here so it does
not read as a leak: `arc`, the distribution's bundled offline assistant, is
pinned to `scott-whitson/arc`. That is a public repository belonging to the same
author. It is a distribution capability, not a personal preference.

## The ioshi concerns

Config is organised by what it is *about*, under three concerns:

- **i — intelligence interface** (`ioshi/i-intelligence/`): Emacs, EWM, theming,
  the shell, the terminal, and the user workspace. Mostly Home Manager modules,
  but not entirely — `ewm.nix` is a NixOS module, because a compositor needs a
  system service.
- **os — operating system** (`ioshi/os-system/`): the NixOS substrate — `base.nix`,
  `init.nix`, `firstboot.nix`.
- **hi — hardware / internet** (`ioshi/hi-hardware/`): hardware **capability**
  only — a GPU option that defaults to null, and the redistributable-firmware
  default. The machine *facts* are not here: which GPU a box has, how its disks
  are partitioned, and what network it joins belong to the consuming flake, the
  only thing that can know them.

The three concerns are **descriptive, not enforced**. They say what a piece of
config is about, not which module system delivers it. Nothing checks the
boundary, and nothing is meant to. When deciding where a file goes, ask what it
is about, not how it is wired.

## Layout

```text
emanix.nix                        # the distribution — one profile, imported by mkHost
ioshi/i-intelligence/             # Emacs, EWM, theme, zsh, git, terminal, agent-shell
ioshi/os-system/                  # base, init, firstboot
ioshi/hi-hardware/                # gpu.nix, firmware.nix — capability, not facts
lib/mkHost.nix                    # the host composer
lib/disk.nix                      # mkDisk, for disko layouts a consumer passes in
lib/{themes,theme-tree}.nix       # palettes, and the rendered runtime theme tree
lib/gen-pi-theme.py               # renders the pi agent theme into that tree
installer/                        # ISO module, fresh-emanix-install, emanix-init.sh
templates/default/                # `nix flake init` host template
checks/                           # eval/derivation checks run by `nix flake check`
tests/                            # shell and python tests the checks call
patches/                          # ewm patches, applied by ewm.nix
docs/                             # frozen design records
```

## There are no roles

`profiles/roles/{workstation,server,wsl}.nix` existed until 2026-08-30, selected
by `mkHost`'s `role` argument. They were deleted.

By the end they differed in almost nothing: which `os-system` file they imported,
and whether they set `emanix.gui`. What they carried was not distribution policy
but **host shape** — whether a machine has speakers, a touchpad, a printer, a
bootloader. A distribution should know *how* to enable those. It cannot know
*which* machines want them.

So Emanix ships one shape. A consumer composes the rest through `extraModules`,
and imports `nixosModules.ewm` explicitly if it wants the compositor — rather
than inheriting it from a role it did not choose.

`role` survives as an argument to `mkHost` and as metadata on `emanix.role`. It
selects nothing. The distribution records the label (`zsh.nix` exports
`EMANIX_ROLE`) and the consumer interprets it.

## Using it from a consuming flake

```nix
{
  inputs.emanix.url = "github:scott-whitson/emanix";
  outputs = { self, emanix, ... }: {
    nixosConfigurations.myhost = emanix.lib.mkHost {
      hostName = "myhost";
      role = "workstation";                     # a label; selects nothing
      username = "alice";
      hardware = ./myhost-hardware.nix;         # optional
      extraModules = [ ./myhost-system.nix ];   # NixOS modules: disks, secrets, network
      homeModules = [ ./alice-home.nix ];       # Home Manager modules for alice
    };
  };
}
```

Use `homeModules` for the user's Home Manager config rather than reaching into
`home-manager.users.alice` from `extraModules`. `mkHost` already knows the
username, and spelling it twice is how the two drift apart.

### The consumer seams

The options a consumer is expected to set. The full list is on
[emanix.net/docs/options.html](https://emanix.net/docs/options.html).

| Option | Tier | Purpose |
| --- | --- | --- |
| `emanix.gui` | Home Manager | This machine has a graphical session |
| `emanix.theme` | Home Manager | Which palette to build the runtime theme tree from |
| `emanix.zellij.enable` | Home Manager | Run Zellij, so SSH logins land in a persistent session |
| `emanix.src.*` | Home Manager | Where the consumer's checkout and this distribution's checkout live |
| `emanix.emacs.extraPackages` | Home Manager | Emacs packages the consumer adds to the distribution's Emacs build |

`emanix.emacs.extraPackages` is a function of the package set, not a plain list:

```nix
home-manager.users.alice.emanix.emacs.extraPackages = epkgs: [ epkgs.s ];
```

It takes the package set so the consumer never names the Emacs variant — which
Emacs to build is the distribution's choice and stays its choice. The seam
exists so a consumer's own elisp can need a package the distribution cannot
justify shipping to every host. The distribution's Emacs is built in one place
(`ioshi/i-intelligence/emacs/packages.nix`), and this is the only way to add
to it.

## The installer ISO

```bash
nix build .#nixosConfigurations.installer.config.system.build.isoImage
```

Boot it, then run `sudo fresh-emanix-install <host>`.

A consuming flake builds its own ISO, so that the target's host keys can be
staged into it; `emanix.installer.flake` and `emanix.installer.keysDir` are the
two knobs. Host-specific install runbooks live in the consuming flake, because
they are about that user's machines, disks and keys — not about the
distribution.

## Themes

The Catppuccin palette is defined once in `lib/themes.nix` and consumed by every
component (Emacs, EWM, Ghostty, TUIs), so colours cannot drift. `lib/theme-tree.nix`
renders it into one directory per palette at build time. A consumer sets
`emanix.theme` per host.

## Validation

```bash
nix flake check
```

This evaluates every host and runs the distribution's 13 checks: the
disk-layout literals, palette contrast, the theme switch, ARC's glue and
bridge, agent-shell's API, sync and glue, the ACP wrapper, the modeline
segments, the welcome keybindings, the template host, and the GPU option.
Most are pure over recorded fixtures — no network, no running services.

The shell tests under `tests/` (installer modes, the `init.el` guard) are NOT
wired into `nix flake check`. Run them directly.
