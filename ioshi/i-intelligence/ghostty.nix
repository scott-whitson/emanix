{ config, lib, pkgs, ... }:

let
  themeLib = import ../../lib/themes.nix { inherit pkgs; };
  palettes = themeLib.palettes;
  ghostty = themeLib.ghostty;
  activePalette = palettes.${config.scott.theme} or palettes.catppuccin-mocha;
in
{
  home.file.".config/ghostty/config" = {
    text = ''
      # -----------------------------------------------
      # Ghostty Configuration — managed by Home Manager
      # -----------------------------------------------

      # --- Theme (swapped by theme-switch script) ---
      config-file = theme.conf

      # --- Font ---
      font-family = JetBrainsMono Nerd Font
      font-size = 12

      # --- Cursor ---
      cursor-style = bar
      cursor-style-blink = false

      # --- Window ---
      window-padding-x = 6
      window-padding-y = 6
      window-decoration = false
      confirm-close-surface = false

      working-directory = home
      window-inherit-working-directory = false
      tab-inherit-working-directory = false

      # --- Scrollback ---
      scrollback-limit = 10000

      # --- Clipboard ---
      copy-on-select = clipboard
    '';
  };

  home.file.".config/ghostty/theme.conf" = {
    text = ghostty activePalette;
  };

  # Pre-generate all theme variants so the runtime switcher can flip symlinks.
  home.file.".config/ghostty/themes/catppuccin-mocha.conf" = {
    text = ghostty palettes.catppuccin-mocha;
  };

  home.file.".config/ghostty/themes/catppuccin-latte.conf" = {
    text = ghostty palettes.catppuccin-latte;
  };
}