# Minimal host config. Everything opinionated is the distribution's job; this
# file holds only what emanix cannot know.
{ config, lib, ... }:
{
  # emanix.gui is a Home Manager option (ioshi/i-intelligence/theme.nix), not
  # a NixOS one — this module is spliced into extraModules, which are NixOS
  # modules, so it must be set through home-manager.users.<username> rather
  # than at the top level. config.emanix.username is the NixOS-level option
  # mkHost sets from its own `username` argument, so it names the right user
  # without this file having to repeat it.
  home-manager.users.${config.emanix.username}.emanix.gui = true;

  # Opt in to autologin only if this machine's disk is encrypted. Without
  # encryption, autologin means physical access alone yields a logged-in
  # session — see ioshi/i-intelligence/ewm.nix for why this is the host's
  # decision and not the distribution's.
  # services.getty.autologinUser = "youruser";

  networking.networkmanager.enable = true;
  time.timeZone = lib.mkDefault "UTC";
  system.stateVersion = "26.11";
}
