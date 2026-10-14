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
# This directory and `modules/` were renamed on 2026-08-30, out of a
# three-concern scheme whose names made every path ambiguous across both repos.
# README.md, "How the config is organised", records what the old names were
# and why the scheme was dropped. They are deliberately not repeated here, so
# there is one place that can be right — and checks/retired-names.nix holds it
# to that.
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
  ];

  # Give `home-manager` a CLI after the first bootstrap switch.
  programs.home-manager.enable = true;
}
