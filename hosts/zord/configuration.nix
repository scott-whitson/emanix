{ config, lib, pkgs, inputs, ... }:

{
  networking.hostName = "zord";

  imports = [
    ../../modules/nixos/hardware/thinkpad-t14-gen5-amd.nix
    ../../modules/nixos/ewm.nix
    ../../modules/nixos/desktop.nix
    ./disko.nix
  ];

  programs.zsh.enable = true;

  users.users.scott = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" "video" ];
    shell = pkgs.zsh;
  };

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
