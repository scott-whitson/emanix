{ config, lib, pkgs, ... }:

let
  themeLib = import ../../lib/themes.nix { inherit pkgs; };
  palettes = themeLib.palettes;
  ghostty = themeLib.ghostty;
  activePalette = palettes.${config.scott.theme} or palettes.catppuccin-mocha;
in
{
  options.scott.ghostty.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.scott.gui;
    defaultText = "config.scott.gui";
    description = "Install ghostty + its managed config. Defaults to the gui flag; whistle (gui=false) sets it true — WSLg renders it like any Wayland app.";
  };

  config = lib.mkIf config.scott.ghostty.enable {
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

          # --- Keybindings (Emacs-style) ---
          keybind = clear
          keybind = super+c=copy_to_clipboard
          keybind = super+v=paste_from_clipboard
          keybind = alt+w=copy_to_clipboard
          keybind = ctrl+y=paste_from_clipboard
        '';
      };
    };

    # Seed theme.conf only when absent, so a fresh machine has a theme before
    # the first dot-theme-set run. `-e` is false for a dangling symlink, which
    # is the case worth re-seeding, so this is the right test.
    home.activation.seedGhosttyTheme =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        target="$HOME/.config/ghostty/theme.conf"
        if [ ! -e "$target" ]; then
          run ln -sfn "$HOME/.config/ghostty/themes/${config.scott.theme}.conf" "$target"
        fi
      '';
  };
}
