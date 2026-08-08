# Datacore → NixOS migration — design

**Date:** 2026-08-05
**Revised:** 2026-08-08 — refreshed after the eminix convergence, which landed
between approval and implementation. The strategy is unchanged; the facts,
host names and repo-work list are. Two decisions were added (host-key identity,
headscale ordering) — see "Revision 2026-08-08" under Decisions.
**Status:** approved, not yet started
**Prior art:** `2026-07-21-weasel-nixos-wsl-design.md`, `docs/ioshi/eminix-install.md`

## Goal

Move datacore — the last Debian machine — to NixOS on the HP freed by the
T14 move. After this the whole fleet (`rafik`, `whistle`, `datacore`) is
flake-managed from this repo, and the standalone-HM path retires.

> The convergence already renamed the T14 `eminix` → `rafik`, deleted
> `zord-old`, and made `eminix` the name of the *distribution* only. Anywhere
> this document said "eminix" or "zord" as a machine, read `rafik`.

## Facts on the ground (surveyed 2026-08-05)

- **Old box:** laptop guts (i5-8250U, 16 GB, 1 TB NVMe: 56 G `/` at 71%,
  844 G `/home` at 40%). Debian 13.5.
- **Data:** one tree, `/home/srv-data` — 299 G at survey, **326 G on
  2026-08-08**. `~scott` adds ~16 G; docker volumes (`/var/lib/docker`) 13 G.
  Total to move ≈ **355 G**, growing ~9 G/day. Re-measure before Phase 1 and
  size the delta window accordingly.
- **Workloads:** 22 containers defined by the `~/projects/datacore-config`
  repo (stacks/ + bootstrap/ + RECOVERY.md): Immich stack (4), media stack
  (Jellyfin, Sonarr/Radarr/Lidarr/Bazarr/Prowlarr, SABnzbd, qBittorrent,
  Navidrome, Audiobookshelf), hindsight app+db, Uptime-Kuma, Beszel
  (+agent), Homepage, Caddy, headscale. Native: syncthing (the fleet hub),
  backrest → restic → B2 (`b2:scott-data-restic`), docker, tailscaled,
  and an Xvfb unit for IB Gateway.
- **Roles other machines depend on:** git mirror
  (`~/projects/dotfiles`; GitHub → datacore → rafik 3-hop — rafik's git `origin` IS datacore, so this breaks during the rebuild window; point rafik at GitHub directly meanwhile),
  syncthing hub, Immich (family photos).
- **Nextcloud does not exist** (stale memory; nothing to migrate).
- **New hardware:** the HP freed by the zord→T14 move — the machine
  `hosts/zord-old` used to describe, before that host was deleted in the
  convergence. Its 1 TB SSD gives ~3× headroom over the payload.
  **Unverified since 2026-07-16** — the machine has been off. Confirm the disk
  before Phase 1; everything downstream assumes it fits.
- **Network:** old box and HP are on the same network but are addressed by
  tailnet name, not LAN IP. Tailscale makes a *direct* connection between them
  (confirmed: peers show `direct 192.168.0.x:41641`), so bulk transfer runs at
  LAN speed. It is not relayed, and it is not routed over the internet.

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

### Revision 2026-08-08 — two decisions added

8. **The HP inherits the OLD box's SSH host key, and that key is the agenix
   recipient.** These are the same decision and must not drift apart.

   On 2026-08-08 a *fresh* host key was generated for datacore and made the
   agenix recipient, on the reasoning that a clean install produces a new key.
   That contradicts decision 5's identity preservation: this migration
   deliberately copies `/etc/ssh/ssh_host_*` from the old box so that no peer
   re-pins anything. A host cannot both inherit the old key and have a
   different key as its agenix recipient — agenix would fail to decrypt on
   first boot.

   Resolution: `secrets/secrets.nix`'s `datacore` recipient becomes the old
   box's actual key (`…IHn7dUeQQeGMDAuQ8YJRxV2Nlo31biEtxpcHxawrBZ1J`), secrets
   are rekeyed, and the generated `~/.ssh/datacore_host_ed25519` pair is
   deleted so it cannot be mistaken for the real one later. The USB staging
   directory `datacore-keys/` carries a copy of the OLD box's key.

9. **headscale moves last, alone, as Phase 2b.** headscale is the tailnet
   control plane *and* a container on the box being replaced. The identity
   rename (`datacore-new` → `datacore`) requires a working control plane, so
   headscale cannot be down during the main flip.

   The old box therefore keeps running headscale — and only headscale —
   through Phase 2, then hands it over as an isolated final step. The stack
   ships its own Caddy bound to host ports 80/443, so it moves as one unit;
   the router's port-forward is re-pointed at the HP. Rejected: moving
   headscale first (the identity flip would then run against a control plane
   that had itself just moved, compounding two risky changes in one window).

   This does **not** weaken decision 6. The identity still flips exactly once,
   in Phase 2. Phase 2b relocates a *service*; no hostname, host key or device
   ID changes in it, and no peer is reconfigured. What 2b buys is that the two
   moments with a scary feel — taking the name, and taking the control plane —
   are never in the same window, so each has a clean rollback of its own.

## Identity preservation (what makes the flip small)

The HP inherits old datacore's identity wholesale, so no other machine is
reconfigured:

- **SSH host keys** (`/etc/ssh/ssh_host_*`) copied → rafik's pinned
  known_hosts and the GitHub → datacore → rafik mirror hop keep working.
  This is also what agenix decrypts with, per decision 8 — the recipient in
  `secrets/secrets.nix` must be this same key.
- **Syncthing keys** (`cert.pem`/`key.pem` = device ID) copied → all
  peers reconnect automatically; zero re-keying.
- **Tailscale:** old node logs out; new box takes the machine name
  `datacore` → `datacore.scottwhitson.ts.net` follows. Fresh node key is
  fine — only the name is pinned anywhere.
- **Paths verbatim:** `/home/srv-data`, `~/projects/dotfiles`,
  `~/projects/datacore-config`.

## Repo changes

Most of this landed during the eminix convergence (2026-08-07/08), before this
migration started. Status as of 2026-08-08:

- ✅ `flake.nix` — `nixosConfigurations.datacore` exists, composed via
  `lib/mkHost` with `role = "server"`. `homeConfigurations` is gone entirely.
- ✅ `ioshi/hi-hardware/disko/datacore.nix` — ESP + 16 G swap + btrfs with
  `@`, `@nix`, `@home`, `@srv-data` (mounted at `/home/srv-data`). Builds:
  `nix build .#nixosConfigurations.datacore.config.system.build.diskoScript`.
- ✅ `hosts/zord-old/` — deleted. `ioshi/hi-hardware/hp-15-ef2013dx.nix` is now
  datacore's hardware module and holds its real values directly, rather than
  datacore `mkForce`-ing over a shared file.
- ✅ `installer/fresh-eminix-install` — takes `[host] [disk]`, so the HP
  installs with `fresh-eminix-install datacore`. It fails closed if the host is
  not yet a recipient in `secrets/secrets.nix`.
- ⬜ `hosts/datacore/configuration.nix` — the remaining repo work. It already
  declares syncthing (hub), backrest, docker and its `stateVersion`; confirm it
  is complete for a *fresh* machine rather than one that inherited state.
- ⬜ `secrets/secrets.nix` — re-point the `datacore` recipient at the old box's
  key and rekey, per decision 8.

## Pre-flight (do before Phase 1)

- **Commit `~/projects/datacore-config`.** It had 12 uncommitted files on
  2026-08-08. The migration treats that repo as the source of truth for every
  stack, so uncommitted work is silently missed.
- **Confirm the HP's disk** has ≥ ~400 G free. Unverified since 2026-07-16.
- **Re-measure the payload.** It grew ~9 G/day over the survey window.

## Phases

**Phase 1 — Build (old box untouched).** Wipe the HP,
`fresh-eminix-install datacore` (stage `datacore-keys/` beside the repo on the
Ventoy USB, holding the **old box's** host key per decision 8). Join the tailnet
under a temp name `datacore-new` — the old box's headscale is still serving, so
this registers normally. Clone `datacore-config`, warm-rsync `/home/srv-data`
plus docker volumes over the tailnet (direct connection, LAN speed), and bring
up **every stack except headscale** — running a second control plane against
copied state would fight the live one. Validate against the copied data: Immich
shows the library, Jellyfin plays, monitoring sees targets. Iterate here over as
many evenings as needed — nobody depends on this box yet.

**Phase 2 — Cutover (target < 1 hour downtime).**
1. Old box: stop containers **except headscale + its caddy**, plus syncthing
   and backrest. sshd stays up; headscale stays up because step 4 needs it.
2. Delta rsync (that day's changes only).
3. Copy ssh host keys + syncthing keys to the HP.
4. Flip the identity **while the old box's headscale is still serving**: old
   box `tailscale logout` and hostname stood down (bootable, but no longer
   claiming the name); HP takes hostname `datacore` and `tailscale up` as
   `datacore`.
5. HP: start syncthing, the five non-headscale stacks, backrest.
6. Verify the ring: phone syncs to Immich; syncthing peers reconnect (same
   device ID); `git fetch` from rafik via the mirror hop; a manual backrest run
   to B2 succeeds.

**Phase 2b — Hand over headscale (its own window).** Only once Phase 2 has
verified. The tailnet control plane moves alone, so nothing else is in flight
if it goes wrong.
1. Old box: stop the headscale stack (headscale + its caddy).
2. Sync its state — `/home/srv-data/stacks-state/headscale/data` and the
   config under `datacore-config/stacks/headscale/config`. Small; seconds.
3. HP: start the headscale stack. Wait until it is genuinely serving before
   touching anything else.
4. **Re-point the router's 80/443 forward** at the HP. This is manual and is
   the one step nothing in either repo can do.
5. Verify from a *third* machine — rafik or whistle — that
   `headscale.stonewallmapletree.com` answers and `tailscale status` is sane.

Existing nodes ride cached peer state through the gap, so an outage here costs
new registrations and renames, not connectivity.

**Phase 3 — Soak + retire.** Success = all 22 containers healthy for a
week, syncthing in sync fleet-wide, one full backrest→B2 cycle with a
spot restore-test, mirror hop proven, whistle→datacore ssh/tailscale
path working, and headscale serving a *new* node registration at least once
(the thing the old control plane could no longer do). Then wipe the laptop —
its disk holds the last pre-migration copy, so wipe only after the soak passes.

## Rollback

- **Before flip step 4:** start old services again; nothing was moved, only
  copied.
- **After the flip, before 2b:** boot the laptop and reverse the identity flip
  — it still has keys and data as of the quiesce, and it is still running
  headscale, so the tailnet can serve the rename back.
- **During 2b:** re-point the router forward at the old box and start its
  headscale stack again. Its state is only as stale as step 2's sync.
- **After retirement:** restore from B2.

The ordering exists so that the two irreversible-feeling moments — the identity
flip and the control-plane handover — never happen in the same window.

## Out of scope

Nixifying individual compose stacks (possible later, one at a time),
headscale's future vs Tailscale, and any change to what the services do.
IB Gateway/pearl-platform decommissioning on the old box needs no work —
they simply don't move.
