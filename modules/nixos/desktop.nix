{ config, lib, pkgs, ... }:

{
  # Shared NixOS desktop module (Phase 2).
  # Home Manager is imported from flake.nix via home-manager.nixosModules.

  # System packages
  environment.systemPackages = with pkgs; [
    docker
    docker-compose
  ];

  # Enable unfree (Steam, Nvidia, etc.)
  nixpkgs.config.allowUnfree = true;

  # Steam
  programs.steam.enable = true;


  # Docker
  virtualisation.docker.enable = true;

  # Network
  networking.networkmanager.enable = true;

  # Printing
  services.printing.enable = true;

  # Bluetooth
  hardware.bluetooth.enable = true;

  # Audio
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}