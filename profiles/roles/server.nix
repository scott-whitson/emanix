{ ... }:

{
  # A headless eminix box.
  imports = [
    ../../ioshi/os-system/server.nix
    ../../ioshi/hi-hardware/net/syncthing.nix
  ];

  home-manager.users.scott = {
    scott.gui = false;
    scott.ewm.enable = false;
    scott.dotfiles.profile = "server";
  };
}
