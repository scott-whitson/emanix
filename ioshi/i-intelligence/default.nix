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
    ./emacs-daemon.nix
    ./syncthing.nix
    ./btop.nix
    ./lf.nix
    ./mpv.nix
    ./yt-dlp.nix
    ./fragpaper.nix
    ./wireplumber.nix
    ./pi.nix
    ./zellij.nix
    ./claude.nix
  ];

  # Give `home-manager` a CLI after the first bootstrap switch.
  programs.home-manager.enable = true;
}
