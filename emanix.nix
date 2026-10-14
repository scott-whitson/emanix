{ lib, ... }:

{
  # The emanix distribution — common core. What is true of EVERY emanix box,
  # regardless of shape.
  #
  # home/ modules (theme, emacs, zsh, ...) are HOME MANAGER modules, delivered
  # to the user via lib/mkHost.nix's mkHmModule
  # (home-manager.users.${username}.imports = [ ./home ]).

  options.emanix.username = lib.mkOption {
    type = lib.types.str;
    # NO default, deliberately. It defaulted to "emanix-user" until 2026-08-18,
    # which meant importing nixosModules.emanix outside mkHost silently created
    # a real account in wheel and docker with no password set. For a
    # distribution that hardcodes no username, "option used but not defined" is
    # the correct behaviour. mkHost always supplies it.
    description = "Primary user account. Set by lib/mkHost.nix from the `username` argument.";
  };

  # `emanix.emacs.extraPackages` is NOT here. It is declared in home/emacs.nix,
  # an HM module, because the consumer sets it as HM config and modules/ewm.nix
  # reaches it through `config.home-manager.users.<user>` — see that file's
  # hmCfg note. Declaring it here would put it out of reach of
  # home/emacs-daemon.nix, which is also an HM module.

  # No text-to-speech anywhere in emanix: the distribution ships no screen
  # reader. See docs/decisions/speechd.md for the 645 MiB measurement, the
  # closure deltas, and why this strength and not mkDefault or mkForce.
  #
  # NB the `config.` prefix: this module declares options.emanix.username, which
  # puts it in the explicit options/config form. A bare `services.…` at the top
  # level here fails with "unsupported attribute `services'".
  config.services.speechd.enable = lib.mkOverride 500 false;

  imports = [
    ./modules/base.nix
    ./modules/firstboot.nix
    ./modules/init.nix
    # Hardware capability — the machine-facing tier, imported by EVERY host and
    # not only graphical ones. See docs/decisions/firmware-default.md for the
    # 791 MiB cost, why it is paid by hosts that cannot use it, the rejected
    # role gate, and why gpu.nix is imported even though it is inert until set.
    ./modules/gpu.nix
    ./modules/firmware.nix
  ];
}
