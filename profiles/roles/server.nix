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
    # Holds ~/.pi/agent as a Syncthing peer but does not run pi. datacore IS
    # an openrouter-auth.age recipient regardless — profiles/eminix.nix and
    # ioshi/os-system/server.nix both import i-intelligence/secrets.nix, so
    # every host of this role decrypts that secret at every activation, full
    # stop. This flag only gates whether ~/.pi/agent/auth.json gets symlinked
    # to it (see ioshi/i-intelligence/pi.nix) — false here means no symlink,
    # not "no recipient".
    scott.pi.enable = false;
  };
}
