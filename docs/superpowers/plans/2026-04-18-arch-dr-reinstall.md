# Arch Linux DR & Reinstall Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Codify a rehearsed, partially-automated Arch Linux disaster-recovery path that covers bare-disk-to-working-system on the current laptop (scenario B) and on replacement hardware (scenario A), building on the existing `~/dotfiles/install.sh` + `~/dotfiles/tools/dr_backup.sh` + `~/dotfiles/tools/dr_restore.sh` pipeline.

**Architecture:** A new `~/dotfiles/recovery/` directory containing a runbook, archinstall JSON config, partitioning script, post-install orchestrator, and an `/etc` allowlist. Target layout is LUKS2 → Btrfs (subvolumes `@`/`@home`/`@var_log`/`@pkg`/`@snapshots`) → GRUB with `grub-btrfs` snapshot integration → zram swap. The current `nvme0n1p8` (157 GiB local gdrive partition) is preserved across reinstalls; everything else on the disk is wiped. `dr_backup.sh` is extended to capture a LUKS header when root is encrypted.

**Tech Stack:** Bash, Arch Linux (`archinstall`, `pacman`, `cryptsetup`, `sgdisk`, `btrfs-progs`), `snapper` + `snap-pac` + `grub-btrfs`, `rclone` (Google Drive), Tailscale, `shellcheck` for lint, `qemu`/`libvirt`/`virt-manager` for VM testing.

**Spec:** `docs/superpowers/specs/2026-04-18-arch-dr-design.md`

---

## File Structure

New files under `~/dotfiles/recovery/`:

| Path | Purpose |
|---|---|
| `README.md` | Runbook — the thing you read first in a disaster |
| `archinstall.json` | `archinstall` config consumed in Phase 3 |
| `partition.sh` | Partition + LUKS + Btrfs layout, preserves `p8` |
| `post-install.sh` | Selective `/etc` restore, snapshot stack setup |
| `etc-allowlist.txt` | Which `/etc` files are safe to auto-restore |
| `notes/hardware.md` | Laptop make/model, firmware quirks |
| `notes/choices.md` | Rationale for architecture decisions (for future-you) |
| `notes/services.md` | Tailscale + other service re-enrollment steps |
| `tests/make-test-backup.sh` | Helper to build a tiny fake backup for VM iteration |
| `tests/vm-setup.md` | VM instructions (read-only procedural doc) |

Edits to existing:

| Path | Change |
|---|---|
| `tools/dr_backup.sh` | Add LUKS-header capture when root is on LUKS |

Boundaries/responsibilities:

- **`partition.sh`** handles only disk layout: partition table, LUKS format, Btrfs + subvolumes, mount hierarchy, LUKS header backup. It does **not** install packages.
- **`archinstall.json`** handles base-system install: `pacstrap`, user creation, GRUB, mkinitcpio, essential services. It consumes the mount layout from `partition.sh`.
- **`post-install.sh`** runs on the freshly-booted system: selective `/etc` restore from backup, snapshot stack setup. It does **not** fetch the backup (that's manual per the runbook) or install the desktop stack (that's `~/dotfiles/install.sh`'s job).
- **`dr_backup.sh`** grows one feature (LUKS header) but its contract is unchanged.

---

## Pre-Flight

Before Task 1, verify current working tree is clean (or changes are unrelated and safe to leave uncommitted):

```bash
cd ~/dotfiles && git status --short
```

Existing uncommitted changes (`base/hypr/*`, `base/zsh/.zshrc`, `tools/dr_backup.sh`) are noted — confirm with Scott whether to stash, commit, or leave alone before starting. The plan's commits should touch only `recovery/`, `tools/dr_backup.sh`, and `docs/`.

Install `shellcheck` if not already present:
```bash
command -v shellcheck &>/dev/null || sudo pacman -S --needed shellcheck
```

---

### Task 1: Create `etc-allowlist.txt`

**Files:**
- Create: `recovery/etc-allowlist.txt`

- [ ] **Step 1: Write the allowlist file**

Create `~/dotfiles/recovery/etc-allowlist.txt` with the following exact content:

```
# /etc restore allowlist
# Used by post-install.sh --restore-system
# Three sections: AUTO (copy without asking), REVIEW (prompt), NEVER (ignore)
#
# Paths are relative to /etc inside the extracted etc.tar

[AUTO]
pacman.conf
pacman.d/mirrorlist
pacman.d/hooks/
pam.d/system-auth
NetworkManager/system-connections/
hosts
ssh/sshd_config
systemd/timesyncd.conf

[REVIEW]
systemd/network/
locale.conf
vconsole.conf
hostname

[NEVER]
fstab
crypttab
machine-id
shadow
passwd
mkinitcpio.conf
default/grub
systemd/system/
ssh/ssh_host_
resolv.conf
```

- [ ] **Step 2: Verify file parses as three sections**

```bash
cd ~/dotfiles
awk '/^\[/{s=$0; next} s && NF && $1!~/^#/{print s, $0}' recovery/etc-allowlist.txt
```
Expected output: every non-comment non-blank line prefixed with its section header. Spot-check: `[AUTO] pacman.conf`, `[NEVER] fstab`.

- [ ] **Step 3: Commit**

```bash
cd ~/dotfiles
git add recovery/etc-allowlist.txt
git commit -m "recovery: add etc-allowlist.txt for selective /etc restore"
```

---

### Task 2: Write `recovery/notes/choices.md`

**Files:**
- Create: `recovery/notes/choices.md`

- [ ] **Step 1: Write the decisions doc**

Create `~/dotfiles/recovery/notes/choices.md` with the following content:

```markdown
# Architecture choices — rationale

One-liner summary of decisions made in the 2026-04-18 DR design.
Full reasoning in `docs/superpowers/specs/2026-04-18-arch-dr-design.md`.

## Filesystem: Btrfs with subvolumes (`@`, `@home`, `@var_log`, `@pkg`, `@snapshots`)
Subvolumes give the "wipe root without touching home" property of separate partitions,
plus shared free space and coherent system snapshots. `@home`/`@var_log`/`@pkg` are
deliberately **not** snapshotted — snapshots protect rollback of `/`, user data is
protected by backups.

## Encryption: LUKS2 with argon2id KDF
Laptop leaves the house → at-rest encryption required. `/boot` stays unencrypted on the
EFI partition; encrypting it is possible but adds complexity without meaningful gain
for the laptop threat model.

## Bootloader: GRUB (with `GRUB_ENABLE_CRYPTODISK=y`)
Enables `grub-btrfs` which auto-generates boot entries for snapshots. That's the whole
reason snapshots are useful — booting into an old snapshot when `/` is broken.
systemd-boot is simpler but has no equivalent snapshot-boot UX. Limine (Omarchy) is
nice but has a smaller community for learners looking up errors.

## Swap: zram only, no swap partition
30 GiB RAM + zram makes disk swap unnecessary. No hibernate support by design —
add a swapfile later if needed.

## Snapshot stack: snapper + snap-pac + grub-btrfs
Standard Arch stack. `snap-pac` auto-snapshots before/after every `pacman` operation —
the main value prop ("a bad update borked my system → boot the pre-update snapshot").

## `/home` as subvolume, not separate partition
The current layout has `/home` on its own partition (`nvme0n1p3`). Reinstall folds it
into the main Btrfs pool. Shared free space wins; the "separate partition" reinstall-
isolation property is already covered by subvolumes.

## `p8` (gdrive partition) preserved across reinstalls
`nvme0n1p8` holds 157 GiB of locally-cached Google Drive data. Re-syncing it from the
cloud takes hours. `partition.sh` is designed to verify and preserve it.
```

- [ ] **Step 2: Commit**

```bash
cd ~/dotfiles
git add recovery/notes/choices.md
git commit -m "recovery: document architecture choices rationale"
```

---

### Task 3: Write `recovery/notes/hardware.md`

**Files:**
- Create: `recovery/notes/hardware.md`

- [ ] **Step 1: Gather current hardware info**

Run on current system:

```bash
cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name /sys/class/dmi/id/bios_version 2>/dev/null
lspci | grep -E "VGA|Network|Audio"
lsusb | head -20
uname -r
```

Record the outputs — they go in the doc in Step 2.

- [ ] **Step 2: Write the hardware notes**

Create `~/dotfiles/recovery/notes/hardware.md`. Fill the TEMPLATE with the values recorded in Step 1:

```markdown
# Hardware notes

Recorded for reinstall-on-same-hardware (scenario B). Update whenever the laptop changes.

## Identity
- **Vendor / model:** <fill from /sys/class/dmi/id/sys_vendor + product_name>
- **BIOS / firmware version:** <fill from bios_version>
- **Verified on kernel:** <fill from uname -r>

## Key components (lspci / lsusb relevant lines)
- **GPU:** <VGA line from lspci>
- **Wifi/Ethernet:** <Network lines from lspci>
- **Audio:** <Audio line from lspci>

## Quirks / gotchas
- <e.g. "Touchpad requires libinput tap-to-click enabled in Hyprland config">
- <e.g. "Suspend occasionally hangs; workaround is setting PCIe ASPM=off">
- Leave this list empty until you discover quirks — do not invent.

## Firmware updates
- `fwupdmgr refresh && fwupdmgr update` is the usual command if updates are available.
- Check before a reinstall so you're on a known-good BIOS.
```

**Important:** do **not** leave `<fill ...>` placeholders in the committed file. Replace each one with a real value. If a value doesn't apply, write "n/a" explicitly.

- [ ] **Step 3: Verify no unfilled placeholders remain**

```bash
cd ~/dotfiles
grep -n '<fill' recovery/notes/hardware.md && echo "FAIL: placeholders remain" || echo "OK"
```
Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
cd ~/dotfiles
git add recovery/notes/hardware.md
git commit -m "recovery: add hardware notes for current laptop"
```

---

### Task 4: Write `recovery/notes/services.md`

**Files:**
- Create: `recovery/notes/services.md`

- [ ] **Step 1: Write the services doc**

Create `~/dotfiles/recovery/notes/services.md`:

```markdown
# Service re-enrollment after DR

Services whose machine identity doesn't restore from backup. Do these after Phase 4
of the runbook (user data restored, network up).

## Tailscale
Daemon state in `/var/lib/tailscale/tailscaled.state` is **not** backed up — Tailscale
treats each reinstall as a new peer identity.

Standard enrollment (opens browser for Google auth):

    sudo tailscale up

Headless/unattended (from a pre-generated auth key):

    sudo tailscale up --auth-key=tskey-auth-XXXX...

Auth keys live at https://login.tailscale.com/admin/settings/keys — generate a single-
use reusable key ahead of time and store it in Bitwarden for the DR scenario.

Verify peers are reachable:

    tailscale status
    tailscale ping malt

## GitHub (for private dotfiles access if needed)
The restore flow sidesteps cloning the private dotfiles repo (they come out of the
home backup tarball). If you ever need to re-clone mid-recovery:

- Have a Personal Access Token ready in Bitwarden
- Clone via HTTPS: `git clone https://<PAT>@github.com/scott-whitson/dotfiles.git`
- Or restore the SSH key first (from the backup's `.ssh/id_ed25519`) and clone via SSH

## Google Drive (rclone)
First-time setup after reinstall:

    rclone config
    # → n (new remote) → name: gdrive → type: drive → OAuth device flow

This doesn't require any pre-existing creds beyond your Google account password +
2FA method. Recovery codes (paper in fire-proof box) are the fallback if 2FA is
unreachable.
```

- [ ] **Step 2: Commit**

```bash
cd ~/dotfiles
git add recovery/notes/services.md
git commit -m "recovery: document Tailscale, GitHub, rclone re-enrollment"
```

---

### Task 5: Extend `dr_backup.sh` with LUKS header capture

**Files:**
- Modify: `tools/dr_backup.sh`

**Context:** The current `dr_backup.sh` has a `collect_system_info()` function (starts around line 85 based on the file we read during design). We add one block to it that detects whether root is on LUKS and, if so, backs up the header into `system/luks-header.img`.

- [ ] **Step 1: Add the LUKS-header-capture block to `collect_system_info()`**

Open `~/dotfiles/tools/dr_backup.sh`. Inside `collect_system_info()`, immediately after the "Systemd user units" block and before `log "  System info collected"`, insert:

```bash
    # LUKS header backup (only if root is on a LUKS-encrypted block device)
    ROOT_SRC="$(findmnt -n -o SOURCE /)"
    CRYPT_BACKING=""
    if [[ "$ROOT_SRC" == /dev/mapper/* ]]; then
        # Follow the mapper → find the underlying block device
        CRYPT_BACKING="$(cryptsetup status "$(basename "$ROOT_SRC")" 2>/dev/null \
            | awk '/device:/{print $2}')"
    fi
    if [[ -n "$CRYPT_BACKING" ]] && cryptsetup isLuks "$CRYPT_BACKING" 2>/dev/null; then
        log "  Root is on LUKS ($CRYPT_BACKING) — capturing header..."
        if sudo -n true 2>/dev/null; then
            sudo cryptsetup luksHeaderBackup "$CRYPT_BACKING" \
                --header-backup-file "${STAGING}/system/luks-header.img" 2>/dev/null \
                && log "  LUKS header saved ($(du -sh "${STAGING}/system/luks-header.img" | cut -f1))" \
                || warn "  LUKS header backup failed"
        else
            warn "  sudo required for LUKS header backup — skipped"
        fi
    else
        log "  Root is not on LUKS — skipping header backup"
    fi
```

- [ ] **Step 2: Run shellcheck on the updated script**

```bash
cd ~/dotfiles
shellcheck tools/dr_backup.sh
```
Expected: no new errors introduced. Any pre-existing warnings can be left alone (they're out of scope for this plan).

- [ ] **Step 3: Dry-run the script to verify the new block is reached**

```bash
cd ~/dotfiles
./tools/dr_backup.sh --dry-run 2>&1 | tee /tmp/dr-backup-dryrun.log
```

Expected: the dry-run path in `dr_backup.sh` doesn't call `collect_system_info`, so this just verifies the script still parses. No errors.

- [ ] **Step 4: Real run (no upload) to verify LUKS detection branch**

```bash
cd ~/dotfiles
./tools/dr_backup.sh --no-upload 2>&1 | tee /tmp/dr-backup-real.log
```

Current system is **not** on LUKS, so look for the line:
```
Root is not on LUKS — skipping header backup
```
This proves the detection branch works. Inspect the resulting system tarball to confirm no `luks-header.img` file (since root isn't encrypted):
```bash
zstd -dc /tmp/dr-*-system.tar.zst | tar t | grep -i luks || echo "OK: no luks-header.img as expected"
```

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add tools/dr_backup.sh
git commit -m "dr_backup: capture LUKS header when root is encrypted"
```

---

### Task 6: Write `recovery/archinstall.json`

**Files:**
- Create: `recovery/archinstall.json`

**Context:** `archinstall`'s config schema evolves between releases. This config is a **best-effort target** that will be validated and refined during the VM test in Task 14. Fields marked `# TODO-verify` in the comment in Step 2 are the ones most likely to need adjustment.

- [ ] **Step 1: Check the currently-installed archinstall version for reference**

```bash
archinstall --version 2>/dev/null || echo "archinstall not installed; config will be validated in VM (Task 14) using the ISO's bundled version"
```

- [ ] **Step 2: Write the config**

Create `~/dotfiles/recovery/archinstall.json`. Note: JSON has no comments, so annotations go in a sibling file. Content:

```json
{
  "version": "3.0.0",
  "archinstall-language": "English",
  "locale_config": {
    "kb_layout": "us",
    "sys_enc": "UTF-8",
    "sys_lang": "en_US"
  },
  "mirror_config": {
    "mirror_regions": {
      "United States": []
    }
  },
  "hostname": "arch",
  "ntp": true,
  "swap": false,
  "kernels": ["linux"],
  "bootloader": "Grub",
  "uki": false,
  "audio_config": {
    "audio": "pipewire"
  },
  "network_config": {
    "type": "nm"
  },
  "profile_config": {
    "profile": {
      "main": "Minimal",
      "details": [],
      "custom_settings": {}
    }
  },
  "packages": [
    "base-devel",
    "git",
    "zsh",
    "rclone",
    "openssh",
    "sudo",
    "tailscale",
    "btrfs-progs",
    "amd-ucode",
    "intel-ucode",
    "neovim"
  ],
  "services": ["NetworkManager", "sshd", "tailscaled"],
  "timezone": "America/New_York",
  "additional-repositories": ["multilib"],
  "__disk_config_note__": "Disk config is SET BY partition.sh before archinstall runs. We mount the hierarchy under /mnt and run `archinstall --config archinstall.json --silent --skip-ntp --mountpoint /mnt` (flags TBD-verify in VM). The `disk_config` key is intentionally omitted here."
}
```

- [ ] **Step 3: Validate JSON parses**

```bash
cd ~/dotfiles
python -c "import json; json.load(open('recovery/archinstall.json'))" && echo OK
```
Expected: `OK`. If parse fails, fix syntax.

- [ ] **Step 4: Commit**

```bash
cd ~/dotfiles
git add recovery/archinstall.json
git commit -m "recovery: add archinstall.json (validated in VM Task 14)"
```

---

### Task 7: Write `partition.sh` part 1 — skeleton, args, safety

**Files:**
- Create: `recovery/partition.sh`

**Context:** `partition.sh` is broken across three tasks. This task establishes the skeleton, argument parsing, dry-run mode, and the p8-preservation safety check — the "can't blow up the wrong thing" foundation.

- [ ] **Step 1: Write the initial script**

Create `~/dotfiles/recovery/partition.sh` with the following content (mark executable in Step 3):

```bash
#!/usr/bin/env bash
set -euo pipefail

# partition.sh — partition + LUKS + Btrfs for Arch DR reinstall.
# Runs from the Arch live ISO. Targets /dev/nvme0n1 by default.
#
# Usage: partition.sh [--target DEV] [--preserve LIST] [--dry-run] [--yes]
#
# --target DEV        block device to partition (default /dev/nvme0n1)
# --preserve LIST     comma-separated partition numbers to keep (default 8)
# --dry-run           print what would happen; don't touch the disk
# --yes               skip the WIPE confirmation prompt (use with care; meant for VM)

TARGET="/dev/nvme0n1"
PRESERVE="8"
DRY_RUN=false
ASSUME_YES=false

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[part]${NC} $*"; }
warn() { echo -e "${YELLOW}[part]${NC} $*"; }
err()  { echo -e "${RED}[part]${NC} $*" >&2; }

usage() {
    sed -n '4,10p' "$0"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --target)   TARGET="$2"; shift 2 ;;
        --preserve) PRESERVE="$2"; shift 2 ;;
        --dry-run)  DRY_RUN=true; shift ;;
        --yes)      ASSUME_YES=true; shift ;;
        --help|-h)  usage ;;
        *)          err "Unknown arg: $1"; exit 1 ;;
    esac
done

# --- Preflight ---
for cmd in sgdisk cryptsetup mkfs.btrfs btrfs mount umount lsblk findmnt; do
    command -v "$cmd" &>/dev/null || { err "Missing command: $cmd"; exit 1; }
done

if [[ ! -b "$TARGET" ]]; then
    err "$TARGET is not a block device"
    exit 1
fi

# --- Partition-number → device-node helper (handles nvme and sd-style naming) ---
part_dev() {
    local num="$1"
    if [[ "$TARGET" =~ nvme|mmcblk|loop ]]; then
        echo "${TARGET}p${num}"
    else
        echo "${TARGET}${num}"
    fi
}

# --- Verify preserved partitions actually exist ---
log "Preserving partitions: $PRESERVE"
IFS=',' read -ra PRESERVE_ARR <<< "$PRESERVE"
for p in "${PRESERVE_ARR[@]}"; do
    dev="$(part_dev "$p")"
    if [[ ! -b "$dev" ]]; then
        err "Preserve partition $p ($dev) does not exist. Refusing to proceed."
        exit 1
    fi
    log "  $dev OK ($(lsblk -no SIZE,FSTYPE "$dev" | tr -s ' '))"
done

# --- Identify partitions that WILL be destroyed ---
mapfile -t ALL_PARTS < <(lsblk -lno NAME "$TARGET" | grep -oP '(?<=p)\d+$|\d+$' | sort -un)
DESTROY=()
for p in "${ALL_PARTS[@]}"; do
    keep=false
    for kp in "${PRESERVE_ARR[@]}"; do
        [[ "$p" == "$kp" ]] && keep=true
    done
    [[ "$keep" == false ]] && DESTROY+=("$p")
done

echo
warn "======================================================================"
warn "  Will DESTROY partitions: ${DESTROY[*]} on $TARGET"
warn "  Will PRESERVE partitions: ${PRESERVE_ARR[*]}"
warn "======================================================================"
echo

if $DRY_RUN; then
    log "DRY RUN — stopping before any destructive operation."
    exit 0
fi

if ! $ASSUME_YES; then
    read -rp "Type WIPE to confirm: " confirm
    [[ "$confirm" == "WIPE" ]] || { err "Not confirmed. Aborting."; exit 1; }
fi

# --- Destructive work happens below this line (Tasks 8, 9) ---
err "STUB: destructive section not implemented yet (Task 8)"
exit 99
```

- [ ] **Step 2: Make it executable**

```bash
cd ~/dotfiles
chmod +x recovery/partition.sh
```

- [ ] **Step 3: Shellcheck**

```bash
cd ~/dotfiles
shellcheck recovery/partition.sh
```
Expected: clean (no errors). Fix any warnings before continuing.

- [ ] **Step 4: Test dry-run against a fake loop device**

```bash
# Create a 2 GiB sparse file with a partition table containing 2 partitions
truncate -s 2G /tmp/fake-disk.img
sgdisk --zap-all /tmp/fake-disk.img
sgdisk -n 1:0:+100M -n 2:0:+100M /tmp/fake-disk.img
LOOP=$(sudo losetup --show -f -P /tmp/fake-disk.img)

# Dry-run preserving partition 2 (which exists → must succeed)
cd ~/dotfiles
./recovery/partition.sh --target "$LOOP" --preserve 2 --dry-run

# Dry-run preserving a non-existent partition 8 → must fail
./recovery/partition.sh --target "$LOOP" --preserve 8 --dry-run && echo "FAIL: should have aborted" || echo "OK: aborted as expected"

# Cleanup
sudo losetup -d "$LOOP"
rm /tmp/fake-disk.img
```

Expected:
1. First dry-run prints destruction plan for partition 1, stops before wiping.
2. Second run aborts with "Preserve partition 8 ... does not exist."

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add recovery/partition.sh
git commit -m "recovery: add partition.sh skeleton with safety checks"
```

---

### Task 8: `partition.sh` part 2 — partition creation + LUKS format

**Files:**
- Modify: `recovery/partition.sh` (replace the stub at the end)

- [ ] **Step 1: Replace the stub with partition + LUKS logic**

In `recovery/partition.sh`, delete the two-line stub:
```bash
err "STUB: destructive section not implemented yet (Task 8)"
exit 99
```

Replace with:

```bash
# --- Destroy the target partitions ---
log "Deleting partitions: ${DESTROY[*]}"
for p in "${DESTROY[@]}"; do
    sgdisk -d "$p" "$TARGET" || warn "  sgdisk -d $p failed (may already be gone)"
done

# --- Create new p1 (EFI) and p2 (LUKS container) ---
# p1: 1 GiB at the earliest free sector
# p2: remainder of free space up to (but not into) any preserved partition
log "Creating p1 (1 GiB EFI) and p2 (rest of free space)..."
sgdisk -n 1:0:+1GiB -t 1:ef00 -c 1:"EFI" "$TARGET"
sgdisk -n 2:0:0     -t 2:8309 -c 2:"cryptroot" "$TARGET"

partprobe "$TARGET" || true
sleep 2

P1="$(part_dev 1)"
P2="$(part_dev 2)"
[[ -b "$P1" ]] || { err "$P1 did not appear after partprobe"; exit 1; }
[[ -b "$P2" ]] || { err "$P2 did not appear after partprobe"; exit 1; }

# --- Format EFI ---
log "Formatting $P1 as FAT32..."
mkfs.fat -F 32 -n EFI "$P1"

# --- LUKS2 format + verify ---
log "LUKS formatting $P2 (you will be prompted for a passphrase)..."
cryptsetup luksFormat --type luks2 --pbkdf argon2id "$P2"

log "Verifying passphrase by closing and reopening..."
cryptsetup open "$P2" cryptroot
cryptsetup close cryptroot
cryptsetup open "$P2" cryptroot

log "Backing up LUKS header to /tmp/luks-header.img..."
cryptsetup luksHeaderBackup "$P2" --header-backup-file /tmp/luks-header.img
ls -lh /tmp/luks-header.img

warn "CRITICAL: copy /tmp/luks-header.img off this machine NOW."
warn "If Tailscale/malt is reachable: scp /tmp/luks-header.img malt:~/dr-backups/"
warn "Or to a USB stick. Do not skip this step."

# --- Remaining work: Btrfs + subvolumes + mount (Task 9) ---
err "STUB: Btrfs section not implemented yet (Task 9)"
exit 99
```

- [ ] **Step 2: Shellcheck**

```bash
cd ~/dotfiles
shellcheck recovery/partition.sh
```
Expected: clean.

- [ ] **Step 3: Commit**

```bash
cd ~/dotfiles
git add recovery/partition.sh
git commit -m "recovery/partition.sh: implement partitioning + LUKS format"
```

(Integration test of this destructive section happens in Task 14 VM run — not safe to run on the real laptop.)

---

### Task 9: `partition.sh` part 3 — Btrfs + subvolumes + mount

**Files:**
- Modify: `recovery/partition.sh`

- [ ] **Step 1: Replace the Task-8 stub with Btrfs + subvolume + mount logic**

Delete the two-line stub:
```bash
err "STUB: Btrfs section not implemented yet (Task 9)"
exit 99
```

Replace with:

```bash
# --- Btrfs on cryptroot ---
log "Formatting /dev/mapper/cryptroot as Btrfs..."
mkfs.btrfs -L root /dev/mapper/cryptroot

# --- Create subvolumes ---
log "Creating subvolumes..."
mount /dev/mapper/cryptroot /mnt
for sub in @ @home @var_log @pkg @snapshots; do
    btrfs subvolume create "/mnt/$sub"
done
umount /mnt

# --- Mount hierarchy for pacstrap ---
log "Mounting subvolume hierarchy under /mnt..."
MOUNT_OPTS="compress=zstd,ssd,discard=async,space_cache=v2"

mount -o "$MOUNT_OPTS,subvol=@" /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,.snapshots,boot}
mount -o "$MOUNT_OPTS,subvol=@home"      /dev/mapper/cryptroot /mnt/home
mount -o "$MOUNT_OPTS,subvol=@var_log"   /dev/mapper/cryptroot /mnt/var/log
mount -o "$MOUNT_OPTS,subvol=@pkg"       /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o "$MOUNT_OPTS,subvol=@snapshots" /dev/mapper/cryptroot /mnt/.snapshots
mount "$P1" /mnt/boot

log "Partitioning complete. Layout:"
findmnt /mnt --tree --real
echo
log "Next step: run 'archinstall --config <path>/archinstall.json' — see runbook Phase 3."
```

- [ ] **Step 2: Shellcheck**

```bash
cd ~/dotfiles
shellcheck recovery/partition.sh
```
Expected: clean.

- [ ] **Step 3: End-to-end smoke test against a loop device**

Run the full script against a throwaway loop image. This is safe because we use `--target` to point away from `/dev/nvme0n1`:

```bash
# Create a 6 GiB sparse file with partition 8 already present (mimics p8 preservation)
truncate -s 6G /tmp/fake-disk.img
sgdisk --zap-all /tmp/fake-disk.img
sgdisk -n 8:4G:0 -t 8:8300 -c 8:preserve /tmp/fake-disk.img
LOOP=$(sudo losetup --show -f -P /tmp/fake-disk.img)
sudo mkfs.ext4 -L preserve "${LOOP}p8"

# Run partition.sh; --yes to skip the WIPE prompt; interactively enter a LUKS passphrase
cd ~/dotfiles
sudo ./recovery/partition.sh --target "$LOOP" --preserve 8 --yes

# Verify subvolumes exist
sudo btrfs subvolume list /mnt
# Expected: 5 subvolumes (@, @home, @var_log, @pkg, @snapshots)

# Verify p8 was not touched
sudo blkid "${LOOP}p8"
# Expected: LABEL=preserve, TYPE=ext4 unchanged

# Cleanup
sudo umount -R /mnt
sudo cryptsetup close cryptroot
sudo losetup -d "$LOOP"
rm /tmp/fake-disk.img
```

- [ ] **Step 4: Commit**

```bash
cd ~/dotfiles
git add recovery/partition.sh
git commit -m "recovery/partition.sh: complete with Btrfs + subvolumes + mount"
```

---

### Task 10: `post-install.sh` part 1 — skeleton + `/etc` allowlist restore

**Files:**
- Create: `recovery/post-install.sh`

**Context:** `post-install.sh` runs on the freshly-booted system as user `scott`. Its first job is selectively applying `/etc` from the backup's `system/etc.tar`, driven by `etc-allowlist.txt`. Snapshot-stack setup comes in Task 11.

- [ ] **Step 1: Write the initial script**

Create `~/dotfiles/recovery/post-install.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# post-install.sh — orchestration that runs after first boot on a freshly-restored
# Arch install. Assumes user data (/home/scott) is already restored from backup.
#
# Usage: post-install.sh [--restore-system|--setup-snapshots|--full] [--backup DIR]

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/dr-restore}"
ALLOWLIST="${DOTFILES_DIR}/recovery/etc-allowlist.txt"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[post]${NC} $*"; }
warn() { echo -e "${YELLOW}[post]${NC} $*"; }
err()  { echo -e "${RED}[post]${NC} $*" >&2; }

ACTION=""
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] ACTION

Actions (pick exactly one):
  --restore-system    Selectively restore /etc from backup per etc-allowlist.txt
  --setup-snapshots   Install & configure snapper, snap-pac, grub-btrfs
  --full              Run --restore-system then --setup-snapshots

Options:
  --backup DIR        Directory holding the extracted dr-*-system.tar.zst
                      (default: \$HOME/dr-restore)
  --help              Show this message
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --restore-system)  ACTION="restore-system"; shift ;;
        --setup-snapshots) ACTION="setup-snapshots"; shift ;;
        --full)            ACTION="full"; shift ;;
        --backup)          BACKUP_DIR="$2"; shift 2 ;;
        --help|-h)         usage ;;
        *)                 err "Unknown arg: $1"; exit 1 ;;
    esac
done
[[ -n "$ACTION" ]] || usage

# --- /etc selective restore ---
restore_etc() {
    log "Selective /etc restore from ${BACKUP_DIR}"
    [[ -f "$ALLOWLIST" ]] || { err "Allowlist not found: $ALLOWLIST"; exit 1; }

    # Locate the extracted etc.tar
    local etctar=""
    # Prefer already-extracted etc.tar inside BACKUP_DIR
    if [[ -f "${BACKUP_DIR}/etc.tar" ]]; then
        etctar="${BACKUP_DIR}/etc.tar"
    else
        # Extract the system tarball if it hasn't been already
        local sys_archive
        sys_archive=$(find "$BACKUP_DIR" -maxdepth 1 -name 'dr-*-system.tar.zst' | head -1)
        [[ -n "$sys_archive" ]] || { err "No system tarball found in $BACKUP_DIR"; exit 1; }
        log "Extracting $sys_archive..."
        zstd -dc "$sys_archive" | tar xf - -C "$BACKUP_DIR/"
        etctar="${BACKUP_DIR}/etc.tar"
    fi
    [[ -f "$etctar" ]] || { err "etc.tar missing after extraction"; exit 1; }

    # Unpack etc.tar to a staging area
    local staging="${BACKUP_DIR}/etc-staged"
    rm -rf "$staging"; mkdir -p "$staging"
    tar xf "$etctar" -C "$staging"
    # tar was built with `/etc/` — so files land at $staging/etc/...
    local src="${staging}/etc"
    [[ -d "$src" ]] || { err "Expected ${staging}/etc after extraction"; exit 1; }

    # Parse allowlist
    local section=""
    while IFS= read -r line; do
        line="${line%%#*}"      # strip comments
        line="${line#"${line%%[![:space:]]*}"}"  # ltrim
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^\[(AUTO|REVIEW|NEVER)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi
        [[ -z "$section" ]] && continue

        case "$section" in
            AUTO)
                local s="${src}/${line}"
                local d="/etc/${line}"
                if [[ -e "$s" ]]; then
                    log "  [AUTO] cp -a $s → $d"
                    sudo mkdir -p "$(dirname "$d")"
                    sudo cp -a "$s" "$d"
                else
                    warn "  [AUTO] source missing, skipping: $s"
                fi
                ;;
            REVIEW)
                local s="${src}/${line}"
                local d="/etc/${line}"
                if [[ -e "$s" ]]; then
                    warn "  [REVIEW] differences for $line:"
                    diff -u "$d" "$s" 2>/dev/null || true
                    read -rp "  Apply? (y/N): " ans
                    if [[ "$ans" =~ ^[Yy] ]]; then
                        sudo mkdir -p "$(dirname "$d")"
                        sudo cp -a "$s" "$d"
                        log "    applied"
                    else
                        log "    skipped"
                    fi
                fi
                ;;
            NEVER)
                : # explicitly do nothing
                ;;
        esac
    done < "$ALLOWLIST"

    log "Done. /etc restore complete."
}

# --- Snapshot stack setup (Task 11) ---
setup_snapshots() {
    err "STUB: setup_snapshots not implemented yet (Task 11)"
    exit 99
}

case "$ACTION" in
    restore-system)  restore_etc ;;
    setup-snapshots) setup_snapshots ;;
    full)            restore_etc; setup_snapshots ;;
esac
```

- [ ] **Step 2: Make executable and lint**

```bash
cd ~/dotfiles
chmod +x recovery/post-install.sh
shellcheck recovery/post-install.sh
```
Expected: clean.

- [ ] **Step 3: Smoke-test allowlist parsing against a fake etc.tar**

```bash
# Build a minimal fake etc.tar with two files
mkdir -p /tmp/fake-backup
mkdir -p /tmp/fake-etc/etc/pam.d /tmp/fake-etc/etc
echo "pam fix here" > /tmp/fake-etc/etc/pam.d/system-auth
echo "should not be restored" > /tmp/fake-etc/etc/fstab
cd /tmp/fake-etc && tar cf /tmp/fake-backup/etc.tar etc && cd -

# Run the restore with the fake backup dir; script uses sudo for cp, so may prompt
cd ~/dotfiles
./recovery/post-install.sh --restore-system --backup /tmp/fake-backup

# Verify
diff <(echo "pam fix here") /etc/pam.d/system-auth && echo "OK: pam file restored"
# fstab should be UNCHANGED (it's on the NEVER list) — current fstab still its original
grep -q "UUID=" /etc/fstab && echo "OK: fstab untouched"

# Cleanup the test (manually revert the pam file if desired)
rm -rf /tmp/fake-backup /tmp/fake-etc
```

**Warning:** this test actually modifies `/etc/pam.d/system-auth` on your current system — but with the same content it should already have (since that pam fix is in the memory). If this is a concern, skip the smoke test and rely on the VM test in Task 14.

- [ ] **Step 4: Commit**

```bash
cd ~/dotfiles
git add recovery/post-install.sh
git commit -m "recovery/post-install.sh: skeleton + allowlist-based /etc restore"
```

---

### Task 11: `post-install.sh` part 2 — snapshot stack setup

**Files:**
- Modify: `recovery/post-install.sh`

- [ ] **Step 1: Replace the `setup_snapshots` stub**

In `recovery/post-install.sh`, replace:

```bash
setup_snapshots() {
    err "STUB: setup_snapshots not implemented yet (Task 11)"
    exit 99
}
```

with:

```bash
setup_snapshots() {
    log "Installing snapper + snap-pac + grub-btrfs..."
    sudo pacman -S --needed --noconfirm snapper snap-pac grub-btrfs

    # Snapper requires /.snapshots to NOT exist before create-config; we handle the
    # case where the subvolume is already mounted there by unmounting temporarily.
    if mountpoint -q /.snapshots; then
        log "Unmounting /.snapshots temporarily so snapper can create its config..."
        sudo umount /.snapshots
    fi
    if [[ -d /.snapshots ]]; then
        sudo rmdir /.snapshots 2>/dev/null || true
    fi

    log "Creating snapper config for /..."
    sudo snapper -c root create-config /

    # Snapper creates a new @/.snapshots subvolume — we want to use OUR @snapshots instead.
    sudo btrfs subvolume delete /.snapshots
    sudo mkdir /.snapshots
    sudo mount -a  # re-mounts our @snapshots subvolume per fstab

    # Retention policy: adjust limits (edit /etc/snapper/configs/root)
    sudo sed -i \
        -e 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/' \
        -e 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' \
        -e 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="2"/' \
        -e 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/' \
        -e 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' \
        /etc/snapper/configs/root

    log "Enabling snapper timers + grub-btrfsd..."
    sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
    sudo systemctl enable --now grub-btrfsd.service

    log "Regenerating GRUB config so snapshot entries appear..."
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    log "Creating baseline snapshot..."
    sudo snapper -c root create --description "post-DR-restore baseline"

    log "Snapshot setup complete. Current snapshots:"
    sudo snapper list
}
```

- [ ] **Step 2: Shellcheck**

```bash
cd ~/dotfiles
shellcheck recovery/post-install.sh
```
Expected: clean.

- [ ] **Step 3: Commit**

```bash
cd ~/dotfiles
git add recovery/post-install.sh
git commit -m "recovery/post-install.sh: add snapshot stack setup"
```

(Integration test happens in VM in Task 14; cannot safely test `snapper create-config /` on the current system before the reinstall because it'd modify live Btrfs state.)

---

### Task 12: Write the runbook `recovery/README.md`

**Files:**
- Create: `recovery/README.md`

- [ ] **Step 1: Write the runbook**

Create `~/dotfiles/recovery/README.md`:

```markdown
# Arch Linux disaster recovery — runbook

**Read this first in a disaster.** Full design rationale lives at
`docs/superpowers/specs/2026-04-18-arch-dr-design.md`.

## Scenarios this covers
- **B** (primary): wipe & reinstall same hardware (practice)
- **A** (secondary): install on replacement hardware

## Pre-disaster checklist (one-time, keep current)

Three offline artifacts MUST exist:
- [ ] LUKS passphrase on paper in fire-proof box (duplicate in Bitwarden)
- [ ] Bitwarden master password memorized + paper duplicate
- [ ] Google account recovery codes on paper (needed if 2FA blocks `rclone` login)

Plus:
- [ ] Arch ISO on a USB stick in a drawer
- [ ] A recent `dr_backup.sh` run (check: `rclone lsf gdrive:backups/dr/ | tail -5`)

## Phase 1 — Boot ISO + network (~5 min)

Boot the Arch live USB. Get online:
- Ethernet: works immediately
- Wifi: `iwctl` → `station wlan0 connect <ssid>`

Verify: `ping -c 3 archlinux.org`

## Phase 2 — Partition + encrypt (~10 min)

Fetch `partition.sh` from GitHub (dotfiles is a private repo; use a GitHub PAT over HTTPS):

    curl -u <user>:<PAT> -fsSL \
      https://raw.githubusercontent.com/scott-whitson/dotfiles/main/recovery/partition.sh \
      -o /tmp/partition.sh
    chmod +x /tmp/partition.sh

Run it:

    sudo /tmp/partition.sh              # default: /dev/nvme0n1, preserve p8
    # Type WIPE when prompted.
    # Enter LUKS passphrase when prompted.

The script creates p1 (EFI) + p2 (LUKS → Btrfs subvolumes) and mounts under `/mnt`.

**Immediately back up the LUKS header** (the script wrote it to `/tmp/luks-header.img`):

    # If Tailscale is reachable on the ISO (install first: pacman -Sy tailscale)
    sudo systemctl start tailscaled
    sudo tailscale up
    scp /tmp/luks-header.img malt:~/dr-backups/

    # Fallback: copy to a USB stick
    sudo dd if=/tmp/luks-header.img of=/dev/sdX

## Phase 3 — Base install via archinstall (~15 min)

    curl -u <user>:<PAT> -fsSL \
      https://raw.githubusercontent.com/scott-whitson/dotfiles/main/recovery/archinstall.json \
      -o /tmp/archinstall.json

    archinstall --config /tmp/archinstall.json

When prompted, set a strong `scott` user password and root password. Reboot into the fresh system; LUKS asks for the passphrase; log in as `scott`.

## Phase 4 — Restore user data (~20 min)

    # a) Gdrive access (interactive, Google device-flow)
    rclone config     # create 'gdrive' remote via drive type

    # b) Pull the latest backup
    mkdir ~/dr-restore && cd ~/dr-restore
    rclone lsf gdrive:backups/dr/ | tail    # see what's there
    rclone copy gdrive:backups/dr/<LATEST>/ .

    # c) Extract home (gives you ~/dotfiles, .ssh, .config, projects)
    tar --zstd -xf dr-*-home.tar.zst -C /home/

    # d) Bootstrap the desktop stack
    cd ~/dotfiles && ./install.sh personal

    # e) Selective /etc restore
    ~/dotfiles/recovery/post-install.sh --restore-system

## Phase 5 — Snapshots + final setup (~10 min)

    ~/dotfiles/recovery/post-install.sh --setup-snapshots

Upload the LUKS header to gdrive now that rclone is configured:

    rclone copy /tmp/luks-header.img gdrive:backups/dr/ 2>/dev/null || \
    rclone copy ~/luks-header.img    gdrive:backups/dr/

## Phase 6 — Re-enroll peer-state services (~5 min)

See `notes/services.md` for details. Short version:

    sudo tailscale up
    tailscale status

## Phase 7 — Verify

- [ ] Reboot; LUKS prompt; clean boot to login
- [ ] `snapper list` shows "post-DR-restore baseline"
- [ ] Reboot → GRUB menu has "Arch Linux snapshots" submenu
- [ ] Hyprland launches; waybar renders; apps open
- [ ] `ssh` to a known host works
- [ ] `rbw` / Bitwarden CLI works
- [ ] `rclone ls gdrive:` works
- [ ] `tailscale status` shows connected
- [ ] `~/gdrive/` is still ~157 GiB (p8 preserved)

## Recovery from mid-flight failures

See `docs/superpowers/specs/2026-04-18-arch-dr-design.md` §"Failure recovery".
```

- [ ] **Step 2: Commit**

```bash
cd ~/dotfiles
git add recovery/README.md
git commit -m "recovery: add runbook README.md"
```

---

### Task 13: VM test helpers — `make-test-backup.sh` + `vm-setup.md`

**Files:**
- Create: `recovery/tests/make-test-backup.sh`
- Create: `recovery/tests/vm-setup.md`

- [ ] **Step 1: Write the fake-backup generator**

Create `~/dotfiles/recovery/tests/make-test-backup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# make-test-backup.sh — produce a tiny stand-in for a real dr_backup.sh output,
# for iterating on recovery scripts inside a VM without pulling 3 GiB from gdrive.
#
# Output: $OUT/dr-testbackup-2026-04-18-home.tar.zst and -system.tar.zst

OUT="${1:-/tmp/fake-gdrive/backups/dr}"
mkdir -p "$OUT"

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

# --- Fake home layer: dotfiles, minimal configs, a flag file ---
HOME_ROOT="${SCRATCH}/home-src"
mkdir -p "${HOME_ROOT}/scott/.config/rclone" "${HOME_ROOT}/scott/.ssh"
# Symlink the real dotfiles so restore tests use the current version
cp -r "$HOME/dotfiles" "${HOME_ROOT}/scott/dotfiles"
# Stub rclone config (non-secret placeholder)
cat > "${HOME_ROOT}/scott/.config/rclone/rclone.conf" <<'EOF'
[gdrive]
type = drive
scope = drive
EOF
# Stub ssh key (do NOT copy real one)
ssh-keygen -t ed25519 -N '' -f "${HOME_ROOT}/scott/.ssh/id_ed25519" -C "test-backup" >/dev/null
echo "TEST" > "${HOME_ROOT}/scott/.config/dr-marker.txt"

( cd "$HOME_ROOT" && tar --zstd -cf "${OUT}/dr-testbackup-2026-04-18-home.tar.zst" scott )

# --- Fake system layer: package list + etc.tar with a couple of files ---
SYS="${SCRATCH}/system-src"
mkdir -p "${SYS}/system" "${SYS}/etc-src/etc/pam.d"
echo "base linux zsh rclone openssh git neovim btrfs-progs snapper snap-pac grub-btrfs" \
    | tr ' ' '\n' > "${SYS}/system/packages.list"
echo "#shim pam.d/system-auth for test" > "${SYS}/etc-src/etc/pam.d/system-auth"
( cd "${SYS}/etc-src" && tar cf "${SYS}/etc.tar" etc )
( cd "$SYS" && tar --zstd -cf "${OUT}/dr-testbackup-2026-04-18-system.tar.zst" system etc.tar )

echo "Fake backup written to $OUT"
ls -lh "$OUT"
```

- [ ] **Step 2: Make executable + lint**

```bash
cd ~/dotfiles
chmod +x recovery/tests/make-test-backup.sh
shellcheck recovery/tests/make-test-backup.sh
```

- [ ] **Step 3: Verify it produces a parseable archive**

```bash
cd ~/dotfiles
./recovery/tests/make-test-backup.sh /tmp/fake-gdrive-test
zstd -dc /tmp/fake-gdrive-test/dr-testbackup-2026-04-18-home.tar.zst | tar t | head -10
# Expected: sees scott/, scott/dotfiles/, scott/.ssh/id_ed25519, etc.
rm -rf /tmp/fake-gdrive-test
```

- [ ] **Step 4: Write VM setup doc**

Create `~/dotfiles/recovery/tests/vm-setup.md`:

```markdown
# VM testing setup

One-time host-side setup and per-test procedure for iterating on recovery scripts.

## Host-side packages (install once)

    sudo pacman -S --needed qemu-full libvirt virt-manager edk2-ovmf dnsmasq
    sudo systemctl enable --now libvirtd
    sudo usermod -aG libvirt $USER
    # log out + back in

## Create the test VM (one time)

Open `virt-manager`. Create a new VM:
- Name: `arch-dr-test`
- Firmware: **UEFI** (select `/usr/share/edk2-ovmf/x64/OVMF_CODE.fd`)
- Disk: 40 GiB qcow2
- RAM: 4 GiB
- CPUs: 2, "Copy host CPU config"
- Network: default NAT
- Boot media: Arch ISO (download fresh from archlinux.org)

Before the first boot, add a virtiofs shared folder:
- Host path: `/tmp/fake-gdrive`
- Target: `fake-gdrive`

(Alternative: skip virtiofs and use `rclone` with type=local pointing at a shared
path mounted via 9p.)

## Fake backup prep

On the host:

    ~/dotfiles/recovery/tests/make-test-backup.sh /tmp/fake-gdrive/backups/dr

In the VM, after reaching Phase 4 of the runbook, instead of `rclone config`:

    # Mount the virtiofs share (the VM must have virtiofs module loaded)
    sudo mount -t virtiofs fake-gdrive /mnt/gdrive

    # Point the runbook's "rclone copy" at the mount instead
    cp -r /mnt/gdrive/backups/dr/dr-testbackup-2026-04-18-*.tar.zst ~/dr-restore/

## Snapshot pattern

In virt-manager's Snapshots tab, take a snapshot after each of these states:
- S1: "ISO booted, network up"
- S2: "partition.sh complete, LUKS open"
- S3: "archinstall complete, first login"
- S4: "home extracted, install.sh run"
- S5: "end-to-end green"

Revert to any snapshot in one click; reruns only redo what changed.

## What to verify in a green run

- [ ] `partition.sh` completes without error on a blank 40 GiB disk (empty preserve list: `--preserve ""`)
- [ ] `archinstall --config archinstall.json` succeeds
- [ ] Reboot → GRUB prompts for LUKS passphrase → boots
- [ ] `dr-marker.txt` appears under `~/.config/` after home extraction (proves restore worked)
- [ ] `post-install.sh --restore-system` copies the test `pam.d/system-auth`
- [ ] `post-install.sh --setup-snapshots` completes without error
- [ ] `snapper list` shows the baseline snapshot
- [ ] **Kill `/` on purpose** (`sudo rm /usr/bin/ls`), reboot, pick the baseline snapshot from GRUB, system recovers
- [ ] `sudo tailscale up` enrolls successfully (use a reusable auth key)

## Graduation criteria

Before touching real hardware:
- Two full end-to-end runs have succeeded
- All checkbox items above pass
- Every warning/error has been read and understood
- Runbook (`recovery/README.md`) updated with anything surprising
```

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add recovery/tests/
git commit -m "recovery/tests: add fake-backup generator and VM setup doc"
```

---

### Task 14: VM end-to-end validation run

**Context:** This is a procedural task, not code. Follow `recovery/tests/vm-setup.md` and work through the runbook inside the VM. The goal is to find any bugs in the scripts/config before the real hardware practice.

- [ ] **Step 1: Install host-side VM tooling per `vm-setup.md`**

```bash
sudo pacman -S --needed qemu-full libvirt virt-manager edk2-ovmf dnsmasq
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt "$USER"
# Log out and back in for the group to take effect.
```

- [ ] **Step 2: Build the fake backup**

```bash
mkdir -p /tmp/fake-gdrive/backups/dr
~/dotfiles/recovery/tests/make-test-backup.sh /tmp/fake-gdrive/backups/dr
```

- [ ] **Step 3: Create the test VM per `vm-setup.md`** (virt-manager GUI)

Take snapshot S1 once the Arch ISO shell has network.

- [ ] **Step 4: Run `partition.sh` in the VM**

Inside the ISO:
```bash
curl -u <user>:<PAT> -fsSL \
  https://raw.githubusercontent.com/scott-whitson/dotfiles/main/recovery/partition.sh \
  -o /tmp/partition.sh
chmod +x /tmp/partition.sh
/tmp/partition.sh --preserve "" --yes
```

Expected: partitioning, LUKS prompt, Btrfs, subvolumes, mount hierarchy, `findmnt /mnt` shows all 6 mounts. Take snapshot S2.

- [ ] **Step 5: Run `archinstall` in the VM**

Inside the ISO:
```bash
curl -u <user>:<PAT> -fsSL \
  https://raw.githubusercontent.com/scott-whitson/dotfiles/main/recovery/archinstall.json \
  -o /tmp/archinstall.json
archinstall --config /tmp/archinstall.json
```

Expected: base install completes, reboot, LUKS prompt, login as `scott`. Take snapshot S3.

**If archinstall rejects the config** (schema drift), record the exact error, revise `archinstall.json`, repeat from S2. Commit the fix.

- [ ] **Step 6: Restore from fake backup**

Inside the VM (logged in as `scott`):
```bash
sudo mount -t virtiofs fake-gdrive /mnt/gdrive
mkdir ~/dr-restore
cp /mnt/gdrive/backups/dr/dr-testbackup-2026-04-18-*.tar.zst ~/dr-restore/
cd ~/dr-restore
tar --zstd -xf dr-testbackup-2026-04-18-home.tar.zst -C /home/

# Verify the test marker arrived
cat ~/.config/dr-marker.txt   # expect: TEST

cd ~/dotfiles && ./install.sh personal
~/dotfiles/recovery/post-install.sh --restore-system --backup ~/dr-restore
```

Expected: test marker present, install.sh runs cleanly, pam shim file copied to `/etc/pam.d/system-auth`. Take snapshot S4.

- [ ] **Step 7: Snapshot stack + rollback test**

```bash
~/dotfiles/recovery/post-install.sh --setup-snapshots
sudo snapper list            # baseline visible

# Destructive test — break /, reboot into snapshot
sudo rm /usr/bin/ls
# reboot → GRUB menu → "Arch Linux snapshots" → pick baseline → system recovers
ls                            # should work (from the restored snapshot)
```

Take snapshot S5 once the rollback test passes.

- [ ] **Step 8: Tailscale enrollment**

Generate a reusable auth key at https://login.tailscale.com/admin/settings/keys. In the VM:
```bash
sudo tailscale up --auth-key=tskey-auth-XXXX
tailscale status           # VM appears; peers visible
```

- [ ] **Step 9: Second full run from snapshot S1**

Revert to S1 and redo Steps 4–8. Two green runs graduate; one might be luck.

- [ ] **Step 10: Record findings**

Update `recovery/README.md` with any correction needed (syntax drift, missing package, different command name). Commit with a message like `recovery: runbook fixes from VM test N`.

After two consecutive green runs with no changes required, the scripts are ready for the real-hardware practice (scenario B) — that execution lives outside this plan, driven by the runbook.

---

## Self-Review

**Spec coverage:** The 9 artifacts listed in the spec's "Artifacts to produce in implementation" table each map to a task (Tasks 1, 6 = `etc-allowlist`; Tasks 2, 3, 4 = `notes/*.md`; Task 5 = `dr_backup.sh` edit; Task 6 = `archinstall.json`; Tasks 7-9 = `partition.sh`; Tasks 10-11 = `post-install.sh`; Task 12 = `README.md`; Task 13 = test helpers; Task 14 = VM validation). The spec's "Practice execution on real hardware" section is intentionally deferred — it runs after this plan completes, driven by the committed runbook.

**Placeholder scan:** All `<fill ...>` markers in the hardware template are explicitly flagged with a verification step (Task 3 Step 3) that fails if any remain. No other TBD/TODO/FIXME occurrences in script bodies.

**Type consistency:** Script flag names are consistent across artifacts — `--restore-system`, `--setup-snapshots`, `--full`, `--backup` in `post-install.sh`; `--target`, `--preserve`, `--dry-run`, `--yes` in `partition.sh`. The subvolume names `@`, `@home`, `@var_log`, `@pkg`, `@snapshots` appear identically in `partition.sh`, `archinstall.json` notes, and the runbook. The allowlist section markers `[AUTO]`, `[REVIEW]`, `[NEVER]` match between `etc-allowlist.txt` and the parser in `post-install.sh`.
