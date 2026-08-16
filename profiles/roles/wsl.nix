{ config, lib, nixos-wsl, pkgs, ... }:

{
  # An eminix instance inside WSL. No hardware layer — nixos-wsl supplies
  # boot and mounts, WSLg supplies the display.
  imports = [ nixos-wsl.nixosModules.default ];

  home-manager.users.${config.eminix.username} = {
    eminix.gui = false;
    eminix.ewm.enable = false;
    eminix.ghostty.enable = true;
    eminix.zellij.enable = true;
  };
}
