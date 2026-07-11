{ config, lib, pkgs, inputs, ... }:

{
  # zord — ThinkPad T14 Gen 5 AMD (future daily driver)
  # This config will be filled in when the T14 arrives.
  # Until then, the HP 15-ef2013dx runs as "zord-old" (see hosts/zord-old/).
  #
  # Home Manager is imported from flake.nix via home-manager.nixosModules.

  networking.hostName = "zord";

  imports = [
    # TODO: ../../modules/nixos/hardware/thinkpad-t14-gen5-amd.nix
    ../../modules/nixos/ewm.nix
    ../../modules/nixos/desktop.nix
  ];

  programs.zsh.enable = true;

  users.users.scott = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" "video" ];
    shell = pkgs.zsh;
  };

  # Placeholder file systems — the T14 hardware config (when written)
  # will use the same LUKS + btrfs subvolume layout as zord-old.
  fileSystems."/" = { device = "/dev/mapper/cryptroot"; fsType = "btrfs"; };
  fileSystems."/boot" = { device = "/dev/nvme0n1p1"; fsType = "vfat"; };

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  system.stateVersion = "24.11";
}