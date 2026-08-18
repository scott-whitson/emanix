{ config, lib, pkgs, ... }:

{
  # A graphical eminix box: EWM compositor, local models, system syncthing.
  imports = [
    ../../ioshi/os-system/desktop.nix
    ../../ioshi/i-intelligence/ewm.nix
    ../../ioshi/i-intelligence/ollama.nix
  ];

  # The role is the single source of truth for these, which previously
  # encoded the same fact by hand in several places.
  # mkDefault throughout: a role is the STARTING SHAPE for a host, not a
  # constraint on it. A consumer overriding one of these in extraModules is
  # making an informed choice (a GUI-capable WSL box, a server that does run
  # pi); a bare definition would meet them with "conflicting definition
  # values" and force mkForce. Invariants belong in assertions, not in
  # definitions a consumer cannot outrank.
  home-manager.users.${config.eminix.username} = {
    eminix.gui = lib.mkDefault true;
    eminix.ewm.enable = lib.mkDefault true;
  };
}
