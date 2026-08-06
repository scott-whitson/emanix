{ config, lib, pkgs, ... }:

{
  # Shared NixOS server module (Phase 2).
  # NOT the whole i-intelligence dir: that default.nix is the Home Manager
  # aggregate (pi.nix/emacs.nix use `home.*`, an HM-only option) — importing
  # it at system level throws "definitions for `home', which is an option
  # that does not exist" (caught by Task 3's build gate). secrets.nix is the
  # one file in there that IS a system module (agenix), same selective
  # pattern profiles/eminix.nix already uses for its i-intelligence picks.
  imports = [
    ../../ioshi/i-intelligence/secrets.nix
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
