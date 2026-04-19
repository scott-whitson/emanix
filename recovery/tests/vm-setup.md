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
