# Emanix — a NixOS distribution

**Emanix** (em·a·nix — **Em**acs + **Nix**OS) is an opinionated NixOS
distribution where *Emacs is the desktop*.

**The manual is [emanix.net](https://emanix.net)** — philosophy, architecture,
keybindings, theming, installation, and every `emanix.*` option. This README is
the contract for consuming the flake. Dated design records live in
[`docs/`](docs/) and are history, not instructions.

[`WALKTHROUGH.md`](WALKTHROUGH.md) explains the whole distribution one time, in
Simplified Technical English — the two tiers, how `mkHost` composes a machine,
the theme system, the installer, the checks, and what the distribution does not
own. Read it before the reference below.

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

## How the config is organised

Two tiers, split by **module system** — the one fact that decides how a file is
imported:

- **`home/`** — the Home Manager tier: Emacs, EWM's user half, theming, the
  shell, the terminal, the agent adapters. `home/default.nix` is the aggregate,
  reached through `mkHost`'s `homeModules`.
- **`modules/`** — the NixOS tier: the substrate (`base.nix`, `init.nix`,
  `firstboot.nix`), hardware **capability** (`gpu.nix` — an option defaulting to
  null — and `firmware.nix`), and the compositor service (`ewm.nix`, exposed as
  `nixosModules.ewm`).

The machine *facts* are in neither: which GPU a box has, how its disks are
partitioned and what network it joins belong to the consuming flake, the only
thing that can know them.

This used to be spelled `ioshi/i-intelligence`, `ioshi/os-system` and
`ioshi/hi-hardware` — a three-concern story (i / os / hi) about what config is
*about* rather than how it is wired. The story was true and is still how the
distribution is reasoned about; it just was not a partitioning of anything.
`i-intelligence` held 48 of the 53 files, and `hi-hardware` never held hardware
facts at all. Worse, it was a boundary nothing enforced, and the consuming flake
used the same three words for its own tree, which made every path in both repos
ambiguous. So it is prose now rather than directories.

## Layout

```text
emanix.nix                        # the distribution — one profile, imported by mkHost
home/                             # Home Manager tier: theme, emacs, zsh, git, terminal, agent-acp
home/default.nix                  # the Home Manager aggregate
modules/                          # NixOS tier: base, init, firstboot, gpu, firmware, ewm
emacs/                            # init.el, config.el, fallback.el, lisp/, test/, packages.nix
zellij/                           # config.kdl, layouts/, plugins/
agent-acp/                        # the ACP adapter scripts
lib/mkHost.nix                    # the host composer
lib/disk.nix                      # mkDisk, for disko layouts a consumer passes in
lib/{themes,theme-tree}.nix       # palettes, and the rendered runtime theme tree
lib/gen-pi-theme.py               # renders the pi agent theme into that tree
installer/                        # ISO module, fresh-emanix-install, emanix-init.sh
templates/default/                # `nix flake init` host template
checks/                           # eval/derivation checks run by `nix flake check`
tests/                            # shell and python tests the checks call
patches/                          # ewm patches, applied by modules/ewm.nix
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
(`emacs/packages.nix`), and this is the only way to add
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
