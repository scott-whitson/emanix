{ config, lib, pkgs, ... }:

{
  # Shared Home Manager config — used by both zord-old (HP) and zord (T14).
  # Imported from the NixOS host configs via home-manager.users.scott.

  imports = [
    ../../modules/home-manager
  ];

  home.username = "scott";
  home.homeDirectory = "/home/scott";

  # Theme
  scott.theme = "catppuccin-mocha";

  # Dotfiles config
  scott.dotfiles = {
    path = "${config.home.homeDirectory}/dotfiles";
    enableSync = false;
    profile = "desktop";
  };

  home.stateVersion = "24.11";
}