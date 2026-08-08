{ ... }:

{
  # A graphical eminix box: EWM compositor, local models, system syncthing.
  imports = [
    ../../ioshi/os-system/desktop.nix
    ../../ioshi/i-intelligence/ewm.nix
    ../../ioshi/i-intelligence/ollama.nix
    ../../ioshi/hi-hardware/net/syncthing.nix
    # IB Gateway. Option-gated (scott.ibgateway.enable, default false) and
    # enabled only on rafik, which is the only machine that uses `ib`. Lives in
    # the workstation role rather than the common core so the layout says that;
    # if a server ever needs it, move this line to profiles/eminix.nix.
    ../../ioshi/i-intelligence/ibgateway.nix
  ];

  # The role is the single source of truth for these three, which previously
  # encoded the same fact by hand in three places.
  home-manager.users.scott = {
    scott.gui = true;
    scott.ewm.enable = true;
  };
}
