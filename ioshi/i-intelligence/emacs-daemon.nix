{ config, lib, pkgs, ... }:

let
  # This host's Emacs is not the system-owned EWM build (ewm.nix); instead we
  # install the non-EWM pgtk Emacs user-side and run it as a systemd user
  # daemon (services.emacs below). Same package set as the eminix system
  # build, minus the EWM package — non-EWM machines have no compositor role.
  emacsPkgs = import ./emacs/packages.nix { inherit pkgs; };
  standaloneEmacs = emacsPkgs.mkEmacs { };
in
{
  # Declared HERE rather than in ewm.nix, which is where the name points. This
  # module is the option's only reader: ewm.nix is a NixOS module and cannot
  # declare a Home Manager option, and it does not consult this one anyway —
  # whether the system-owned EWM Emacs gets built is decided by the workstation
  # role's imports. So the switch genuinely lives at two tiers: role imports
  # decide the system Emacs, this option decides the user daemon, and nothing
  # ties them together. Keep them agreeing; a host with both builds two full
  # emacs-pgtk derivations and starts the very daemon ewm.nix pkills to avoid.
  options.eminix.ewm.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      This machine's Emacs is the system-owned EWM build (ewm.nix). When false,
      the home layer installs the non-EWM pgtk Emacs and runs the daemon as a
      systemd user service (this module).
    '';
  };

  config = lib.mkIf (!config.eminix.ewm.enable) {
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
    home.sessionVariables.ELISA_VEC0_PATH = emacsPkgs.elisaVecPath;
  };
}
