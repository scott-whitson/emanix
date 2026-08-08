{ nixos-wsl, ... }:

{
  # An eminix instance inside WSL. No hardware layer — nixos-wsl supplies
  # boot and mounts, WSLg supplies the display.
  imports = [ nixos-wsl.nixosModules.default ];

  home-manager.users.scott = {
    scott.gui = false;
    scott.ewm.enable = false;
    # gui = false, but a real terminal under WSLg is still wanted, and ssh
    # sessions from other hosts land in zellij. Both opt in surgically.
    scott.ghostty.enable = true;
    scott.zellij.enable = true;
    scott.dotfiles.profile = "wsl";
  };
}
