{ config, pkgs, ... }:

{
  # Datacore — headless home server: Immich + media stacks (docker compose,
  # ~/projects/datacore-config), syncthing fleet hub, git mirror, backrest→B2.
  # NixOS owns the substrate only; app workloads are compose stacks unchanged
  # from the Debian box. Spec: docs/superpowers/specs/2026-08-05-datacore-nixos-design.md

  # networking.hostName: mkHost already supplies "datacore" via mkDefault
  # (flake.nix hostName param) — dropped the plain assignment here to match.

  # os-system/server.nix (via profiles/roles/server.nix) and
  # hi-hardware/net/tailscale.nix (via profiles/eminix.nix): now supplied by
  # the role/core, same as the base.nix/zsh/users note below.

  # programs.zsh.enable / users.users.scott: now supplied by the eminix core
  # (ioshi/os-system/base.nix, via profiles/eminix.nix). Declaring them here
  # too duplicated users.users.scott.shell, a non-mergeable option, and broke
  # the build once datacore moved onto mkHost.

  services.openssh.enable = true;

  # Syncthing — the fleet hub. Device identity (cert.pem/key.pem) and the
  # hub's device/folder config are RUNTIME state copied from the old box at
  # cutover into configDir below. Deliberately NO overrideDevices /
  # overrideFolders: declaring folders here would fight the copied
  # config.xml that every peer already agrees with.
  services.syncthing = {
    enable = true;
    user = "scott";
    group = "users";
    dataDir = "/home/scott";
    configDir = "/home/scott/.local/state/syncthing";
    openDefaultPorts = true;
    guiAddress = "0.0.0.0:8384";

    # datacore is the fleet's syncthing HUB: its devices and folders are
    # managed by hand via the REST API / GUI, not declaratively. Nix must
    # never override them. These are plain assignments, not mkForce — after
    # roles/server.nix stopped importing net/syncthing.nix (which set both
    # true), nothing else defines them, and the nixpkgs DEFAULT is true.
    # Leaving them defaulted is inert only while settings.devices/folders are
    # empty; the day one is added, syncthing-init would wipe the real config.
    overrideDevices = false;
    overrideFolders = false;
  };
  # GUI/REST reachable over the tailnet only — rafik administers the hub
  # via datacore:8384 (see ioshi/hi-hardware/net/syncthing.nix comment).
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8384 ];

  # Backrest — restic scheduler/UI for b2:scott-data-restic. nixpkgs ships
  # the package but no service module; config.json is runtime state copied
  # from the old box at cutover.
  systemd.services.backrest = {
    description = "Backrest (restic scheduler/UI)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      User = "scott";
      Group = "users";
      ExecStart = "${pkgs.backrest}/bin/backrest";
      Restart = "on-failure";
    };
    environment = {
      BACKREST_PORT = "127.0.0.1:9898";
      BACKREST_CONFIG = "/home/scott/.config/backrest/config.json";
      BACKREST_DATA = "/home/scott/.local/share/backrest";
      HOME = "/home/scott";
    };
  };

  # time.timeZone / i18n.defaultLocale / console.keyMap / nix.settings /
  # nix.gc: also now supplied by the core's base.nix (identical values) —
  # removed here for the same reason as above.

  # The compose stacks in ~/projects/datacore-config invoke `docker compose`
  # (16 call sites), and backrest shells out to restic. virtualisation.docker
  # (from the server role) supplies neither, so without these nothing starts:
  # no stack, no backup.
  environment.systemPackages = with pkgs; [
    docker-compose
    restic
  ];

  # First-install release (matches whistle/rafik era) — never bump.
  system.stateVersion = "26.11";
}
