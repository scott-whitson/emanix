{ config, lib, pkgs, ... }:

{
  # Shared Home Manager config — used by both zord-old (HP) and zord (T14).
  # Imported from the NixOS host configs via home-manager.users.scott.

  imports = [
    ../../ioshi/i-intelligence
  ];

  home.username = "scott";
  home.homeDirectory = "/home/scott";

  # Theme
  scott.theme = "catppuccin-mocha";

  # Cursor theme — without one, Wayland/GTK apps warn (Gdk: unable to load
  # sb_v_double_arrow...) and some cursor shapes go missing under EWM.
  home.pointerCursor = {
    package = pkgs.catppuccin-cursors.mochaDark;
    name = "catppuccin-mocha-dark-cursors"; # must match the dir in share/icons
    size = 24;
    gtk.enable = true;
  };

  # Dotfiles config
  scott.dotfiles = {
    path = "${config.home.homeDirectory}/dotfiles";
    enableSync = false;
    profile = "desktop";
  };

  home.stateVersion = "24.11";
}