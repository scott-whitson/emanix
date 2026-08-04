{ config, lib, pkgs, ... }:

let
  # Same package set as the eminix system build (ewm.nix), minus the EWM
  # package — non-EWM machines (foreign-distro nodes AND whistle/NixOS-WSL)
  # have no compositor role.
  emacsPkgs = import ./emacs/packages.nix { inherit pkgs; };
  standaloneEmacs =
    ((pkgs.emacsPackagesFor pkgs.emacs-pgtk).overrideScope emacsPkgs.orgOverride)
      .emacsWithPackages emacsPkgs.list;
in
{
  config = lib.mkIf (!config.scott.ewm.enable) {
    # On EWM machines the Emacs build is system-owned (ewm.nix). Non-EWM
    # machines install it user-side and run the daemon as a systemd user
    # service.
    programs.emacs = {
      enable = true;
      package = standaloneEmacs;
    };

    services.emacs = {
      enable = true;
      client.enable = true;
      startWithUserSession = true;
    };

    # elisa's sqlite-vec extension path — set by ewm.nix on eminix. Chat is
    # non-functional until the node has an Ollama (deferred per the spec),
    # but requiring elisa must not error.
    home.sessionVariables.ELISA_VEC0_PATH = "${pkgs.sqlite-vec}/lib/vec0.so";
  };
}
