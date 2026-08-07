{ config, lib, pkgs, ... }:

let
  cfg = config.scott.ibgateway;
in
{
  # IB Gateway + IBC as a NixOS system service (imported via profiles/eminix.nix,
  # like ewm.nix/secrets.nix/ollama.nix — NOT via i-intelligence/default.nix,
  # which aggregates Home Manager modules only).
  #
  # IB Gateway itself stays an imperative payload in /opt/ibgateway so IBKR's
  # forced auto-updates keep working. Everything around it is declarative.
  options.scott.ibgateway = {
    enable = lib.mkEnableOption "IB Gateway with IBC automation";

    tradingMode = lib.mkOption {
      type = lib.types.enum [ "live" "paper" ];
      default = "live";
      description = "IBC TradingMode.";
    };

    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 4001;
      description = "TWS API port the gateway listens on (IBC OverrideTwsApiPort).";
    };

    display = lib.mkOption {
      type = lib.types.str;
      default = ":50";
      description = "X display for the headless gateway.";
    };

    vncPort = lib.mkOption {
      type = lib.types.port;
      default = 5901;
      description = "Xvnc RFB port. Bound to localhost only.";
    };

    twsPath = lib.mkOption {
      type = lib.types.path;
      default = "/opt/ibgateway/jts";
      description = ''
        IB Gateway install + settings dir. Imperative payload, not Nix-managed:
        IBKR's auto-updater rewrites it.
      '';
    };

    twsMajorVersion = lib.mkOption {
      type = lib.types.str;
      default = "1046";
      description = ''
        IB Gateway major version, no dot (10.46 -> 1046). Must match the
        directory under twsPath/ibgateway/. A forced IBKR upgrade needs this bumped.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # uid/gid pinned to what is already on disk so the existing /opt/ibgateway
    # files keep valid ownership across the switch — no recursive chown needed.
    users.groups.ibgateway.gid = 991;

    users.users.ibgateway = {
      isSystemUser = true;
      uid = 993;
      group = "ibgateway";
      home = "/var/lib/ibgateway";
      createHome = true;
      description = "IB Gateway service account";
    };

    # scott needs group membership to read gateway logs.
    users.users.scott.extraGroups = [ "ibgateway" ];

    # THE BUG FIX. IBC's first act is writing jts.ini into twsPath; when the
    # service ran as scott against an ibgateway-owned 0755 dir it died at 1ms
    # with exit 1109. These rules guarantee the service user can write there.
    systemd.tmpfiles.rules = [
      "d /opt/ibgateway          0755 ibgateway ibgateway -"
      "d ${cfg.twsPath}          0755 ibgateway ibgateway -"
      "d /var/lib/ibgateway      0750 ibgateway ibgateway -"
      "d /var/lib/ibgateway/ibc  0750 ibgateway ibgateway -"
      "d /var/lib/ibgateway/ibc/logs 0750 ibgateway ibgateway -"
    ];
  };
}
