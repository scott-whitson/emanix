# Emanix — a walkthrough

This document explains the distribution. Read it one time to understand the
distribution. Read `README.md` after that for the interface.
[emanix.net](https://emanix.net) is the manual for the user of a machine.

The text uses Simplified Technical English. Most sentences are shorter than 25
words. The text uses the active voice. One word has one meaning.

## Words used in this document

- **the distribution** — Emanix. This repository.
- **the consumer** — the flake that uses the distribution. A personal
  configuration repository is a consumer.
- **machine** — one computer.
- **module** — one Nix file that adds configuration.
- **option** — one setting with a name, a type, and a default.
- **tier** — one group of modules for one module system.
- **compose** — to build one machine from the modules.

## 1. What the distribution does

The distribution supplies a base system. The base system uses Emacs as the
desktop. The distribution supplies one shape. The consumer composes the shape of
each machine.

The distribution makes one promise:

> Any Emanix machine can be built again from the configuration alone. If a
> setting is not in a flake, the setting does not exist.

## 2. One shape, and the consumer

The distribution does not hold a machine name, a user name, a key, a secret, or
a disk layout. The consumer supplies all of these parts.

The division is one rule:

> A general ability belongs in the distribution. A fact about one machine
> belongs in the consumer.

| The distribution supplies | The consumer supplies |
| --- | --- |
| The NixOS base system | The list of machines |
| Emacs, and the EWM compositor | The hardware of each machine |
| The shell and the terminal | The partition layout of each disk |
| The theme system | The network and the secrets |
| The first-boot convention | The personal Home Manager layer |

**One exception is deliberate.** The distribution holds `arc`, an offline
assistant. The assistant reads the configuration of the machine. The source of
`arc` is a public repository. The distribution names the source in the
configuration. That name is a distribution feature, not a personal preference.

### There are no roles

An earlier version had three profiles: `workstation`, `server`, and `wsl`. The
files were deleted on 2026-08-30. Each file held the same modules at the end.
What the files held was the SHAPE of a machine. A distribution can supply the
ability to do a thing. A distribution cannot know which machine needs the
thing.

The distribution now supplies one shape. The consumer adds the rest with
`extraModules`. A machine that needs the compositor imports
`nixosModules.ewm` directly.

`role` remains an argument of `mkHost`. The distribution records the value. The
consumer reads the value. The value selects nothing.

## 3. The two tiers

The modules are divided into two tiers. The division is by **module system**.
The module system decides how you import the file. Therefore the division is
useful.

```text
home/       the Home Manager tier: the settings of one user
modules/    the NixOS tier: the settings of the machine
```

**`home/`** holds 15 modules and one aggregate. The aggregate is
`home/default.nix`. The aggregate imports the other 15 modules. The file
`flake.nix` gives the aggregate to Home Manager.

**`modules/`** holds six modules:

| Module | Function |
| --- | --- |
| `base.nix` | The base system: users, the shell, the network |
| `init.nix` | The first system generation |
| `firstboot.nix` | The first-boot convention |
| `gpu.nix` | One option for the graphics hardware. The default is `null` |
| `firmware.nix` | The default for the redistributable firmware |
| `ewm.nix` | The EWM compositor service |

`gpu.nix` and `firmware.nix` supply an ABILITY. They do not hold a hardware
fact. Which graphics card a machine has is a fact about the machine. That fact
belongs in the consumer.

An earlier version called these tiers `ioshi/i-intelligence`,
`ioshi/os-system`, and `ioshi/hi-hardware`. The three names were a story about
what configuration is ABOUT. The story was true, but the division was not
useful: `i-intelligence` held 48 of the 53 files, and `hi-hardware` held no
hardware fact. The names are gone. The story stays in this paragraph.

## 4. How a machine is composed

One function composes every machine. The function is `lib.mkHost`.

```nix
myhost = emanix.lib.mkHost {
  hostName    = "myhost";
  role        = "workstation";   # a label. It selects nothing
  username    = "alice";
  hardware    = ./myhost-hardware.nix;   # optional
  extraModules = [ ./myhost-system.nix ];  # NixOS modules
  homeModules  = [ ./alice-home.nix ];     # Home Manager modules
};
```

`mkHost` does six steps:

1. It loads the distribution core, `emanix.nix`.
2. It sets `emanix.username` from the `username` argument.
3. It sets `emanix.role` from the `role` argument.
4. It loads the Home Manager module and the aggregate in `home/`.
5. It loads the `hardware` file, if the consumer supplies one.
6. It loads each module in `extraModules`.

Use `homeModules` for the settings of the user. Do not write
`home-manager.users.alice` in `extraModules`. `mkHost` knows the user name
already. A second copy of the name is how the two copies become different.

## 5. The public interface

A consumer uses these outputs.

| Output | Function |
| --- | --- |
| `nixosModules.emanix` | The distribution core. `default` is the same module |
| `nixosModules.ewm` | The compositor. Import the module if the machine needs a desktop |
| `nixosModules.installer` | The installer. The consumer supplies the keys |
| `lib.mkHost` | The composer of a machine |
| `lib.mkDisk` | The disk layout builder |
| `templates.default` | The template for `nix flake init` |
| `packages.installerIso` | The installer image |

### The options

The options use the name `emanix.*`. The name tells the reader which repository
holds the option. `emanix.*` is in this repository.

| Option | Function |
| --- | --- |
| `emanix.username` | The user of the machine |
| `emanix.role` | The label. `workstation`, `server`, or `wsl` |
| `emanix.theme` | The name of the palette |
| `emanix.gui` | The machine has a screen |
| `emanix.git.userName`, `emanix.git.userEmail` | The git identity |
| `emanix.ghostty.enable` | Use Ghostty as the terminal |
| `emanix.zellij.enable` | Use Zellij. A login over SSH continues after a disconnect |
| `emanix.emacs.extraPackages` | The Emacs packages of the consumer |
| `emanix.hardware.gpu` | The graphics option. The default is `null` |
| `emanix.firstboot.runtimeInputs`, `emanix.firstboot.text` | The first-boot script |
| `emanix.src.*` | The paths of the two checkouts |
| `emanix.ewm.enable` | Set by the distribution. Do not set it by hand |

## 6. The directory tree

```text
emanix.nix      the core. It imports the modules of the NixOS tier
flake.nix       the outputs, the composer, and the checks
home/           the Home Manager tier. home/default.nix is the aggregate
modules/        the NixOS tier
emacs/          the Emacs configuration: init.el, config.el, lisp/, test/
zellij/         the Zellij configuration: config.kdl, layouts/, plugins/
agent-acp/      the adapters between Emacs and a coding agent
lib/            mkHost, mkDisk, the palettes, and the theme renderer
installer/      the installer image and the install script
checks/         the tests of the distribution
tests/          the shell and Python tests that the checks call
patches/        the patches for EWM
templates/      the template that `nix flake init` uses
docs/           the frozen design records
```

## 7. The theme system

One file holds every palette. The file is `lib/themes.nix`. A palette holds the
colors for every part of the system: Emacs, EWM, Ghostty, and the text-mode
tools. Therefore a color changes in one place.

The file `lib/theme-tree.nix` reads the palettes. It writes one directory for
each palette. Each directory holds every file that the system reads at the
moment of a theme change. The build writes this tree into the store.

The option `emanix.theme` selects the palette of a machine. The option
`emanix.src.themesDir` holds the path of the tree. A consumer with its own
palettes overrides this path.

## 8. The paths, and the two kinds of change

The distribution reads two checkouts. The two paths have different jobs, and
the difference is easy to lose.

**`emanix.src.path`** is the checkout of the DISTRIBUTION. The default is
`~/projects/emanix`.

The Emacs Lisp files in `emacs/` are delivered from this checkout through a
symbolic link. The option is `emanix.src.liveElisp`, and the default is `true`.
Therefore an edit to a Lisp file changes the running Emacs after a restart.
You do not rebuild for this.

The Nix modules are different. The flake reads the modules from the PINNED
revision. An edit to a module does nothing until you commit the edit, push it,
and update the input in the consumer.

> A host can therefore run Lisp files that are newer or older than its own pin.
> The screen shows nothing about this. The command `dot-drift-check` in the
> consumer reports the difference.

**`emanix.src.dotfilesPath`** is the checkout of the CONSUMER. The default is
`~/dotfiles`. The distribution ships no `bin/` directory, so
`emanix.src.binDir` points into this checkout.

## 9. The installer

The distribution builds a rescue image. The rescue image holds no key.

```bash
nix build .#nixosConfigurations.installer.config.system.build.isoImage
```

A real install uses the image of the CONSUMER. The consumer builds its own
image, because the image must hold the keys of the target machine. The consumer
sets two options:

| Option | Function |
| --- | --- |
| `emanix.installer.flake` | The consumer flake that the image carries |
| `emanix.installer.keysDir` | The directory that holds the host keys |

Start the image on the target machine. Then run this command:

```bash
sudo fresh-emanix-install <machine>
```

The command does four steps. It partitions the disk. It copies the system. It
puts the host key in the machine. It prepares the first boot.

## 10. The first-boot convention

The distribution supplies a place for the steps, and it supplies nothing else.
The distribution owns the CONVENTION and the build-time check. The consumer owns
the content.

The distribution puts one command on the PATH of the installed system. The name
of the command is `emanix-firstboot`. The operator runs the command one time
after the first boot.

```nix
emanix.firstboot = {
  runtimeInputs = [ pkgs.tailscale ];
  text = '' ... '';
};
```

The build checks the script. A broken script fails the build. A broken script
does not fail the first boot. The first boot is the one moment when nobody can
read a screen.

## 11. The checks

The command `nix flake check` reads every machine and runs 16 checks. The
checks test the distribution against itself. Most checks read a recorded file.
No check needs the network.

| Check | What it finds |
| --- | --- |
| `role-workstation`, `role-server`, `role-wsl` | Each role evaluates. The `homeModules` seam is exercised too |
| `palette-contrast` | The colors of every palette have enough contrast |
| `template-host` | The template builds. The template is the only thing a new user has |
| `disk-layout` | The disk layout agrees with the recorded layout |
| `hardware-gpu` | The GPU option reaches the kernel modules |
| `theme-switch` | The theme switch works |
| `arc-glue`, `arc-bridge` | The assistant holds its interface |
| `agent-shell-api` | The upstream interface of the agent shell |
| `agent-shell-glue`, `agent-shell-sync` | The agent wiring and the buffer sync |
| `agent-acp-wrapper` | The adapter runs with a small PATH |
| `modeline-segments` | The extension point for the consumer works |
| `welcome-keys` | Every key in the welcome text is a real key |

The directory `tests/` holds the shell and Python tests. The checks call these
tests. The checks do not call two files: `installer-modes.sh` and
`init-guard.sh`. Run these two files by hand.

## 12. How to change the distribution

Use this sequence.

1. Read the file that you will change.
2. Change the file.
3. Run `nix flake check`. This step finds most errors.
4. If the change removes a module or moves a module, update the consumer. The
   consumer names paths in this repository.
5. Commit the change. Push it.
6. In the consumer, update the input:
   `nix flake lock --update-input emanix`.
7. Apply the change to the machines.

Step 4 is the step that is easy to forget. The consumer holds the paths of this
repository in its comments and in its checks. A move in this repository without
a change in the consumer breaks the consumer.

## 13. What the distribution does not own

These parts belong to the consumer. Do not add them here.

- A machine name, a user name, a key, or a secret.
- A disk layout, and the device name of a disk.
- A network name, a tailnet, or a login server.
- The settings of the personal Home Manager layer.
- The list of Emacs packages that one person needs.
- A hardware fact, such as the model of a graphics card.

The reason is one sentence: the distribution does not know the machine.
