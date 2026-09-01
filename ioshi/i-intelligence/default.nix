# The HOME MANAGER aggregate for this directory — NOT the directory's index.
#
# ioshi's three concerns are descriptive (see README): i-intelligence says what
# a thing is about, not which module system delivers it. So this directory holds
# 17 modules and this list imports 16. The one it deliberately omits is a NixOS
# module, exposed as `nixosModules.ewm` and imported at system level by the
# consuming flake instead:
#
#   ewm.nix      the EWM compositor service, the system-owned Emacs build
#
# Adding a module here? If it configures the user's environment through Home
# Manager, add it to the list below. If it needs the NixOS tier, expose it as a
# flake output and let the consumer import it — do NOT add it here. This file is
# a Home Manager aggregate: importing it at system level throws, because NixOS
# has no `programs.*` of the shape these modules set.
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
    ./zellij.nix
  ];

  # Give `home-manager` a CLI after the first bootstrap switch.
  programs.home-manager.enable = true;
}
