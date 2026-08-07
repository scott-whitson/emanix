{ pkgs, config, ... }:

{
  # eminix (T14) host-specific config.
  # Platform (os + i) comes from profiles/eminix.nix; hardware + disko layout
  # are wired in flake.nix via lib/mkHost.

  # Fresh install (2026) — pin the current release.
  system.stateVersion = "26.11";

  # Passwordless nixos-rebuild for scott: elisa's rebuilds run from non-interactive
  # SSH sessions (no TTY for a sudo prompt). Scoped tightly to the rebuild
  # binary only — not blanket wheel NOPASSWD.
  security.sudo.extraRules = [{
    users = [ "scott" ];
    commands = [{
      command = "/run/current-system/sw/bin/nixos-rebuild";
      options = [ "NOPASSWD" ];
    }];
  }];

  # Override Steam to force X11 for games (Steam runtime sets
  # SDL_VIDEODRIVER=wayland,x11 by default, but Factorio 1.1 only
  # supports X11). XWayland is started by a separate wrapper script
  # (added in ewm.nix) so it doesn't affect steam-run (used by ibgateway).
  programs.steam.package = pkgs.steam.override {
    extraEnv = {
      SDL_VIDEODRIVER = "x11";
    };
  };

  # IB Gateway — manual up/down via `ib up live`, never started at boot.
  scott.ibgateway.enable = true;
}
