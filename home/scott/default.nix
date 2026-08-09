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

  # Pin catppuccin/nix's opt-in model before upstream changes the default.
  #
  # Setting `autoEnable` explicitly at all is what silences the module's
  # eval warning: the warning lives behind `mkIf enable`, and `enable` is
  # computed as `if (release >= 27.05 || autoEnableWasSet) then
  # catppuccin.enable else true`. Until now nothing set it outside
  # firefox.nix's `mkIf scott.gui`, so whistle and datacore warned on every
  # rebuild. Keep this UNGATED, and do not also define it in firefox.nix —
  # a second definition at the same priority is an eval conflict, not a merge.
  #
  # `enable = false` is deliberate and is NOT what upstream's warning text
  # suggests. It suggests `enable = true`, but that is not behaviour-
  # preserving here: catppuccin's firefox port gates on
  # `config.catppuccin.enable && profile.enable`, and since `enable` has
  # always defaulted to false, `catppuccin.firefox.enable = true` in
  # ioshi/i-intelligence/firefox.nix has never actually done anything.
  # Flipping it on makes the port write
  # `programs.firefox.profiles.default.extensions.settings."FirefoxColor@mozilla.com"`,
  # which trips Home Manager's assertion that setting `extensions.settings`
  # overrides all previous extension settings unless `extensions.force` (or
  # the per-extension `force`) acknowledges it — rafik fails to build.
  #
  # So: false pins the status quo (firefox theming off, as it has been in
  # practice) and survives upstream's flip unchanged. To actually turn the
  # theming on, set enable = true AND acknowledge the extensions assertion;
  # that is a visible browser change, not a warning fix.
  catppuccin = {
    enable = false;
    autoEnable = false;
  };

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
