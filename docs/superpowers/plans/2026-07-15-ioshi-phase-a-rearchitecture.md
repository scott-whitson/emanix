# ioshi Phase A — Rearchitecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recarve the repo from technology-split (`modules/nixos` + `modules/home-manager`) into the ioshi concern-split (`ioshi/{i-intelligence,os-system,hi-hardware}` + `profiles/eminix` + `lib/mkHost`), and rename the T14 host `zord` → `eminix`.

**Architecture:** Concern-based layers at repo depth 2 (so relative imports inside moved modules are preserved). Hosts compose the `eminix` profile + their `hi` layer via `lib/mkHost`. Everything except the rename is behavior-neutral, guarded by per-host derivation-path (drv) invariance.

**Tech Stack:** Nix flakes, NixOS, Home Manager, disko, git (`git mv` to preserve history).

## Global Constraints

- **No Nix on the WSL authoring box.** Every `nix …` command runs on zord-old via the sync loop: edit here → `git bundle create $BUNDLE main` → `scp $BUNDLE zord-old:~/dotfiles.bundle` → on zord-old `cd ~/dotfiles-build && git fetch -q ~/dotfiles.bundle main && git reset -q --hard FETCH_HEAD` → `nix eval …`. zord-old already has flakes enabled; no `--extra-experimental-features` needed.
- **Correctness gate = drv-invariance.** For every task except A5 (rename), both hosts' `config.system.build.toplevel.drvPath` MUST be byte-identical before and after. A changed drv means a move was not faithful — stop and diff, do not commit.
- **Layer depth = 2.** `ioshi/<layer>/` sits at the same depth as the old `modules/<x>/`, so `../../lib`, `../../base` imports inside moved modules stay valid. Do NOT introduce deeper nesting in this phase (workspace/ sub-grouping is a later cosmetic step).
- **Commits:** NEVER add a `Co-Authored-By` trailer. Scope `git add` to the paths named in each task; never `git add -A` (unrelated dirty `base/claude/.claude/settings.json` must not be swept in). `git mv` preserves history — use it, not delete+create.
- **Host baselines (from Phase 0 end, commit `5c761dc`):** zord drv `ykwkmizv…`, zord-old drv `57hmk5w9…`. Re-capture live baselines in A1 Step 1 (they are the reference for A1–A4).
- **Canonical line = GitHub `main`.** Push after each task so the bundle reflects it.

---

## Task A1: os-system layer (move desktop, extract base)

**Files:**
- Move: `modules/nixos/desktop.nix` → `ioshi/os-system/desktop.nix`
- Create: `ioshi/os-system/base.nix`
- Modify: `hosts/zord/configuration.nix`, `hosts/zord-old/configuration.nix` (drop the now-shared base settings + fix the desktop import path)

**Interfaces:**
- Produces: `ioshi/os-system/base.nix` (a `{ pkgs, ... }:` module with the settings common to both hosts) and `ioshi/os-system/desktop.nix` (unchanged content).

- [ ] **Step 1: Capture live baselines (before any change)**

Sync current `main` to zord-old, then:
```bash
nix eval .#nixosConfigurations.zord.config.system.build.toplevel.drvPath      # record as ZORD_BASE
nix eval .#nixosConfigurations.zord-old.config.system.build.toplevel.drvPath  # record as ZOLD_BASE
```

- [ ] **Step 2: Move desktop.nix with history**

```bash
cd ~/dotfiles
mkdir -p ioshi/os-system
git mv modules/nixos/desktop.nix ioshi/os-system/desktop.nix
```

- [ ] **Step 3: Create `ioshi/os-system/base.nix`** (verbatim common settings)

```nix
{ pkgs, ... }:

{
  # os layer — settings shared by every eminix host.
  programs.zsh.enable = true;

  users.users.scott = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" "video" ];
    shell = pkgs.zsh;
  };

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  system.stateVersion = "24.11";
}
```

- [ ] **Step 4: Remove those settings from BOTH host configs and repoint the desktop import**

In `hosts/zord/configuration.nix` and `hosts/zord-old/configuration.nix`: delete the `programs.zsh.enable`, `users.users.scott`, `time.timeZone`, `i18n.defaultLocale`, `console.keyMap`, `nix.settings`, `nix.gc`, and `system.stateVersion` blocks (they now come from `base.nix`). In each `imports = [ … ]`, replace `../../modules/nixos/desktop.nix` with `../../ioshi/os-system/desktop.nix` and add `../../ioshi/os-system/base.nix`.

(Note: `zord-old` keeps its own extra settings — tailscale, syncthing, openssh, autologin — inline for now; they move in Phase C. `users.users.scott.openssh.authorizedKeys` on zord-old merges fine with base's `users.users.scott`.)

- [ ] **Step 5: Sync + verify drv-invariance**

Sync to zord-old (bundle→reset), then:
```bash
nix eval .#nixosConfigurations.zord.config.system.build.toplevel.drvPath      # MUST equal ZORD_BASE
nix eval .#nixosConfigurations.zord-old.config.system.build.toplevel.drvPath  # MUST equal ZOLD_BASE
```
Expected: both identical to Step 1. If either differs, a setting was not extracted faithfully — diff `config` and fix before committing.

- [ ] **Step 6: Commit + push**

```bash
git add ioshi/os-system/ hosts/zord/configuration.nix hosts/zord-old/configuration.nix
git commit -m "refactor(ioshi): os-system layer — shared base.nix + desktop.nix"
GIT_SSH_COMMAND='ssh -o BatchMode=yes' git push origin main
```

---

## Task A2: i-intelligence layer (Emacs/EWM/pi/workspace)

**Files:**
- Move: `modules/nixos/ewm.nix` → `ioshi/i-intelligence/ewm.nix`
- Move: `modules/home-manager/*` (all files + the `emacs/` dir) → `ioshi/i-intelligence/`
- Modify: `hosts/zord/configuration.nix`, `hosts/zord-old/configuration.nix` (repoint ewm import)
- Modify: `home/scott/default.nix` (repoint HM aggregator import)
- Modify: `modules/nixos/server.nix` (repoint HM import) — then move it in A3-adjacent note below

**Interfaces:**
- Produces: `ioshi/i-intelligence/default.nix` (the HM aggregator, moved unchanged — its internal `./theme.nix` etc. imports stay valid) and `ioshi/i-intelligence/ewm.nix` (system EWM module).

- [ ] **Step 1: Move the EWM system module + all HM modules with history**

```bash
cd ~/dotfiles
mkdir -p ioshi/i-intelligence
git mv modules/nixos/ewm.nix ioshi/i-intelligence/ewm.nix
git mv modules/home-manager/* ioshi/i-intelligence/
```
Both `modules/nixos/` and `modules/home-manager/` are now empty (or `modules/nixos/` still holds `server.nix` + `hardware/`).

- [ ] **Step 2: Verify no relative import inside moved files broke**

Depth is unchanged (2), so `../../lib/themes.nix` (swaylock.nix, ghostty.nix), `../../base/pi/...` (pi.nix), and the aggregator's `./*.nix` imports remain correct.
```bash
grep -rn '\.\./\.\./' ioshi/i-intelligence/   # expect only ../../lib and ../../base references, still valid
```

- [ ] **Step 3: Repoint the three external references**

- `home/scott/default.nix`: change `../../modules/home-manager` → `../../ioshi/i-intelligence`.
- `hosts/zord/configuration.nix` and `hosts/zord-old/configuration.nix`: change `../../modules/nixos/ewm.nix` → `../../ioshi/i-intelligence/ewm.nix`.
- `modules/nixos/server.nix`: change `../../modules/home-manager` → `../../ioshi/i-intelligence`.

- [ ] **Step 4: Sync + verify drv-invariance**

```bash
nix eval .#nixosConfigurations.zord.config.system.build.toplevel.drvPath      # MUST equal ZORD_BASE
nix eval .#nixosConfigurations.zord-old.config.system.build.toplevel.drvPath  # MUST equal ZOLD_BASE
```
Expected: both unchanged. A break here is almost always a missed import repoint (eval will name the missing path).

- [ ] **Step 5: Commit + push**

```bash
git add ioshi/i-intelligence/ home/scott/default.nix hosts/zord/configuration.nix hosts/zord-old/configuration.nix modules/nixos/server.nix
git commit -m "refactor(ioshi): i-intelligence layer — emacs/ewm/pi/workspace"
GIT_SSH_COMMAND='ssh -o BatchMode=yes' git push origin main
```

---

## Task A3: hi-hardware layer (hardware + disko)

**Files:**
- Move: `modules/nixos/hardware/thinkpad-t14-gen5-amd.nix` → `ioshi/hi-hardware/lenovo-t14-gen5-amd.nix`
- Move: `modules/nixos/hardware/hp-15-ef2013dx.nix` → `ioshi/hi-hardware/hp-15-ef2013dx.nix`
- Move: `hosts/zord/disko.nix` → `ioshi/hi-hardware/disko/eminix.nix`
- Move: `modules/nixos/server.nix` → `ioshi/os-system/server.nix` (fold datacore's server profile into os layer)
- Modify: `hosts/zord/configuration.nix`, `hosts/zord-old/configuration.nix`, `hosts/datacore/configuration.nix`, `flake.nix` (repoint moved paths)

- [ ] **Step 1: Move with history**

```bash
cd ~/dotfiles
mkdir -p ioshi/hi-hardware/disko
git mv modules/nixos/hardware/thinkpad-t14-gen5-amd.nix ioshi/hi-hardware/lenovo-t14-gen5-amd.nix
git mv modules/nixos/hardware/hp-15-ef2013dx.nix ioshi/hi-hardware/hp-15-ef2013dx.nix
git mv hosts/zord/disko.nix ioshi/hi-hardware/disko/eminix.nix
git mv modules/nixos/server.nix ioshi/os-system/server.nix
rmdir modules/nixos/hardware modules/nixos modules/home-manager 2>/dev/null || true
```

- [ ] **Step 2: Repoint references**

- `hosts/zord/configuration.nix`: `../../modules/nixos/hardware/thinkpad-t14-gen5-amd.nix` → `../../ioshi/hi-hardware/lenovo-t14-gen5-amd.nix`; `./disko.nix` → `../../ioshi/hi-hardware/disko/eminix.nix`.
- `hosts/zord-old/configuration.nix`: `../../modules/nixos/hardware/hp-15-ef2013dx.nix` → `../../ioshi/hi-hardware/hp-15-ef2013dx.nix`.
- `hosts/datacore/configuration.nix`: `../../modules/nixos/server.nix` → `../../ioshi/os-system/server.nix`.
- `flake.nix`: `diskoConfigurations.zord = import ./hosts/zord/disko.nix;` → `import ./ioshi/hi-hardware/disko/eminix.nix;`.

- [ ] **Step 3: Sync + verify drv-invariance**

```bash
nix eval .#nixosConfigurations.zord.config.system.build.toplevel.drvPath      # MUST equal ZORD_BASE
nix eval .#nixosConfigurations.zord-old.config.system.build.toplevel.drvPath  # MUST equal ZOLD_BASE
```
Expected: both unchanged. (The hardware file rename `thinkpad-…` → `lenovo-…` is content-identical; drv unaffected.)

- [ ] **Step 4: Commit + push**

```bash
git add ioshi/ hosts/ flake.nix
git commit -m "refactor(ioshi): hi-hardware layer — hardware modules + disko"
GIT_SSH_COMMAND='ssh -o BatchMode=yes' git push origin main
```

---

## Task A4: profiles/eminix + lib/mkHost + flake refactor

**Files:**
- Create: `profiles/eminix.nix`, `lib/mkHost.nix`
- Modify: `lib/default.nix` (expose `mkHost`)
- Modify: `flake.nix` (use `mkHost`; thin host list)
- Modify: `hosts/zord/configuration.nix`, `hosts/zord-old/configuration.nix` (reduce to host-unique + hi selection)

**Interfaces:**
- Consumes: all ioshi layer modules from A1–A3.
- Produces: `profiles/eminix.nix` (imports `ioshi/os-system/{base,desktop}.nix` + `ioshi/i-intelligence/ewm.nix`; the shared NixOS-side platform). `lib.mkHost { hostName; hardware; extraModules ? []; }` → a `nixosSystem`.

- [ ] **Step 1: Create `profiles/eminix.nix`**

```nix
# The eminix platform (NixOS side): os + i, composed. Hosts add their hi layer.
{ ... }:
{
  imports = [
    ../ioshi/os-system/base.nix
    ../ioshi/os-system/desktop.nix
    ../ioshi/i-intelligence/ewm.nix
  ];
}
```

- [ ] **Step 2: Create `lib/mkHost.nix`**

```nix
# mkHost: compose an eminix nixosSystem from a host's hi selection.
{ nixpkgs, home-manager, disko, ewm, nixpkgsModule, hmModule, sharedSpecialArgs, system }:
{ hostName, hardware, extraModules ? [] }:
nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = sharedSpecialArgs // { inherit ewm; };
  modules = [
    ../profiles/eminix.nix
    hardware
    { networking.hostName = hostName; }
    nixpkgsModule
    home-manager.nixosModules.home-manager
    hmModule
  ] ++ extraModules;
}
```

- [ ] **Step 3: Expose `mkHost` from `lib/default.nix`**

```nix
{
  theme = import ./themes.nix;
  mkHost = import ./mkHost.nix;
}
```
(`mkHost` is a curried function; the flake applies its first arg set. `lib/default.nix` stays a plain attrset — do not add a `{ pkgs }` param, per the Phase 0 fix.)

- [ ] **Step 4: Refactor `flake.nix` nixosConfigurations to use mkHost**

Replace the two inline `nixpkgs.lib.nixosSystem { … }` blocks with:
```nix
      mkHost = (import ./lib/mkHost.nix) {
        inherit nixpkgs home-manager disko ewm nixpkgsModule hmModule sharedSpecialArgs system;
      };
    in
    {
      nixosConfigurations = {
        zord-old = mkHost {
          hostName = "zord-old";
          hardware = ./ioshi/hi-hardware/hp-15-ef2013dx.nix;
          extraModules = [ ./hosts/zord-old/configuration.nix ];
        };
        zord = mkHost {
          hostName = "zord";
          hardware = ./ioshi/hi-hardware/lenovo-t14-gen5-amd.nix;
          extraModules = [ ./hosts/zord/configuration.nix disko.nixosModules.disko ./ioshi/hi-hardware/disko/eminix.nix ];
        };
      };
      # … diskoConfigurations, devShells, formatter unchanged …
```
(The `disko.nixosModules.disko` + disko layout move into zord's `extraModules`; `profiles/eminix.nix` no longer needs them. `networking.hostName` now comes from `mkHost`, so remove it from the host configs in Step 5.)

- [ ] **Step 5: Thin the host configs**

`hosts/zord/configuration.nix` and `hosts/zord-old/configuration.nix`: remove `networking.hostName` (now set by mkHost) and the `imports` of profile/hardware/disko (now supplied by mkHost/profile). What remains: only genuinely host-unique settings (zord: nothing left → may become `{ }`; zord-old: tailscale/syncthing/openssh/autologin block).

- [ ] **Step 6: Sync + verify drv-invariance**

```bash
nix eval .#nixosConfigurations.zord.config.system.build.toplevel.drvPath      # MUST equal ZORD_BASE
nix eval .#nixosConfigurations.zord-old.config.system.build.toplevel.drvPath  # MUST equal ZOLD_BASE
nix eval .#nixosConfigurations.zord.config.networking.hostName                # "zord"
```
Expected: both drvs unchanged (composition is equivalent to the old inline module list), hostName still `zord`.

- [ ] **Step 7: Commit + push**

```bash
git add flake.nix lib/ profiles/ hosts/
git commit -m "refactor(ioshi): profiles/eminix + lib/mkHost; hosts become thin"
GIT_SSH_COMMAND='ssh -o BatchMode=yes' git push origin main
```

---

## Task A5: rename zord → eminix

The one intentional behavior change. zord-old must stay invariant; zord's config becomes `eminix` (drv changes only by hostname).

**Files:**
- Move: `hosts/zord/` → `hosts/eminix/`
- Modify: `flake.nix` (output key `zord` → `eminix`; `hostName = "eminix"`; `diskoConfigurations.zord` → `eminix`; extraModules path)

- [ ] **Step 1: Move the host dir**

```bash
cd ~/dotfiles
git mv hosts/zord hosts/eminix
```

- [ ] **Step 2: Update `flake.nix`**

- Rename the `nixosConfigurations.zord` entry to `eminix`; set `hostName = "eminix"`; update `extraModules` path `./hosts/zord/configuration.nix` → `./hosts/eminix/configuration.nix`.
- Rename `diskoConfigurations.zord` → `diskoConfigurations.eminix`.

- [ ] **Step 3: Sync + verify**

```bash
nix eval .#nixosConfigurations.eminix.config.networking.hostName               # "eminix"
nix eval .#nixosConfigurations.zord-old.config.system.build.toplevel.drvPath   # MUST equal ZOLD_BASE
nix eval .#nixosConfigurations.zord 2>&1 | grep -qi "does not exist" && echo "zord gone: OK"
nix build .#nixosConfigurations.eminix.config.system.build.toplevel --no-link  # builds
```
Expected: hostName `eminix`; zord-old drv unchanged; `zord` output gone; eminix builds.

- [ ] **Step 4: Commit + push**

```bash
git add flake.nix hosts/
git commit -m "refactor(ioshi): rename T14 host zord -> eminix"
GIT_SSH_COMMAND='ssh -o BatchMode=yes' git push origin main
```

---

## Final acceptance (Phase A)

- [ ] Repo tree matches the north-star: `ioshi/{i-intelligence,os-system,hi-hardware}`, `profiles/eminix.nix`, `lib/mkHost.nix`, `hosts/{eminix,zord-old,datacore}`; `modules/` gone.
- [ ] `nix flake check` passes.
- [ ] `nixosConfigurations.eminix` and `.zord-old` both `nix build` clean.
- [ ] zord-old drv unchanged across the whole phase (`57hmk5w9…`/live baseline); only `eminix` differs from the old `zord` drv, and only by hostname.
- [ ] `git log` shows history preserved through the `git mv`s (`git log --follow ioshi/i-intelligence/emacs.nix` reaches the original commits).
