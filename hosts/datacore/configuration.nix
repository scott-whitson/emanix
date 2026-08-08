{ config, lib, pkgs, ... }:

{
  # Datacore — headless home server: Immich + media stacks (docker compose,
  # ~/projects/datacore-config), syncthing fleet hub, git mirror, backrest→B2.
  # NixOS owns the substrate only; app workloads are compose stacks unchanged
  # from the Debian box. Spec: docs/superpowers/specs/2026-08-05-datacore-nixos-design.md
  networking.hostName = "datacore";

  imports = [
    ../../ioshi/os-system/server.nix
    ../../ioshi/hi-hardware/net/tailscale.nix
  ];

  programs.zsh.enable = true;

  users.users.scott = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    shell = pkgs.zsh;
  };

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

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # First-install release (matches whistle/rafik era) — never bump.
  system.stateVersion = "26.11";
}
