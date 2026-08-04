# weasel — NixOS-WSL Work Distro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `weasel` NixOS-WSL distro from the dotfiles flake side-by-side with the Debian WSL, cut work content over deliberately, and stage Debian's retirement.

**Architecture:** A new `nixosConfigurations.weasel` (nixos-wsl module + `hosts/weasel/` + home-manager NixOS module with the existing `ioshi` home layer, profile `wsl`). Prerequisite flag split: `scott.ewm.enable` takes over the "which Emacs" decision from `scott.standalone`. One declarative DB (`pearl-platform-db`); worktree DBs stay compose-managed.

**Tech Stack:** Nix flakes, NixOS-WSL, home-manager (NixOS module), agenix, oci-containers/docker, syncthing, tailscale (headscale).

**Spec:** `docs/superpowers/specs/2026-07-21-weasel-nixos-wsl-design.md`

> **Renamed:** this host was renamed `weasel` → `whistle` on 2026-08-04
> (`docs/superpowers/specs/2026-08-04-whistle-rename-design.md`). The name
> `weasel` below is preserved as the historical record.

## Global Constraints

- NEVER run `git add -A` or `git add .` on this machine — stage explicit paths only.
- NO `Co-Authored-By` trailers in any commit.
- drvPath identity gate: `nixosConfigurations.{eminix,zord-old}.config.system.build.toplevel.drvPath` and `homeConfigurations."scott@datacore"/"scott@work".activationPackage.drvPath` must be BYTE-IDENTICAL before/after Task 1. List order in `home.packages` is derivation-load-bearing — never reorder list elements; gate with in-place `lib.mkIf`/`lib.optional` only.
- Single-writer discipline: Debian WSL is the sole writer of `~/projects` and `~/docs/org/work` until the explicit write-handoff step in Task 8. weasel must not edit synced content before that step.
- `~/clients` NEVER syncs, never leaves the laptop (one-time local copy only).
- datacore syncthing API key: read into a shell variable only — never echo/print/persist it, never use `curl -v` with it. All REST calls use absolute paths for `-d @file` (no `~`).
- Never edit datacore's `~/projects/dotfiles` tree (git hub, updateInstead).
- Do not touch `~/.pi/agent/settings.json` or `auth.json` CONTENTS on any node.
- `wsl --shutdown` and `wsl --terminate Debian` kill live Claude/zellij sessions — such steps are Scott-run, at his timing.
- Tasks 1–3 are repo tasks (subagent-friendly, run on this Debian WSL in `~/dotfiles`). Tasks 4–10 are operational (live systems, Scott participates); execute them in order, inline, with Scott present for the marked steps.
- All flake evaluation commands run from `/home/scott/dotfiles`.

---

### Task 1: Flag split — `scott.ewm.enable`

**Files:**
- Modify: `ioshi/i-intelligence/theme.nix` (add option)
- Modify: `ioshi/i-intelligence/standalone.nix` (re-gate)
- Modify: `flake.nix` (hmModule sets the new flag)

**Interfaces:**
- Produces: HM option `scott.ewm.enable` (bool, default `false`). `true` = this machine's Emacs is the system-owned EWM build (`ewm.nix`); `false` = the home layer installs the non-EWM pgtk Emacs and runs the daemon as a user service. Task 2's weasel config relies on the default `false`.

- [ ] **Step 1: Capture the BEFORE drvPaths**

```bash
cd /home/scott/dotfiles
for a in 'nixosConfigurations.eminix.config.system.build.toplevel.drvPath' \
         'nixosConfigurations.zord-old.config.system.build.toplevel.drvPath' \
         'homeConfigurations."scott@datacore".activationPackage.drvPath' \
         'homeConfigurations."scott@work".activationPackage.drvPath'; do
  nix eval ".#$a"
done | tee /tmp/drv-before.txt
```
Expected: four `/nix/store/...drv` paths, no errors.

- [ ] **Step 2: Add the option in `theme.nix`**

Inside `options.scott = { ... }`, directly after the `standalone` option block, add:

```nix
    ewm.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "This machine's Emacs is the system-owned EWM build (ewm.nix). When false, the home layer installs the non-EWM pgtk Emacs and runs the daemon as a systemd user service (standalone.nix).";
    };
```

Also update the `standalone` option's `description` string to:

```nix
      description = "Home Manager runs standalone on a foreign distro (no NixOS layer): skip agenix-dependent files (pi auth.json symlink). Which Emacs to install is scott.ewm.enable's decision, not this flag's.";
```

- [ ] **Step 3: Re-gate `standalone.nix`**

Change line 12 from:

```nix
  config = lib.mkIf config.scott.standalone {
```

to:

```nix
  config = lib.mkIf (!config.scott.ewm.enable) {
```

Replace the header comment (lines 4–5 area) and the inner comment (lines 13–14 area) so they describe the new meaning:

```nix
  # Same package set as the eminix system build (ewm.nix), minus the EWM
  # package — non-EWM machines (foreign-distro nodes AND weasel/NixOS-WSL)
  # have no compositor role.
```
and
```nix
    # On EWM machines the Emacs build is system-owned (ewm.nix). Non-EWM
    # machines install it user-side and run the daemon as a systemd user
    # service.
```

- [ ] **Step 4: Set the flag for the EWM hosts in `flake.nix`**

In `hmModule` (`users.scott` block), change:

```nix
          users.scott = {
            imports = [ ./home/scott/default.nix ];
          };
```

to:

```nix
          users.scott = {
            imports = [ ./home/scott/default.nix ];
            # eminix instances run the system-owned EWM Emacs. mkDefault so a
            # non-EWM NixOS host (weasel) can opt out while reusing hmModule.
            scott.ewm.enable = nixpkgs.lib.mkDefault true;
          };
```

- [ ] **Step 5: Verify the AFTER drvPaths are identical**

```bash
cd /home/scott/dotfiles
for a in 'nixosConfigurations.eminix.config.system.build.toplevel.drvPath' \
         'nixosConfigurations.zord-old.config.system.build.toplevel.drvPath' \
         'homeConfigurations."scott@datacore".activationPackage.drvPath' \
         'homeConfigurations."scott@work".activationPackage.drvPath'; do
  nix eval ".#$a"
done | tee /tmp/drv-after.txt
diff /tmp/drv-before.txt /tmp/drv-after.txt && echo IDENTICAL
```
Expected: `IDENTICAL`. If ANY path differs, STOP — find what leaked (the gate state must be: eminix/zord-old inactive block before and after; datacore/work active block before and after). Do not proceed with a differing drvPath.

- [ ] **Step 6: Commit**

```bash
cd /home/scott/dotfiles
git add ioshi/i-intelligence/theme.nix ioshi/i-intelligence/standalone.nix flake.nix
git commit -m "refactor(flags): split scott.ewm.enable out of scott.standalone"
```

---

### Task 2: nixos-wsl input + `nixosConfigurations.weasel`

**Files:**
- Modify: `flake.nix` (input + output arg + weasel config)
- Create: `hosts/weasel/configuration.nix`

**Interfaces:**
- Consumes: `scott.ewm.enable` default `false` (Task 1); existing modules `ioshi/os-system/base.nix`, `ioshi/hi-hardware/net/tailscale.nix`, `ioshi/hi-hardware/net/ssh.nix`, `ioshi/i-intelligence/secrets.nix`.
- Produces: `nixosConfigurations.weasel`, evaluable on this machine. `docker-pearl-platform-db.service` (oci-containers unit name) with DB on host port 5434, bind mount `/var/lib/pearl-db/data`, env file `/var/lib/pearl-db/env` (created in Task 8).

- [ ] **Step 1: Add the flake input**

In `flake.nix` `inputs`, after the `agenix` block:

```nix
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

Add `nixos-wsl` to the `outputs` argument set (after `agenix`).

- [ ] **Step 2: Confirm `system.stateVersion` for the new host**

```bash
cd /home/scott/dotfiles
nix eval --raw '.#nixosConfigurations.eminix.pkgs.lib.trivial.release'
```
Expected: `26.11` (verified at plan-writing time, 2026-07-21). If it differs (flake.lock moved), use the printed value in Step 3 instead of `26.11`.

- [ ] **Step 3: Create `hosts/weasel/configuration.nix`**

```nix
{ lib, ... }:

{
  # weasel — NixOS-WSL work distro (design spec 2026-07-21).
  # No hardware/disko/EWM layer: nixos-wsl supplies boot + mounts, WSLg
  # supplies the display. Home layer arrives via the flake's hmModule with
  # profile "wsl" (same home as the retired scott@work standalone config).
  imports = [
    ../../ioshi/os-system/base.nix
    ../../ioshi/hi-hardware/net/tailscale.nix
    ../../ioshi/hi-hardware/net/ssh.nix
    ../../ioshi/i-intelligence/secrets.nix
  ];

  networking.hostName = "weasel";

  wsl = {
    enable = true;
    defaultUser = "scott";
    wslConf = {
      # Carried over from the hand-tuned Debian /etc/wsl.conf (2026-05-13
      # plan9 tuning): metadata mounts + no Windows PATH pollution.
      automount.options = "metadata,uid=1000,gid=1000,umask=022,fmask=11,case=off,msize=262144";
      interop.appendWindowsPath = false;
    };
  };

  # WSL owns /etc/resolv.conf. tailscale.nix enables resolved for the real
  # hosts; on WSL it would fight the generated resolv.conf — force it off
  # and keep tailscale's hands off DNS (connectivity only, as the userspace
  # daemon on Debian worked today).
  services.resolved.enable = lib.mkForce false;
  services.tailscale.extraUpFlags = [ "--accept-dns=false" ];

  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      # The 2026-07-21 lesson: 137 GB of buildkit cache in 3 days. Cap it.
      builder.gc = {
        enabled = true;
        defaultKeepStorage = "25GB";
      };
    };
  };

  # The ONE long-lived dev DB (spec decision: worktree DBs stay compose).
  # Env file carries POSTGRES_PASSWORD; hand-placed in the cutover (it must
  # match the value pearl-platform's .env derives its DATABASE_URL from).
  virtualisation.oci-containers = {
    backend = "docker";
    containers.pearl-platform-db = {
      image = "pgvector/pgvector:pg16";
      environment = {
        POSTGRES_USER = "pearl";
        POSTGRES_DB = "pearl";
      };
      environmentFiles = [ "/var/lib/pearl-db/env" ];
      ports = [ "5434:5432" ];
      volumes = [ "/var/lib/pearl-db/data:/var/lib/postgresql/data" ];
    };
  };

  # Vendor binaries (npm native modules, downloaded tools) without FHS pain.
  programs.nix-ld.enable = true;

  # NB: system.stateVersion records first-install release; never bump later.
  system.stateVersion = "26.11";
}
```

- [ ] **Step 4: Add weasel to `flake.nix`**

In `nixosConfigurations`, after the `eminix` entry:

```nix
        # NixOS-WSL on the work laptop — replaces the Debian WSL + scott@work
        # standalone HM pair at cutover (spec 2026-07-21). Not an eminix
        # instance (no EWM/hardware layer), so composed here, not via mkHost.
        weasel = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = sharedSpecialArgs;
          modules = [
            nixos-wsl.nixosModules.default
            ./hosts/weasel/configuration.nix
            nixpkgsModule
            agenix.nixosModules.default
            home-manager.nixosModules.home-manager
            hmModule
            {
              home-manager.users.scott = {
                scott.dotfiles.profile = "wsl";
                scott.gui = false;
                scott.ewm.enable = false;
              };
            }
          ];
        };
```

- [ ] **Step 5: Verify weasel evaluates and nothing else moved**

```bash
cd /home/scott/dotfiles
nix eval '.#nixosConfigurations.weasel.config.system.build.toplevel.drvPath'
```
Expected: a `/nix/store/...weasel...drv` path (first run updates `flake.lock` with the nixos-wsl input; that is expected and committed below).

```bash
cd /home/scott/dotfiles
for a in 'nixosConfigurations.eminix.config.system.build.toplevel.drvPath' \
         'homeConfigurations."scott@work".activationPackage.drvPath'; do
  nix eval ".#$a"
done > /tmp/drv-task2.txt
while read -r p; do grep -qF "$p" /tmp/drv-after.txt && echo "OK $p" || echo "CHANGED $p"; done < /tmp/drv-task2.txt
```
Expected: two `OK` lines — both drvPaths must appear verbatim in Task 1's `/tmp/drv-after.txt` (the followed nixos-wsl input must not perturb existing configs). Any `CHANGED` = STOP and investigate. (If `/tmp/drv-after.txt` is gone — different session — regenerate it from the still-clean parent commit with `git stash`, rerun Task 1 Step 1, `git stash pop`.)

- [ ] **Step 6: Sanity-check weasel's composition**

```bash
cd /home/scott/dotfiles
nix eval '.#nixosConfigurations.weasel.config.home-manager.users.scott.scott.dotfiles.profile'   # expect "wsl"
nix eval '.#nixosConfigurations.weasel.config.home-manager.users.scott.scott.ewm.enable'          # expect false
nix eval '.#nixosConfigurations.weasel.config.home-manager.users.scott.services.syncthing.enable' # expect true
nix eval '.#nixosConfigurations.weasel.config.virtualisation.oci-containers.containers.pearl-platform-db.image' # expect pgvector image
nix eval '.#nixosConfigurations.weasel.config.services.tailscale.enable'                          # expect true
```
Expected: the annotated values. The syncthing check proves the profile-gated HM syncthing config (wsl profile) activates for weasel.

- [ ] **Step 7: Full build dry-run (eval-deep check)**

```bash
cd /home/scott/dotfiles
nix build '.#nixosConfigurations.weasel.config.system.build.toplevel' --dry-run 2>&1 | tail -5
```
Expected: a list of derivations that "will be built" — no evaluation errors. (Do NOT actually build; the Emacs closure is large and Task 4 builds it on weasel.)

- [ ] **Step 8: Commit**

```bash
cd /home/scott/dotfiles
git add flake.nix flake.lock hosts/weasel/configuration.nix
git commit -m "feat(weasel): NixOS-WSL work distro as a third nixosConfiguration"
```

---

### Task 3: Runbook — `docs/ioshi/weasel.md`

**Files:**
- Create: `docs/ioshi/weasel.md`

**Interfaces:**
- Consumes: the exact commands from Tasks 4–10 (this runbook is their durable home; the plan is the working copy).

- [ ] **Step 1: Write the runbook**

Create `docs/ioshi/weasel.md` containing, in this order (content mirrors Tasks 4–10 of this plan — keep the commands verbatim so the runbook works standalone after this plan is archived):

1. **What weasel is** — one paragraph: third nixosConfiguration, NixOS-WSL, replaces Debian WSL + scott@work.
2. **Import & bootstrap** — the Task 4 command sequence.
3. **Rebuild** — `sudo nixos-rebuild switch --flake ~/dotfiles#weasel` (weasel rebuilds from its local clone; it is the dotfiles writer — no 3-hop).
4. **agenix recipient flow** — Task 5 sequence.
5. **tailscale join ritual** — Task 6 sequence (headscale preauthkey from datacore).
6. **syncthing join** — Task 7 outline (datacore REST recipe pointer to `docs/ioshi/work-sync.md`).
7. **Cutover checklist** — Tasks 8–9 condensed to a checkbox list.
8. **Retirement** — Task 10 condensed; the "do not run until the trust week passes" warning.
9. **Gotchas** — port 5434 is owned by the declarative `pearl-platform-db`; `docker compose up db` in the pearl-platform main checkout now collides — use the declarative DB (worktree DBs on other ports unaffected). WSLg GUI via `ec` unchanged. `wsl --manage weasel --set-sparse true` requires the distro stopped.

- [ ] **Step 2: Commit**

```bash
cd /home/scott/dotfiles
git add docs/ioshi/weasel.md
git commit -m "docs(weasel): import, rebuild, cutover, and retirement runbook"
```

- [ ] **Step 3: Push (feeds datacore/eminix mirrors as usual)**

```bash
cd /home/scott/dotfiles && git push
```

---

### Task 4: Import weasel + bootstrap + WSLg smoke test  **[OPS — Scott present]**

No repo changes. Highest-risk integration test happens here, before any data moves.

- [ ] **Step 1: Download the NixOS-WSL release** (from Debian WSL)

```bash
cd /mnt/c/Users/swhitson.CENTRALDATA/Downloads
curl -LO https://github.com/nix-community/NixOS-WSL/releases/latest/download/nixos.wsl
```

- [ ] **Step 2: Import (Scott, PowerShell or `!` prefix — does NOT disturb running distros)**

```powershell
wsl --import weasel $env:LOCALAPPDATA\wsl\weasel $env:USERPROFILE\Downloads\nixos.wsl --version 2
```
If `--import` rejects the `.wsl` file (older WSL): `wsl --install --from-file $env:USERPROFILE\Downloads\nixos.wsl` and adjust the distro name below to what it registers (`wsl -l -v`).

- [ ] **Step 3: Sparse vhdx from day one (weasel must be stopped; it is — never started)**

```powershell
wsl --manage weasel --set-sparse true
```

- [ ] **Step 4: First boot, seed SSH key, clone dotfiles** (Scott: `wsl -d weasel`, default user `nixos`)

```bash
sudo -i
export NIX_CONFIG="experimental-features = nix-command flakes"   # in case the base image predates default-on flakes
/mnt/c/Windows/System32/wsl.exe -d Debian -u scott tar -C /home/scott -cf - .ssh | tar -xf - -C /root/
chmod 700 /root/.ssh && chmod 600 /root/.ssh/id_ed25519
GIT_SSH_COMMAND="ssh -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new" \
  nix run nixpkgs#git -- clone git@github.com:scott-whitson/dotfiles.git /tmp/dotfiles
```

- [ ] **Step 5: First rebuild (creates user scott, applies everything)**

```bash
nixos-rebuild switch --flake /tmp/dotfiles#weasel
```
Expected: builds the Emacs closure (long first build), switches, ends with activation output including home-manager. The switch exits NONZERO with three EXPECTED failures that self-heal later: the agenix activation snippet (no host key + not yet a recipient — Task 5), docker-pearl-platform-db.service (env file — Task 8), and tailscaled-autoconnect.service (authkey — Task 6). These are not stop conditions; only the Emacs/WSLg smoke test (Step 7) is. Exit weasel, `wsl --terminate weasel` (Scott), re-enter `wsl -d weasel` — now lands as user `scott` with zsh.

- [ ] **Step 6: Move the clone home + hand over SSH**

```bash
# as scott on weasel
sudo mv /tmp/dotfiles /home/scott/dotfiles && sudo chown -R scott:users /home/scott/dotfiles
sudo cp -r /root/.ssh /home/scott/.ssh && sudo chown -R scott:users /home/scott/.ssh
chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_ed25519
git -C ~/dotfiles remote -v   # expect git@github.com:scott-whitson/dotfiles.git
sudo rm -rf /root/.ssh
```

- [ ] **Step 7: SMOKE TEST (Scott): WSLg + pgtk Emacs**

On weasel: `ec` → the Emacs GUI must open as a Wayland (WSLg) window with correct fonts. In it: `C-h v window-system RET` shows `pgtk`. If this fails, STOP the project here — Debian untouched, zero blast radius; debug before any migration.

- [ ] **Step 8: Verify the system services**

```bash
systemctl --user status emacs.service --no-pager | head -3    # active (running)
systemctl --user status syncthing.service --no-pager | head -3 # active (running)
systemctl status docker.service --no-pager | head -3           # active (running)
systemctl status tailscaled.service --no-pager | head -3       # active (auth pending — Task 6; tailscaled-autoconnect.service failed is expected until then)
systemctl status docker-pearl-platform-db.service --no-pager | head -3 # failing is EXPECTED (env file arrives in Task 8)
test -f /run/agenix/openrouter-auth || echo "agenix activation snippet failure is EXPECTED until Task 5 (/run/agenix empty, ~/.pi/agent/auth.json a dangling symlink until then)"
docker info --format '{{json .DefaultRuntime}}' >/dev/null && echo docker-ok
```

---

### Task 5: agenix — weasel becomes a recipient  **[OPS]**

**Files:**
- Modify: `secrets/secrets.nix` (on the Debian WSL clone — still the writer until Task 8; weasel pulls)

- [ ] **Step 1: Capture weasel's host key** (net/ssh.nix enabled sshd → host keys exist)

```bash
# on weasel
sudo cat /etc/ssh/ssh_host_ed25519_key.pub
```

- [ ] **Step 2: Add recipient + rekey (on Debian WSL, in ~/dotfiles)**

In `secrets/secrets.nix`, add above the `scott` line (key text from Step 1):

```nix
  weasel = "ssh-ed25519 AAAA<weasel-host-key> root@weasel";
```
and extend: `"openrouter-auth.age".publicKeys = [ eminix zordold weasel scott ];`

```bash
cd /home/scott/dotfiles/secrets
nix run github:ryantm/agenix -- --rekey -i /home/scott/.ssh/id_ed25519
cd /home/scott/dotfiles
git add secrets/secrets.nix secrets/openrouter-auth.age
git commit -m "secrets: add weasel as openrouter-auth recipient"
git push
```

- [ ] **Step 3: Rebuild weasel and verify decryption**

```bash
# on weasel
git -C ~/dotfiles pull --ff-only
sudo nixos-rebuild switch --flake ~/dotfiles#weasel
sudo test -f /run/agenix/openrouter-auth && echo secret-ok
readlink ~/.pi/agent/auth.json    # expect /run/agenix/openrouter-auth
```
(Never cat the secret.)

---

### Task 6: tailscale join  **[OPS]**

- [ ] **Step 1: Pre-auth key from datacore's headscale** (from Debian WSL, existing ssh access)

```bash
ssh datacore "docker exec headscale headscale preauthkeys create --user 1 --expiration 1h"
```

- [ ] **Step 2: Place the key on weasel and connect**

```bash
# on weasel — paste the key from Step 1
echo '<preauthkey>' | sudo tee /var/lib/tailscale-authkey >/dev/null
sudo systemctl restart tailscaled-autoconnect
sleep 5; tailscale status | head -5
```
Expected: weasel listed plus datacore/eminix peers. Then:

```bash
tailscale ping datacore   # expect pong, ideally direct
```

---

### Task 7: syncthing join — weasel as a second (read-side) spoke  **[OPS]**

Debian REMAINS the writer throughout this task. weasel must not edit `~/projects` or `~/docs/org/work` yet.

- [ ] **Step 1: weasel's device ID**

```bash
# on weasel
syncthing --device-id
```

- [ ] **Step 2: Register weasel on datacore + attach folders (from Debian WSL)**

Follow the Phase 3 REST recipe (`docs/ioshi/work-sync.md`): read the API key from datacore's `~/.local/state/syncthing/config.xml` into a shell variable (never print), then via `curl -sS` (never `-v`): add weasel as a device, and add weasel's device ID to the `devices` arrays of folders `work-projects` and `work-docs`. Use absolute paths for any `-d @file` payloads.

- [ ] **Step 3: Wait for full sync, then verify**

```bash
# on weasel — completion via the local REST API, or simply:
watch -n 30 'df -h ~; find ~/projects -maxdepth 1 | wc -l'
```
Done when folder status in weasel's syncthing log shows both folders idle/up-to-date. Verify:

```bash
# spot-check checksums Debian vs weasel on a couple of files
/mnt/c/Windows/System32/wsl.exe -d Debian -u scott sha256sum /home/scott/docs/org/work/*.org | sha256sum
sha256sum ~/docs/org/work/*.org | sha256sum
```
Expected: identical digest-of-digests.

---

### Task 8: Write handoff + data migration  **[OPS — Scott's timing; point of commitment]**

- [ ] **Step 1: Quiesce Debian (Scott: close/park other Claude sessions' edits first)**

```bash
# on Debian
systemctl --user stop syncthing && systemctl --user disable syncthing
```
Verify on datacore (REST or log) both work folders are idle. From this moment weasel is the writer.

- [ ] **Step 2: DB password + env file on weasel**

```bash
# on Debian — recover the live password without printing it:
PW=$(docker inspect pearl-platform-db-1 --format '{{range .Config.Env}}{{println .}}{{end}}' | grep '^POSTGRES_PASSWORD=' | cut -d= -f2-)
# push it into weasel's env file via interop (still not printed):
printf 'POSTGRES_PASSWORD=%s\n' "$PW" | /mnt/c/Windows/System32/wsl.exe -d weasel -u root -- sh -c 'umask 077; mkdir -p /var/lib/pearl-db; cat > /var/lib/pearl-db/env'
unset PW
```

- [ ] **Step 3: Migrate pearl-platform-db**

```bash
# on Debian — dump AFTER the write quiesce
docker exec pearl-platform-db-1 pg_dump -U pearl -d pearl > /home/scott/pearl-dump.sql
# stream to weasel and restore
/mnt/c/Windows/System32/wsl.exe -d weasel -u root -- systemctl restart docker-pearl-platform-db.service
sleep 10
cat /home/scott/pearl-dump.sql | /mnt/c/Windows/System32/wsl.exe -d weasel -u scott -- docker exec -i pearl-platform-db psql -U pearl -d pearl -v ON_ERROR_STOP=1 -q
```
Verify (on weasel): `docker exec pearl-platform-db psql -U pearl -d pearl -c '\dt'` lists the expected tables; spot-check one row count against Debian. Then delete `/home/scott/pearl-dump.sql` on Debian.

- [ ] **Step 4: Worktree DBs (only branches still alive)**

For each live worktree (`chat-interrupt` :5435, `kb-cores` :5444, `ap-automation-phase1`): the worktree tree arrived on weasel via syncthing. On weasel, in each worktree: `docker compose up -d db`, then repeat Step 3's dump/restore pattern per DB (container names as on Debian). Skip any branch already merged/dead — note which were skipped.

- [ ] **Step 5: Home state one-time copy (list is exhaustive — nothing else copies)**

```bash
# on weasel — pull from Debian via interop; .ssh already arrived in Task 4
/mnt/c/Windows/System32/wsl.exe -d Debian -u scott -- tar -C /home/scott -cf - \
  --exclude='.pi/agent/auth.json' \
  clients .claude .pi .gitconfig.local .zsh_history \
  | tar -xf - -C /home/scott
```
The exclude is required: on weasel `~/.pi/agent/auth.json` is an HM-managed symlink to `/run/agenix/openrouter-auth`, and Debian's plain file would otherwise replace it, breaking the next home-manager activation with an "existing file in the way" conflict and re-introducing a plaintext key on disk.

(If `echo $HISTFILE` on Debian names a different path than `~/.zsh_history`, copy that path instead.) Then copy the md2org audit log only (NOT the whole backups dir — `cd-audit-premirror-20260720.git` holds dirty history and must not propagate):

```bash
mkdir -p ~/.local/backups
/mnt/c/Windows/System32/wsl.exe -d Debian -u scott cat /home/scott/.local/backups/md2org-conversion-log-20260721.txt > ~/.local/backups/md2org-conversion-log-20260721.txt
```

- [ ] **Step 6: Dotfiles writer handoff**

```bash
# on Debian — nothing unpushed?
git -C /home/scott/dotfiles status --short --branch && git -C /home/scott/dotfiles log --oneline origin/main..main
```
Expected: clean, no unpushed commits (push if any). weasel's clone (Task 4) is now the working copy.

- [ ] **Step 7: Reinstall pi and claude (verified install methods, 2026-07-21)**

Neither is an npm *global* on Debian. pi is an npm package under the `~/.local` prefix plus a launcher script; claude uses the native installer (versions under `~/.local/share/claude`, symlinked from `~/.local/bin/claude`). Node itself arrives via HM (`packages.nix` ships `nodejs`).

```bash
# on weasel
npm install -g --prefix ~/.local @earendil-works/pi-coding-agent
/mnt/c/Windows/System32/wsl.exe -d Debian -u scott cat /home/scott/.local/bin/pi > ~/.local/bin/pi && chmod +x ~/.local/bin/pi
curl -fsSL https://claude.ai/install.sh | bash   # native installer; nix-ld (Task 2) lets the binary run on NixOS
pi --version && claude --version
```
Auth/config: `~/.pi` and `~/.claude` were copied in Step 5; pi's auth.json is the agenix symlink from Task 5 — verify `pi` starts without demanding auth.

- [ ] **Step 8: Remove Debian's syncthing device from datacore**

Same REST recipe: remove Debian's device ID from `work-projects`/`work-docs` device arrays and delete the device entry. Debian is now fully out of the sync topology.

---

### Task 9: Windows finish  **[OPS — Scott]**

- [ ] **Step 1: Windows Terminal profile** — in WT `settings.json` (path per `docs`/memory: the domain profile's `AppData/Local/Packages/Microsoft.WindowsTerminal_*/LocalState/settings.json`), the generated weasel profile appears automatically; set its `startingDirectory` to `//wsl$/weasel/home/scott` and pick it as WT's default profile if desired.
- [ ] **Step 2: Default distro**

```powershell
wsl --set-default weasel
```
- [ ] **Step 3: GlazeWM** — nothing to do (the `msrdc` ignore rule covers all WSLg windows).
- [ ] **Step 4: Begin the trust week.** Daily driving on weasel; Debian stays registered but dormant (its syncthing disabled, its DBs stopped: `wsl -d Debian -u scott docker stop $(...)` optional). Log any friction in the quarterly tracker.

---

### Task 10: Retirement  **[OPS — only on Scott's explicit go, after the trust week]**

- [ ] **Step 1 (Scott): Unregister Debian — IRREVERSIBLE, destroys its vhdx (~65 GB reclaimed)**

```powershell
wsl --unregister Debian
```

- [ ] **Step 2: Flake cleanup (on weasel, now the dotfiles writer)**

Remove `"scott@work" = mkHome "wsl";` from `flake.nix` `homeConfigurations` (datacore's entry stays). Update the `mkHome` comment ("Debian WSL" reference) and `docs/ioshi/standalone-hm.md` (scott@work retired → pointer to `docs/ioshi/weasel.md`).

```bash
cd ~/dotfiles
nix eval '.#homeConfigurations."scott@datacore".activationPackage.drvPath'   # still evaluates
nix eval '.#nixosConfigurations.weasel.config.system.build.toplevel.drvPath' # still evaluates
git add flake.nix docs/ioshi/standalone-hm.md
git commit -m "chore(weasel): retire the scott@work standalone config"
git push
```

- [ ] **Step 3: Close the ledger** — append completion to `.superpowers/sdd/progress.md`; update memory (`project_three_node_model.md` or a new weasel project memory).

---

## Success criteria (from the spec)

- eminix/zord-old/datacore/work drvPaths untouched by Task 1; weasel evaluates and builds.
- `ec` opens pgtk Emacs under WSLg on weasel; org-roam finds the work vault; magit/zellij/claude/pi work.
- pearl-platform-db answers on 5434 with migrated data; build cache capped at 25 GB declaratively.
- `~/projects` + `~/docs/org/work` identical on weasel/datacore/eminix; weasel sole writer; Debian's syncthing device removed.
- tailscaled (kernel, non-userspace) on the tailnet; direct connection to datacore.
- After Task 10: Debian gone, `scott@work` removed, flake evaluates cleanly.
