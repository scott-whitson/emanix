{ config, lib, pkgs, ... }:

{
  networking.hostName = "zord";

  imports = [
    ../../modules/nixos/hardware/thinkpad-t14-gen5-amd.nix
    ../../modules/nixos/ewm.nix
    ../../ioshi/os-system/base.nix
    ../../ioshi/os-system/desktop.nix
    # Single source of truth for the disk layout. Also referenced by
    # flake.nix's diskoConfigurations.zord, so `disko` (partitioning) and the
    # built system agree by construction.
    ./disko.nix
  ];
}
