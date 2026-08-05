# Datacore → NixOS migration — design

**Date:** 2026-08-05
**Status:** approved (in-session)
**Prior art:** `2026-07-21-weasel-nixos-wsl-design.md`, `docs/ioshi/eminix-install.md`, `docs/new-host-checklist.md`

## Goal

Move datacore — the last Debian machine — to NixOS on new hardware. After
this, the whole fleet (whistle, eminix, zord, datacore) is flake-managed
from this repo, and the standalone-HM path retires.

## Facts on the ground (surveyed 2026-08-05)

- **Old box:** laptop guts (i5-8250U, 16 GB, 1 TB NVMe: 56 G `/` at 71%,
  844 G `/home` at 40%). Debian 13.5.
- **Data:** one tree, `/home/srv-data`, 299 G. `~scott` adds ~16 G.
  Total to move ≈ 350 G including docker volumes (`/var/lib/docker`, 13 G).
- **Workloads:** 22 containers defined by the `~/projects/datacore-config`
  repo (stacks/ + bootstrap/ + RECOVERY.md): Immich stack (4), media stack
  (Jellyfin, Sonarr/Radarr/Lidarr/Bazarr/Prowlarr, SABnzbd, qBittorrent,
  Navidrome, Audiobookshelf), hindsight app+db, Uptime-Kuma, Beszel
  (+agent), Homepage, Caddy, headscale. Native: syncthing (the fleet hub),
  backrest → restic → B2 (`b2:scott-data-restic`), docker, tailscaled,
  and an Xvfb unit for IB Gateway.
- **Roles other machines depend on:** git mirror
  (`~/projects/dotfiles`; GitHub → datacore → eminix/zord 3-hop),
  syncthing hub, Immich (family photos).
- **Nextcloud does not exist** (stale memory; nothing to migrate).
- **New hardware:** the HP freed by the zord→T14 move (currently
  `hosts/zord-old`, NixOS, offline). Its validated 1 TB SSD stays — 3×
  headroom over the 350 G payload.

## Decisions (with rationale)

1. **Parallel build on the HP; old box serves until one flip.**
2. **Fresh install** (not an in-place zord-old rename): new disko layout
   sized for a server, current `stateVersion`, no desktop residue.
3. **NixOS owns the substrate only** — disks, sshd, tailscale, native
   syncthing, docker, backrest, users/HM. **Compose stacks run unchanged**
   from `datacore-config`. Rejected: porting 22 containers to
   oci-containers (big-bang risk, no benefit now); hybrid (two config
   systems forever).
4. **Workload triage:** all 22 containers move (headscale included).
   Retired instead of moved — both native/non-container tenants: the
   IB Gateway + its Xvfb unit, and the unused pearl-platform compose
   files under `~/work`.
5. **Data path preserved verbatim:** `/home/srv-data` on the new box too.
   Zero compose-file edits beats path aesthetics mid-migration. (No data
   is ever deleted by the migration: the old box keeps its copy until
   retirement; B2 is the third copy.)
6. **Cutover = two-pass rsync + single identity flip** (approach A).
   Rejected: staged service-by-service (double-touches every peer device,
   two boxes fight over the name); big-bang weekend (no validation soak).
7. **Old laptop stays powered-off-but-intact 2–4 weeks** after cutover,
   then retires. Point of no return is never during the migration.

## Identity preservation (what makes the flip small)

The HP inherits old datacore's identity wholesale, so no other machine is
reconfigured:

- **SSH host keys** (`/etc/ssh/ssh_host_*`) copied → eminix/zord pinned
  known_hosts and the mirror 3-hop keep working.
- **Syncthing keys** (`cert.pem`/`key.pem` = device ID) copied → all
  peers reconnect automatically; zero re-keying.
- **Tailscale:** old node logs out; new box takes the machine name
  `datacore` → `datacore.scottwhitson.ts.net` follows. Fresh node key is
  fine — only the name is pinned anywhere.
- **Paths verbatim:** `/home/srv-data`, `~/projects/dotfiles`,
  `~/projects/datacore-config`.

## Repo changes

- `hosts/datacore/configuration.nix` — finish the existing Phase-2
  skeleton: server profile, syncthing/backrest/docker, current
  `stateVersion`.
- `flake.nix` — add `nixosConfigurations.datacore` (via `lib/mkHost`);
  delete `homeConfigurations."scott@datacore"` and, since it's the last
  standalone-HM node, the standalone-HM block (`hmPkgs`, `mkHome`) if
  nothing else uses it.
- `ioshi/hi-hardware/disko/datacore.nix` — 1 TB SSD: ESP + root + the
  large data filesystem mounted to preserve `/home/srv-data`.
- `hosts/zord-old/` — delete once the HP is wiped.

## Phases

**Phase 1 — Build (old box untouched).** Wipe the HP,
`nixos-install --flake .#datacore` per the install docs (agenix, keys),
join tailnet under a temp name (`datacore-new`). Clone `datacore-config`,
warm-rsync `/home/srv-data` + docker volumes over LAN, bring up every
stack. Validate against the copied data: Immich shows the library,
Jellyfin plays, Caddy routes, monitoring sees targets. Iterate here over
as many evenings as needed — nobody depends on this box yet.

**Phase 2 — Cutover (target < 1 hour downtime).**
1. Old box: stop containers, syncthing, backrest (sshd stays up).
2. Delta rsync (that day's changes only).
3. Copy ssh host keys + syncthing keys. Old box: `tailscale logout`,
   hostname stood down — bootable, but no longer claiming the identity.
4. HP: hostname `datacore`, `tailscale up` as datacore, start syncthing,
   stacks, backrest.
5. Verify the ring: phone syncs to Immich; syncthing peers reconnect
   (same device ID); `git fetch` from eminix via the mirror hop; manual
   backrest run to B2 succeeds.

**Phase 3 — Soak + retire.** Success = all 22 containers healthy for a
week, syncthing in sync fleet-wide, one full backrest→B2 cycle with a
spot restore-test, mirror hop proven, whistle→datacore ssh/tailscale
path working. Then wipe the laptop (its disk holds the last
pre-migration copy — wipe only after the soak passes).

## Rollback

- Before flip step 3: start old services again; nothing was moved, only
  copied.
- After cutover, during soak: boot the laptop, reverse the identity flip
  (it still has keys + data as of the quiesce).
- After retirement: restore from B2.

## Out of scope

Nixifying individual compose stacks (possible later, one at a time),
headscale's future vs Tailscale, and any change to what the services do.
IB Gateway/pearl-platform decommissioning on the old box needs no work —
they simply don't move.
