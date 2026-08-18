{ config, lib, ... }:

{
  # A headless eminix box.
  imports = [
    ../../ioshi/os-system/server.nix
  ];

  # mkDefault throughout: a role is the STARTING SHAPE for a host, not a
  # constraint on it. A consumer overriding one of these in extraModules is
  # making an informed choice (a GUI-capable WSL box, a server that does run
  # pi); a bare definition would meet them with "conflicting definition
  # values" and force mkForce. Invariants belong in assertions, not in
  # definitions a consumer cannot outrank.
  home-manager.users.${config.eminix.username} = {
    eminix.gui = lib.mkDefault false;
    eminix.pi.enable = lib.mkDefault false;
  };
}
