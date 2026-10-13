{ config, lib, pkgs, ... }:

let
  # This host's Emacs is not the system-owned EWM build (ewm.nix); instead we
  # install the non-EWM pgtk Emacs user-side and run it as a systemd user
  # daemon (services.emacs below). Same package set as the emanix system
  # build, minus the EWM package — non-EWM machines have no compositor role.
  emacsPkgs = import ../emacs/packages.nix { inherit pkgs; };
  # extraPackages is a function of the package set (see emanix.nix's option):
  # pass it straight through so a consumer's packages reach this build too.
  standaloneEmacs = emacsPkgs.mkEmacs {
    extraPackages = config.emanix.emacs.extraPackages;
  };
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
    # and here for the non-EWM daemon hosts. Search is non-functional until
    # the node serves Ollama embeddings, but loading arc must not error, and
    # arc signals at database-open time if this points nowhere.
    #
    # Twice, because the two reach different processes. sessionVariables
    # reaches interactive shells. The daemon is a systemd user unit whose
    # ExecStart is `bash -l -c', which sources no HM session file (there is no
    # ~/.profile), so with sessionVariables alone the daemon ran with
    # `arc-sqlite-vec-path' nil and arc could never open its database. On the
    # unit itself rather than in environment.d: environment.d is read when the
    # user manager starts, so a switch would not reach a restarted daemon
    # until the next login, while the unit's Environment does.
    home.sessionVariables.ARC_VEC0_PATH = emacsPkgs.arcVecPath;
    systemd.user.services.emacs.Service.Environment =
      [ "ARC_VEC0_PATH=${emacsPkgs.arcVecPath}" ];
  };
}
