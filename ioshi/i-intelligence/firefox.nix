{ config, lib, pkgs, ... }:

let
  themeLib = import ../../lib/themes.nix { inherit pkgs; };
  inherit (themeLib) palettes;
  # Resolved once, from config.eminix.theme, at rebuild time — NOT what
  # `dot-theme-set` changes. Unlike ghostty (which pre-renders all four
  # palettes so the runtime switcher can pick one), Firefox renders exactly
  # this one palette and the switcher never touches it. Running
  # `dot-theme-set` does not change Firefox at all, on restart or ever;
  # only editing eminix.theme and rebuilding does. See docs/manual/02-theming.md.
  activePalette = palettes.${config.eminix.theme} or palettes.catppuccin-mocha;
in
{
  # Gated on eminix.gui. The ibgateway branch imported this unconditionally,
  # which put a browser on the headless server and on WSL. programs.firefox
  # installs the package itself, so packages.nix must NOT also list `firefox` —
  # doing both gives two identical firefox entries in home.packages.
  config = lib.mkIf config.eminix.gui {
    # Firefox, following the active palette's variant via the
    # ui.systemUsesDarkTheme pref below. Deliberately NOT Catppuccin-themed:
    # catppuccin/nix's firefox port works by installing
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

        # Chrome only, by design: catppuccin's firefox port themed the browser
        # UI by installing the FirefoxColor extension, and page content is
        # left exactly as authored. To force the palette onto page content
        # too, set browser.display.document_color_use = 2 here — see spec
        # decision 3 for why that is not the default.
        userChrome = themeLib.firefoxChrome activePalette;

        settings = {
          # Follows the active palette's variant, not hardcoded: under either
          # light palette the chrome CSS above renders light, and if this
          # pref stayed pinned to 1, Firefox's own UI theme and every
          # prefers-color-scheme page would stay dark underneath it — an
          # actively incoherent result, not just a missed opportunity.
          "ui.systemUsesDarkTheme" = if activePalette.variant == "dark" then 1 else 0;
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

          # Without this Firefox ignores userChrome.css entirely.
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        };
      };
    };
  };
}
