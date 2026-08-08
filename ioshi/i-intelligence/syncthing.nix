{ config, lib, pkgs, ... }:

{
  # Work-WSL syncthing (Phase 3): hub-and-spoke with datacore only.
  # eminix's syncthing is the NixOS module (ioshi/hi-hardware/net/syncthing.nix);
  # datacore's is Debian-managed (the hub, configured via REST). This HM-native
  # config exists only for the wsl profile.
  config = lib.mkIf (config.scott.role == "wsl") {
    # User-unit counterpart of the ordering in net/syncthing.nix (system
    # service on rafik/datacore); ported from the same retired stow drop-in
    # (base/systemd/.config/systemd/user/syncthing.service.d/override.conf).
    systemd.user.services.syncthing.Unit = {
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    services.syncthing = {
      enable = true;
      overrideDevices = true;
      overrideFolders = true;
      settings = {
        devices.datacore.id =
          "FXOPHIF-EMJAP6C-CLI6PB4-HCLUDMK-RJ3PXLE-GIV4IJ7-3NMTE35-YHRNIAI";
        # Per-device path asymmetry (user decision): ALL of ~/projects here,
        # lands at ~/projects/work on datacore/rafik. ~/clients lives OUTSIDE
        # ~/projects and is never shared.
        folders.work-projects = {
          id = "work-projects";
          label = "work-projects";
          path = "/home/scott/projects";
          devices = [ "datacore" ];
        };
        folders.work-docs = {
          id = "work-docs";
          label = "work-docs";
          path = "/home/scott/docs/org/work";
          devices = [ "datacore" ];
        };
      };
    };

    # Ignore build junk at the source. NB: no trailing slashes — syncthing
    # ignores are not gitignore. .git is intentionally synced (spec).
    home.file."projects/.stignore" = {
      force = true;
      text = ''
        // Build/venv/cache junk — arch- and machine-specific, never sync
        node_modules
        .venv
        venv
        __pycache__
        .direnv
        .pytest_cache
        .mypy_cache
        .ruff_cache
        target
        dist
        build
        *.pyc
      '';
    };
  };
}
