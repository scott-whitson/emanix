{ config, lib, pkgs, ... }:

{
  # Shared NixOS desktop module (Phase 2).
  # Home Manager is imported from flake.nix via home-manager.nixosModules.

  # System packages (docker CLI comes from virtualisation.docker.enable)
  environment.systemPackages = with pkgs; [
    docker-compose
  ];

  # Enable unfree (Steam, Nvidia, etc.)
  nixpkgs.config.allowUnfree = true;

  # bitwarden-desktop rides an EOL electron that nixpkgs flags insecure.
  # Version-pinned: when bitwarden bumps electron this goes stale and the
  # build error names the new version to put here (or delete the line).
  nixpkgs.config.permittedInsecurePackages = [
    "electron-39.8.10"
  ];

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