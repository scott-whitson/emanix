# eminix Convergence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `eminix` name only the distribution, compose every machine through one code path, and retire stow.

**Architecture:** `profiles/eminix.nix` shrinks to the common core every eminix box shares (`os-system/base.nix`, `net/tailscale.nix`, `net/ssh.nix`, `i-intelligence/secrets.nix` — empirically the exact set whistle already imports by hand). Role profiles under `profiles/roles/` supply what a *kind* of box needs. `lib/mkHost.nix` gains a `role` argument and an optional `hardware`, so all three hosts compose through it. Then `base/` and stow are removed in favour of Home Manager.

**Tech Stack:** Nix flakes, NixOS, Home Manager, agenix, disko, nixos-wsl.

## Global Constraints

- **`system.stateVersion` is per-host and must never be shared or bumped.** It records the release a machine was first installed under.
- **Never regenerate an SSH host key during this work.** `secrets/secrets.nix` identifies agenix recipients by host public key, not hostname. Key strings — including stale comments like `root@eminix` and `root@weasel` — must stay **verbatim**.
- **Never add `Co-Authored-By` or tool-attribution trailers to commits.**
- All `.nix` files must pass `nixpkgs-fmt --check` before commit.
- Build command (used throughout): `nix build --no-link --print-out-paths .#nixosConfigurations.<host>.config.system.build.toplevel`
- Switch command: `sudo nixos-rebuild switch --flake ~/dotfiles#<host>`
- Rollout order for Phases B–D: `datacore` → `whistle` → `rafik`. **Phase A is the exception and runs `rafik` first**, since rafik is the host changing identity.

## File Structure

| File | Responsibility |
|---|---|
| `profiles/eminix.nix` | **Rewritten.** Common core only — what is true of every eminix box |
| `profiles/roles/workstation.nix` | **New.** Desktop + EWM + ollama + syncthing; sets gui/ewm/profile |
| `profiles/roles/server.nix` | **New.** Headless + syncthing; sets gui/ewm/profile |
| `profiles/roles/wsl.nix` | **New.** nixos-wsl; sets gui/ewm/ghostty/zellij/profile |
| `lib/mkHost.nix` | **Modified.** Gains `role`, `hardware` becomes optional |
| `flake.nix` | **Modified.** Three `mkHost` calls; ~90 lines of inline modules deleted |
| `hosts/rafik/configuration.nix` | **Renamed** from `hosts/eminix/` |
| `ioshi/hi-hardware/disko/rafik.nix` | **Renamed** from `disko/eminix.nix` |
| `ioshi/hi-hardware/hp-15-ef2013dx.nix` | **Modified.** Absorbs datacore's `mkForce` overrides once zord-old is gone |
| `ioshi/i-intelligence/zellij/` | **New dir.** Content moved out of `base/zellij/` |
| `ioshi/i-intelligence/pi/` | **New dir.** Content moved out of `base/pi/` |
| `bin/` | **Absorbs** `base/bin/.local/bin/*`. No module needed — `zsh.nix:35` already puts `$DOTFILES/bin` on PATH |
| `ioshi/i-intelligence/fragpaper.nix` | **New.** The four fragpaper systemd user units |
| `ioshi/i-intelligence/wireplumber.nix` | **New.** Ports `base/wireplumber/` |
| `ioshi/i-intelligence/emacs-daemon.nix` | **Renamed** from `standalone.nix` — it means "non-EWM Emacs as a user daemon", not "foreign distro" |
| `ioshi/i-intelligence/systemd.nix` | **Deleted** in Task 11 once its only content (the dot-sync timer) goes |
| `base/`, `bin/dot-restow`, `bin/dot-sync` | **Deleted** at the end of Phase C |

---

## Phase A — Rename eminix → rafik

### Task 1: Rename in-repo

**Files:**
- Modify: `flake.nix` (the `eminix` nixosConfigurations key)
- Rename: `hosts/eminix/` → `hosts/rafik/`
- Rename: `ioshi/hi-hardware/disko/eminix.nix` → `ioshi/hi-hardware/disko/rafik.nix`
- Modify: `secrets/secrets.nix` (variable name only)

**Interfaces:**
- Produces: `nixosConfigurations.rafik`. Every later task references `rafik`, never `eminix`, when it means the machine.

- [ ] **Step 1: Record the current closure as the baseline**

```bash
cd ~/dotfiles
nix build --no-link --print-out-paths .#nixosConfigurations.eminix.config.system.build.toplevel | tee /tmp/rafik-before.txt
```

Save that path. A rename changes `networking.hostName`, so the closure **will** move — the baseline is for diffing what moved, not for matching.

- [ ] **Step 2: Rename the directories and files with git mv**

```bash
git mv hosts/eminix hosts/rafik
git mv ioshi/hi-hardware/disko/eminix.nix ioshi/hi-hardware/disko/rafik.nix
```

- [ ] **Step 3: Update the flake entry**

In `flake.nix`, change the host key and its disko path. The `hostName` argument is what sets `networking.hostName`:

```nix
        # ThinkPad T14 Gen 5 AMD — daily driver
        rafik = mkHost {
          hostName = "rafik";
          hardware = ./ioshi/hi-hardware/lenovo-t14-gen5-amd.nix;
          extraModules = [
            nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen5
            ./hosts/rafik/configuration.nix
            disko.nixosModules.disko
            ./ioshi/hi-hardware/disko/rafik.nix
          ];
        };
```

- [ ] **Step 4: Rename the agenix recipient variable — but NOT the key string**

In `secrets/secrets.nix`, rename the binding `eminix` to `rafik` and update its use in `publicKeys`. **Leave the key string and its `root@eminix` comment byte-identical** — the host key was not regenerated, so that string is the machine's actual identity. Add a note matching the existing whistle precedent:

```nix
  # Key comment still reads root@eminix: the host was renamed to rafik on
  # 2026-08-07 but its SSH host key was NOT regenerated, so this string must
  # stay verbatim. Same situation as whistle (renamed from weasel 2026-08-04).
  rafik = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHiZAqCjE7nX2iXAlZDdZIzURl/X55ljlbpVHNlN9Za8 root@eminix";
```

- [ ] **Step 5: Confirm no stale references remain**

```bash
grep -rn "eminix" --include="*.nix" . | grep -v "profiles/eminix\|worktrees"
```

Expected: no hits referring to the *machine*. Hits for `profiles/eminix.nix`, "eminix instance" and "the eminix platform" are correct and must stay — those mean the distro.

- [ ] **Step 6: Format and build**

```bash
nixpkgs-fmt flake.nix secrets/secrets.nix
nix build --no-link --print-out-paths .#nixosConfigurations.rafik.config.system.build.toplevel
```

Expected: builds successfully. `.#nixosConfigurations.eminix` must now fail with an attribute error — that proves the rename took.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(rafik): rename the T14 from eminix to rafik

eminix now names only the distribution. The agenix key string keeps its
root@eminix comment verbatim — the host key was not regenerated, so that
string is still the machine's identity (same as whistle/weasel)."
```

### Task 2: Switch rafik and update off-repo identity

**Files:** none in-repo. This task is operational.

- [ ] **Step 1: Switch rafik**

```bash
sudo nixos-rebuild switch --flake ~/dotfiles#rafik
```

- [ ] **Step 2: Verify the hostname and that secrets still decrypt**

```bash
hostname                                    # expect: rafik
sudo systemctl status agenix                # expect: no failure
ls -l /run/agenix/openrouter-auth           # expect: exists, owner scott
```

**If the secret fails to decrypt, stop.** That means the host key changed, which contradicts the premise. Roll back with `sudo nixos-rebuild switch --rollback` and investigate before continuing.

- [ ] **Step 3: Rename the Tailscale node**

In the Tailscale admin console, rename the machine to `rafik` so MagicDNS resolves `rafik.<tailnet>.ts.net`. Then confirm from another host:

```bash
tailscale status | grep -i rafik
```

- [ ] **Step 4: Update ssh aliases on the other hosts**

On `whistle` and `datacore`, update any `Host eminix` block in `~/.ssh/config` to `Host rafik` and drop the stale `known_hosts` entry:

```bash
ssh-keygen -R eminix
```

The host key itself is unchanged, so the new entry will be accepted on first connect and will match the old fingerprint.

- [ ] **Step 5: Verify round-trip connectivity**

```bash
ssh rafik hostname      # from whistle — expect: rafik
ssh datacore hostname   # from rafik    — expect: datacore
```

- [ ] **Step 6: Commit any ssh config that lives in the repo**

If `~/.ssh/config` is repo-managed, commit the change. If it is hand-maintained, note that in the commit for Task 1 instead and skip this step.

---

## Phase B — Role profiles

### Task 3: Create the role profiles and extend mkHost

**Files:**
- Modify: `profiles/eminix.nix`
- Create: `profiles/roles/workstation.nix`, `profiles/roles/server.nix`, `profiles/roles/wsl.nix`
- Modify: `lib/mkHost.nix`, `flake.nix`

**Interfaces:**
- Produces: `mkHost { hostName, role, hardware ? null, extraModules ? [] }` where `role` is one of `"workstation" | "server" | "wsl"`. Tasks 4 and 5 call it with these exact names.

- [ ] **Step 1: Record baselines for all four hosts**

```bash
cd ~/dotfiles
for h in rafik zord-old whistle datacore; do
  echo "$h $(nix build --no-link --print-out-paths .#nixosConfigurations.$h.config.system.build.toplevel)"
done | tee /tmp/phaseB-before.txt
```

**`rafik`'s path is the gate.** This phase is a pure refactor for rafik; if its path moves in Step 8, behaviour changed by accident.

- [ ] **Step 2: Rewrite `profiles/eminix.nix` as the common core**

```nix
{ ... }:

{
  # The eminix distribution — common core.
  # What is true of EVERY eminix box, regardless of shape. This is exactly the
  # set whistle had been importing by hand before it moved to mkHost.
  #
  # Deliberately NOT here:
  #   - net/syncthing.nix  : system-level syncthing suits workstation/server,
  #                          but whistle runs an HM-level one (profile "wsl").
  #   - desktop/ewm/ollama : workstation concerns, see roles/workstation.nix
  imports = [
    ../ioshi/os-system/base.nix
    ../ioshi/hi-hardware/net/tailscale.nix
    ../ioshi/hi-hardware/net/ssh.nix
    ../ioshi/i-intelligence/secrets.nix
  ];
}
```

- [ ] **Step 3: Create `profiles/roles/workstation.nix`**

```nix
{ ... }:

{
  # A graphical eminix box: EWM compositor, local models, system syncthing.
  imports = [
    ../../ioshi/os-system/desktop.nix
    ../../ioshi/os-system/firstboot.nix
    ../../ioshi/i-intelligence/ewm.nix
    ../../ioshi/i-intelligence/ollama.nix
    ../../ioshi/hi-hardware/net/syncthing.nix
  ];

  # The role is the single source of truth for these three, which previously
  # encoded the same fact by hand in three places.
  home-manager.users.scott = {
    scott.gui = true;
    scott.ewm.enable = true;
    scott.dotfiles.profile = "desktop";
  };
}
```

- [ ] **Step 4: Create `profiles/roles/server.nix`**

```nix
{ ... }:

{
  # A headless eminix box.
  imports = [
    ../../ioshi/os-system/server.nix
    ../../ioshi/hi-hardware/net/syncthing.nix
  ];

  home-manager.users.scott = {
    scott.gui = false;
    scott.ewm.enable = false;
    scott.dotfiles.profile = "server";
  };
}
```

- [ ] **Step 5: Create `profiles/roles/wsl.nix`**

`nixos-wsl` arrives through `specialArgs` (wired in Step 6).

```nix
{ nixos-wsl, ... }:

{
  # An eminix instance inside WSL. No hardware layer — nixos-wsl supplies
  # boot and mounts, WSLg supplies the display.
  imports = [ nixos-wsl.nixosModules.default ];

  home-manager.users.scott = {
    scott.gui = false;
    scott.ewm.enable = false;
    # gui = false, but a real terminal under WSLg is still wanted, and ssh
    # sessions from other hosts land in zellij. Both opt in surgically.
    scott.ghostty.enable = true;
    scott.zellij.enable = true;
    scott.dotfiles.profile = "wsl";
  };
}
```

- [ ] **Step 6: Rewrite `lib/mkHost.nix`**

Two details matter. `networking.hostName` uses `mkDefault` so whistle can force it empty (WSL bug NixOS-WSL#888). `system.name` is deliberately **not** set here — setting it would move rafik's closure and break this phase's gate.

```nix
# mkHost — compose an eminix nixosSystem from a role and an optional hi layer.
# The flake applies the first argument set (its inputs + shared modules); each
# host calls the result with { hostName, role, hardware ? null, extraModules ? [] }.
{ nixpkgs, home-manager, ewm, agenix, nixos-wsl, nixpkgsModule, hmModule, sharedSpecialArgs, system }:
{ hostName, role, hardware ? null, extraModules ? [ ] }:
nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = sharedSpecialArgs // { inherit ewm nixos-wsl; };
  modules = [
    ../profiles/eminix.nix
    ../profiles/roles/${role}.nix
    # mkDefault: whistle must force this empty — NixOS setting the hostname at
    # activation breaks WSL's systemd user-session bootstrap (NixOS-WSL#888).
    { networking.hostName = nixpkgs.lib.mkDefault hostName; }
    nixpkgsModule
    agenix.nixosModules.default
    home-manager.nixosModules.home-manager
    hmModule
  ]
  ++ nixpkgs.lib.optional (hardware != null) hardware
  ++ extraModules;
}
```

- [ ] **Step 7: Pass `nixos-wsl` into mkHost and add `role` to the existing calls**

In `flake.nix`, add `nixos-wsl` to the `mkHost` argument set, and give `rafik` and `zord-old` their roles:

```nix
      mkHost = import ./lib/mkHost.nix {
        inherit nixpkgs home-manager ewm agenix nixos-wsl nixpkgsModule hmModule sharedSpecialArgs system;
      };
```

```nix
        zord-old = mkHost {
          hostName = "zord-old";
          role = "workstation";
          hardware = ./ioshi/hi-hardware/hp-15-ef2013dx.nix;
          extraModules = [ ./hosts/zord-old/configuration.nix ];
        };

        rafik = mkHost {
          hostName = "rafik";
          role = "workstation";
          hardware = ./ioshi/hi-hardware/lenovo-t14-gen5-amd.nix;
          extraModules = [
            nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen5
            ./hosts/rafik/configuration.nix
            disko.nixosModules.disko
            ./ioshi/hi-hardware/disko/rafik.nix
          ];
        };
```

Leave `whistle` and `datacore` inline for now — Task 4 moves them.

- [ ] **Step 8: Verify rafik's closure is byte-identical**

```bash
nixpkgs-fmt profiles/eminix.nix profiles/roles/*.nix lib/mkHost.nix flake.nix
nix build --no-link --print-out-paths .#nixosConfigurations.rafik.config.system.build.toplevel
```

Compare against `/tmp/phaseB-before.txt`. **The path must match exactly.**

If it differs, find out why before proceeding — `nix-diff` the two derivations:

```bash
nix-diff $(grep rafik /tmp/phaseB-before.txt | awk '{print $2}') <new-path>
```

The most likely causes are a module that moved between core and role, or `system.name` having been set.

- [ ] **Step 9: Verify zord-old too**

```bash
nix build --no-link --print-out-paths .#nixosConfigurations.zord-old.config.system.build.toplevel
```

Also expected to match its baseline. It is deleted in Task 4, but a match here confirms the refactor is clean for both workstations.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "refactor(profiles): split eminix into a common core plus role profiles

profiles/eminix.nix now holds only what every eminix box shares — which is
exactly the set whistle had been importing by hand. Roles supply the rest.
The role also sets scott.gui / ewm.enable / dotfiles.profile, which
previously encoded the same fact in three hand-maintained places.

rafik and zord-old closures are byte-identical, confirming pure refactor."
```

### Task 4: Move whistle and datacore onto mkHost, delete zord-old

**Files:**
- Modify: `flake.nix`, `hosts/whistle/configuration.nix`
- Delete: `hosts/zord-old/`

- [ ] **Step 1: Force whistle's empty hostname**

`mkHost` now sets `networking.hostName` with `mkDefault`, but whistle assigns it plainly. Change `hosts/whistle/configuration.nix` to force it, so intent is explicit rather than relying on precedence:

```nix
  networking.hostName = lib.mkForce "";
```

- [ ] **Step 2: Replace whistle's inline definition**

The role now supplies `nixos-wsl`, `gui`, `ewm.enable`, `ghostty.enable`, `zellij.enable` and `profile`, so only the genuinely host-specific bits remain:

```nix
        whistle = mkHost {
          hostName = "whistle";
          role = "wsl";
          extraModules = [
            ./hosts/whistle/configuration.nix
            {
              # Syncthing ports moved off the defaults during Debian
              # cohabitation. Debian retired 2026-08-04 — see Step 6.
              home-manager.users.scott = {
                services.syncthing.guiAddress = "127.0.0.1:8385";
                services.syncthing.settings.options.listenAddresses = [
                  "tcp://0.0.0.0:22001"
                  "quic://0.0.0.0:22001"
                ];
              };
            }
          ];
        };
```

- [ ] **Step 3: Replace datacore's inline definition**

```nix
        datacore = mkHost {
          hostName = "datacore";
          role = "server";
          hardware = ./ioshi/hi-hardware/hp-15-ef2013dx.nix;
          extraModules = [
            ./hosts/datacore/configuration.nix
            disko.nixosModules.disko
            ./ioshi/hi-hardware/disko/datacore.nix
          ];
        };
```

Keep datacore's `mkForce` block for `fileSystems`/`swapDevices`/`luks.devices` for now — Task 5 removes it.

- [ ] **Step 4: Delete zord-old**

```bash
git rm -r hosts/zord-old
```

Remove its `nixosConfigurations.zord-old` entry from `flake.nix`.

- [ ] **Step 5: Build both migrated hosts**

```bash
nixpkgs-fmt flake.nix hosts/whistle/configuration.nix
for h in whistle datacore rafik; do
  echo "$h $(nix build --no-link --print-out-paths .#nixosConfigurations.$h.config.system.build.toplevel)"
done
```

Expected: all three build. `rafik` must still match its Task 3 path. `whistle` and `datacore` legitimately move — they gain the common core.

- [ ] **Step 6: Diff what whistle and datacore actually gained**

```bash
nix-diff <old-whistle-path> <new-whistle-path> | head -50
```

Expected for whistle: **no change at all**, or only trivial ordering. It already imported `base.nix`, `tailscale.nix`, `ssh.nix` and `secrets.nix` by hand — the common core is that same set. If something substantive appears, the core is wrong.

Expected for datacore: it gains `tailscale.nix` and `ssh.nix` if it did not import them before. Confirm that is intended and does not conflict with anything in `hosts/datacore/configuration.nix`.

- [ ] **Step 7: Determine whether whistle's syncthing port overrides are still needed**

They exist only because whistle shared a network namespace with the Debian WSL distro, which was retired 2026-08-04. On whistle:

```bash
ss -ltnp | grep -E '8384|8385|22000|22001'
```

If nothing else holds 8384/22000, the overrides are vestigial. **Removing them changes the ports other devices connect to**, so if you remove them, re-pair with datacore in the Syncthing UI. If in doubt, keep them and note the decision — they are harmless.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(flake): compose whistle and datacore via mkHost; delete zord-old

All three hosts now go through one code path. flake.nix loses ~90 lines of
inline module lists that duplicated what mkHost exists to provide.

zord-old is deleted rather than renamed: datacore superseded it on the same
physical HP. Its removal unblocks the hp-15-ef2013dx.nix cleanup in the
next commit."
```

### Task 5: Fold datacore's overrides into the hardware module

**Files:**
- Modify: `ioshi/hi-hardware/hp-15-ef2013dx.nix`, `flake.nix`

- [ ] **Step 1: Read both sides**

`hp-15-ef2013dx.nix` currently describes zord-old's LUKS-encrypted install with literal `/dev/mapper/cryptroot` devices. It was pinned byte-identical so zord-old's derivation path would not move. datacore is unencrypted with its own GPT partlabel layout, so it overrides those with `mkForce` in `flake.nix`.

With zord-old deleted, the hardware file has exactly one consumer and can simply be correct.

- [ ] **Step 2: Move the real values into the hardware module**

Replace the LUKS-era `fileSystems`, `swapDevices` and `boot.initrd.luks.devices` in `hp-15-ef2013dx.nix` with datacore's actual values:

```nix
  boot.initrd.luks.devices = { };
  fileSystems."/boot".device = "/dev/disk/by-partlabel/disk-main-boot";
  fileSystems."/".device = "/dev/disk/by-partlabel/disk-main-root";
  fileSystems."/nix".device = "/dev/disk/by-partlabel/disk-main-root";
  fileSystems."/home".device = "/dev/disk/by-partlabel/disk-main-root";
  swapDevices = [{ device = "/dev/disk/by-partlabel/disk-main-swap"; }];
```

Update the file's header comment: it is now datacore's hardware module, not a shared one.

- [ ] **Step 3: Delete the mkForce block from flake.nix**

Remove the entire `{ boot.initrd.luks.devices = mkForce { }; ... }` module from datacore's `extraModules`, and the comment above it explaining the byte-identical pin.

- [ ] **Step 4: Verify datacore's closure did not move**

```bash
nixpkgs-fmt ioshi/hi-hardware/hp-15-ef2013dx.nix flake.nix
nix build --no-link --print-out-paths .#nixosConfigurations.datacore.config.system.build.toplevel
```

Expected: **identical to the Task 4 Step 5 path.** `mkForce X` and simply defining `X` produce the same final value, so the closure must not move. If it does, a value was transcribed wrong.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(hardware): fold datacore's disk overrides into hp-15-ef2013dx.nix

The file was pinned byte-identical so zord-old's drvPath would not move,
which forced datacore to mkForce its own fileSystems/swapDevices/luks
devices from flake.nix. zord-old is gone, so the module can just be
correct. Closure unchanged."
```

### Task 6: Roll out Phase B

- [ ] **Step 1: Switch datacore**

```bash
ssh datacore 'sudo nixos-rebuild switch --flake ~/projects/dotfiles#datacore'
```

Note datacore's checkout is at `~/projects/dotfiles`, not `~/dotfiles`. Pull first if it is behind.

- [ ] **Step 2: Verify datacore**

```bash
ssh datacore 'hostname; systemctl is-system-running; systemctl is-active syncthing tailscaled sshd'
```

Expected: `datacore`, then `running` (or `degraded` with a pre-existing unrelated failure), then `active` for each.

- [ ] **Step 3: Switch and verify whistle**

```bash
sudo nixos-rebuild switch --flake ~/dotfiles#whistle
hostname                                  # expect: whistle (from wsl.conf)
systemctl --user is-active emacs syncthing
```

**If the user manager fails**, that is the known WSL cgroup-squatting bug — `wsl-user-session-rescue.service` should heal it. Check with `systemctl status wsl-user-session-rescue`.

- [ ] **Step 4: Switch and verify rafik**

```bash
sudo nixos-rebuild switch --flake ~/dotfiles#rafik
hostname                                  # expect: rafik
systemctl --user is-active emacs
```

rafik's closure is byte-identical to what is already running, so this should be a no-op activation.

- [ ] **Step 5: Push**

```bash
git push origin main
git push eminix main
```

---

## Phase C — Stow retirement

### Task 7: Move zellij content out of base/

**Files:**
- Move: `base/zellij/.config/zellij/` → `ioshi/i-intelligence/zellij/`
- Modify: `ioshi/i-intelligence/zellij.nix`

**Context for the implementer:** this is *not* a stow-vs-HM conflict. `~/.config/zellij` is already an HM `mkOutOfStoreSymlink` that points into `base/zellij`. Only the content's location changes.

- [ ] **Step 1: Move the content**

```bash
git mv base/zellij/.config/zellij ioshi/i-intelligence/zellij
git rm base/zellij/.stow-local-ignore
```

- [ ] **Step 2: Update the symlink target**

In `ioshi/i-intelligence/zellij.nix`:

```nix
    xdg.configFile."zellij".source = config.lib.file.mkOutOfStoreSymlink
      "${config.scott.dotfiles.path}/ioshi/i-intelligence/zellij";
```

Update the two comments that say "deployed live from base/zellij" and "the kdl files in base/zellij" to the new path.

- [ ] **Step 3: Switch and verify the symlink resolves**

```bash
sudo nixos-rebuild switch --flake ~/dotfiles#whistle
readlink -f ~/.config/zellij
```

Expected: `/home/scott/dotfiles/ioshi/i-intelligence/zellij`

- [ ] **Step 4: Verify zellij still starts with its plugins**

```bash
zellij -l default
```

Expected: the zellaude bar renders. Detach with the usual binding.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(zellij): move config out of base/ into the module's own dir

Not a stow migration — ~/.config/zellij was already an HM out-of-store
symlink pointing into base/zellij. Only the content location changes, so
the file stays live-editable exactly as before."
```

### Task 8: Move pi content out of base/

**Files:**
- Move: `base/pi/.pi/` → `ioshi/i-intelligence/pi/`
- Modify: `ioshi/i-intelligence/pi.nix:16,34`

- [ ] **Step 1: Move the content**

```bash
git mv base/pi/.pi ioshi/i-intelligence/pi
```

- [ ] **Step 2: Update both references in pi.nix**

Line 16 (`settings.json` install) and line 34 (`AGENTS.md` source) use relative store paths. Update them:

```nix
      run install -m 600 ${./pi/agent/settings.json} "$HOME/.pi/agent/settings.json"
```

```nix
    source = ./pi/agent/AGENTS.md;
```

- [ ] **Step 3: Build and verify the paths resolve**

```bash
nix build --no-link .#nixosConfigurations.rafik.config.system.build.toplevel
```

Expected: builds. A wrong relative path fails at evaluation with "path does not exist", so a successful build is the check.

- [ ] **Step 4: Switch and verify pi's files landed**

```bash
sudo nixos-rebuild switch --flake ~/dotfiles#whistle
ls -l ~/.pi/agent/settings.json ~/.pi/agent/AGENTS.md
```

Expected: both exist. `settings.json` is mode 600.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(pi): move agent config out of base/ into the module's own dir"
```

### Task 9: Deploy bin/ via Home Manager and drop the dead wrappers

**Files:**
- Create: `ioshi/i-intelligence/bin.nix`
- Delete: `base/bin/.local/bin/hypr-*` (5 files)
- Move: remaining `base/bin/.local/bin/*` → `bin/`
- Modify: `ioshi/i-intelligence/default.nix`

- [ ] **Step 1: Delete the Hyprland-era wrappers**

EWM replaced Hyprland; these call `hyprctl` and cannot work.

```bash
git rm base/bin/.local/bin/hypr-brightness \
       base/bin/.local/bin/hypr-calc \
       base/bin/.local/bin/hypr-cheatsheet \
       base/bin/.local/bin/hypr-rename-workspace \
       base/bin/.local/bin/hypr-wifi
rm -f ~/.local/bin/hypr-*
```

- [ ] **Step 2: Consolidate the remaining scripts into the top-level bin/**

The repo currently has two script dirs — `bin/` (dot-* tooling) and `base/bin/.local/bin/` (user-facing wrappers). Merge them:

```bash
git mv base/bin/.local/bin/firefox bin/
git mv base/bin/.local/bin/fragpaper-ctl bin/
git mv base/bin/.local/bin/fragpaper-launch bin/
git mv base/bin/.local/bin/fragpaper-playlist bin/
git mv base/bin/.local/bin/news bin/
git mv base/bin/.local/bin/obsidian bin/
git mv base/bin/.local/bin/pi bin/
git mv base/bin/.local/bin/trackpad-toggle bin/
git mv base/bin/.local/bin/window-picker bin/
git rm -r base/bin
```

- [ ] **Step 3: No Home Manager module is needed — confirm why**

`ioshi/i-intelligence/zsh.nix:35` already does `export PATH="$DOTFILES/bin:$PATH"`. Moving the scripts into `bin/` therefore puts them on PATH with no further work, and they stay live-editable because they are read from the checkout.

**Do not create a module that symlinks `~/.local/bin` to the repo.** That directory holds things this repo does not own — most importantly `~/.local/bin/claude`, which points into `~/.local/share/claude/versions/`. A whole-directory symlink would hide it and break the Claude Code CLI.

Verify the PATH line is present before relying on it:

```bash
grep -n 'DOTFILES/bin' ioshi/i-intelligence/zsh.nix
```

Expected: the `export PATH="$DOTFILES/bin:$PATH"` line.

- [ ] **Step 4: Remove the stale stow symlinks from ~/.local/bin**

These point into `base/bin`, which no longer exists. Remove only the ones this repo created — leave `claude` and anything else alone:

```bash
for f in firefox fragpaper-ctl fragpaper-launch fragpaper-playlist news obsidian pi trackpad-toggle window-picker \
         hypr-brightness hypr-calc hypr-cheatsheet hypr-rename-workspace hypr-wifi; do
  [ -L "$HOME/.local/bin/$f" ] && rm -f "$HOME/.local/bin/$f"
done
ls -la ~/.local/bin/
```

Expected: only `claude` (and any other non-dotfiles entries) remain.

- [ ] **Step 5: Verify the scripts still resolve**

```bash
which dot-theme-set firefox news pi
command -v claude
```

Expected: the first four resolve into `/home/scott/dotfiles/bin`, and `claude` still resolves — proof the CLI survived.

- [ ] **Step 6: Confirm the removed wrappers are gone**

```bash
ls ~/.local/bin/ | grep -E "^(hypr-|helix$)"; echo "exit=$?"
which hypr-wifi 2>/dev/null; echo "expect: not found"
```

Expected: no matching files and no resolvable `hypr-*` command.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(bin): deploy scripts via HM; drop the Hyprland wrappers

Merges base/bin/.local/bin into the top-level bin/ so there is one script
directory, deployed with mkOutOfStoreSymlink. The five hypr-* wrappers go:
they shell out to hyprctl, which EWM replaced."
```

### Task 10: Activate the dormant modules

**Files:**
- Modify: `ioshi/i-intelligence/default.nix`
- Delete: `base/btop`, `base/lf`, `base/mpv`, `base/yt-dlp`, `base/claude`, `base/nvim`, `base/hypr`

- [ ] **Step 1: Read each dormant module against the file it would replace**

`btop.nix`, `lf.nix`, `mpv.nix`, `yt-dlp.nix` and `claude.nix` have been commented out and may have drifted from what `base/` actually deploys. There is no mechanical diff for this — a `.nix` module and a `.conf` file are different formats — so read both and compare by hand:

```bash
for p in btop lf mpv yt-dlp claude; do
  echo "═══════ $p"
  echo "--- module:"; cat "ioshi/i-intelligence/$p.nix"
  echo "--- stow files:"; find "base/$p" -type f -exec sh -c 'echo "  → $1"; cat "$1"' _ {} \;
done 2>&1 | less
```

For each setting present in the `base/` file, confirm the module produces the same value. **Where they disagree, the `base/` file wins** — it is what has actually been running. Record any setting you carry over from `base/` into the module in the commit message, so the change is reviewable.

- [ ] **Step 2: Uncomment the five imports**

In `ioshi/i-intelligence/default.nix`, move `./btop.nix`, `./lf.nix`, `./mpv.nix`, `./yt-dlp.nix` and `./claude.nix` into the active list.

- [ ] **Step 3: Delete the superseded stow packages**

```bash
git rm -r base/btop base/lf base/mpv base/yt-dlp base/claude
```

- [ ] **Step 4: Delete the genuinely dead ones**

`nvim` — Emacs is the sole editor. `hypr` — EWM replaced Hyprland.

```bash
git rm -r base/nvim base/hypr
rm -rf ~/.config/nvim ~/.config/hypr
```

- [ ] **Step 5: Switch and verify each app reads its config**

```bash
sudo nixos-rebuild switch --flake ~/dotfiles#rafik
btop --version && ls -l ~/.config/btop/btop.conf
lf -version && ls -l ~/.config/lf/lfrc
```

Expected: each config path exists and is owned by the HM generation (a symlink into `/nix/store`).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(hm): activate the dormant btop/lf/mpv/yt-dlp/claude modules

Each had a module that was commented out while its base/ twin deployed via
stow, so both were maintained and only one won. Where they had drifted, the
base/ content wins — that is what has actually been running.

nvim and hypr are deleted outright: Emacs is the sole editor and EWM
replaced Hyprland."
```

### Task 11: Port the systemd user units and wireplumber

**Files:**
- Create: `ioshi/i-intelligence/fragpaper.nix`, `ioshi/i-intelligence/wireplumber.nix`
- Modify: `ioshi/i-intelligence/systemd.nix`, `ioshi/i-intelligence/default.nix`
- Delete: `base/systemd`, `base/wireplumber`

**These units are Debian-era and contain paths that do not exist on NixOS** — `/usr/bin/pkill`, `/bin/sleep`, `/usr/bin/systemctl`, `/bin/bash`. `fragpaper-resume` and the `ExecStop` have therefore been silently broken since the NixOS migration. The port below fixes them; that is a behaviour change and an intended one.

- [ ] **Step 1: Create `ioshi/i-intelligence/fragpaper.nix`**

Gated on `config.scott.gui` — a wallpaper daemon means nothing headless. The long `ExecStart` shader playlist is copied verbatim from the original unit; `%h/.local/share/fragpaper` is a deliberate out-of-store path because fragpaper is built outside Nix.

```nix
{ config, lib, pkgs, ... }:

{
  # Ported from base/systemd/.config/systemd/user/ during the stow retirement.
  # The originals hardcoded /usr/bin/pkill, /bin/sleep, /usr/bin/systemctl and
  # /bin/bash — none of which exist on NixOS, so ExecStop and the resume hook
  # had been failing silently since the migration. Now resolved from pkgs.
  config = lib.mkIf config.scott.gui {
    systemd.user.services.fragpaper = {
      Unit = {
        Description = "Fragpaper live wallpaper";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "%h/.local/share/fragpaper/target/release/fragpaper --bg-color \"#1a1b26\" --palette dark --playlist %h/.local/share/fragpaper/shaders/mandelbrot.frag:90 %h/.local/share/fragpaper/shaders/julia.frag:90 %h/.local/share/fragpaper/shaders/burningship.frag:60 %h/.local/share/fragpaper/shaders/gradient.frag:60 %h/.local/share/fragpaper/shaders/waveform.frag:45 %h/.local/share/fragpaper/shaders/mist.frag:45 ca:45 coral:60 highlife:45 morley:45 gliders:60 glidersrandom:60 rd:90 lenia:60 %h/.local/share/fragpaper/shaders/attractors.vert:%h/.local/share/fragpaper/shaders/attractors.frag:90";
        ExecStop = "${pkgs.procps}/bin/pkill -9 -f fragpaper";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStartSec = 10;
        Environment = [ "RUST_LOG=info" ];
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services.fragpaper-resume = {
      Unit = {
        Description = "Restart fragpaper after sleep/wake";
        After = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" "suspend-then-hibernate.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
        ExecStart = "${pkgs.systemd}/bin/systemctl --user restart fragpaper.service";
      };
      Install.WantedBy = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" "suspend-then-hibernate.target" ];
    };

    systemd.user.services.fragpaper-monitor = {
      Unit.Description = "Check if fragpaper is running and restart if not";
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c 'if ! ${pkgs.systemd}/bin/systemctl --user is-active --quiet fragpaper.service; then ${pkgs.systemd}/bin/systemctl --user restart fragpaper.service; fi'";
      };
    };

    systemd.user.timers.fragpaper-monitor = {
      Unit.Description = "Monitor fragpaper and restart if dead";
      Timer = {
        OnBootSec = 30;
        OnUnitActiveSec = 60;
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
```

- [ ] **Step 2: Handle the two drop-in overrides**

`hyprpolkitagent.service.d/override.conf` is Hyprland-era — **delete it, do not port**.

`syncthing.service.d/override.conf` contains only ordering:

```ini
[Unit]
After=network-online.target
Wants=network-online.target
```

Fold that into the existing syncthing config rather than recreating a drop-in. In `ioshi/hi-hardware/net/syncthing.nix`, add:

```nix
  systemd.services.syncthing = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
```

Note the original was a **user** unit drop-in while `net/syncthing.nix` declares a **system** service. Confirm which one actually runs on rafik before placing this — `systemctl is-active syncthing` versus `systemctl --user is-active syncthing`. Put the ordering on whichever is real.

- [ ] **Step 3: Delete the dot-sync units**

`dot-sync.service` and `dot-sync.timer` go — `dot-sync` itself is removed in Task 12. Also remove the now-dead `dot-sync` timer block from `ioshi/i-intelligence/systemd.nix`, which leaves that file with two empty attribute sets; delete the file and drop its import from `default.nix`.

- [ ] **Step 4: Port wireplumber**

One file, a WirePlumber drop-in that silences ACP probe warnings on AMD hardware. Create `ioshi/i-intelligence/wireplumber.nix`:

```nix
{ config, lib, ... }:

{
  config = lib.mkIf config.scott.gui {
    # Silences ACP-related boot warnings on AMD ("Failed to create
    # 'api.alsa.acp.device' device", "Path Mic ACP LED is not a volume or mute
    # control"). WirePlumber probes the AMD ACP platform device, which exposes a
    # non-standard LED control; the split-device feature then tries to open
    # hw:acp and fails because the ALSA ACP plugin is not available. Disabling
    # split mode skips the probe — the real cards (HDMI + HDA) still enumerate
    # normally via their PCI paths.
    xdg.configFile."wireplumber/wireplumber.conf.d/50-disable-acp-led.conf".text = ''
      monitor.alsa.properties = {
        api.alsa.split-enable = false
      }
    '';
  };
}
```

- [ ] **Step 5: Import both, delete the stow packages**

Add `./fragpaper.nix` and `./wireplumber.nix` to `default.nix`, then:

```bash
git rm -r base/systemd base/wireplumber
```

- [ ] **Step 6: Switch and verify the units exist and start**

```bash
sudo nixos-rebuild switch --flake ~/dotfiles#rafik
systemctl --user list-unit-files | grep fragpaper
systemctl --user is-active fragpaper
systemctl --user list-timers | grep fragpaper
```

Expected: the units are present and fragpaper is active. Confirm the wallpaper is actually rendering, not just that the unit claims success.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(systemd): port fragpaper and wireplumber to Home Manager

systemd.nix held only a dot-sync timer while the real user units lived in
base/systemd. fragpaper's four units and wireplumber's config move to HM,
both gated on scott.gui. The hyprpolkitagent drop-in is deleted (Hyprland-
era) and the dot-sync units go with dot-sync itself."
```

### Task 12: Remove stow

**Files:**
- Delete: `base/`, `bin/dot-restow`, `bin/dot-sync`
- Modify: `ioshi/i-intelligence/packages.nix`, `ioshi/i-intelligence/theme.nix`

- [ ] **Step 1: Confirm base/ is empty of anything still referenced**

```bash
find base -type f 2>/dev/null
grep -rn "base/" --include="*.nix" ioshi/ home/ profiles/ lib/ flake.nix
grep -rn "dot-restow\|dot-sync" bin/ ioshi/ --include="*" 2>/dev/null
```

Expected: no files under `base/`, and no `.nix` references. Any hit here is a task that was missed — fix it before continuing.

- [ ] **Step 2: Delete stow and its tooling**

```bash
git rm -r base 2>/dev/null || rmdir base
git rm bin/dot-restow bin/dot-sync
```

Remove `stow` from `ioshi/i-intelligence/packages.nix` along with the comment above it explaining that every node stows `base/`.

- [ ] **Step 3: Remove the now-dead enableSync option**

`scott.dotfiles.enableSync` existed only to gate the dot-sync timer. Remove the option from `ioshi/i-intelligence/theme.nix` and its assignment in `home/scott/default.nix`.

- [ ] **Step 4: Build all three hosts**

```bash
for h in rafik whistle datacore; do
  echo "$h $(nix build --no-link --print-out-paths .#nixosConfigurations.$h.config.system.build.toplevel)"
done
```

Expected: all build. A reference to a deleted option fails evaluation, so this is the real check.

- [ ] **Step 5: Verify nothing in $HOME still points at base/**

```bash
find ~ -maxdepth 4 -lname "*dotfiles/base*" 2>/dev/null
```

Expected: no output. Any dangling symlink here is a stow leftover — remove it.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: remove stow

base/ is empty, every consumer moved to Home Manager, and nothing in \$HOME
points into it. dot-restow, dot-sync, the stow package and the now-dead
scott.dotfiles.enableSync option all go with it.

One config system owns the home directory again."
```

---

## Phase D — Legacy prune and docs

### Task 13: Prune the Hyprland-era modules and the standalone flag

**Files:**
- Delete: `ioshi/i-intelligence/hyprland.nix`, `mako.nix`, `fuzzel.nix`
- Modify: `ioshi/i-intelligence/default.nix`, `theme.nix`
- Rename: `ioshi/i-intelligence/standalone.nix` → `emacs-daemon.nix`

- [ ] **Step 1: Delete the Hyprland-era modules**

They have been commented out of `default.nix` since EWM replaced Hyprland.

```bash
git rm ioshi/i-intelligence/hyprland.nix ioshi/i-intelligence/mako.nix ioshi/i-intelligence/fuzzel.nix
```

Remove their commented-out import lines from `default.nix`.

- [ ] **Step 2: Confirm scott.standalone is dead**

```bash
grep -rn "scott.standalone\|config.scott.standalone" --include="*.nix" .
```

It meant "Home Manager runs standalone on a foreign distro", and the last such node retired when datacore moved to NixOS. If the only hit is the option definition in `theme.nix`, delete the option. **If anything reads it, stop and report** — the premise is wrong.

- [ ] **Step 3: Rename standalone.nix**

Its name now misleads: it means "this host's Emacs is the non-EWM pgtk build run as a user daemon", not "foreign distro". whistle depends on it, so it stays — under a name that says what it does.

```bash
git mv ioshi/i-intelligence/standalone.nix ioshi/i-intelligence/emacs-daemon.nix
```

Update the import in `default.nix` and the cross-references in `ioshi/i-intelligence/emacs.nix` and `emacs/packages.nix` that mention `standalone.nix`.

- [ ] **Step 4: Build all three hosts**

```bash
for h in rafik whistle datacore; do
  nix build --no-link --print-out-paths .#nixosConfigurations.$h.config.system.build.toplevel
done
```

Expected: all build, and whistle's Emacs still comes from `emacs-daemon.nix`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: prune Hyprland-era modules; rename standalone.nix

hyprland/mako/fuzzel have been commented out since EWM replaced Hyprland.
scott.standalone meant 'HM on a foreign distro' and the last such node went
when datacore moved to NixOS.

standalone.nix keeps its job (whistle needs it) but not its name: it means
'non-EWM Emacs run as a user daemon', so it is now emacs-daemon.nix."
```

### Task 14: Refresh the docs

**Files:**
- Modify: `home/scott/default.nix`, `README.md`, `docs/manual/07-nix-roadmap.md`, `docs/manual/01-install.md`, `docs/manual/05-philosophy.md`

- [ ] **Step 1: Fix the stale header in home/scott/default.nix**

It reads "used by both zord-old (HP) and zord (T14)". Both names are now wrong:

```nix
  # Shared Home Manager config for every eminix instance.
  # Imported from the NixOS host configs via home-manager.users.scott.
```

- [ ] **Step 2: Rewrite or retire docs/manual/07-nix-roadmap.md**

It describes the Debian→NixOS migration as a future plan ("Status: Planning phase. Debian 13 (trixie) on zord."). That migration is complete. Either retire the file, or replace its contents with a short description of the finished architecture — core profile, roles, mkHost, three hosts.

- [ ] **Step 3: Sweep the manual for retired vocabulary**

```bash
grep -rniE "stow|base/|zord|hyprland|helix|nvim" docs/manual/ README.md
```

Fix anything describing the **present**. Leave anything describing the **past** — `01-install.md`'s Debian bootstrap chapter is history and should stay history, but should say so.

- [ ] **Step 4: Verify the spec's own claims still hold**

Re-read `docs/superpowers/specs/2026-08-07-eminix-convergence-design.md`. Where implementation diverged from it (for example, if whistle's syncthing overrides were kept rather than removed), add a short "as-built" note at the end rather than silently editing the design.

- [ ] **Step 5: Commit and push**

```bash
git add -A
git commit -m "docs: refresh for the eminix convergence

07-nix-roadmap.md described the Debian->NixOS migration as a future plan;
it is done. home/scott/default.nix still named zord and zord-old. Manual
references to stow, base/ and Hyprland now describe a system that no longer
exists.

Debian-era chapters are kept but marked as history."
git push origin main
git push eminix main
```

---

## Self-Review Notes

**Spec coverage.** Every section of the design maps to a task: rename → 1–2; role profiles → 3; mkHost unification and zord-old deletion → 4; hardware cleanup → 5 (unblocked by 4, exactly as the spec predicted); stow retirement → 7–12; legacy prune → 13; docs → 14. The spec's two read-before-touch items are resolved and encoded: agenix keying is Task 1 Step 4, and the zellij "conflict" turned out not to exist, which Task 7 states explicitly so the implementer does not go looking for one.

**Known divergence from the spec.** The spec listed `zellij` and `systemd` together as "reconcile, do not port". Investigation showed they are different problems: zellij is a pure content move (Task 7), while `systemd.nix` is nearly empty and the real units live in `base/systemd` (Task 11). The spec's framing was based on an unverified assumption; this plan reflects what is actually there.

**Verification gates.** Three closure-identity checks carry the correctness argument: rafik after Task 3 (pure refactor), rafik after Task 4, and datacore after Task 5 (`mkForce X` and defining `X` must agree). Phases A, C and D change content by design, so they verify behaviourally instead.
