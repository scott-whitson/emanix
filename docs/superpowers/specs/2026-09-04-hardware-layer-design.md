# emanix owns the hardware interface

**Date:** 2026-09-04
**Status:** design, approved in brainstorm; not yet planned

## Problem

emanix cannot install itself on an unfamiliar machine. Every fact about
hardware lives in a personal repo, so the distribution has no answer to "boot
this on a laptop it has never seen".

The evidence is duplication. `dotfiles/ioshi/hi-hardware/lenovo-t14-gen5-amd.nix`
and `hp-15-ef2013dx.nix` carry the same comment, verbatim, in two files:

    # Load amdgpu in the initrd so the GPU is fully initialized before
    # userspace starts — EWM launches from tty1 autologin at boot and loses
    # the DRM-master race against late GPU bring-up otherwise.

That is not a fact about a ThinkPad or about an HP. It is a fact about EWM,
written twice, in the wrong repo. Any emanix host with an AMD GPU needs it;
nobody has written the Intel equivalent, so an Intel machine gets a black
screen and no explanation.

The two files are roughly 80% identical: same firmware line, same power
management, same amdgpu reasoning. What is genuinely per-machine is a few
lines about which wifi chip is present, and `nixos-generate-config` already
finds that.

## The ownership line

**emanix owns what is true regardless of who owns the machine. dotfiles owns
what is a choice.**

| Concern | Owner | Why |
| --- | --- | --- |
| amdgpu/i915 in initrd | emanix | EWM's tty1 DRM-master race |
| `enableRedistributableFirmware` | emanix (`mkDefault`) | Without it wifi does not come up |
| nixos-hardware selection | emanix | A machine database is distro infrastructure |
| Disk layout *shape* | emanix (parameterized) | btrfs-subvolumes-on-LUKS is the distro's opinion |
| `device = "/dev/nvme0n1"` | dotfiles | A fact about one box |
| audio, bluetooth, printing, touchpad | dotfiles | `naturalScrolling = true` is a taste |
| `powerManagement`, `power-profiles-daemon` | dotfiles | A server wanting a performance governor is legitimate |
| timezone, ssh keys, syncthing peers | dotfiles | Personal |

`role` remains the only axis. No `shape` field is introduced: a second name for
what a host is, adjacent to `role` and free to disagree with it, is the drift
`lib/mkHost.nix` already warns about. `os-system/desktop.nix` and `server.nix`
do not move.

This does not overturn the two standing rulings. `mkHost` deleted *role
dispatch* — the distribution deciding what a host is. Named modules a consumer
imports are a different thing, and `nixosModules.ewm` is already precedent.
Likewise the flake's "disko configurations are defined by consumers" survives
in substance: the consumer still states which disk and which options; emanix
only stops everyone retyping the same btrfs layout.

## What emanix gains

**1. `ioshi/hi-hardware/` — a new, deliberately thin layer.**

- `gpu.nix` — declares `emanix.hardware.gpu = "amd" | "intel" | null`, a
  **NixOS-tier** option (it drives `boot.initrd.kernelModules`, which is NixOS,
  not Home Manager). Puts the right module in the initrd, with the EWM race
  documented once instead of twice.
- `firmware.nix` — `hardware.enableRedistributableFirmware = mkDefault true`.

`intel` is written from the *verified mechanism* rather than a verified
machine: the DRM-master race was confirmed on zord-old with amdgpu, and early
compositor startup is not vendor-specific. It ships labelled
reasoned-not-verified. NVIDIA is out of scope — Wayland plus NVIDIA is a
project, not a line.

**2. `nixos-hardware` as an emanix input**, reachable by consumers as
`emanix.inputs.nixos-hardware.nixosModules.<name>`. dotfiles drops its own
input and its `follows` entry. emanix does not re-wrap the 421 modules under a
namespace of its own — that would be a second name for each machine, free to
drift from upstream's.

**3. `lib/disk.nix`** — `templates/default/disko.nix` promoted, gaining
`extraSubvolumes`. Exported as `lib.mkDisk`.

## Why there is no hardware auto-detection

Hardware discovery is `nixos-generate-config`, exactly as it is generic-kernel-
plus-udev for Debian. emanix adds no detection layer of its own. This was
measured before it was decided.

`nixos-hardware` at `dc3f0cf` exports 421 modules and contains no DMI machinery
anywhere — no reference to `sys_vendor`, `product_family` or `dmi/id`. Its
naming is not a convention:

| Machine | Module name | Pattern |
| --- | --- | --- |
| T14 Gen 5 AMD | `lenovo-thinkpad-t14-amd-gen5` | vendor-cpu-gen |
| Framework 13 | `framework-13-7040-amd` | size-chipset-cpu |
| HP laptop | `hp-laptop-15s-fq1xxx` | wildcard suffix |
| X1 Carbon Gen 9 | *(absent under that name)* | — |

rafik's own DMI cannot name rafik's module: `product_family` is
`ThinkPad T14 Gen 5`, with no "amd" anywhere in DMI, while both `-amd-gen5` and
`-intel-gen6` variants exist upstream.

A prototype generating candidates from `sys_vendor` + `product_family` +
`product_name` + CPU vendor, tested for membership against the real 421 names,
resolved **2 of 6** realistic machines. No normalization derives
`framework-13-7040-amd` from `Laptop 13 (AMD Ryzen 7040Series)`. A detector that
is wrong more often than it is right, on a step that precedes wiping a disk, is
worse than no detector: it invites a user to accept a guess they cannot check.

**One detection survives, and it is a different kind.** `emanix.hardware.gpu`
cannot come from `nixos-generate-config`, which writes
`boot.initrd.availableKernelModules` (modules permitted in the initrd) and never
`boot.initrd.kernelModules` (modules forced to load). The EWM race needs the
forced form. So the installer asks:

    Graphics [amd/intel/none] (amd):

defaulting from the PCI vendor ID in `lspci` — `0x1002` AMD, `0x8086` Intel.
That is a two-value lookup, not model-name archaeology, and the user confirms it
either way. Asking is not guessing.

## How a host states its hardware, in each repo

`host.nix` is a **template** artifact. dotfiles has no per-host `host.nix` and
does not gain one; its hosts are composed in `flake.nix`. Both repos state the
same two facts, in the idiom each already uses:

| | Template-generated host | dotfiles (rafik) |
| --- | --- | --- |
| nixos-hardware module | `hardwareModule = "…"` in `host.nix`, read by the template's `flake.nix` | `emanix.inputs.nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen5` in the host's `extraModules`, as today |
| GPU | `gpu = "amd"` in `host.nix` | `emanix.hardware.gpu = "amd";` in `hosts/rafik/configuration.nix` |
| Disk layout | `mkDisk` called from the template with `host.*` | `mkDisk` called from `dotfiles/flake.nix` with literals |

Neither `hardwareModule` nor `gpu` is an argument to `mkHost`. mkHost stays a
composer; adding hardware arguments to it would re-introduce exactly the
dispatch that was deleted. The template dispatches on its own `host.nix`, which
is a consumer doing consumer work.

## Scope: rafik only

The new hardware layer is adopted by rafik at its SSD-swap reinstall. datacore
and whistle keep what they have.

The reinstall is a free migration: the disk is being wiped regardless, so the
layout is applied fresh either way and a bug in new code costs nothing that was
not already being spent. Moving datacore at the same time would mean a failure
during the reinstall has two candidate causes.

## dotfiles afterward

| File | Fate |
| --- | --- |
| `hi-hardware/lenovo-t14-gen5-amd.nix` | deleted. amdgpu+firmware → emanix; `availableKernelModules`/`kernelParams` → generate-config; `powerManagement` → `hosts/rafik/configuration.nix` |
| `hi-hardware/disko/rafik.nix` | replaced by a `emanix.lib.mkDisk` call |
| `hosts/rafik/hardware-configuration.nix` | new, committed — generate-config output from the reinstall |
| `nixos-hardware` input + `follows` | dropped; arrives via emanix |
| `os-system/desktop.nix`, `server.nix` | untouched |
| `hi-hardware/hp-15-ef2013dx.nix`, `disko/datacore.nix` | untouched |

## Verification

**Gate 1 — done, 2026-09-04, before any code was written.** Both layouts are
pure evaluations, so the prototype was diffed against the committed files with
rafik running normally:

| Check | Result |
| --- | --- |
| rafik: `mkDisk` vs hand-written | identical, 2417 bytes of `disko.devices` |
| datacore: `mkDisk` + `extraSubvolumes` vs hand-written | identical, 2522 bytes |
| negative control (`luks` flipped) | differs, 59 lines — comparison is not vacuous |

datacore matching is worth recording: **datacore's disko file is expressible;
its `hp-15-ef2013dx.nix` is not.** The non-inert part of datacore was never the
disk layout but the duplicate `fileSystems` block in the hardware file, which
concatenates with disko's own rather than overriding it (documented in that
file as a live hazard). So when datacore's turn comes the disk half is free and
only the hardware half moves the closure. Deferring datacore is a choice, not a
limitation.

**Gate 2 — `nix flake check`.** Extend `checks/template-host.nix` to compose a
host through `mkDisk` and force its toplevel.

**Gate 3 — the reinstall.** The acceptance test.

## Out of scope

- DMI-based auto-detection of a `nixos-hardware` module. Measured at 2/6 and
  cut; see "Why there is no hardware auto-detection".
- NVIDIA graphics.
- Moving datacore or whistle.
- `os-system/desktop.nix` and `server.nix`, which stay personal.
- Any `shape` option.
- Deduplicating datacore's `fileSystems` block (tracked, not done here).
