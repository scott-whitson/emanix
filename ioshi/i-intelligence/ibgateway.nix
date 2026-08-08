{ config, lib, pkgs, ... }:

let
  cfg = config.scott.ibgateway;

  ibc = pkgs.callPackage ./ibgateway/ibc.nix { };

  # Zulu (the old choice) has no JavaFX, and IBC's login dialog is a JavaFX
  # WebView. Pristine ibcstart.sh already passes --add-exports for javafx.web,
  # so it assumes a JavaFX-bearing JDK — this override supplies exactly that.
  # It is a distinct derivation from plain openjdk17 and is in cache.nixos.org.
  #
  # The old /tmp/javafx-sdk + JAVA_TOOL_OPTIONS workaround could never work:
  # ibcstart.sh:480 clears JAVA_TOOL_OPTIONS unconditionally.
  jdk = pkgs.openjdk17.override { enableJavaFX = true; };

  # Non-secret IBC settings. Credentials are appended at runtime from agenix,
  # so nothing here reaches the world-readable Nix store.
  ibcSettings = pkgs.writeText "ibc-settings.ini" ''
    TradingMode=${cfg.tradingMode}
    IbDir=${cfg.twsPath}
    OverrideTwsApiPort=${toString cfg.apiPort}
    AcceptIncomingConnectionAction=accept
    AcceptNonBrokerageAccountWarning=yes
    ExistingSessionDetectedAction=primary
    ReloginAfterSecondFactorAuthenticationTimeout=no
    BypassOrderPrecautions=yes
    SecondFactorAuthenticationTimeout=180
    CommandServerPort=7462
    ControlFrom=127.0.0.1
  '';

  runtimeIni = "/run/ibgateway/ibc-config.ini";

  # Stands in for IBC's gatewaystart.sh, whose variable block upstream hardcodes
  # and marks as the user-editable part. displaybannerandlaunch.sh and
  # ibcstart.sh ship pristine; this only supplies the env they read.
  launcher = pkgs.writeShellApplication {
    name = "ibgateway-launcher";
    runtimeInputs = [ pkgs.coreutils pkgs.procps pkgs.gnugrep pkgs.gawk ];
    text = ''
      export IBC_PATH=${ibc}
      export IBC_INI=${runtimeIni}
      export TWS_PATH=${cfg.twsPath}
      export TWS_SETTINGS_PATH=${cfg.twsPath}
      export TWS_MAJOR_VRSN=${cfg.twsMajorVersion}
      export LOG_PATH=/var/lib/ibgateway/ibc/logs
      export JAVA_PATH=${jdk}/bin
      export TRADING_MODE=${cfg.tradingMode}
      export TWOFA_TIMEOUT_ACTION=exit
      export APP=GATEWAY
      # Credentials come from the ini, not these. displaybannerandlaunch.sh
      # dereferences them unconditionally, so they must exist.
      export TWSUSERID=""
      export TWSPASSWORD=""
      export FIXUSERID=""
      export FIXPASSWORD=""
      exec ${ibc}/scripts/displaybannerandlaunch.sh
    '';
  };

  # Fails fast with a named cause instead of a bare exit 1109.
  preflight = pkgs.writeShellScript "ibgateway-preflight" ''
    set -euo pipefail
    creds=${config.age.secrets.ibkr-creds.path}

    if [[ ! -s "$creds" ]]; then
      echo "ibgateway: credentials $creds missing or empty" >&2
      exit 1
    fi
    if [[ ! -d "${cfg.twsPath}/ibgateway/${cfg.twsMajorVersion}/jars" ]]; then
      echo "ibgateway: no jars at ${cfg.twsPath}/ibgateway/${cfg.twsMajorVersion}/jars —" \
           "IB Gateway may have auto-updated; bump scott.ibgateway.twsMajorVersion" >&2
      exit 1
    fi
    if [[ ! -w "${cfg.twsPath}" ]]; then
      echo "ibgateway: ${cfg.twsPath} not writable by $(id -un) —" \
           "this is the condition that produced the silent exit 1109" >&2
      exit 1
    fi

    umask 077
    cat ${ibcSettings} "$creds" > ${runtimeIni}
    chmod 0400 ${runtimeIni}
  '';

  ibCli = pkgs.writeShellApplication {
    name = "ib";
    runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
    text = ''
      # ib — IB Gateway control. The gateway is a SYSTEM unit (runs as the
      # ibgateway user); a polkit rule lets scott manage it without a password.
      # Minne remains user units.
      action="''${1:-status}"
      mode="''${2:-${cfg.tradingMode}}"

      gateway_ready() {
        timeout 1 bash -c ">/dev/tcp/127.0.0.1/${toString cfg.apiPort}" 2>/dev/null
      }

      case "$action" in
        up)
          if [[ "$mode" != "${cfg.tradingMode}" ]]; then
            echo "ERROR: this gateway is built for ${cfg.tradingMode} (scott.ibgateway.tradingMode)." >&2
            echo "Requested mode '$mode' does not match. Switching modes is not" >&2
            echo "runtime-selectable — set scott.ibgateway.tradingMode and rebuild." >&2
            exit 1
          fi

          echo "Starting IB Gateway ($mode)..."
          if ! systemctl start ibgateway.service; then
            echo "ERROR: failed to start ibgateway.service. Recent log:" >&2
            journalctl -u ibgateway.service -n 30 --no-pager >&2
            exit 1
          fi

          for _ in $(seq 1 120); do
            if gateway_ready; then
              echo "IB Gateway ready on port ${toString cfg.apiPort}"
              systemctl --user start minne-ibkr-gateway minne-ibkr-record
              echo "Minne IBKR services started"
              exit 0
            fi
            if ! systemctl is-active --quiet ibgateway.service; then
              echo "ERROR: ibgateway.service died. Recent log:" >&2
              journalctl -u ibgateway.service -n 30 --no-pager >&2
              exit 1
            fi
            sleep 1
          done

          echo "WARNING: gateway did not open port ${toString cfg.apiPort} within 120s" >&2
          echo "Approve the 2FA push on your phone, or attach a viewer:" >&2
          echo "  vncviewer localhost:${toString cfg.vncPort}" >&2
          exit 1
          ;;

        down)
          echo "Stopping IB Gateway ($mode)..."
          systemctl --user stop minne-ibkr-record minne-ibkr-gateway 2>/dev/null || true
          systemctl stop ibgateway.service ibgateway-xvnc.service
          echo "IB Gateway stopped"
          ;;

        status)
          echo "=== IB Gateway ==="
          systemctl is-active ibgateway.service || true
          echo "=== Display ==="
          systemctl is-active ibgateway-xvnc.service || true
          echo "=== Port ${toString cfg.apiPort} ==="
          if gateway_ready; then echo open; else echo closed; fi
          echo "=== Minne IBKR ==="
          systemctl --user is-active minne-ibkr-gateway minne-ibkr-record || true
          ;;

        *)
          echo "Usage: ib {up|down|status} [${cfg.tradingMode}]" >&2
          echo "This gateway is built for ${cfg.tradingMode}; mode is validated, not selected." >&2
          exit 1
          ;;
      esac
    '';
  };
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

    # Headless X for the gateway. Xvnc rather than Xvfb: identical behaviour
    # when IBC drives the login, but keeps a viewer escape hatch when it does
    # not. -localhost keeps the RFB port off the tailnet.
    #
    # Declaring this as a unit is what stops the old :50-vs-:99 mismatch
    # recurring: previously the start script used :50 (a stray unmanaged Xvnc)
    # while the unit depended on xvfb.service on :99.
    systemd.services.ibgateway-xvnc = {
      description = "Xvnc virtual display for IB Gateway";
      wantedBy = [ ];  # started as a dependency of ibgateway.service
      serviceConfig = {
        Type = "simple";
        User = "ibgateway";
        Group = "ibgateway";
        StateDirectory = "ibgateway";
        Environment = [ "HOME=/var/lib/ibgateway" ];
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.tigervnc}/bin/Xvnc"
          cfg.display
          "-geometry 1280x1024"
          "-depth 24"
          "-SecurityTypes=None"
          "-rfbport ${toString cfg.vncPort}"
          "-localhost"
        ];
        Restart = "always";
        RestartSec = 5;
      };
    };

    age.secrets.ibkr-creds = {
      file = ../../secrets/ibkr-creds.age;
      owner = "ibgateway";
      group = "ibgateway";
      mode = "0400";
    };

    systemd.services.ibgateway = {
      description = "IB Gateway (IBC-managed)";
      requires = [ "ibgateway-xvnc.service" ];
      after = [ "ibgateway-xvnc.service" "network-online.target" ];
      wants = [ "network-online.target" ];

      # Manual up/down only. Boot-starting would fire an unattended IBKR
      # authentication and push 2FA to Scott's phone on every startup.
      wantedBy = [ ];

      environment = {
        DISPLAY = cfg.display;
        HOME = "/var/lib/ibgateway";
      };

      serviceConfig = {
        Type = "simple";
        User = "ibgateway";
        Group = "ibgateway";
        RuntimeDirectory = "ibgateway";
        RuntimeDirectoryMode = "0700";
        StateDirectory = "ibgateway";
        ExecStartPre = preflight;
        ExecStart = "${launcher}/bin/ibgateway-launcher";
        Restart = "on-failure";
        RestartSec = 10;
        TimeoutStartSec = 660;
      };

      # The old unit had Restart=on-failure with NO cap and reached 4085
      # restarts, silently hammering IBKR auth with a broken config.
      startLimitBurst = 5;
      startLimitIntervalSec = 300;
    };

    environment.systemPackages = [ ibCli ];

    # extraConfig alone doesn't guarantee polkit runs; upstream wraps it in
    # mkIf cfg.enable and it currently rides in only implicitly (NetworkManager
    # /ModemManager/rtkit). Without this, dropping those would silently discard
    # the rule below with no eval error — ib up would just start failing with
    # "Interactive authentication required".
    security.polkit.enable = true;

    # Let scott manage just these two units without a password. Narrower than
    # a sudo rule: it grants nothing else, to nobody else.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            subject.user == "scott") {
          var unit = action.lookup("unit");
          if (unit == "ibgateway.service" || unit == "ibgateway-xvnc.service") {
            return polkit.Result.YES;
          }
        }
      });
    '';
  };
}
