{ ... }:

{
  # A graphical eminix box: EWM compositor, local models, system syncthing.
  imports = [
    ../../ioshi/os-system/desktop.nix
    ../../ioshi/os-system/firstboot.nix
    ../../ioshi/i-intelligence/ewm.nix
    ../../ioshi/i-intelligence/ollama.nix
    ../../ioshi/hi-hardware/net/syncthing.nix
  ];

  # The role is the single source of truth for these three, which previously
  # encoded the same fact by hand in three places.
  home-manager.users.scott = {
    scott.gui = true;
    scott.ewm.enable = true;
    scott.dotfiles.profile = "desktop";
  };
}
