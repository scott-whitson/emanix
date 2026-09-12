{ config, lib, pkgs, ... }:

let
  themeLib = import ../../lib/themes.nix { inherit pkgs; };
  inherit (themeLib) palettes ghostty;
in
{
  options.emanix.ghostty.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.emanix.gui;
    defaultText = "config.emanix.gui";
    description = "Install ghostty + its managed config. Defaults to the gui flag; non-GUI hosts (WSLg) set it true.";
  };

  config = lib.mkIf config.emanix.ghostty.enable {
    # Every palette is pre-rendered here; the runtime switcher picks one.
    # theme.conf is deliberately NOT declared as home.file: bin/dot-theme-set
    # owns that path, and two owners means Home Manager renames the runtime
    # symlink to theme.conf.hm-bak at every activation — silently reverting
    # the active theme on the next rebuild.
    home.file = lib.mapAttrs'
      (name: palette: lib.nameValuePair
        ".config/ghostty/themes/${name}.conf"
        { text = ghostty palette; })
      palettes
    // {
      ".config/ghostty/config" = {
        text = ''
          # -----------------------------------------------
          # Ghostty Configuration — managed by Home Manager
          # -----------------------------------------------

          # --- Theme (swapped by theme-switch script) ---
          config-file = theme.conf

          # --- Font ---
          font-family = JetBrains Mono
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

          # --- Keybindings (Emacs-style) ---
          keybind = clear
          keybind = super+c=copy_to_clipboard
          keybind = super+v=paste_from_clipboard
          keybind = alt+w=copy_to_clipboard
          keybind = ctrl+y=paste_from_clipboard
        '';
      };
    };

    # NO seeding hook. `emanix/theme-init' converges the whole machine on the
    # first Emacs start when ~/.config/dotfiles/active-theme is absent, which
    # is a fresh install -- and it seeds btop, zellij, swaylock, gtk and the
    # consumer's registrations too, not only this one symlink. Removed
    # 2026-09-11 with the theme-authority inversion.
  };
}
