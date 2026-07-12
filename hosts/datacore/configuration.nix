{ config, lib, pkgs, ... }:

{
  # Datacore NixOS configuration (Phase 2 — headless server).
  networking.hostName = "datacore";

  imports = [
    ../../modules/nixos/server.nix
  ];

  # Zsh for interactive use
  programs.zsh.enable = true;

  # User
  users.users.scott = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    shell = pkgs.zsh;
  };

  # Locale
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # Nix settings
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