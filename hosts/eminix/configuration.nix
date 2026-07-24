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

  # Override Steam to auto-start XWayland if needed before launch, and
  # force X11 for games (Steam runtime sets SDL_VIDEODRIVER=wayland,x11
  # by default, but Factorio 1.1 only supports X11).
  # Steam's bwrap container needs an X display; under EWM (pure Wayland)
  # we start XWayland on-demand. Runs before bwrap so it has host access.
  programs.steam.package = pkgs.steam.override {
    extraEnv = {
      SDL_VIDEODRIVER = "x11";
    };
    extraPreBwrapCmds = ''
      if [ ! -S /tmp/.X11-unix/X0 ]; then
        _xw_wd=""
        for _sock in "$XDG_RUNTIME_DIR"/wayland-*; do
          [ -S "$_sock" ] && _xw_wd="''${_sock##*/}" && break
        done
        if [ -n "$_xw_wd" ]; then
          env WAYLAND_DISPLAY="$_xw_wd" Xwayland :0 &
          for _ in $(seq 1 10); do
            [ -S /tmp/.X11-unix/X0 ] && break
            sleep 0.3
          done
        fi
      fi
    '';
  };
}
