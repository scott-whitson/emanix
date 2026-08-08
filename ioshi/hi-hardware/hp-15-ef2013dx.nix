{ config, lib, pkgs, ... }:

{
  # HP 15-ef2013dx hardware configuration — datacore's box.
  # Ryzen 5 5500U, AMD Radeon Graphics, 32 GB, 1 TB NVMe.
  #
  # Unencrypted, GPT partlabels (see ioshi/hi-hardware/disko/datacore.nix):
  #   disk-main-boot  → /boot (vfat)
  #   disk-main-root  → /, /nix, /home (shared partition)
  #   disk-main-swap  → swap
  #
  # No LUKS — this machine has no disk encryption.

  # Kernel
  boot.kernelParams = [ "quiet" ];

  # Load amdgpu in the initrd so the GPU is fully initialized before
  # userspace starts — EWM launches from tty1 autologin at boot and loses
  # the DRM-master race against late GPU bring-up otherwise.
  boot.initrd.kernelModules = [ "amdgpu" ];

  # AMD GPU — RADV (Mesa) is the default Vulkan driver.
  # hardware.graphics.enable is set by ewm.nix (required for EWM).

  # Firmware
  hardware.enableRedistributableFirmware = true;

  # Wireless (RTL8821CE) — uses kernel's built-in rtw88 driver.

  # Audio, Bluetooth, touchpad, and the bootloader live in desktop.nix.

  # Power management
  powerManagement.enable = true;
  services.power-profiles-daemon.enable = true;

  # No LUKS on this machine.
  boot.initrd.luks.devices = { };

  # File systems — btrfs subvolumes on the root partition, by GPT partlabel.
  # NOTE: disko/datacore.nix also declares device/fsType/options for these
  # same mountpoints. options is list-typed, so the two concatenate instead
  # of overriding — evaluated "/" options duplicate subvol=@ and
  # compress=zstd. Inert (dup mount options are idempotent); predates the
  # mkForce removal, which discarded rather than merged and masked it.
  # Hazard: an edit on one side won't override the other, it appends — they
  # can silently diverge. Dedup is deliberate future work: it'd change the
  # fstab and move the closure.
  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/disk-main-root";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd" ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-partlabel/disk-main-root";
    fsType = "btrfs";
    options = [ "subvol=@nix" "compress=zstd" "noatime" ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-partlabel/disk-main-root";
    fsType = "btrfs";
    options = [ "subvol=@home" "compress=zstd" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/disk-main-boot";
    fsType = "vfat";
  };

  # Swap — disko/datacore.nix's swap partition already contributes the
  # single swapDevices entry; no need to redeclare it here.
}
