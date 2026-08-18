# The HOME MANAGER aggregate for this directory — NOT the directory's index.
#
# ioshi's three concerns are descriptive (see README): i-intelligence says what
# a thing is about, not which module system delivers it. So this directory holds
# 20 modules and this list imports 18. The two it deliberately omits are NixOS
# modules, imported at system level by profiles/roles/workstation.nix instead:
#
#   ewm.nix      the EWM compositor service, the system-owned Emacs build
#   ollama.nix   local model serving
#
# Adding a module here? If it configures the user's environment through Home
# Manager, add it to the list below. If it needs the NixOS tier, add it to a
# role profile and leave this list alone — importing this file at system level
# throws (ioshi/os-system/server.nix documents why).
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
    ./firefox.nix
    ./btop.nix
    ./lf.nix
    ./mpv.nix
    ./yt-dlp.nix
    ./wireplumber.nix
    ./pi.nix
    ./zellij.nix
    ./claude.nix
  ];

  # Give `home-manager` a CLI after the first bootstrap switch.
  programs.home-manager.enable = true;
}
