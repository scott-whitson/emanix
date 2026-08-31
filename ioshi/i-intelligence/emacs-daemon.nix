{ config, lib, pkgs, ... }:

let
  # This host's Emacs is not the system-owned EWM build (ewm.nix); instead we
  # install the non-EWM pgtk Emacs user-side and run it as a systemd user
  # daemon (services.emacs below). Same package set as the emanix system
  # build, minus the EWM package — non-EWM machines have no compositor role.
  emacsPkgs = import ./emacs/packages.nix { inherit pkgs; };
  standaloneEmacs = emacsPkgs.mkEmacs { };
in
{
  # Declared HERE rather than in ewm.nix, which is where the name points. This
  # module is the option's only reader: ewm.nix is a NixOS module and cannot
  # declare a Home Manager option, and it does not consult this one anyway —
  # whether the system-owned EWM Emacs gets built is decided by the workstation
  # role's imports. The two tiers are nonetheless TIED, and nothing here needs
  # hand-maintaining: ewm.nix sets this option itself, as a hard definition
  # rather than mkDefault (447c467, "the import IS the switch"). Importing
  # ewm.nix therefore builds the system Emacs and disables the user daemon
  # below in one act. That is what stops a host from building two full
  # emacs-pgtk derivations and starting the very daemon ewm.nix pkills to
  # avoid — which is exactly what happened while the flag lived by hand in
  # the consumer's host config, next to the import it had to agree with.
  options.emanix.ewm.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      This machine's Emacs is the system-owned EWM build (ewm.nix). When false,
      the home layer installs the non-EWM pgtk Emacs and runs the daemon as a
      systemd user service (this module).
    '';
  };

  config = lib.mkIf (!config.emanix.ewm.enable) {
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

    # arc's sqlite-vec extension path — set by ewm.nix on emanix workstations,
    # and here for the non-EWM daemon hosts. Answering is non-functional until
    # the node has an Ollama (deferred per the spec), but loading arc must not
    # error, and arc signals at database-open time if this points nowhere.
    home.sessionVariables.ARC_VEC0_PATH = emacsPkgs.arcVecPath;
  };
}
