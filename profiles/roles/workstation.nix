{ config, lib, pkgs, ... }:

{
  # A graphical eminix box: EWM compositor, local models, system syncthing.
  imports = [
    ../../ioshi/os-system/desktop.nix
    ../../ioshi/i-intelligence/ewm.nix
    ../../ioshi/i-intelligence/ollama.nix
  ];

  # The role is the single source of truth for these three, which previously
  # encoded the same fact by hand in three places.
  home-manager.users.${config.eminix.username} = {
    eminix.gui = true;
    eminix.ewm.enable = true;
  };
}
