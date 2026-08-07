{ config, lib, pkgs, ... }:

{
  # User-level packages installed via Home Manager.
  # NB: element ORDER below is derivation-load-bearing for eminix — the gui
  # splices sit exactly where those packages originally were. Reordering (or
  # merging the gui blocks) changes the eminix system drv and forces a
  # rebuild; re-check the toplevel drvPath if you restructure.
  # System-level packages (Hyprland, Docker, etc.) stay under apt for Phase 1
  # and move to the NixOS layer in Phase 2.
  home.packages = with pkgs; [
    # CLI essentials
    ripgrep
    fd
    jq
    htop
    btop
    fastfetch
    unzip
    xz
    file

    # Developer tools
    gh
    lazygit
    nodejs # pi coding agent runtime
    pi-coding-agent # declarative — replaces the old npm post-install
    just
    nixd
    nixpkgs-fmt
    deadnix
    statix

    # NOTE: nixpkgs#pi-coding-agent may lag npm latest. When it catches up,
    # this is the canonical install path. For now, this pins to nixpkgs version.

    # Media (CLI)
    ffmpeg
    imagemagick
  ] ++ lib.optional config.scott.gui mpv # Media (GUI)
  ++ [
    # Network
    curl
    wget
    mosh
    nmap
    iperf3
  ] ++ lib.optionals config.scott.gui [
    # Wayland tools
    grim
    slurp
    wl-clipboard
    wf-recorder
    swappy

    # Notifications
    libnotify

    # Terminal — config lives in ghostty.nix; the package (and its XDG
    # desktop entry, which EWM's s-d launcher needs) is installed here.
    ghostty

    # GUI apps
    firefox
    bitwarden-desktop

    # Steam wrapper — starts XWayland on :0 if needed, then runs the real steam.
    # This is separate from the steam-run wrapper (used by ibgateway) so
    # XWayland only starts when you actually launch Steam.
    (pkgs.writeShellScriptBin "steam" ''
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
      exec /run/current-system/sw/bin/steam "$@"
    '')
  ] ++ [
    # Fonts — every node: pgtk emacs under WSLg reads nix-profile fonts
    jetbrains-mono
    nerd-fonts.jetbrains-mono
    # Symbol fallback for TUIs in vterm (Claude Code's ⏵ ⏸ ⏺). No JetBrains
    # face — nor Nerd Font's symbol set — covers the media-control block
    # U+23F5/23F8/23FA, so emacs drew hex-tofu boxes. NotoSansSymbols2 (in
    # this package) is the only thing in nixpkgs checked that has them.
    # Picked up by fontconfig fallback; set-fontset-font is inert here.
    noto-fonts

    # dot-restow / dot-sync dependency — every node stows base/. Was never
    # declared in nix: pre-migration boxes had a distro package, and the
    # symlinks it made survived the move, hiding the gap until dot-sync's
    # restow step started failing on whistle (found 2026-08-05).
    stow
  ]
  # ghostty for non-gui hosts that opt in (whistle/WSLg). gui hosts already
  # get it from the gui block above — appended HERE so their list is
  # byte-identical (order is derivation-load-bearing, see Task-1 gate).
  ++ lib.optional (config.scott.ghostty.enable && !config.scott.gui) pkgs.ghostty;
}
