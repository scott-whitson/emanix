{ ... }:

{
  # A headless eminix box.
  imports = [
    ../../ioshi/os-system/server.nix
    # Deliberately NOT net/syncthing.nix: that module is the workstation-side
    # peer config (declares datacore as a remote device, overrideDevices /
    # overrideFolders = true). A server-role host that IS the fleet's
    # syncthing hub (datacore) would import it and declare itself its own
    # peer, forcing its real config to a bogus self-referential set on
    # activation. Hub hosts declare services.syncthing directly instead.
  ];

  home-manager.users.scott = {
    scott.gui = false;
    scott.ewm.enable = false;
    scott.dotfiles.profile = "server";
  };
}
