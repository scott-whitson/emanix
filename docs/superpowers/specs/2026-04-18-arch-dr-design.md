# Arch Linux DR & Reinstall Plan

**Date:** 2026-04-18
**Status:** Design approved, ready for implementation plan
**Scope:** Single-machine disaster recovery for Scott's Arch laptop — codifying reinstall on same or new hardware, practiced first in a VM then on current hardware.

## Goal

Turn the current ad-hoc setup into a rehearsed, documented, partially-automated recovery path so that any of the following scenarios ends in a working laptop within a few hours:

- **B** (primary): wipe and reinstall same hardware
- **A** (secondary): install on replacement hardware after loss/destruction
- **C** (low priority): offline recovery with no internet — deferred

Existing pieces `~/dotfiles/install.sh`, `~/dotfiles/tools/dr_backup.sh`, and `~/dotfiles/tools/dr_restore.sh` already cover the "after first login as scott on a working Arch install" portion. This design fills the gap before that point (bare disk → running Arch), closes known backup gaps, and adds a testing/execution discipline.

## Current-state audit

- Hardware: nvme0n1 with 8 partitions. p1 EFI, p2+p3 Btrfs (root+home split across partitions with subvolumes), p6 redundant swap, p7 orphan ext4 (old Ubuntu root), p8 ext4 at `/home/scott/gdrive` (157 GiB local gdrive data). Windows files removed; NVRAM still has stale Windows/Ubuntu entries.
- Bootloader: systemd-boot active. `/boot/grub` and `/boot/limine` dirs are leftover artifacts.
- Swap: zram0 (4 GiB, priority 100, active) + nvme0n1p6 (7.1 GiB, priority -1, unused). Effectively zram-only.
- No disk encryption.
- No snapshots.
- Mesh VPN: Tailscale active (`tailscaled.service`). NetBird uninstalled; `~/.config/netbird/active_profile.txt` is a stale leftover.

## Architecture decisions

### Disk layout (post-reinstall)

```
nvme0n1p1  →  /boot                    EFI, 1 GiB, unencrypted (FAT32)
nvme0n1p2  →  LUKS2 container → Btrfs with subvolumes:
                @            →  /
                @home        →  /home
                @var_log     →  /var/log
                @pkg         →  /var/cache/pacman/pkg
                @snapshots   →  /.snapshots
nvme0n1p8  →  /home/scott/gdrive       ext4, UNTOUCHED (preserves 157 GiB)
```

p3 (separate /home partition), p6 (dead swap), p7 (old Ubuntu) are reclaimed into p2.

### Key choices

| Decision | Chosen | Why |
|---|---|---|
| Filesystem | Btrfs with subvolumes | Shared free space across roles; coherent snapshots; modern default |
| /home | Subvolume (`@home`) — not separate partition | Same isolation benefits as separate partition plus shared free space |
| Encryption | LUKS2 with argon2id KDF | Laptop threat model (stolen device) requires at-rest encryption |
| /boot | Unencrypted FAT32 on EFI partition | Simpler; LUKS on root is sufficient for laptop threat model |
| Bootloader | GRUB (with `GRUB_ENABLE_CRYPTODISK=y`) | Enables `grub-btrfs` snapshot-boot-menu integration; broadest documentation for learners |
| Swap | Zram only, no swap partition | 30 GiB RAM makes disk swap unnecessary; zram is simpler |
| Snapshot tool | snapper + snap-pac + grub-btrfs | Standard Arch stack; `snap-pac` auto-snapshots on every pacman operation |
| Snapshotted subvolumes | `@` only (not `@home`, `@var_log`, `@pkg`) | Snapshots protect system rollback; user data protected by backups |

### Snapshots vs backups (not the same thing)

- **Snapshots** = "I broke `/` with a bad package update; boot an old snapshot." Local, fast, doesn't help if drive dies.
- **Backups** = "Laptop stolen / drive dead; restore my data." Remote (gdrive), slow, survives hardware loss.

Both are needed; they solve different problems.

## Repo layout

New top-level directory in `~/dotfiles`:

```
~/dotfiles/recovery/
├── README.md            # runbook (start here in a disaster)
├── archinstall.json     # archinstall config (disk, locale, hostname, user, base packages)
├── partition.sh         # manual pre-partitioning, preserves p8
├── post-install.sh      # orchestrates first-boot tasks
├── etc-allowlist.txt    # which /etc files are safe to auto-restore vs. review vs. skip
└── notes/
    ├── hardware.md      # laptop make/model/quirks
    ├── choices.md       # rationale for architecture decisions (this doc's TL;DR)
    └── services.md      # Tailscale re-enrollment steps, other service pointers
```

`tools/dr_backup.sh` and `tools/dr_restore.sh` stay in place — they work and have `~/.local/bin/` wrappers. The `recovery/` directory is install-time-only material, separate mental model from daily tools.

### What is committed vs. kept offline

| Artifact | Location | Rationale |
|---|---|---|
| `archinstall.json` (no passwords) | git | Config as code |
| `partition.sh`, `post-install.sh`, runbook | git | Config as code |
| LUKS header backup (`luks-header.img`) | `gdrive:backups/dr/` + `malt:~/dr-backups/` | Binary, sensitive, critical |
| LUKS passphrase | Paper in fire-proof box + Bitwarden | Offline, irrecoverable if lost |
| Bitwarden master password | Paper in fire-proof box + memorized | Root of trust |
| Google account recovery codes | Paper in fire-proof box | Needed for `rclone` device-flow auth if 2FA blocks login |

## Restore flow (the runbook)

7-phase flow from booted ISO to verified system. Approximate total: 75 min on a fresh machine with good internet.

### Phase 0 — Pre-disaster preparation *(one-time, keep current)*

Three offline artifacts must exist:
- LUKS passphrase (paper, fire-proof box; duplicate in Bitwarden)
- Bitwarden master password (memorized; paper duplicate)
- Arch ISO on Ventoy USB (deferred; scenario C, low priority)

### Phase 1 — Boot ISO, establish network *(~5 min)*

Boot the Arch live USB. Get online:
- Ethernet: works immediately.
- Wifi: `iwctl` → `station wlan0 connect <ssid>`.

Verify: `ping -c 3 archlinux.org`.

### Phase 2 — Partition, encrypt, format *(~10 min)*

Fetch `partition.sh` from the dotfiles GitHub (HTTPS + PAT if repo is private) and run it. The script:

1. Creates GPT layout: p1 (1 GiB EFI), p2 (everything except p8).
2. **Refuses to proceed if p8 cannot be detected.** Prompts for explicit "WIPE" confirmation showing which partitions will be destroyed.
3. `cryptsetup luksFormat /dev/nvme0n1p2` (prompts for passphrase).
4. `cryptsetup open /dev/nvme0n1p2 cryptroot`.
5. **Verifies the passphrase works** by closing and re-opening the mapping before continuing.
6. `mkfs.btrfs /dev/mapper/cryptroot` and creates subvolumes `@`, `@home`, `@var_log`, `@pkg`, `@snapshots`.
7. Mounts the hierarchy under `/mnt`.
8. Backs up the LUKS header to `/tmp/luks-header.img` and copies it to `malt:~/dr-backups/` via Tailscale. gdrive upload happens later after restore completes.

### Phase 3 — Base install via archinstall *(~15 min)*

```bash
archinstall --config /tmp/archinstall.json
```

Config fetched from the dotfiles repo. It:
- Runs `pacstrap` for base + essential packages (NetworkManager, openssh, zsh, git, rclone, sudo).
- Sets up GRUB with `GRUB_ENABLE_CRYPTODISK=y`.
- Adds `encrypt` hook to mkinitcpio so LUKS unlocks at boot.
- Creates user `scott`.
- Does **not** install the desktop stack; `install.sh` handles that in Phase 4.

Reboot into the fresh system. LUKS prompts for passphrase. Log in as `scott`.

### Phase 4 — Restore user data *(~20 min)*

```bash
# a) Set up gdrive access (interactive, Google device-flow, ~3 min)
rclone config

# b) Pull latest backup
mkdir ~/dr-restore && cd ~/dr-restore
rclone copy gdrive:backups/dr/LATEST/ .

# c) Extract home tarball (dotfiles, .ssh, .config, projects all come back)
tar --zstd -xf dr-*-home.tar.zst -C /home/

# d) Bootstrap desktop (install.sh is idempotent after restore)
cd ~/dotfiles && ./install.sh personal

# e) Selective /etc restore (not wholesale; see etc-allowlist.txt)
~/dotfiles/recovery/post-install.sh --restore-system
```

**Chicken-and-egg resolutions:**
- Rclone creds → Google device-flow auth, no prior credential needed.
- Private dotfiles repo clone → skipped entirely; dotfiles come out of the backup tarball.
- SSH keys → restored from backup in step (c).
- Package list → `system/packages.list` from backup, `sudo pacman -S --needed - < packages.list`.

### Phase 5 — Snapshots + final system setup *(~10 min)*

```bash
sudo pacman -S snapper snap-pac grub-btrfs
sudo snapper -c root create-config /
# Edit /etc/snapper/configs/root for retention policy
sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
sudo systemctl enable --now grub-btrfsd.service
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo snapper -c root create --description "post-DR-restore baseline"
```

Upload the LUKS header backup to gdrive now that rclone is configured:
```bash
rclone copy /tmp/luks-header.img gdrive:backups/dr/
```

### Phase 6 — Re-enroll peer-state services *(~5 min)*

```bash
sudo tailscale up          # browser device-flow auth, or --auth-key=tskey-...
tailscale status           # verify peers visible
```

### Phase 7 — Verify

- [ ] Reboot; LUKS prompt appears; system boots clean.
- [ ] `snapper list` shows the baseline snapshot.
- [ ] Reboot → GRUB menu shows "Arch Linux snapshots" submenu.
- [ ] Hyprland launches, waybar renders, apps open.
- [ ] `ssh` to a known host works (keys restored).
- [ ] `rbw` / Bitwarden CLI works.
- [ ] `rclone ls gdrive:` works.
- [ ] `tailscale status` shows this machine connected.
- [ ] `~/gdrive/` still holds its ~157 GiB (p8 preserved).

## Backup gap fixes

### Gap 1 — LUKS header backup

Add to `dr_backup.sh`: when root is on LUKS, dump the header into `system/luks-header.img` and include it in the system tarball. Takes ~16 MiB. Detect via `lsblk` on `/dev/nvme0n1p2`.

### Gap 2 — Selective `/etc` restore

Replace the manual "diff and cherry-pick" flow in `dr_restore.sh` with an allowlist-driven restore in `post-install.sh`. Three categories:

**Auto-restore (safe):**
- `pacman.conf`, `pacman.d/mirrorlist`, `pacman.d/hooks/`
- `pam.d/system-auth` (critical — preserves the `pam_systemd_home` fix)
- `NetworkManager/system-connections/` (saved wifi networks)
- `hosts`
- `ssh/sshd_config`
- `systemd/timesyncd.conf`

**Never auto-restore (new on every install):**
- `fstab`, `crypttab`, `machine-id`, `shadow`, `passwd`
- `mkinitcpio.conf`, `default/grub`
- `systemd/system/*`, `ssh/ssh_host_*`, `resolv.conf`

**Review (prompt user):**
- `systemd/network/`, `locale.conf`, `vconsole.conf`, `hostname`

Lists live in `recovery/etc-allowlist.txt`. `dr_restore.sh` stays as-is for backward compatibility; new logic lives in `post-install.sh`.

### Gap 3 — Secrets never on disk

Paper in fire-proof box at home:
- LUKS passphrase
- Bitwarden master password
- Google account recovery codes

Ideally also an off-site duplicate (parent's house / safe deposit box), but not blocking.

### Gap 4 — Tailscale re-enrollment

Tailscale machine state is not backed up (lives in `/var/lib/tailscale/`). Re-enroll via `sudo tailscale up` after first login. `recovery/notes/services.md` documents the enrollment flow and pre-generated auth-key option for unattended installs.

### Gap 5 — One-time bootstrap secrets

The only two secrets required in Phase 1-4 of the restore (before the backup can be decrypted) are:
- LUKS passphrase (Phase 2)
- Google account login (Phase 4 step a)

Everything else — SSH keys, GPG, rclone saved config, dotfiles, Bitwarden vault — comes back from the backup itself.

## VM testing strategy

Test the entire flow end-to-end in `qemu` before touching real hardware.

### Setup (one-time)

```bash
sudo pacman -S --needed qemu-full libvirt virt-manager edk2-ovmf dnsmasq
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $USER   # re-login to take effect
```

### VM configuration

| Setting | Value |
|---|---|
| Firmware | UEFI (OVMF) |
| Disk | 40 GiB qcow2 |
| RAM | 4 GiB |
| CPU | 2 vCPU, host passthrough |
| Network | virt-manager default NAT |
| Boot media | Fresh Arch ISO |

### Fake backup for fast iteration

Build a toy home tarball (~200 MiB) with just the minimum: dotfiles, `.ssh`, `.config/rclone`, a few sample configs. Serve it through an `rclone local` remote instead of real gdrive. Cuts iteration time from ~75 min to ~20 min per full run.

### Snapshot-driven iteration

Take a VM snapshot after each stable state so iterations only redo what changed:

| Snapshot | Captured state |
|---|---|
| S1 | Booted ISO, network up |
| S2 | Partitioned, LUKS open |
| S3 | Fresh Arch, first login |
| S4 | Backup extracted |
| S5 | End-to-end working baseline |

### Verification checklist

- [ ] `partition.sh` completes on blank disk
- [ ] `archinstall --config archinstall.json` succeeds non-interactively
- [ ] Reboot → GRUB prompts for LUKS passphrase → unlocks → login
- [ ] `rclone config` flow works (device-flow or local-remote)
- [ ] `dr_restore.sh` extracts home tarball
- [ ] `install.sh personal` runs on top of restored home without errors
- [ ] `snapper list` shows baseline
- [ ] **Snapshot rollback test:** break `/` on purpose (`sudo rm -f /usr/bin/ls`), reboot, pick old snapshot from GRUB, verify recovery
- [ ] `tailscale up` enrolls

### Graduation criteria

Green light to do the bare-metal practice wipe only when:
1. Two full end-to-end runs have succeeded in the VM (one could be luck).
2. All checklist items pass.
3. Every error/warning has been understood.
4. Runbook updated with any surprises.

## Practice execution on real hardware

### Point of no return

The first destructive `sgdisk`/`parted` write in Phase 2. Everything before is reversible (yank USB, reboot current system); everything after is one-way.

### Pre-flight checklist (day of)

**Redundant backups:**
- [ ] Fresh `dr_backup.sh` run, verified
- [ ] Copy of backup also on malt via `rsync` — LAN fallback if gdrive auth breaks

**Paper-in-safe:**
- [ ] LUKS passphrase, Bitwarden master, Google recovery codes all written and legible

**Arch USB:**
- [ ] Flashed with current Arch ISO
- [ ] Booted to the ISO shell as a dry run
- [ ] Internet reached, `rclone config` auth succeeded, test download from `gdrive:backups/dr/` actually retrieved a file
- [ ] Reboot back to current Arch

**Runbook:**
- [ ] `~/dotfiles/recovery/` committed and pushed
- [ ] GitHub PAT ready in Bitwarden for `curl` over HTTPS in live ISO
- [ ] VM has passed two full green runs

**Calendar:**
- [ ] No deadlines next day
- [ ] ~4 hours blocked (real time ~75 min, padded for surprises)
- [ ] Laptop plugged in

### Hardware-specific nuances

1. **p8 preservation:** `partition.sh` must verify p8 is present and unchanged before touching anything, and require explicit "WIPE" confirmation listing exactly which partitions die.
2. **Passphrase verification:** after `luksFormat`, close and re-open the LUKS mapping before continuing. Catches typos immediately.
3. **Early header backup:** back up LUKS header to malt via `scp` right after format, not at the end. Header is pristine at that point.

### Failure recovery

| Failure | Recovery |
|---|---|
| Partition script wipes wrong partition | Stop. Live USB. Re-sync gdrive data from cloud (it's replicated). |
| LUKS passphrase mistyped, caught in verification | Re-run `luksFormat`. |
| LUKS passphrase mistyped, not caught | Unrecoverable. Prevention > recovery. |
| `archinstall` fails on current ISO (schema drift) | Fall back to manual install per Arch Wiki, using `recovery/notes/choices.md` as the decision log. ~45 min extra. |
| Backup download from gdrive fails | Use malt copy: `rsync malt:~/dr-backups/latest ./`. |
| GRUB doesn't unlock LUKS at boot | Live USB, chroot, fix `GRUB_CMDLINE_LINUX="cryptdevice=UUID=... root=/dev/mapper/cryptroot"`, `grub-mkconfig`. |
| Hyprland fails to start | Console login still works. Re-run `install.sh personal`, check journal. |

### Done-done criteria

- [ ] Phase 7 verification checklist passes
- [ ] 48 hours of normal use with no regressions
- [ ] `~/gdrive/` still ~157 GiB
- [ ] A **new** `dr_backup.sh` run succeeds on the fresh system (closes the loop)
- [ ] Runbook updated with anything surprising

## Housekeeping items *(unrelated to DR but worth doing)*

- Delete stale EFI NVRAM entries: `sudo efibootmgr -b 0000 -B` (Windows), `-b 0001 -B` (dead disk), `-b 0003 -B` (Ubuntu).
- Remove old bootloader directories: `/boot/grub`, `/boot/limine`.
- Update `memory/dr_backup.md` memory file after scripts are extended.

## Out of scope

- Scenario C (offline recovery via Ventoy USB). Deferred; will be revisited after the above is in production.
- Hibernate-to-disk (requires real swap or swapfile). Not needed with 30 GiB RAM + zram.
- Full-disk encryption for `/boot` (adds complexity without meaningful threat-model benefit for laptop).
- Multi-machine DR (this is explicitly single-laptop).
- TPM-bound auto-unlock (could be added later; starts with passphrase-only).

## Artifacts to produce in implementation

| File | Type | Status |
|---|---|---|
| `~/dotfiles/recovery/README.md` | Runbook | New |
| `~/dotfiles/recovery/archinstall.json` | Config | New |
| `~/dotfiles/recovery/partition.sh` | Script | New |
| `~/dotfiles/recovery/post-install.sh` | Script | New |
| `~/dotfiles/recovery/etc-allowlist.txt` | Data | New |
| `~/dotfiles/recovery/notes/hardware.md` | Doc | New |
| `~/dotfiles/recovery/notes/choices.md` | Doc | New |
| `~/dotfiles/recovery/notes/services.md` | Doc | New |
| `~/dotfiles/tools/dr_backup.sh` | Script | Edit — add LUKS header backup |
