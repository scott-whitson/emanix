{ config, lib, ... }:

{
  # Gated on scott.gui. The ibgateway branch imported this unconditionally,
  # which put a browser on the headless server and on WSL. programs.firefox
  # installs the package itself, so packages.nix must NOT also list `firefox` —
  # doing both gave rafik two identical firefox entries in home.packages.
  config = lib.mkIf config.scott.gui {
    # Firefox, dark via the ui.systemUsesDarkTheme pref below. Deliberately
    # NOT Catppuccin-themed: catppuccin/nix's firefox port works by installing
    # the FirefoxColor extension, which is more than is wanted here. A
    # `catppuccin.firefox` block did sit here, but it gated on
    # `config.catppuccin.enable` — never set, so always false — and had
    # therefore never applied. Removed 2026-08-09 along with the catppuccin
    # flake input, which nothing else used. The dark theme is unaffected; it
    # was never what that block did.
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
  };
}
