# NixOS+EWM Phase 0 (Foundation & Correctness) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the flake evaluate cleanly, get the emacs-overlay onto the machines actually booted, and give every setting exactly one home — without introducing new subsystems.

**Architecture:** Single source of truth throughout. The emacs-overlay and nixpkgs config are applied to the NixOS systems via one shared module (inherited by Home Manager through `useGlobalPkgs`). Home Manager is wired exactly one way (NixOS module). There is one nixpkgs instantiation. Cross-cutting desktop concerns live in `desktop.nix`; hardware modules are hardware-only.

**Tech Stack:** Nix flakes, NixOS (nixos-unstable), Home Manager, disko, emacs-overlay, EWM.

## Global Constraints

- **No Nix on the authoring machine (WSL).** Every `nix …` / `nixos-rebuild …` command in this plan MUST be run on a Nix host — datacore (the mirror) or the T14/zord-old itself. Do not claim a step passed without real command output from such a host.
- **Repo:** `~/dotfiles` on non-NixOS boxes is a git checkout; on the NixOS boxes it is `/etc/dotfiles`. Workflow is main → GitHub → datacore mirror → pull+rebuild.
- **Commits:** NEVER add a `Co-Authored-By` trailer. Use scoped `git add <explicit paths>` — never `git add -A` (the tree carries an unrelated dirty `base/claude/.claude/settings.json` that must not be swept in).
- **Only intended behavior change for the whole phase:** the emacs-overlay now applies system-wide. Tasks 2–5 must be behavior-neutral for the NixOS systems (guarded by drvPath-invariance).
- **`emacs-overlay.overlays.default`** is the exact overlay attribute. **`permittedInsecurePackages`** value is exactly `[ "electron-39.8.10" ]` (copy verbatim from current `desktop.nix`).
- **Spec:** `docs/superpowers/specs/2026-07-15-nixos-ewm-phase0-foundation-design.md`.

---

## Task 0: Clean base — commit the pre-existing install fix

The tree already contains reviewed, uncommitted install-blocker fixes (disko single-source, amdgpu-in-initrd, dead `inputs` strip) in `hosts/zord/configuration.nix`, `hosts/zord-old/configuration.nix`, and `modules/nixos/hardware/thinkpad-t14-gen5-amd.nix`. Commit them first so Phase 0 commits stay clean and don't entangle them.

**Files:**
- Commit (already modified): `hosts/zord/configuration.nix`, `hosts/zord-old/configuration.nix`, `modules/nixos/hardware/thinkpad-t14-gen5-amd.nix`

- [ ] **Step 1: Confirm exactly the three expected files are modified**

Run: `git -C ~/dotfiles status -s`
Expected: the three files above show ` M`, plus the pre-existing ` M base/claude/.claude/settings.json` (leave that one alone).

- [ ] **Step 2: Commit the three install-fix files (scoped)**

```bash
cd ~/dotfiles
git add hosts/zord/configuration.nix hosts/zord-old/configuration.nix modules/nixos/hardware/thinkpad-t14-gen5-amd.nix
git commit -m "fix(zord): disko as single source of truth for disk layout; amdgpu initrd; drop dead inputs arg"
```

- [ ] **Step 3: Verify the base evaluates (on a Nix host)**

Run: `nix eval .#nixosConfigurations.zord.config.system.build.toplevel.drvPath`
Expected: prints a `/nix/store/…-nixos-system-zord-….drv` path (this is the proof the earlier install blocker is gone). Repeat for `zord-old`.

---

## Task 1: Apply emacs-overlay + nixpkgs config to the NixOS systems

**Files:**
- Modify: `flake.nix` (add `nixpkgsModule` in the `let`; add it to both hosts' `modules` lists)
- Modify: `modules/nixos/desktop.nix` (remove `nixpkgs.config.*` — now owned by `nixpkgsModule`)

**Interfaces:**
- Produces: `nixpkgsModule` (a NixOS module attrset in `flake.nix`'s `let`) consumed by both `nixosConfigurations` entries.

- [ ] **Step 1: Write the failing test — overlay is NOT applied yet**

Run: `nix eval .#nixosConfigurations.zord.config.nixpkgs.overlays --apply builtins.length`
Expected (before change): `0`

- [ ] **Step 2: Add `nixpkgsModule` to the `let` block in `flake.nix`**

Insert immediately after the `sharedSpecialArgs` binding:

```nix
      nixpkgsModule = {
        nixpkgs.overlays = [ emacs-overlay.overlays.default ];
        nixpkgs.config.allowUnfree = true;
        nixpkgs.config.permittedInsecurePackages = [ "electron-39.8.10" ];
      };
```

- [ ] **Step 3: Add `nixpkgsModule` to both hosts' module lists in `flake.nix`**

`zord-old` modules become:
```nix
          modules = [
            ./hosts/zord-old/configuration.nix
            nixpkgsModule
            home-manager.nixosModules.home-manager
            hmModule
          ];
```

`zord` modules become:
```nix
          modules = [
            ./hosts/zord/configuration.nix
            nixpkgsModule
            disko.nixosModules.disko
            home-manager.nixosModules.home-manager
            hmModule
          ];
```

- [ ] **Step 4: Remove the now-duplicated nixpkgs config from `desktop.nix`**

Delete these lines from `modules/nixos/desktop.nix`:
```nix
  # Enable unfree (Steam, Nvidia, etc.)
  nixpkgs.config.allowUnfree = true;

  # bitwarden-desktop rides an EOL electron that nixpkgs flags insecure.
  # Version-pinned: when bitwarden bumps electron this goes stale and the
  # build error names the new version to put here (or delete the line).
  nixpkgs.config.permittedInsecurePackages = [
    "electron-39.8.10"
  ];
```

- [ ] **Step 5: Run the test — overlay IS now applied**

Run: `nix eval .#nixosConfigurations.zord.config.nixpkgs.overlays --apply builtins.length`
Expected (after change): `1`

Bonus spot-check (overlay-exclusive attr resolves; use any attr the overlay provides, e.g. `emacs-git` or `emacs-unstable`):
Run: `nix eval .#nixosConfigurations.zord.pkgs.emacs-git.pname`
Expected: `emacs` (before the change this errored with `attribute 'emacs-git' missing`).

- [ ] **Step 6: Confirm the config still builds**

Run: `nixos-rebuild build --flake .#zord`
Expected: completes, produces a `result` symlink. (drvPath is *expected to change* here — this is the one behavior change.)

- [ ] **Step 7: Commit**

```bash
git add flake.nix modules/nixos/desktop.nix
git commit -m "feat(nix): apply emacs-overlay + nixpkgs config to NixOS systems"
```

---

## Task 2: Collapse to one Home Manager wiring

**Files:**
- Modify: `flake.nix` (delete the `homeConfigurations` output)

- [ ] **Step 1: Write the failing test — standalone homeConfigurations still exists**

Run: `nix eval .#homeConfigurations --apply 'x: builtins.attrNames x'`
Expected (before change): `[ "scott@zord" ]`

- [ ] **Step 2: Delete the `homeConfigurations` block from `flake.nix`**

Remove the entire output (including its `# --- Standalone Home Manager ---` comment):
```nix
      # --- Standalone Home Manager ---
      homeConfigurations = {
        "scott@zord" = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./modules/home-manager
            ./home/scott/default.nix
          ];
          extraSpecialArgs = sharedSpecialArgs;
        };
      };
```

- [ ] **Step 3: Run the test — homeConfigurations is gone**

Run: `nix eval .#homeConfigurations --apply 'x: builtins.attrNames x' 2>&1 || true`
Expected (after change): error `attribute 'homeConfigurations' … does not exist` (the output no longer exists).

- [ ] **Step 4: Confirm the NixOS-integrated HM is still present and system unchanged**

Run: `nix eval .#nixosConfigurations.zord.config.home-manager.users.scott.home.username`
Expected: `scott`

Run: `nix eval .#nixosConfigurations.zord.config.system.build.toplevel.drvPath`
Expected: identical to the drvPath from the end of Task 1 (removing the standalone output does not change the system).

- [ ] **Step 5: Commit**

```bash
git add flake.nix
git commit -m "refactor(nix): drop redundant standalone homeConfigurations"
```

---

## Task 3: Fix the theme-library wiring

**Files:**
- Modify: `flake.nix` (correct the `dotfilesLib` binding and `sharedSpecialArgs`)

**Interfaces:**
- Produces: `dotfilesLib` (was `lib`) in `flake.nix`'s `let`, now `import ./lib` (an attrset `{ theme = <fn>; }`), passed via `sharedSpecialArgs`.

- [ ] **Step 1: Write the failing test — the current call site is the latent bug**

Run: `nix eval --impure --expr 'builtins.typeOf ((import ~/dotfiles/lib) { })' 2>&1 || true`
Expected (before): an error — applying the attrset from `lib/default.nix` to an argument (`{ }`, standing in for `{ inherit pkgs; }`) fails with `attempt to call something which is not a function`. This is exactly why the current `lib = import ./lib { inherit pkgs; }` would throw if ever forced.

- [ ] **Step 2: Fix the binding and `sharedSpecialArgs` in `flake.nix`**

Replace:
```nix
      lib = import ./lib { inherit pkgs; };

      sharedSpecialArgs = { dotfilesLib = lib; };
```
with:
```nix
      dotfilesLib = import ./lib;

      sharedSpecialArgs = { inherit dotfilesLib; };
```

- [ ] **Step 3: Run the test — `import ./lib` is a valid attrset**

Run: `nix eval --impure --expr 'builtins.typeOf (import ~/dotfiles/lib)'`
Expected: `"set"`

Run: `nix eval --impure --expr 'builtins.typeOf (import ~/dotfiles/lib).theme'`
Expected: `"lambda"` (the palette generator, ready to be called with `{ pkgs; }` when wired up in Phase 2).

- [ ] **Step 4: Confirm the flake still evaluates and the system is unchanged**

Run: `nix flake check`
Expected: no errors.

Run: `nix eval .#nixosConfigurations.zord.config.system.build.toplevel.drvPath`
Expected: identical to the Task 2 end drvPath.

- [ ] **Step 5: Commit**

```bash
git add flake.nix
git commit -m "fix(nix): correct dotfilesLib wiring (import ./lib, no bogus pkgs arg)"
```

---

## Task 4: One nixpkgs instantiation

Depends on Tasks 2 and 3 (the only remaining consumers of the manually-built top-level `pkgs` are `devShells` and `formatter`).

**Files:**
- Modify: `flake.nix` (replace the top-level `pkgs` binding)

- [ ] **Step 1: Write the failing test — a second, manual nixpkgs instantiation still exists**

Run: `grep -n 'import nixpkgs' ~/dotfiles/flake.nix`
Expected (before): one match — the `pkgs = import nixpkgs {` binding.

- [ ] **Step 2: Replace the top-level `pkgs` binding in `flake.nix`**

Replace:
```nix
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ emacs-overlay.overlays.default ];
      };
```
with:
```nix
      # Only devShell + formatter use this; the NixOS systems build their own
      # pkgs (with the overlay) via nixpkgsModule.
      pkgs = nixpkgs.legacyPackages.${system};
```

- [ ] **Step 3: Run the test — no manual nixpkgs instantiation remains**

Run: `grep -n 'import nixpkgs' ~/dotfiles/flake.nix || echo "none"`
Expected (after): `none`

- [ ] **Step 4: Confirm devShell + formatter still resolve**

Run: `nix eval .#devShells.x86_64-linux.default.name`
Expected: prints the shell derivation name (e.g. `nix-shell`).

Run: `nix flake check`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add flake.nix
git commit -m "refactor(nix): single nixpkgs instantiation (devShell uses legacyPackages)"
```

---

## Task 5: Dedup cross-cutting config into `desktop.nix`

Pure refactor. Audio (rtkit+pipewire), Bluetooth, libinput, and the bootloader are currently defined in both hardware modules AND `desktop.nix`. Consolidate into `desktop.nix`; strip from hardware modules. The system derivation must be unchanged.

**Files:**
- Modify: `modules/nixos/desktop.nix` (ensure it owns all four; add libinput)
- Modify: `modules/nixos/hardware/hp-15-ef2013dx.nix` (remove the four)
- Modify: `modules/nixos/hardware/thinkpad-t14-gen5-amd.nix` (remove the four)

- [ ] **Step 1: Write the failing test — capture the baseline drvPaths**

Run and record both values:
```bash
nix eval .#nixosConfigurations.zord-old.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.zord.config.system.build.toplevel.drvPath
```
Also confirm the values that must survive the move:
```bash
nix eval .#nixosConfigurations.zord-old.config.services.pipewire.enable      # true
nix eval .#nixosConfigurations.zord-old.config.hardware.bluetooth.enable     # true
nix eval .#nixosConfigurations.zord-old.config.services.libinput.enable      # true
nix eval .#nixosConfigurations.zord-old.config.boot.loader.systemd-boot.enable  # true
```

- [ ] **Step 2: Make `desktop.nix` the sole owner of the four concerns**

Ensure `modules/nixos/desktop.nix` contains exactly one definition of each (it already has audio, bluetooth, and bootloader; add libinput). The desktop-owned block should read:

```nix
  # Input — touchpad (user preference, shared across hosts)
  services.libinput = {
    enable = true;
    touchpad = {
      naturalScrolling = true;
      disableWhileTyping = true;
    };
  };

  # Bluetooth
  hardware.bluetooth.enable = true;

  # Audio
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
```

(The existing `hardware.bluetooth.enable`, audio, and boot blocks in `desktop.nix` already match — do not duplicate them; only add the `services.libinput` block.)

- [ ] **Step 3: Remove the four concerns from `hp-15-ef2013dx.nix`**

Delete from `modules/nixos/hardware/hp-15-ef2013dx.nix`:
```nix
  # Audio
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Bluetooth
  hardware.bluetooth.enable = true;

  # Touchpad
  services.libinput = {
    enable = true;
    touchpad = {
      naturalScrolling = true;
      disableWhileTyping = true;
    };
  };
```
and the bootloader block:
```nix
  # Bootloader
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };
```

- [ ] **Step 4: Remove the four concerns from `thinkpad-t14-gen5-amd.nix`**

Delete the identical `# Audio`, `# Bluetooth`, `# Touchpad`, and `# Bootloader` blocks from `modules/nixos/hardware/thinkpad-t14-gen5-amd.nix`. Keep: `boot.kernelParams`, `boot.initrd.availableKernelModules`, `boot.initrd.kernelModules = [ "amdgpu" ]`, `hardware.enableRedistributableFirmware`, `powerManagement.enable`, `services.power-profiles-daemon.enable`, and the disk-layout comment.

Note: the T14's bootloader must not vanish — it now comes from `desktop.nix` (the T14 imports `desktop.nix` via `hosts/zord/configuration.nix`). Confirm in Step 6.

- [ ] **Step 5: Verify the retained values are unchanged**

Run:
```bash
nix eval .#nixosConfigurations.zord-old.config.services.pipewire.enable      # true
nix eval .#nixosConfigurations.zord-old.config.hardware.bluetooth.enable     # true
nix eval .#nixosConfigurations.zord-old.config.services.libinput.enable      # true
nix eval .#nixosConfigurations.zord-old.config.boot.loader.systemd-boot.enable  # true
nix eval .#nixosConfigurations.zord.config.boot.loader.systemd-boot.enable   # true
```
Expected: all `true`.

- [ ] **Step 6: Verify the system derivation is unchanged (pure refactor)**

Run:
```bash
nix eval .#nixosConfigurations.zord-old.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.zord.config.system.build.toplevel.drvPath
```
Expected: **identical** to the Step 1 baseline drvPaths. If they differ, a moved definition was not truly identical — stop and diff before committing.

- [ ] **Step 7: Commit**

```bash
git add modules/nixos/desktop.nix modules/nixos/hardware/hp-15-ef2013dx.nix modules/nixos/hardware/thinkpad-t14-gen5-amd.nix
git commit -m "refactor(nix): dedup audio/bluetooth/libinput/bootloader into desktop.nix"
```

---

## Task 6: Lint gate — statix / deadnix / fmt clean

**Files:**
- Modify: any files flagged by the linters (fixes only)

- [ ] **Step 1: Run the linters to see current state**

```bash
cd ~/dotfiles
nix fmt
nix run nixpkgs#statix -- check .
nix run nixpkgs#deadnix -- .
```
Expected: note any warnings (e.g. dead bindings, unused args, anti-patterns).

- [ ] **Step 2: Fix each reported issue**

Apply the specific fix statix/deadnix names (e.g. remove a genuinely-unused `let` binding, collapse a redundant pattern). Do NOT remove `dotfilesLib`/`ewm`/`config`/`lib`/`pkgs` module args that are part of the module interface even if unused in a given file — deadnix's `--no-lambda-arg` behavior; if deadnix flags a module arg that is intentionally part of the interface, leave it and note why.

- [ ] **Step 3: Re-run to confirm clean**

```bash
nix fmt
nix run nixpkgs#statix -- check .
nix run nixpkgs#deadnix -- .
nix flake check
```
Expected: no warnings; `nix flake check` passes.

- [ ] **Step 4: Commit**

```bash
# Scoped to tracked .nix files only — never `git add -u` (would sweep in the
# unrelated dirty base/claude/.claude/settings.json).
git add -u '*.nix'
git commit -m "style(nix): statix/deadnix/fmt clean for Phase 0"
```

---

## Final acceptance (whole phase)

- [ ] `nix flake check` passes.
- [ ] `nix eval .#nixosConfigurations.zord.config.nixpkgs.overlays --apply builtins.length` → `1` (overlay reaches the booted system).
- [ ] `nixos-rebuild build --flake .#zord` and `--flake .#zord-old` both complete.
- [ ] `nix eval .#homeConfigurations` errors (standalone HM removed); NixOS-integrated HM present.
- [ ] `grep 'import nixpkgs' flake.nix` → none (single instantiation).
- [ ] Tasks 2–5 left the system drvPaths unchanged relative to their pre-task baselines (only Task 1 changed them).
