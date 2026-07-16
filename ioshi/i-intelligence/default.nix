{
  imports = [
    # Core — always enabled
    ./theme.nix
    ./emacs.nix
    ./git.nix
    ./zsh.nix
    ./ghostty.nix
    ./packages.nix
    ./swaylock.nix
    ./xdg.nix

    # Optional — enable as needed per machine
    # ./helix.nix
    # ./hyprland.nix
    # ./waybar.nix
    # ./mako.nix
    # ./fuzzel.nix
    # ./btop.nix
    # ./lf.nix
    # ./mpv.nix
    ./systemd.nix
    ./pi.nix
    # ./claude.nix
    # ./yt-dlp.nix
    # ./zellij.nix
  ];

  # Give `home-manager` a CLI after the first bootstrap switch.
  programs.home-manager.enable = true;
}