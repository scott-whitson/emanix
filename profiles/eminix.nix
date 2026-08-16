{ lib, ... }:

{
  # The eminix distribution — common core.
  # What is true of EVERY eminix box, regardless of shape.
  #
  # i-intelligence modules (theme, emacs, zsh, ...) are HOME MANAGER modules;
  # they are delivered to the user via lib/mkHost.nix's mkHmModule
  # (home-manager.users.${username}.imports = [ ./ioshi/i-intelligence ]).

  options.eminix.username = lib.mkOption {
    type = lib.types.str;
    default = "eminix-user";
    description = "Primary user account. Set by lib/mkHost.nix from the `username` argument.";
  };

  imports = [
    ../ioshi/os-system/base.nix
    ../ioshi/os-system/firstboot.nix
    ../ioshi/hi-hardware/net/tailscale.nix
  ];
}
