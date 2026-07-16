{ config, lib, pkgs, ... }:

{
  # Shared NixOS server module (Phase 2).
  imports = [
    ../../ioshi/i-intelligence
  ];

  # Headless server
  systemd.targets.multi-user.enable = true;

  # Docker
  virtualisation.docker.enable = true;

  # Network
  networking.networkmanager.enable = true;

  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}