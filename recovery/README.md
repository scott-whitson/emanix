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

## Phase 3 — Base install (~15 min)

**Verified path — `manual-install.sh`:**

    curl -u <user>:<PAT> -fsSL \
      https://raw.githubusercontent.com/scott-whitson/dotfiles/main/recovery/manual-install.sh \
      -o /tmp/manual-install.sh
    chmod +x /tmp/manual-install.sh
    /tmp/manual-install.sh

It runs `pacstrap`, generates `fstab`, chroots in to set timezone/locale/hostname, installs GRUB with cryptodisk, enables NetworkManager + sshd, and creates user `scott` (default password `test123` — **change with `passwd` after first login**).

Override via env vars if needed:

    TARGET_HOSTNAME=myhost TARGET_TIMEZONE=America/Denver /tmp/manual-install.sh

Reboot into the fresh system; LUKS prompts for the passphrase; log in as `scott`.

**Alternative — `archinstall`:**

    curl -u <user>:<PAT> -fsSL \
      https://raw.githubusercontent.com/scott-whitson/dotfiles/main/recovery/archinstall.json \
      -o /tmp/archinstall.json
    archinstall --config /tmp/archinstall.json

Tested against archinstall 4.1 (2026-04-20) — the pre-mounted disk configuration failed with "Root partition not found". `archinstall.json` is retained for future re-testing as archinstall evolves, but `manual-install.sh` is the path that works today.

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
