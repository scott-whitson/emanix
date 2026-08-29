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
    # NO default, deliberately. It defaulted to "eminix-user" until 2026-08-18,
    # which meant importing nixosModules.eminix outside mkHost silently created
    # a real account named eminix-user in wheel and docker with no password set.
    # For a distribution that hardcodes no username, failing loudly with
    # "option used but not defined" is the correct behaviour. mkHost always
    # supplies it.
    description = "Primary user account. Set by lib/mkHost.nix from the `username` argument.";
  };

  # No text-to-speech anywhere in eminix.
  #
  # NB `config.` prefix: this module declares options.eminix.username, which
  # puts it in the explicit options/config form. A bare `services.…` at the
  # top level here fails with "unsupported attribute `services'".
  #
  # nixos/modules/services/misc/graphical-desktop.nix enables services.speechd
  # for anything that declares itself a graphical desktop, which every EWM host
  # now does. It pulls speech-dispatcher -> espeak-ng -> mbrola ->
  # mbrola-voices, and the VOICE DATA ALONE IS 645 MiB. Measured on datacore:
  # importing ewm.nix moved the closure 6.2 -> 7.4 GiB, and turning this off
  # brought it back to 6.7 GiB — so more than half the apparent cost of "EWM"
  # was text-to-speech nothing in this distribution ever calls. EWM itself is
  # 16.5 MiB.
  #
  # Stated here rather than per-role because it is true of every eminix box:
  # the distribution does not ship a screen reader. The nixpkgs default for the
  # option is already false; this only counteracts that module.
  #
  # NOT mkDefault — graphical-desktop.nix uses mkDefault true, and two
  # mkDefaults TIE ("conflicting definition values"). NOT mkForce, which would
  # stop a host disagreeing without mkForce of its own. mkOverride 500 outranks
  # that module's 1000 while still losing to a plain definition (100) in a
  # host's config, so a machine that genuinely needs TTS writes
  # `services.speechd.enable = true;` and wins.
  config.services.speechd.enable = lib.mkOverride 500 false;

  imports = [
    ../ioshi/os-system/base.nix
    ../ioshi/os-system/firstboot.nix
    ../ioshi/hi-hardware/net/tailscale.nix
  ];
}
