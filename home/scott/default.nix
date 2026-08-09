{ config, lib, pkgs, ... }:

{
  # Shared Home Manager config for every eminix instance.
  # Imported from the NixOS host configs via home-manager.users.scott.

  imports = [
    ../../ioshi/i-intelligence
  ];

  home.username = "scott";
  home.homeDirectory = "/home/scott";

  # Theme
  scott.theme = "catppuccin-mocha";

  # No catppuccin/nix module here on purpose. The flake input and its
  # homeModules import were removed 2026-08-09: the only consumer was
  # firefox.nix's `catppuccin.firefox` block, which gated on
  # `config.catppuccin.enable` — never set anywhere, so always false — and
  # had therefore never applied. Catppuccin colours still reach everything
  # that actually shows them, from sources that do not need the input:
  # lib/themes.nix carries the palettes by hand (ghostty, swaylock),
  # pkgs.catppuccin-cursors and the catppuccin-theme Emacs package come
  # from nixpkgs, and Firefox is dark via a plain pref.

  # Cursor theme — without one, Wayland/GTK apps warn (Gdk: unable to load
  # sb_v_double_arrow...) and some cursor shapes go missing under EWM.
  home.pointerCursor = lib.mkIf config.scott.gui {
    enable = true;
    package = pkgs.catppuccin-cursors.mochaDark;
    name = "catppuccin-mocha-dark-cursors"; # must match the dir in share/icons
    size = 24;
    gtk.enable = true;
  };

  # Dotfiles config
  scott.dotfiles = {
    path = "${config.home.homeDirectory}/dotfiles";
  };

  home.stateVersion = "24.11";
}
