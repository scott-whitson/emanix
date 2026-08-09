{ config, lib, pkgs, ... }:

let
  # Map our theme variant to catppuccin flavor.
  flavorForTheme = theme:
    if builtins.match ".*latte.*" theme != null then "latte"
    else if builtins.match ".*frappe.*" theme != null then "frappe"
    else if builtins.match ".*macchiato.*" theme != null then "macchiato"
    else "mocha"; # default / catppuccin-mocha
in
{
  # Gated on scott.gui. The ibgateway branch imported this unconditionally,
  # which put a browser on the headless server and on WSL. programs.firefox
  # installs the package itself, so packages.nix must NOT also list `firefox` —
  # doing both gave rafik two identical firefox entries in home.packages.
  config = lib.mkIf config.scott.gui {
    # Firefox with Catppuccin Mocha theme — matches Emacs and Ghostty.
    programs.firefox = {
      enable = true;

      # Pinned to the legacy path rather than left to the stateVersion-dependent
      # default, which warns on every eval. The live profile already lives at
      # ~/.mozilla/firefox/default — moving to the XDG path would strand it.
      configPath = ".mozilla/firefox";

      profiles.default = {
        id = 0;
        isDefault = true;

        settings = {
          # Dark theme by default
          "ui.systemUsesDarkTheme" = 1;
          "browser.tabs.firefoxview.enableCache" = true;

          # Respect wayland
          "widget.use-xdg-desktop-portal.file-picker" = 1;
          "widget.use-xdg-desktop-portal.mime-handler" = 1;

          # Smooth scrolling
          "general.smoothScroll" = true;

          # Disable annoying features
          "browser.newtabpage.activity-stream.showSponsored" = false;
          "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
          "browser.newtabpage.activity-stream.default.sites" = "";
        };
      };
    };

    # catppuccin.autoEnable = false lives in home/scott/default.nix, ungated —
    # it was here, inside mkIf scott.gui, so whistle and datacore never set it
    # and warned on every rebuild. This is the per-port opt-in it enables.
    catppuccin.firefox = {
      enable = true;
      flavor = flavorForTheme config.scott.theme;
      accent = "mauve"; # matches Emacs catppuccin-theme default
    };
  };
}
