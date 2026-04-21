#!/usr/bin/env bash
set -euo pipefail

# manual-install.sh — pacstrap-based base install, used when archinstall cannot
# accept our pre-mounted layout (archinstall 4.x has rejected "Pre-mounted
# configuration" with our archinstall.json as of 2026-04-20; manual is the
# documented fallback).
#
# Runs from the Arch ISO AFTER partition.sh has mounted the hierarchy at /mnt.
#
# Env overrides (all optional):
#   TARGET_HOSTNAME  (default: arch)
#   TARGET_USERNAME  (default: scott)
#   TARGET_TIMEZONE  (default: America/New_York)
#   LUKS_DEV         (default: auto-detect the first LUKS partition)

TARGET_HOSTNAME="${TARGET_HOSTNAME:-arch}"
TARGET_USERNAME="${TARGET_USERNAME:-scott}"
TARGET_TIMEZONE="${TARGET_TIMEZONE:-America/New_York}"
LUKS_DEV="${LUKS_DEV:-$(lsblk -lnp -o NAME,FSTYPE | awk '$2=="crypto_LUKS"{print $1; exit}')}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[install]${NC} $*"; }
warn() { echo -e "${YELLOW}[install]${NC} $*"; }
err()  { echo -e "${RED}[install]${NC} $*" >&2; }

# --- Sanity checks ---
mountpoint -q /mnt       || { err "/mnt is not mounted — run partition.sh first"; exit 1; }
mountpoint -q /mnt/boot  || { err "/mnt/boot is not mounted"; exit 1; }
[[ -b /dev/mapper/cryptroot ]] || { err "/dev/mapper/cryptroot not open"; exit 1; }
[[ -n "$LUKS_DEV" ]]     || { err "Could not auto-detect LUKS device; set LUKS_DEV=..."; exit 1; }

log "Target: host=$TARGET_HOSTNAME user=$TARGET_USERNAME tz=$TARGET_TIMEZONE luks=$LUKS_DEV"

log "Installing base system via pacstrap (may take ~5 min)..."
pacstrap -K /mnt \
    base base-devel linux linux-firmware \
    btrfs-progs grub efibootmgr cryptsetup \
    networkmanager openssh sudo zsh git rclone neovim \
    amd-ucode intel-ucode

log "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

log "Configuring system inside chroot..."
LUKS_UUID=$(blkid -s UUID -o value "$LUKS_DEV")
export LUKS_UUID TARGET_HOSTNAME TARGET_USERNAME TARGET_TIMEZONE

arch-chroot /mnt /bin/bash <<CHROOT
set -euo pipefail

ln -sf /usr/share/zoneinfo/${TARGET_TIMEZONE} /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "${TARGET_HOSTNAME}" > /etc/hostname

# mkinitcpio with encrypt hook (required for LUKS boot)
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# GRUB with cryptodisk
if grep -q '^#GRUB_ENABLE_CRYPTODISK' /etc/default/grub; then
    sed -i 's/^#GRUB_ENABLE_CRYPTODISK.*/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
elif ! grep -q '^GRUB_ENABLE_CRYPTODISK' /etc/default/grub; then
    echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub
fi
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=${LUKS_UUID}:cryptroot root=/dev/mapper/cryptroot\"|" /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager sshd

useradd -m -G wheel -s /bin/zsh ${TARGET_USERNAME}
echo "${TARGET_USERNAME}:test123" | chpasswd
echo "root:test123" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
CHROOT

log "Install complete."
warn "Default user password is 'test123' — change with 'passwd' after first login."
warn "Default root password is 'test123' — change with 'sudo passwd root'."
log "Reboot to enter the new system. LUKS prompt appears at boot."
