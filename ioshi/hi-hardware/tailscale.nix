{ config, lib, ... }:

{
  options.eminix.tailscale = {
    # Opt-in, like every other module here with a network or credential
    # dependency (pi, claude, ollama). It defaulted TRUE until 2026-08-18,
    # which meant a fresh eminix host — a server with no tailnet included —
    # came up running a mesh VPN and, because authKeyFile was hardcoded to a
    # path nothing creates, with a failing tailscaled-autoconnect unit.
    enable = lib.mkEnableOption "Tailscale mesh VPN";

    loginServer = lib.mkOption {
      type = lib.types.str;
      default = "https://controlplane.tailscale.com";
      description = "Coordination server URL. Set to a self-hosted headscale URL when used.";
    };

    authKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/var/lib/tailscale-authkey";
      description = ''
        Pre-authentication key file for unattended enrolment. Null (the
        default) means none: tailscaled starts and waits for an interactive
        `tailscale up`, which is the right behaviour for a host being brought
        up by hand.

        This was hardcoded to /var/lib/tailscale-authkey, so every host got a
        tailscaled-autoconnect unit that failed until someone happened to
        create that file. Point it at a real key — ideally an agenix path —
        only on hosts that genuinely enrol unattended.
      '';
    };
  };

  config = lib.mkIf config.eminix.tailscale.enable {
    services.tailscale = {
      enable = true;
      extraUpFlags = [ "--login-server=${config.eminix.tailscale.loginServer}" ];
    } // lib.optionalAttrs (config.eminix.tailscale.authKeyFile != null) {
      authKeyFile = config.eminix.tailscale.authKeyFile;
    };
    services.resolved.enable = true;

    # extraUpFlags above is ONLY read by tailscaled-autoconnect
    # (services/networking/tailscale.nix), which nixpkgs defines exclusively
    # when authKeyFile != null — most hosts here have no authKeyFile, so
    # nothing in the built system ever runs `tailscale up` with
    # --login-server on their behalf. eminix-firstboot still needs this
    # value for its own manual `tailscale up --login-server=...`, and the
    # alternative (re-evaluating the flake at runtime, or hardcoding this
    # URL a second time in the script) is worse than a one-line file. This
    # is the single source of truth the script reads; nothing else consumes
    # it, so it costs one file in the closure, not a duplicated literal.
    environment.etc."eminix/tailscale-login-server".text =
      config.eminix.tailscale.loginServer;
  };
}
