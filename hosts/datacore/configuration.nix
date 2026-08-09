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

  # `docker compose` and `restic` already work WITHOUT these packages:
  # - virtualisation.docker.package (docker-29.6.0) is a wrapper that sets
  #   DOCKER_CLI_PLUGIN_DIRS to a docker-compose-5.3.0/libexec/docker/cli-plugins
  #   path, so `docker compose` resolves before this list is even considered.
  # - pkgs.backrest's wrapper sets BACKREST_RESTIC_COMMAND to a store restic
  #   path, so backrest finds restic on its own too.
  #
  # Kept anyway, on purpose: closure growth is zero (both store paths are
  # already pulled in by the mechanisms above), and an interactive `restic`
  # on PATH is genuinely needed for the manual restore test in Task 8.
  #
  # Caveat — this list does NOT reach backrest.service: its generated unit
  # PATH is only coreutils/findutils/gnugrep/gnused/systemd; the systemd unit
  # sandbox does not add /run/current-system/sw/bin. So environment.systemPackages
  # was never what would have made restic resolve for the service, only the
  # wrapper's baked-in path was. If a command hook is ever added to backrest's
  # config.json, it needs systemd.services.backrest.path set explicitly, or a
  # bare `docker`/`restic` in the hook will not be found.
  environment.systemPackages = with pkgs; [
    docker-compose
    restic
  ];

  # First-install release (matches whistle/rafik era) — never bump.
  system.stateVersion = "26.11";
}
