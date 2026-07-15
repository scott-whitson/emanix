# Phase 0 — Foundation & correctness (NixOS + Emacs/EWM)

**Date:** 2026-07-15
**Status:** Design — awaiting review
**Part of:** the "clean, proper NixOS + Emacs/EWM deployment" modernization
(Phase 0 of 5; later phases: structure/mkHost, one-Emacs, nixos-hardware,
secrets. flake-parts and impermanence are deferred.)

## Context

`~/dotfiles` is a Nix flake deploying two NixOS hosts:

- **zord** — ThinkPad T14 Gen 5 AMD, daily driver (disko full-disk LUKS+btrfs).
- **zord-old** — HP 15-ef2013dx, backup/pilot (hand-written fileSystems, no disko).

Both run Emacs-as-WM (EWM) launched from tty1 autologin, with Home Manager for
the user environment.

A recent install attempt burned ~8 hours because the config for `zord` did not
evaluate at all. That blocker has already been fixed as prerequisite work
(separate from this phase):

- Removed the duplicate hand-written `fileSystems`/`luks` from the T14 hardware
  module so disko is the single source of truth; `configuration.nix` now
  imports `hosts/zord/disko.nix` instead of duplicating the spec inline.
- Added `boot.initrd.kernelModules = [ "amdgpu" ]` on the T14 (EWM DRM-master
  race, proven necessary on zord-old).
- Stripped the dead `inputs` module argument from both host configs.

This phase addresses the *remaining* correctness and duplication problems that
make the flake fragile and misleading, without introducing new subsystems.

## Problems this phase fixes

1. **The emacs-overlay never reaches the booted machines.** The flake builds a
   top-level `pkgs = import nixpkgs { overlays = [ emacs-overlay… ]; }` used only
   by the standalone `homeConfigurations` and the devShell. The NixOS systems
   build their own pkgs (no overlay); with `useGlobalPkgs = true`, HM-in-NixOS
   and `ewm.nix`'s Emacs inherit that overlay-less pkgs. Net: the overlay is
   active only in the path that is never booted.

2. **Home Manager is wired twice** — standalone `homeConfigurations."scott@zord"`
   *and* as a NixOS module on both hosts. The machines use the NixOS path; the
   standalone entry is redundant (and is the only place the overlay "works",
   which is what makes the bug hard to see). Confirmed safe to remove.

3. **Cross-cutting config is duplicated across modules.** rtkit+pipewire,
   Bluetooth, libinput touchpad prefs, and the systemd-boot bootloader are each
   defined in *both* the per-host hardware modules *and* `desktop.nix` (bootloader
   is defined in three places). They merge today only because the values happen
   to be identical — a rename-time landmine.

4. **Dead, latently-broken theme-library plumbing.** `sharedSpecialArgs` passes
   `dotfilesLib = import ./lib { inherit pkgs; }` to every module, but nothing
   references it (only comments do). `lib/default.nix` is a bare attrset, so
   `import ./lib { inherit pkgs; }` applies an attrset to an argument — an eval
   error that survives only because the thunk is never forced. This plumbing is
   also a reason the top-level overlay `pkgs` exists.

## Goal & non-goals

**Goal:** the flake evaluates cleanly, the emacs-overlay reaches the machines
actually booted, and every setting has exactly one home.

**Only intended behavior change:** the emacs-overlay now applies system-wide (so
Emacs/EWM builds against overlay packages). Everything else is structural — the
built system should otherwise be equivalent.

**Non-goals (explicitly deferred to later phases):**
- No `mkHost`/profile restructure (Phase 1).
- No collapsing of the two Emacs builds (Phase 2) — only ensure both now see the
  overlay.
- No nixos-hardware (Phase 3), no secrets management (Phase 4).
- No flake-parts, no impermanence.

## Design

### 1. Overlay + nixpkgs config applied to NixOS

Define the nixpkgs settings once in the flake and include the module in both
hosts (so HM inherits via `useGlobalPkgs`):

```nix
nixpkgsModule = {
  nixpkgs.overlays = [ emacs-overlay.overlays.default ];
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [ "electron-39.8.10" ];
};
```

- `allowUnfree` and `permittedInsecurePackages` move here **out of** `desktop.nix`.
- Added to each host's `modules` list in `nixosConfigurations`.

### 2. One Home Manager wiring

- Delete the entire `homeConfigurations` output.
- Keep `home-manager.nixosModules.home-manager` + the `hmModule` integration.
- Path stays: NixOS `home-manager.users.scott.imports = [ ./home/scott/default.nix ]`
  → which imports `modules/home-manager`. Single chain.

### 3. One nixpkgs instantiation

- Remove the top-level `pkgs = import nixpkgs { overlays = … }`.
- `devShells` and `formatter` switch to `nixpkgs.legacyPackages.${system}`
  (nixd, nixpkgs-fmt, deadnix, statix need no overlay).

### 4. Fix the theme library, keep it

- `lib/default.nix` stays a plain attrset; fix the call site to
  `dotfilesLib = import ./lib;` (drop the bogus `{ inherit pkgs; }`).
- `lib/themes.nix` remains a function; consumers call
  `dotfilesLib.theme { inherit pkgs; }` when they wire it up (Phase 2).
- `dotfilesLib` stays in `sharedSpecialArgs`, now correctly plumbed and ready.

### 5. Dedup cross-cutting config into `desktop.nix`

Move to `desktop.nix` (single definition), remove the duplicates from
`modules/nixos/hardware/hp-15-ef2013dx.nix` and
`modules/nixos/hardware/thinkpad-t14-gen5-amd.nix`:

- `security.rtkit.enable` + `services.pipewire` block
- `hardware.bluetooth.enable`
- `services.libinput` (touchpad prefs are user preference, not hardware)
- `boot.loader.systemd-boot` + `boot.loader.efi.canTouchEfiVariables`

Hardware modules keep only hardware-unique settings: `boot.kernelParams`,
`boot.initrd.{availableKernelModules,kernelModules}`,
`hardware.enableRedistributableFirmware`, `powerManagement`,
`services.power-profiles-daemon`, and GPU specifics (amdgpu-in-initrd).

`hardware.graphics.enable` remains set by `ewm.nix` (EWM requirement) — unchanged.

## Verification

None of this is verifiable on the WSL laptop (no Nix). Run on datacore (mirror)
or the T14 live/installed system, from a clean pull:

1. `nix flake check`
2. `nix eval .#nixosConfigurations.zord.config.system.build.toplevel.drvPath`
   — and the same for `zord-old`; both must print a store path (before the
   overlay/dedup work, still expected to succeed after the disko prerequisite;
   this phase must not regress it).
3. Confirm the overlay is live, e.g. compare
   `nix eval .#nixosConfigurations.zord.config.programs.ewm.emacsPackage.version`
   (or the resulting emacs) against a no-overlay baseline, or check that an
   overlay-only attribute resolves.
4. `nix fmt` (nixpkgs-fmt), `statix check`, `deadnix` — no warnings.
5. Sanity: `nixos-rebuild build --flake .#zord` completes.

## Risks

- **Overlay changes what Emacs builds against.** Turning the overlay on
  system-wide may pull a newer Emacs/packages than the machines have been
  running. Mitigation: this is the intended fix; verify the EWM Emacs still
  builds (step 5) before switching a machine. If the overlay Emacs is
  undesirable, we scope the overlay to only what's needed in Phase 2.
- **Option-merge surprises during dedup.** Removing a duplicate that was *not*
  actually identical would change behavior. Mitigation: the dedup targets are
  verified identical across the current files; `nixos-rebuild build` +
  eyeballing the diff of `config.systemd`/`config.services` guards this.
- **Cannot self-verify here.** All gates run on a Nix host; this spec's "done"
  depends on Scott (or a Nix-capable agent) running the commands.

## Out of scope / follow-on

Phases 1–4 (structure, one-Emacs, nixos-hardware, secrets) each get their own
spec. flake-parts and impermanence remain deferred pending a later decision.
