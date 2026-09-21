# The HOME MANAGER aggregate — NOT the directory's index.
#
# `home/` is every module that configures the USER's environment through Home
# Manager. `modules/` is the other tier: the NixOS substrate, the two
# hardware-capability modules, and the compositor service. The split is by
# module system, because that is the one fact that decides how a file is
# imported — a Home Manager module goes in the list below; a NixOS module is
# exposed as a flake output (`nixosModules.ewm`) and imported at system level by
# the consuming flake.
#
# This file is the aggregate for the HOME MANAGER tier only. Importing it at
# system level throws, because NixOS has no `programs.*` of the shape these
# modules set.
#
# This directory used to be `ioshi/i-intelligence/`, and `modules/` used to be
# `ioshi/os-system/` plus `ioshi/hi-hardware/`. The ioshi three-concern story is
# still how the distribution is reasoned about; it is just no longer a directory
# contract. See README.
{
  imports = [
    # Core — always enabled
    ./theme.nix
    ./emacs.nix
    ./git.nix
    ./zsh.nix
    ./ghostty.nix
    ./packages.nix
    ./xdg.nix
    ./emacs-daemon.nix
    ./agent-acp.nix
    ./firefox.nix
    ./btop.nix
    ./mpv.nix
    ./yt-dlp.nix
    ./wireplumber.nix
    ./zellij.nix
  ];

  # Give `home-manager` a CLI after the first bootstrap switch.
  programs.home-manager.enable = true;
}
