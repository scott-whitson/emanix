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

    # Fonts
    jetbrains-mono
    nerd-fonts.jetbrains-mono
  ];
}