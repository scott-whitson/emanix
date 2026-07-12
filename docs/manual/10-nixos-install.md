# NixOS Install Guide — zord-old (HP 15-ef2013dx)

This guide covers replacing Debian with NixOS on the HP 15-ef2013dx
as a dry run before the ThinkPad T14 arrives.

**Applies to the T14 too** — same layout, just different hardware
config and hostname.

## Prerequisites

- Ventoy USB with NixOS minimal ISO (already set up)
- Dotfiles repo cloned and flake verified (`nix flake check`)
- Network access (the NixOS live env has networking)

## Partition Layout (LUKS + btrfs)

| Partition | Size | Encrypted | Mount | Format | Notes |
|-----------|------|-----------|-------|--------|-------|
| `nvme0n1p1` | 1 GB | no | `/boot` | vfat | EFI, must be unencrypted |
| `nvme0n1p2` | rest minus swap | **LUKS** | `/` | btrfs | Root + nix + home (subvolumes) |
| `nvme0n1p3` | 32 GB | **LUKS** | swap | swap | Encrypted swap |

### Subvolume layout

Inside the LUKS container:

| Subvolume | Mount | Notes |
|-----------|-------|-------|
| `@` | `/` | Root filesystem |
| `@nix` | `/nix` | Nix store — compression saves big here |
| `@home` | `/home` | User data |

`/home` is a subvolume, not a separate partition. You can snapshot it
before any risky operation and roll back if needed. On a full reinstall,
you mount the LUKS volume and reuse the `@home` subvolume directly.

> **Why btrfs?** It's the NixOS community standard. `zstd` compression
> on `/nix/store` saves 30-50% disk space (all those compressed JS
> bundles and duplicate text files). Subvolumes give you snapshot-based
> rollbacks that pair naturally with NixOS generations.

## Step-by-Step

### 1. Boot from Ventoy

1. Plug in the Ventoy USB
2. Reboot and enter the boot menu (typically **F9** on HP)
3. Select the Ventoy USB
4. Choose `nixos-unstable-minimal-x86_64.iso`
5. Wait for the live environment to load

### 2. Verify networking

```bash
ip a
ping -c 3 nixos.org
```

The live ISO uses DHCP by default. If you need Wi-Fi:

```bash
iwctl
# device list
# station wlan0 scan
# station wlan0 connect "your-ssid"
# exit
```

### 3. Partition

```bash
# WARNING: This wipes the entire drive. Verify you're on the right disk.
lsblk
# Confirm nvme0n1 is your internal drive

# Wipe the existing partition table
sudo parted /dev/nvme0n1 -- mklabel gpt

# Create EFI partition (1 GB)
sudo parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 1025MiB
sudo parted /dev/nvme0n1 -- set 1 esp on

# Create root partition (rest minus 32 GB for swap)
sudo parted /dev/nvme0n1 -- mkpart primary 1025MiB 931GiB

# Create swap partition (32 GB)
sudo parted /dev/nvme0n1 -- mkpart primary linux-swap 931GiB 100%

# Verify
sudo parted /dev/nvme0n1 -- print
```

### 4. Set up LUKS encryption

```bash
# Load the dm-crypt kernel module
sudo modprobe dm-crypt

# Encrypt root (single LUKS container for everything)
sudo cryptsetup luksFormat /dev/nvme0n1p2
# You'll be prompted for a passphrase

# Encrypt swap
sudo cryptsetup luksFormat /dev/nvme0n1p3
# Same passphrase is fine

# Open the volumes
sudo cryptsetup open /dev/nvme0n1p2 cryptroot
sudo cryptsetup open /dev/nvme0n1p3 cryptswap
```

### 5. Format

```bash
# EFI
sudo mkfs.vfat -F 32 /dev/nvme0n1p1

# Root — btrfs on the LUKS device
sudo mkfs.btrfs -L nixos /dev/mapper/cryptroot

# Swap
sudo mkswap -L swap /dev/mapper/cryptswap
```

### 6. Create subvolumes and mount

```bash
# Mount root temporarily to create subvolumes
sudo mount /dev/mapper/cryptroot /mnt
sudo btrfs subvolume create /mnt/@
sudo btrfs subvolume create /mnt/@nix
sudo btrfs subvolume create /mnt/@home
sudo umount /mnt

# Mount subvolumes in the right order
sudo mount -o subvol=@,compress=zstd /dev/mapper/cryptroot /mnt
sudo mkdir -p /mnt/{nix,home,boot}
sudo mount -o subvol=@nix,compress=zstd,noatime /dev/mapper/cryptroot /mnt/nix
sudo mount -o subvol=@home,compress=zstd /dev/mapper/cryptroot /mnt/home
sudo mount /dev/nvme0n1p1 /mnt/boot

# Enable swap
sudo swapon /dev/mapper/cryptswap
```

### 7. Get the dotfiles

```bash
# Enter a shell with git
sudo nix-shell -p git

# Clone the dotfiles repo
git clone https://github.com/your-org/dotfiles /mnt/etc/dotfiles

# If using SSH, copy your key from the Ventoy data partition first
# (Ventoy data partition is usually auto-mounted at /run/media)
```

### 8. Generate hardware config

```bash
sudo nixos-generate-config --root /mnt
```

This creates `/mnt/etc/nixos/hardware-configuration.nix`. Read it
to verify it detected:

- `boot.initrd.luks.devices."cryptroot"` — device `/dev/nvme0n1p2`
- `boot.initrd.luks.devices."cryptswap"` — device `/dev/nvme0n1p3`
- `fileSystems."/"` — device `/dev/mapper/cryptroot`, subvol `@`
- `fileSystems."/nix"` — device `/dev/mapper/cryptroot`, subvol `@nix`
- `fileSystems."/home"` — device `/dev/mapper/cryptroot`, subvol `@home`
- `fileSystems."/boot"` — device `/dev/nvme0n1p1`
- `swapDevices` — device `/dev/mapper/cryptswap`

If the generated config is correct, copy it over the manual one:

```bash
sudo cp /mnt/etc/nixos/hardware-configuration.nix \
       /mnt/etc/dotfiles/modules/nixos/hardware/hp-15-ef2013dx.nix
```

If you prefer the manual one, it already has the correct LUKS + btrfs
setup and you can skip this step.

### 9. Install

```bash
cd /mnt/etc/dotfiles
git add -A

sudo nixos-install --flake /mnt/etc/dotfiles#zord-old --root /mnt
```

This will:

- Build the full system from the flake
- Compile Emacs with all packages + EWM embedded
- Set up home-manager for user `scott`
- Configure systemd-boot + LUKS initrd unlocking
- Prompt for a **root password**

### 10. Set your user password

```bash
sudo nixos-enter
passwd scott
# Enter your password
exit
```

### 11. Reboot

```bash
sudo umount -R /mnt
sudo cryptsetup close cryptswap
sudo cryptsetup close cryptroot
sudo swapoff /dev/mapper/cryptswap
reboot
```

### 12. First boot

1. Remove the Ventoy USB
2. The system boots — you'll see a LUKS prompt for your passphrase
3. NixOS loads into systemd-boot, then the display manager
4. Select "ewm" at the login screen
5. Emacs + EWM starts — verify:

```bash
# Inside Emacs:
# C-s             → consult-line
# C-c q           → quarter tracker
# s-d             → consult-buffer (app launcher)
# s-d, ghostty   → terminal
# In Ghostty: pi → Pi agent with images
```

### 13. Post-install

- Run `sudo nix-collect-garbage` periodically to trim the store
- btrfs compression is already on (`compress=zstd` on all subvolumes)

### 14. Verify compression savings

```bash
sudo compsize /nix/store
# You should see ~30-50% compression ratio
```

## Recovery

### Reinstall NixOS (keeping /home)

Since `/home` is a btrfs subvolume on the same LUKS volume as root:

1. Boot the NixOS ISO
2. Open the LUKS volume: `sudo cryptsetup open /dev/nvme0n1p2 cryptroot`
3. Mount and delete the old `@` and `@nix` subvolumes, keep `@home`
4. Create fresh `@` and `@nix` subvolumes
5. Mount and reinstall

Or, easier: snapshot `@home` before wiping, restore after install.

### Broken bootloader

```bash
# From live ISO:
sudo cryptsetup open /dev/nvme0n1p2 cryptroot
sudo cryptsetup open /dev/nvme0n1p3 cryptswap
sudo mount -o subvol=@,compress=zstd /dev/mapper/cryptroot /mnt
sudo mount -o subvol=@nix,compress=zstd,noatime /dev/mapper/cryptroot /mnt/nix
sudo mount -o subvol=@home,compress=zstd /dev/mapper/cryptroot /mnt/home
sudo mount /dev/nvme0n1p1 /mnt/boot
sudo nixos-enter
nixos-rebuild boot
exit
reboot
```

### Broken initrd (can't unlock)

```bash
# From live ISO — open and mount as above
sudo nixos-enter
nixos-rebuild boot
exit
reboot
```

## T14 Migration Notes

When the ThinkPad T14 arrives:

1. Create `modules/nixos/hardware/thinkpad-t14-gen5-amd.nix`
   (same LUKS + btrfs layout, different kernel modules)
2. Install following this same guide, substituting:
   - Hostname: `zord` instead of `zord-old`
   - Flake: `--flake /path#zord` instead of `#zord-old`
   - Hardware: T14 hardware config instead of HP
3. Both machines share `home/scott/default.nix` — identical user
   environments
