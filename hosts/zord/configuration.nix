{ config, lib, pkgs, ... }:

{
  networking.hostName = "zord";

  imports = [
    ../../ioshi/hi-hardware/lenovo-t14-gen5-amd.nix
    ../../ioshi/i-intelligence/ewm.nix
    ../../ioshi/os-system/base.nix
    ../../ioshi/os-system/desktop.nix
    # Single source of truth for the disk layout. Also referenced by
    # flake.nix's diskoConfigurations, so `disko` (partitioning) and the
    # built system agree by construction.
    ../../ioshi/hi-hardware/disko/eminix.nix
  ];
}
