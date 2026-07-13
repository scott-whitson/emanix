{ config, lib, pkgs, ... }:

{
  # User-level packages installed via Home Manager.
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
    nodejs # pi coding agent runtime (pi itself: npm install per install/07-pi.sh)
    just
    nixd
    nixpkgs-fmt
    deadnix
    statix

    # Media
    ffmpeg
    imagemagick
    mpv

    # Network
    curl
    wget
    mosh
    nmap
    iperf3

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

    # Fonts
    jetbrains-mono
    nerd-fonts.jetbrains-mono
  ];
}