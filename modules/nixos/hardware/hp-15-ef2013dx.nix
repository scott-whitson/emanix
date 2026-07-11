{ config, lib, pkgs, ... }:

{
  # HP 15-ef2013dx hardware configuration.
  # Ryzen 5 5500U, AMD Radeon Graphics, 32 GB, 1 TB NVMe.
  #
  # LUKS + btrfs layout:
  #   nvme0n1p1  → /boot       (unencrypted vfat)
  #   nvme0n1p2  → cryptroot   (LUKS → btrfs with subvolumes)
  #   nvme0n1p3  → cryptswap   (LUKS → swap)
  #
  # Subvolumes inside cryptroot:
  #   @      → /                (compress=zstd)
  #   @nix   → /nix             (compress=zstd, noatime)
  #   @home  → /home            (compress=zstd)

  # Kernel
  boot.kernelParams = [ "quiet" ];

  # AMD GPU — RADV (Mesa) is the default Vulkan driver.
  # hardware.graphics.enable is set by ewm.nix (required for EWM).

  # Firmware
  hardware.enableRedistributableFirmware = true;

  # Wireless (RTL8821CE) — uses kernel's built-in rtw88 driver.

  # Audio
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Bluetooth
  hardware.bluetooth.enable = true;

  # Touchpad
  services.libinput = {
    enable = true;
    touchpad = {
      naturalScrolling = true;
      disableWhileTyping = true;
    };
  };

  # Power management
  powerManagement.enable = true;
  services.power-profiles-daemon.enable = true;

  # Bootloader
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # LUKS — single passphrase for root, one for swap
  boot.initrd.luks.devices = {
    "cryptroot" = { device = "/dev/nvme0n1p2"; };
    "cryptswap" = { device = "/dev/nvme0n1p3"; };
  };

  # File systems — btrfs subvolumes on LUKS
  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd" ];
  };

  fileSystems."/nix" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@nix" "compress=zstd" "noatime" ];
  };

  fileSystems."/home" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@home" "compress=zstd" ];
  };

  fileSystems."/boot" = {
    device = "/dev/nvme0n1p1";
    fsType = "vfat";
  };

  # Swap on its own LUKS volume
  swapDevices = [{ device = "/dev/mapper/cryptswap"; }];
}