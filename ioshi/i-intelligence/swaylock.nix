{ config, lib, pkgs, ... }:

let
  themeLib = import ../../lib/themes.nix { inherit pkgs; };
  palettes = themeLib.palettes;
  activePalette = palettes.${config.eminix.theme} or palettes.catppuccin-mocha;
in
{
  config = lib.mkIf config.eminix.gui {
    # Config only — the swaylock package and its PAM entry are host-level
    # (modules/nixos/ewm.nix): unlocking auths through PAM, and a swaylock
    # installed without security.pam.services.swaylock can never unlock.
    home.file.".config/swaylock/config" = {
      text = ''
        # -----------------------------------------------
        # Swaylock Configuration — managed by Home Manager
        # -----------------------------------------------
        daemonize
        ${themeLib.swaylock activePalette}
      '';
    };
  };
}
