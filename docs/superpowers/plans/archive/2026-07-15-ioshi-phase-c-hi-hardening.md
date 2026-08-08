# ioshi Phase C — hi-hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the `hi` layer: adopt `nixos-hardware` for the T14 (eminix), and consolidate the networking/session services into reusable `ioshi/hi-hardware/net/` modules that both eminix and zord-old share — with eminix gaining autologin, Tailscale, Syncthing, and OpenSSH.

**Architecture:** `nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen5` is added to eminix; the hand-rolled hardware file is trimmed to what the module doesn't cover. Net/session services move to shared modules: autologin into `ewm.nix` (the EWM session enabler), and Tailscale/SSH/Syncthing into `ioshi/hi-hardware/net/`, imported by `profiles/eminix.nix`.

**Tech Stack:** Nix flakes, NixOS, nixos-hardware, Tailscale/headscale, Syncthing.

## Global Constraints

- **No Nix on the WSL box.** Verify on zord-old via the loop: edit here → `git bundle create $BUNDLE main` → `scp` → on zord-old `cd ~/dotfiles-build && git fetch -q ~/dotfiles.bundle main && git reset -q --hard FETCH_HEAD` → `nix …`.
- **Gates are mixed:** C1 changes eminix's drv (gains microcode/pstate/s2idle) — functional gate. C2 must be **functionally invariant for zord-old** (net relocated faithfully; if the drv rehashes from module-order, confirm with `nix store diff-closures` = empty, as in Phase A4) and eminix gains the services.
- **Commits:** no `Co-Authored-By`; scope `git add`; push after each task.
- **nixos-hardware module confirmed to exist:** `lenovo-thinkpad-t14-amd-gen5` (`import ./lenovo/thinkpad/t14/amd/gen5`) — verified against nixos-hardware master flake.nix. It sets `acpi.ec_no_wakeup=1` + a kernel-version guard, and imports the T14/AMD parent + AMD-pstate common (microcode, pstate, firmware).
- **Tailscale authkey stays plaintext** (`/var/lib/tailscale-authkey`) this phase — agenix moves it in Phase D.

---

## Task C1: adopt nixos-hardware for eminix

**Files:**
- Modify: `flake.nix` (add `nixos-hardware` input + output arg; add its module to eminix's `extraModules`)
- Modify: `ioshi/hi-hardware/lenovo-t14-gen5-amd.nix` (trim redundant bits)

- [ ] **Step 1: Capture baselines (before)**

Sync `main` to zord-old, then record:
```bash
nix eval --raw .#nixosConfigurations.eminix.config.system.build.toplevel.drvPath     # EMINIX_C0
nix eval --raw .#nixosConfigurations.zord-old.config.system.build.toplevel.drvPath   # ZOLD_C0 (must stay invariant through C1)
```

- [ ] **Step 2: Add the `nixos-hardware` input to `flake.nix`**

In `inputs`:
```nix
    nixos-hardware.url = "github:NixOS/nixos-hardware";
```
In the `outputs = { … }:` argument set, add `nixos-hardware` (before `...`).

- [ ] **Step 3: Add the module to eminix's `extraModules`**

In `nixosConfigurations.eminix`, prepend the hardware module to `extraModules`:
```nix
        eminix = mkHost {
          hostName = "eminix";
          hardware = ./ioshi/hi-hardware/lenovo-t14-gen5-amd.nix;
          extraModules = [
            nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen5
            ./hosts/eminix/configuration.nix
            disko.nixosModules.disko
            ./ioshi/hi-hardware/disko/eminix.nix
          ];
        };
```

- [ ] **Step 4: Trim `ioshi/hi-hardware/lenovo-t14-gen5-amd.nix`**

Remove `hardware.enableRedistributableFirmware = true;` (nixos-hardware's parent sets it). KEEP: `boot.kernelParams = [ "quiet" ]`, `boot.initrd.availableKernelModules` (boot-device detection — nixos-hardware doesn't set these), `boot.initrd.kernelModules = [ "amdgpu" ]` (EWM DRM-race fix), `powerManagement.enable`, `services.power-profiles-daemon.enable`, and the disk-layout comment. Add a comment noting nixos-hardware now supplies firmware/microcode/pstate/s2idle.

- [ ] **Step 5: Sync + verify**

```bash
nix flake lock 2>&1 | tail -2   # locks the new nixos-hardware input (run where the bundle is fetched? no — lock happens from the edit side; see note)
sys=$(nix build --no-link --print-out-paths .#nixosConfigurations.eminix.config.system.build.toplevel 2>/dev/null)
echo "eminix builds: ${sys:+ok}"
echo "kernelParams: $(nix eval --json .#nixosConfigurations.eminix.config.boot.kernelParams 2>/dev/null)"   # expect both "quiet" and "acpi.ec_no_wakeup=1"
echo "amd microcode: $(nix eval .#nixosConfigurations.eminix.config.hardware.cpu.amd.updateMicrocode 2>/dev/null)"  # expect true (from nixos-hardware)
echo "zord-old drv (expect == ZOLD_C0): $(nix eval --raw .#nixosConfigurations.zord-old.config.system.build.toplevel.drvPath 2>/dev/null)"
```
Expected: eminix builds; kernelParams contains `quiet` + `acpi.ec_no_wakeup=1`; microcode true; zord-old drv unchanged (C1 doesn't touch it).

**NOTE on flake.lock:** the new input must be locked. `nix flake lock` runs on the edit side but this box has no nix. Instead, lock on zord-old against the bundle is not possible (read-only fetch). Approach: commit the flake.nix change, then on zord-old in the build clone run `nix flake lock` to generate `flake.lock`, copy the updated `flake.lock` back to this box (scp from zord-old), and amend it into the commit. Concretely:
```bash
# after committing flake.nix edit + syncing to zord-old:
ssh zord-old 'cd ~/dotfiles-build && /run/current-system/sw/bin/nix flake lock 2>&1 | tail -3'
scp zord-old:~/dotfiles-build/flake.lock ~/dotfiles/flake.lock
# then git add flake.lock and amend/commit
```

- [ ] **Step 6: Commit + push** (flake.nix + flake.lock + trimmed hardware file)

```bash
git add flake.nix flake.lock ioshi/hi-hardware/lenovo-t14-gen5-amd.nix
git commit -m "feat(hi): adopt nixos-hardware lenovo-t14-amd-gen5 for eminix; trim hand-rolled hw"
GIT_SSH_COMMAND='ssh -o BatchMode=yes' git push origin main
```

---

## Task C2: consolidate net/session into shared modules

**Files:**
- Modify: `ioshi/i-intelligence/ewm.nix` (add autologin)
- Create: `ioshi/hi-hardware/net/tailscale.nix`, `ioshi/hi-hardware/net/ssh.nix`, `ioshi/hi-hardware/net/syncthing.nix`
- Modify: `profiles/eminix.nix` (import the net modules)
- Modify: `hosts/zord-old/configuration.nix` (remove the now-shared services)

- [ ] **Step 1: Capture baseline (zord-old must stay functionally invariant)**

```bash
nix build --no-link --print-out-paths .#nixosConfigurations.zord-old.config.system.build.toplevel 2>/dev/null   # ZOLD_C1 build path
```

- [ ] **Step 2: Add autologin to `ewm.nix`**

Add (EWM is the tty1 session; LUKS gates the machine):
```nix
  # Autologin scott on the console — EWM's tty1 launch hook takes over from here.
  services.getty.autologinUser = "scott";
```

- [ ] **Step 3: Create `ioshi/hi-hardware/net/tailscale.nix`**

```nix
{ ... }:
{
  # Tailscale over self-hosted headscale. Fresh-install join ritual:
  #   datacore$ docker exec headscale headscale preauthkeys create --user 1 --expiration 1h
  #   host$     echo '<key>' | sudo tee /var/lib/tailscale-authkey
  #             sudo systemctl restart tailscaled-autoconnect
  # (authKeyFile moves to agenix in Phase D.)
  services.tailscale = {
    enable = true;
    authKeyFile = "/var/lib/tailscale-authkey";
    extraUpFlags = [ "--login-server=https://headscale.stonewallmapletree.com" ];
  };
  services.resolved.enable = true;
}
```

- [ ] **Step 4: Create `ioshi/hi-hardware/net/ssh.nix`**

```nix
{ ... }:
{
  services.openssh.enable = true;
  users.users.scott.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHeRiEMkgSu+cBXTs7ekkJdT5JzJYCfDadrpFgDFn560 scott@datacore"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINW1gKUfmcHDWf02SHUpZuIZEqq7qk4IJfmd8hlLAUQi swhitson-11l"
  ];
}
```

- [ ] **Step 5: Create `ioshi/hi-hardware/net/syncthing.nix`**

Copy zord-old's `services.syncthing` block verbatim (user=scott, group=users, dataDir/configDir, openDefaultPorts, overrideDevices/Folders, settings.devices.datacore.id + folders pi-agent & docs). Each host gets a unique device id automatically; **datacore must pair each host** (deploy step — note in Phase E runbook).

- [ ] **Step 6: Import net modules in `profiles/eminix.nix`**

```nix
  imports = [
    ../ioshi/os-system/base.nix
    ../ioshi/os-system/desktop.nix
    ../ioshi/i-intelligence/ewm.nix
    ../ioshi/hi-hardware/net/tailscale.nix
    ../ioshi/hi-hardware/net/ssh.nix
    ../ioshi/hi-hardware/net/syncthing.nix
  ];
```

- [ ] **Step 7: Remove the now-shared services from `hosts/zord-old/configuration.nix`**

Delete the `services.getty.autologinUser`, `services.openssh` + `users.users.scott.openssh.authorizedKeys`, `services.tailscale` + `services.resolved`, and `services.syncthing` blocks. The file becomes an empty/near-empty host anchor (`{ ... }: { }` plus any truly host-unique comment).

- [ ] **Step 8: Sync + verify**

```bash
newzold=$(nix build --no-link --print-out-paths .#nixosConfigurations.zord-old.config.system.build.toplevel 2>/dev/null)
echo "zord-old builds: ${newzold:+ok}"
echo "=== zord-old functionally invariant? (diff-closures vs ZOLD_C1 — expect empty) ==="
nix store diff-closures <ZOLD_C1> "$newzold"
echo "=== eminix gained the services ==="
for h in eminix zord-old; do
  echo "$h: autologin=$(nix eval --raw .#nixosConfigurations.$h.config.services.getty.autologinUser 2>/dev/null) tailscale=$(nix eval .#nixosConfigurations.$h.config.services.tailscale.enable 2>/dev/null) ssh=$(nix eval .#nixosConfigurations.$h.config.services.openssh.enable 2>/dev/null) syncthing=$(nix eval .#nixosConfigurations.$h.config.services.syncthing.enable 2>/dev/null)"
done
nix build --no-link .#nixosConfigurations.eminix.config.system.build.toplevel && echo "eminix build OK"
nix flake check 2>&1 | tail -1
```
Expected: zord-old builds; diff-closures empty (functionally invariant — net merely relocated); both hosts show autologin=scott, tailscale=true, ssh=true, syncthing=true; eminix builds; `all checks passed!`.

- [ ] **Step 9: Commit + push**

```bash
git add ioshi/i-intelligence/ewm.nix ioshi/hi-hardware/net/ profiles/eminix.nix hosts/zord-old/configuration.nix
git commit -m "feat(hi): shared net/ layer (tailscale, ssh, syncthing) + autologin; eminix joins"
GIT_SSH_COMMAND='ssh -o BatchMode=yes' git push origin main
```

---

## Final acceptance (Phase C)

- [ ] `nixos-hardware` locked in `flake.lock`; eminix imports `lenovo-thinkpad-t14-amd-gen5`; `kernelParams` has `acpi.ec_no_wakeup=1`; AMD microcode on.
- [ ] `ioshi/hi-hardware/lenovo-t14-gen5-amd.nix` trimmed to non-redundant bits (kept: availableKernelModules, initrd amdgpu, quiet, power-profiles-daemon).
- [ ] Net/session services live once in `ioshi/hi-hardware/net/` (+ autologin in ewm.nix), imported by `profiles/eminix.nix`; removed from zord-old's host config.
- [ ] Both eminix and zord-old: autologin=scott, tailscale/ssh/syncthing enabled.
- [ ] zord-old closure functionally unchanged by C2 (diff-closures empty).
- [ ] `nix flake check` passes; eminix + zord-old build.
