{ config, lib, pkgs, ... }:

{
  # A headless eminix box.
  imports = [
    ../../ioshi/os-system/server.nix
  ];

  home-manager.users.${config.eminix.username} = {
    eminix.gui = false;
    eminix.ewm.enable = false;
    eminix.pi.enable = false;
  };
}
