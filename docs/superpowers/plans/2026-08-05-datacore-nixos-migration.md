# Datacore → NixOS Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Operational caveat:** Only Part A (Tasks 1–4) is pure repo work executable
> from whistle. Parts B–E are migration operations needing the HP at a console
> (Task 5), ssh to live boxes, and Scott's go/no-go at each gate. Execute those
> inline with Scott present — never via unattended subagents.

**Goal:** Replace Debian datacore with fresh NixOS on the HP 15-ef2013dx (currently zord-old), preserving its identity (ssh host keys, syncthing device ID, tailnet name, data paths) so no other machine needs reconfiguring.

**Architecture:** NixOS owns the substrate (disko, sshd, tailscale, native syncthing, docker, backrest); the 22 app containers keep running from unmodified `~/projects/datacore-config` compose stacks. Two-pass rsync + single identity flip (spec: `docs/superpowers/specs/2026-08-05-datacore-nixos-design.md`).

**Tech Stack:** nix flake (`lib/mkHost` NOT used — composed directly like whistle), disko, agenix, home-manager, docker-compose, rsync, tailscale, syncthing, backrest/restic/B2.

## Global Constraints

- `system.stateVersion = "26.11"` (current release, matches whistle/eminix; never copied from the 24.11 skeleton, never bumped later).
- Disk is UNENCRYPTED btrfs (decision 2026-08-05: headless box must reboot unattended; B2 is the encrypted copy). Do not copy eminix's LUKS layout.
- Data path `/home/srv-data` verbatim — zero compose-file edits allowed.
- Identity is COPIED, never regenerated: `/etc/ssh/ssh_host_*`, syncthing `cert.pem`/`key.pem`, tailnet name `datacore`.
- The old laptop is never wiped or data-deleted during Parts A–D. Wipe happens only in Task 13 after the soak gate passes.
- `ioshi/i-intelligence/packages.nix` element order is derivation-load-bearing for eminix — this plan must not touch that file.
- Commit style: `type(scope): summary`, no Co-Authored-By trailers, spec-referencing bodies.
- New box joins the tailnet as `datacore-new` until cutover; `networking.hostName` is `datacore` from day one (only the tailnet name is temporary).
- Syncthing on the new box MUST NOT hold the hub's keys before cutover (two live nodes with one device ID corrupts the fleet's sync state).

---

## Part A — Repo preparation (from whistle, hardware not needed)

### Task 1: Disko layout for datacore

**Files:**
- Create: `ioshi/hi-hardware/disko/datacore.nix`

**Interfaces:**
- Produces: disko module consumed by Task 3's flake block and by the install-day `disko` run (Task 5). Mountpoints `/`, `/nix`, `/home`, `/home/srv-data`, `/boot`, swap.

- [ ] **Step 1: Write the disko file**

```nix
{ ... }: {
  # Datacore (HP 15-ef2013dx, 1 TB NVMe) — headless server layout.
  # UNENCRYPTED by decision (2026-08-05 spec Q&A): the box must reboot
  # unattended; B2/restic is the encrypted copy. @srv-data is its own
  # subvolume so snapshots/quotas can treat service data separately, but
  # the MOUNTPOINT stays /home/srv-data — compose stacks bind-mount that
  # path verbatim (global constraint).
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1"; # verify against lsblk on the installer before running disko (Task 5)
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "fmask=0077" "dmask=0077" ];
          };
        };
        swap = {
          size = "16G";
          content = { type = "swap"; };
        };
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes = {
              "@" = { mountpoint = "/"; mountOptions = [ "compress=zstd" ]; };
              "@nix" = { mountpoint = "/nix"; mountOptions = [ "compress=zstd" "noatime" ]; };
              "@home" = { mountpoint = "/home"; mountOptions = [ "compress=zstd" ]; };
              "@srv-data" = { mountpoint = "/home/srv-data"; mountOptions = [ "compress=zstd" ]; };
            };
          };
        };
      };
    };
  };
}
```

- [ ] **Step 2: Syntax-check the file**

Run: `nix eval --impure --expr 'builtins.attrNames (import ./ioshi/hi-hardware/disko/datacore.nix {}).disko.devices.disk'`
Expected: `[ "main" ]`

- [ ] **Step 3: Commit**

```bash
git add ioshi/hi-hardware/disko/datacore.nix
git commit -m "feat(datacore): disko layout — unencrypted btrfs, @srv-data subvolume at /home/srv-data"
```

### Task 2: Finish hosts/datacore/configuration.nix

**Files:**
- Modify: `hosts/datacore/configuration.nix` (full rewrite of the Phase-2 skeleton)

**Interfaces:**
- Consumes: `ioshi/os-system/server.nix` (docker, boot loader, networkmanager), `ioshi/hi-hardware/net/tailscale.nix`.
- Produces: the host module Task 3 wires into the flake. Syncthing configDir `/home/scott/.local/state/syncthing` and backrest config path `/home/scott/.config/backrest/config.json` are the exact destinations the cutover (Task 11) copies runtime state into.

- [ ] **Step 1: Rewrite the file**

```nix
{ config, lib, pkgs, ... }:

{
  # Datacore — headless home server: Immich + media stacks (docker compose,
  # ~/projects/datacore-config), syncthing fleet hub, git mirror, backrest→B2.
  # NixOS owns the substrate only; app workloads are compose stacks unchanged
  # from the Debian box. Spec: docs/superpowers/specs/2026-08-05-datacore-nixos-design.md
  networking.hostName = "datacore";

  imports = [
    ../../ioshi/os-system/server.nix
    ../../ioshi/hi-hardware/net/tailscale.nix
  ];

  programs.zsh.enable = true;

  users.users.scott = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    shell = pkgs.zsh;
  };

  services.openssh.enable = true;

  # Syncthing — the fleet hub. Device identity (cert.pem/key.pem) and the
  # hub's device/folder config are RUNTIME state copied from the old box at
  # cutover into configDir below. Deliberately NO overrideDevices /
  # overrideFolders: declaring folders here would fight the copied
  # config.xml that every peer already agrees with.
  services.syncthing = {
    enable = true;
    user = "scott";
    group = "users";
    dataDir = "/home/scott";
    configDir = "/home/scott/.local/state/syncthing";
    openDefaultPorts = true;
    guiAddress = "0.0.0.0:8384";
  };
  # GUI/REST reachable over the tailnet only — eminix administers the hub
  # via datacore:8384 (see ioshi/hi-hardware/net/syncthing.nix comment).
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8384 ];

  # Backrest — restic scheduler/UI for b2:scott-data-restic. nixpkgs ships
  # the package but no service module; config.json is runtime state copied
  # from the old box at cutover.
  systemd.services.backrest = {
    description = "Backrest (restic scheduler/UI)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      User = "scott";
      Group = "users";
      ExecStart = "${pkgs.backrest}/bin/backrest";
      Restart = "on-failure";
    };
    environment = {
      BACKREST_PORT = "127.0.0.1:9898";
      BACKREST_CONFIG = "/home/scott/.config/backrest/config.json";
      BACKREST_DATA = "/home/scott/.local/share/backrest";
      HOME = "/home/scott";
    };
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

  # First-install release (matches whistle/eminix era) — never bump.
  system.stateVersion = "26.11";
}
```

- [ ] **Step 2: Syntax-check**

Run: `nix-instantiate --parse hosts/datacore/configuration.nix >/dev/null && echo PARSE-OK`
Expected: `PARSE-OK`
(Full eval happens at Task 3's build gate — the module isn't in the flake yet.)

- [ ] **Step 3: Commit**

```bash
git add hosts/datacore/configuration.nix
git commit -m "feat(datacore): finish host config — syncthing hub, backrest unit, tailscale, stateVersion 26.11"
```

### Task 3: Wire datacore into the flake; retire standalone HM

**Files:**
- Modify: `flake.nix` (add `nixosConfigurations.datacore`, add `diskoConfigurations.datacore`, remove `homeConfigurations."scott@datacore"` and the now-unused standalone-HM support if nothing else consumes it)

**Interfaces:**
- Consumes: Task 1's disko file, Task 2's host module, the existing `./ioshi/hi-hardware/hp-15-ef2013dx.nix` hardware module (shared with zord-old until Task 13 deletes zord-old).
- Produces: `.#nixosConfigurations.datacore` — the install target for Task 5 and rebuild target ever after; `.#diskoConfigurations.datacore` for the installer's disko run.

- [ ] **Step 1: Read the whistle block** (`flake.nix`, the `nixosConfigurations.whistle` entry) and note its exact home-manager wiring shape (`hmModule`, inline `scott.*` options). The datacore block mirrors it minus the WSL module.

- [ ] **Step 2: Add the datacore block** to `nixosConfigurations`, after `whistle`:

```nix
        # Headless home server on the HP freed by zord's T14 move — replaces
        # Debian datacore (spec 2026-08-05-datacore-nixos-design.md). Not an
        # eminix instance (no EWM layer), so composed here, not via mkHost.
        # Hardware module shared with zord-old until zord-old is deleted
        # post-soak.
        datacore = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = sharedSpecialArgs;
          modules = [
            ./hosts/datacore/configuration.nix
            ./ioshi/hi-hardware/hp-15-ef2013dx.nix
            disko.nixosModules.disko
            ./ioshi/hi-hardware/disko/datacore.nix
            nixpkgsModule
            agenix.nixosModules.default
            home-manager.nixosModules.home-manager
            hmModule
            {
              home-manager.users.scott = {
                scott.gui = false;
                scott.dotfiles.profile = "server";
              };
            }
          ];
        };
```

Adjust the inline `home-manager.users.scott` block to match whatever shape the whistle block actually uses (Step 1) — the option names (`scott.gui`, `scott.dotfiles.profile`) must be identical to whistle's, with profile value `"server"` (the value the retiring `mkHome "server"` used).

- [ ] **Step 3: Add the disko output** next to eminix's:

```nix
      diskoConfigurations = {
        eminix = import ./ioshi/hi-hardware/disko/eminix.nix;
        datacore = import ./ioshi/hi-hardware/disko/datacore.nix;
      };
```

- [ ] **Step 4: Build gate — datacore evaluates and builds**

Run: `nix build --no-link .#nixosConfigurations.datacore.config.system.build.toplevel`
Expected: success. If `scott.gui`/profile options error, fix the inline block per whistle's shape and rerun.

- [ ] **Step 5: Record other hosts' drvPaths, then remove standalone HM**

```bash
for h in whistle eminix zord-old; do nix eval --raw ".#nixosConfigurations.$h.config.system.build.toplevel.drvPath"; echo " $h"; done > /tmp/drv-before.txt
grep -n "mkHome\|hmPkgs" flake.nix   # confirm only the scott@datacore entry consumes them
```
Then delete `homeConfigurations."scott@datacore"` — and if the grep shows `mkHome`/`hmPkgs` now unreferenced, delete those bindings and the `homeConfigurations` output too (last standalone node; spec says the block retires with it).

- [ ] **Step 6: Build gate — nothing else changed**

```bash
nix build --no-link .#nixosConfigurations.datacore.config.system.build.toplevel
for h in whistle eminix zord-old; do nix eval --raw ".#nixosConfigurations.$h.config.system.build.toplevel.drvPath"; echo " $h"; done > /tmp/drv-after.txt
diff /tmp/drv-before.txt /tmp/drv-after.txt && echo "OTHER HOSTS UNCHANGED"
```
Expected: `OTHER HOSTS UNCHANGED` (adding outputs must not perturb existing hosts).

- [ ] **Step 7: Commit**

```bash
git add flake.nix
git commit -m "feat(datacore): nixosConfigurations.datacore + disko output; retire standalone HM (last Debian node)"
```

### Task 4: Push and document Part A

- [ ] **Step 1:** `bin/dot-sync` (commits nothing new, pushes Tasks 1–3; restow + glazewm steps are silent no-ops for this change).
- [ ] **Step 2:** Verify GitHub has the commits: `git log origin/main --oneline -4`.

---

## Part B — Install day (Scott at the HP console; whistle assists)

### Task 5: Wipe the HP and install datacore

**Precondition:** zord-old's disk holds nothing unique (it was zord's backup machine, retired by the T14). Scott confirms before wipe — this is the only destructive step in Parts A–D and it destroys zord-old, not datacore.

- [ ] **Step 1:** Boot the HP from a current NixOS ISO USB. Get LAN connectivity (ethernet or `wpa_supplicant`).
- [ ] **Step 2:** Confirm the disk device: `lsblk -o NAME,SIZE,MODEL`. If the 1 TB SSD is not `/dev/nvme0n1`, edit `device` in `ioshi/hi-hardware/disko/datacore.nix`, commit + push from whistle, and re-clone below.
- [ ] **Step 3:** On the installer:

```bash
git clone https://github.com/scott-whitson/dotfiles /tmp/dotfiles   # public read over https; no key needed
cd /tmp/dotfiles
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko --flake .#datacore
```
Expected: partitions created; `findmnt /mnt/home/srv-data` shows the btrfs subvolume.

- [ ] **Step 4:** Install and set the user password:

```bash
sudo nixos-install --flake .#datacore
sudo nixos-enter --root /mnt -c 'passwd scott'
reboot
```

- [ ] **Step 5:** First boot — from whistle, confirm reachability: `ssh scott@<HP-LAN-IP> hostname` → `datacore`. (LAN IP from the router or console `ip a`; the tailnet name comes next task.)

### Task 6: Enroll identity prerequisites (agenix + tailnet as datacore-new)

- [ ] **Step 1:** From whistle, fetch the new host key and enroll it per the documented agenix flow (`docs/new-host-checklist.md` + memory `reference-agenix-secret-editing`):

```bash
ssh scott@<HP-LAN-IP> 'cat /etc/ssh/ssh_host_ed25519_key.pub'
# add to secrets/secrets.nix, then re-key and push:
cd ~/dotfiles && agenix -r -i <admin-key> && git add secrets && git commit -m "feat(datacore): enroll new host key in agenix" && bin/dot-sync
```

- [ ] **Step 2:** On the HP: clone the repo to its permanent home and rebuild with secrets:

```bash
git clone https://github.com/scott-whitson/dotfiles ~/projects/dotfiles-tmp-clone  # placeholder remote; the real mirror arrives with the data copy (Task 8)
sudo nixos-rebuild switch --flake ~/projects/dotfiles-tmp-clone#datacore
```

- [ ] **Step 3:** Join the tailnet under the TEMP name: `sudo tailscale up --hostname datacore-new`, authenticate, then from whistle: `tailscale status | grep datacore-new` → active.
- [ ] **Step 4:** Confirm syncthing started with FRESH keys and zero shared folders (`ssh datacore-new 'syncthing cli show system | head -3'` — a device ID that is NOT `FXOPHIF-…`). It must stay an island until cutover (global constraint).

---

## Part C — Build & validate (over ssh, old box untouched and serving)

### Task 7: Warm data copy

- [ ] **Step 1:** From the HP (pull over LAN; old box stays up):

```bash
rsync -aHAX --info=progress2 scott@<old-datacore-LAN-IP>:/home/srv-data/ /home/srv-data/
rsync -aHAX --info=progress2 --exclude='.cache' --exclude='dotfiles-usb-snapshot' scott@<old-datacore-LAN-IP>:/home/scott/ /home/scott/old-home-staging/
```
`~scott` lands in a staging dir — the new box's `~` is HM-managed; only curated pieces move in Step 2. Expect ~300 G / several hours on GbE for the first command.

- [ ] **Step 2:** Move the curated pieces into place:

```bash
mv ~/old-home-staging/projects/dotfiles ~/projects/dotfiles         # the git mirror, history + remotes intact
rm -rf ~/projects/dotfiles-tmp-clone
mv ~/old-home-staging/projects/datacore-config ~/projects/datacore-config
mv ~/old-home-staging/docs ~/docs
# .config/backrest and syncthing state deliberately NOT moved — cutover-only (Task 11).
```

- [ ] **Step 3:** Docker volume audit — bind mounts vs named volumes:

```bash
grep -rn "volumes:" ~/projects/datacore-config/stacks | head -30
```
Every path-style mount under `/home/srv-data` is already covered by Step 1. For each NAMED volume found, copy its data explicitly (old box: `docker run --rm -v <vol>:/from -v /home/srv-data/_volmigrate:/to alpine tar -C /from -cf /to/<vol>.tar .` → rsync → load on new box the same way in reverse). Record the list in the task notes; `immich_postgres` data is the one that must be treated with care (stop-copy-start at cutover if it's a named volume — its warm copy here is for validation only).

### Task 8: Bring up the stacks and validate

- [ ] **Step 1:** Per `~/projects/datacore-config` (its README/bootstrap order): `docker compose up -d` each stack.
- [ ] **Step 2:** Validation checklist — each line must pass before cutover is scheduled:

```
docker ps --format '{{.Names}} {{.Status}}'   # all Up, healthy where healthchecks exist
Immich   → http://datacore-new:2283 shows the copied library, search works
Jellyfin → http://datacore-new:8096 plays one known file
Caddy    → routes respond on the vhosts it fronts
Homepage/Uptime-Kuma/Beszel → dashboards up, targets green (old-box targets may alarm — expected)
headscale → container healthy (its clients, if any, are NOT repointed until after soak)
```
- [ ] **Step 3:** Fix-forward anything broken here, over as many evenings as needed. Nobody depends on this box yet — that is the point of Phase 1. Note every fix in `~/projects/datacore-config` (commit there) so the stacks stay self-describing.

---

## Part D — Cutover (scheduled window, target < 1 hour; Scott present)

### Task 9: Pre-flight (day of, before quiescing)

- [ ] **Step 1:** Both boxes reachable; validation checklist (Task 8) still green; `git -C ~/projects/dotfiles fetch origin` works on the new box (mirror healthy).
- [ ] **Step 2:** Announce/accept Immich downtime; note the time.

### Task 10: Quiesce old + final delta

- [ ] **Step 1 (old box):**

```bash
docker stop $(docker ps -q)
systemctl --user stop syncthing
sudo systemctl stop backrest
```
sshd stays up. Old box is now read-only in practice.

- [ ] **Step 2 (new box):** delta rsync — same two commands as Task 7 Step 1 plus named-volume re-copy for anything stateful found in Task 7 Step 3 (this is the authoritative copy of e.g. immich postgres). Minutes, not hours.
- [ ] **Step 3 (new box):** stop the stacks (`docker compose down` each) and syncthing (`sudo systemctl stop syncthing`) so identity lands on quiet services.

### Task 11: Identity flip

- [ ] **Step 1 — ssh host keys** (old → new; preserves eminix/zord known_hosts and the mirror hop):

```bash
# from whistle, old box still reachable:
ssh scott@<old-LAN> 'sudo tar -C /etc/ssh -cf - $(cd /etc/ssh && ls ssh_host_*)' | ssh scott@datacore-new 'sudo tar -C /etc/ssh -xf -'
ssh scott@datacore-new 'sudo systemctl restart sshd'
```

- [ ] **Step 2 — syncthing identity + hub config** (old → new):

```bash
ssh scott@<old-LAN> 'tar -C ~ -cf - $(ls -d .local/state/syncthing .config/syncthing 2>/dev/null | head -1)' | ssh scott@datacore-new 'tar -C ~ -xf -'
# if the old path was ~/.config/syncthing, move it: mv ~/.config/syncthing ~/.local/state/syncthing (config.xml is path-independent; folder paths inside are absolute and unchanged)
```

- [ ] **Step 3 — backrest config:** `ssh scott@<old-LAN> 'tar -C ~ -cf - .config/backrest' | ssh scott@datacore-new 'tar -C ~ -xf -'`
- [ ] **Step 4 — tailnet name:** old box `sudo tailscale logout`; delete the old `datacore` node in the Tailscale admin console; new box `sudo tailscale set --hostname datacore` (falls back to `sudo tailscale up --hostname datacore` if `set` lacks the flag on this version). From whistle: `tailscale status | grep " datacore "` shows the HP's IP. Old box's hostname is stood down but the machine stays bootable + intact.
- [ ] **Step 5 — start everything (new box):** `sudo systemctl start syncthing backrest`, then `docker compose up -d` each stack.

### Task 12: Verify the ring

- [ ] Phone syncs a photo to Immich (`datacore` name, not datacore-new).
- [ ] Syncthing: peers reconnect within minutes with the SAME device ID (`FXOPHIF-…`) — check from whistle's syncthing UI (8385) that datacore shows connected + folders syncing, not "new device".
- [ ] Git mirror hop: on eminix (or via ssh from whistle): `git -C ~/projects/dotfiles fetch` from its datacore remote succeeds with no host-key warning.
- [ ] Backrest: manual backup run to `b2:scott-data-restic` succeeds.
- [ ] This session's own path: `ssh datacore hostname` from whistle → `datacore`.
- [ ] Old laptop: power off. It keeps disk + data as the rollback image.

---

## Part E — Soak, retire, cleanup

### Task 13: Soak gate (1 week), then retire the laptop and zord-old

- [ ] **Step 1 — soak checklist (day 7):** all 22 containers healthy all week (uptime-kuma history), syncthing in sync fleet-wide, at least one scheduled backrest→B2 cycle ran, spot restore-test one file (`restic restore` a single photo to /tmp, open it), no unexplained alerts.
- [ ] **Step 2 — retire the laptop (2–4 weeks post-cutover, Scott's call):** boot it once, `sudo blkdiscard /dev/nvme0n1` (or DBAN-equivalent), recycle/shelve.
- [ ] **Step 3 — repo cleanup:** delete `hosts/zord-old/` and its `nixosConfigurations.zord-old` block (the hardware file `hp-15-ef2013dx.nix` STAYS — datacore uses it); update its comment ("backup machine" → datacore's hardware). Build gate: datacore + whistle + eminix toplevels still build; commit `refactor(fleet): retire zord-old — the HP is datacore now`.
- [ ] **Step 4 — docs:** update `docs/ioshi/standalone-hm.md` (standalone HM fully retired) and `docs/new-host-checklist.md` if install day taught anything; commit.
- [ ] **Step 5 — memory:** update `project_datacore_nixos` memory to COMPLETE with cutover date + gotchas learned; fix any memory that still says datacore is Debian ([[reference-eminix-access]] wording, weekly-report assumptions).
- [ ] **Step 6:** `bin/dot-sync`.

## Self-review notes (done at write time)

- Spec coverage: identity preservation (T11), repo changes (T1–3), phases 1/2/3 (Parts C/D/E), rollback (implicit: old box intact until T13 Step 2 — no task ever writes to the old box), workload triage (T7/T8 carry stacks; IB Gateway/pearl-platform simply never copied), standalone-HM retirement (T3 Step 5), zord-old deletion (T13 Step 3). No gaps found.
- The one intentional spec deviation: spec said "via lib/mkHost" — mkHost bakes the EWM desktop profile, so datacore composes directly like whistle (recorded in T3's comment).
- Type/name consistency: `datacore-new` (tailnet temp name) used consistently in T6/T8/T11; configDir/backrest paths in T2 match T11's copy destinations.
