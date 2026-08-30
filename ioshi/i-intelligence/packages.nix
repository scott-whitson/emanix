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
    usbutils # lsusb — camera/device detection

    # Developer tools
    gh
    lazygit
    nodejs # JS runtime for the web toolchain below
    just
    nixpkgs-fmt
    deadnix
    statix

    # Python toolchain. Nothing Python-shaped was installed on this box before
    # 2026-08-07 — not even an interpreter. basedpyright is the LSP server
    # (eglot talks to it); ruff does lint + format. Both are also what the
    # Emacs config drives, so editor and CLI agree.
    python3
    ruff

    # Web toolchain, added 2026-08-20. djlint reformats Jinja2 templates;
    # prettier does HTML and CSS. Both are what the Emacs config drives, so
    # editor and CLI agree — the same arrangement as ruff above.
    #
    # `prettier`, NOT `nodePackages.prettier`: nodePackages was removed from
    # nixpkgs and that attribute no longer evaluates.
    djlint
    prettier

    # NOTE: nixpkgs#pi-coding-agent may lag npm latest. When it catches up,
    # this is the canonical install path. For now, this pins to nixpkgs version.

    # Media (CLI)
    ffmpeg
    imagemagick
    gphoto2 # pull photos off USB cameras (Canon R50); paired with programs.gphoto2 NixOS module

    # Media (GUI): NOT listed here. mpv.nix's `programs.mpv.enable`, gated on
    # the same config.eminix.gui, already supplies it — nixpkgs's top-level
    # `pkgs.mpv` is itself a wrapper with pname "mpv-with-scripts" (even with
    # an empty scripts list), so adding it here too collided with mpv.nix's
    # wrapped derivation in this same buildEnv (two different
    # "mpv-with-scripts" outputs, both providing bin/mpv).
  ] ++ [
    # Network
    curl
    wget
    mosh
    nmap
    iperf3
  ] ++ lib.optionals config.eminix.gui [
    # Wayland tools
    grim
    slurp
    wl-clipboard
    wf-recorder
    swappy

    # No notifications: libnotify was dropped 2026-08-08. There is no daemon to
    # receive them — mako went with the Hyprland stack and EWM implements no
    # org.freedesktop.Notifications service — so notify-send had nothing to talk
    # to. Its two callers (the zellaude hook's Claude notification path and
    # tools/stt/push-to-talk.sh) both guard on `command -v notify-send`, so they
    # now skip cleanly rather than silently no-op. Reinstate libnotify AND a
    # daemon together if desktop notifications are ever wanted back.

    # Terminal — config lives in ghostty.nix; the package (and its XDG
    # desktop entry, which EWM's s-d launcher needs) is installed here.
    ghostty

    # GUI apps. NOT firefox: firefox.nix's programs.firefox installs it (with the
    # catppuccin theming), and listing it here too put two identical firefox
    # entries in home.packages. Same shape as the mpv/mpv-with-scripts overlap.
    bitwarden-desktop

    # Photo editor (RAW dev) — GUI. Import keyed to the gphoto2 stack below.
    darktable

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
    #
    # jetbrains-mono is the TYPEFACE (11.9 MiB); symbols-only is JUST the Nerd
    # Font icon glyphs (4.7 MiB), reached by fontconfig fallback. This replaced
    # nerd-fonts.jetbrains-mono, which is the same typeface with the icons
    # patched into every weight and style — 222.5 MiB for the identical
    # rendering. emacs/config.el asks for "JetBrains Mono" accordingly; asking
    # for "JetBrainsMono Nerd Font" here would find nothing.
    jetbrains-mono
    nerd-fonts.symbols-only
    # Symbol fallback for TUIs in vterm (Claude Code's ⏵ ⏸ ⏺). No JetBrains
    # face — nor Nerd Font's symbol set — covers the media-control block
    # U+23F5/23F8/23FA, so emacs drew hex-tofu boxes. NotoSansSymbols2 (in
    # this package) is the only thing in nixpkgs checked that has them.
    # Picked up by fontconfig fallback; set-fontset-font is inert here.
    noto-fonts
    # Prose faces for eminix-prose-mode (markdown/org rendered as documents).
    # Plex Sans for body, Plex Serif for headings — a designed companion to
    # a monospace, so it sits next to JetBrainsMono code blocks without
    # clashing.
    #
    # The Latin sub-families ONLY, never the bare `ibm-plex' meta-package:
    # that one joins every script family and closes over 334 MB (Chinese SC
    # 118, Chinese TC 77, Japanese 76, Korean 27, plus Arabic/Devanagari/
    # Hebrew/Thai/Condensed/Math/Mono). These two are the identical OTFs the
    # meta-package symlinks to, at 11.1 MB the pair.
    ibm-plex.sans
    ibm-plex.serif
  ]
  # ghostty for non-gui hosts that opt in (non-GUI hosts (WSLg)). gui hosts already
  # get it from the gui block above — appended HERE so their list is
  # byte-identical (order is derivation-load-bearing, see Task-1 gate).
  ++ lib.optional (config.eminix.ghostty.enable && !config.eminix.gui) pkgs.ghostty;
}
