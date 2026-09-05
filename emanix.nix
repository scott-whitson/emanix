{ lib, ... }:

{
  # The emanix distribution — common core.
  # What is true of EVERY emanix box, regardless of shape.
  #
  # i-intelligence modules (theme, emacs, zsh, ...) are HOME MANAGER modules;
  # they are delivered to the user via lib/mkHost.nix's mkHmModule
  # (home-manager.users.${username}.imports = [ ./ioshi/i-intelligence ]).

  options.emanix.username = lib.mkOption {
    type = lib.types.str;
    # NO default, deliberately. It defaulted to "emanix-user" until 2026-08-18,
    # which meant importing nixosModules.emanix outside mkHost silently created
    # a real account named emanix-user in wheel and docker with no password set.
    # For a distribution that hardcodes no username, failing loudly with
    # "option used but not defined" is the correct behaviour. mkHost always
    # supplies it.
    description = "Primary user account. Set by lib/mkHost.nix from the `username` argument.";
  };

  # No text-to-speech anywhere in emanix.
  #
  # NB `config.` prefix: this module declares options.emanix.username, which
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
  # Stated here rather than per-role because it is true of every emanix box:
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
    ./ioshi/os-system/base.nix
    ./ioshi/os-system/firstboot.nix
    ./ioshi/os-system/init.nix
    # hi-hardware — the machine-facing tier. Imported by EVERY host, not only
    # graphical ones. The two modules are imported together but they are NOT
    # both free, and the earlier version of this comment implied they were.
    #
    # gpu.nix is genuinely inert until set: it declares an option defaulting to
    # null, and its config block is behind mkIf, so a headless or WSL host
    # carries the declaration and none of the effect. Gating THAT import on a
    # role would mean `emanix.hardware.gpu` did not exist on hosts that merely
    # have not set it, which is a worse error message than a no-op.
    #
    # firmware.nix is a different thing and is imported here anyway.
    # `hardware.enableRedistributableFirmware = mkDefault true` contributes
    # UNCONDITIONALLY — it pulls linux-firmware, roughly 791 MiB of closure,
    # onto every emanix host: the headless server that has no wifi to bring up
    # and the WSL guest that has no hardware at all, as much as the laptop the
    # default exists for. That is real, and it is paid by machines that cannot
    # use it.
    #
    # It is still the right default. A distribution whose installer completes
    # onto a laptop that then cannot see its wifi has not installed anything,
    # and the operator has no network with which to fix it — the cost of being
    # wrong is asymmetric, and it is asymmetric in the direction of shipping
    # the firmware. Debian reached the same conclusion for the same reason.
    #
    # The alternative — gating the import on "is this a WSL/headless host" —
    # was rejected outright: that puts a host SHAPE into the distribution,
    # which is precisely what this design does not do. emanix is ONE shape.
    #
    # What makes the cost acceptable is that it is one line to decline.
    # mkDefault, not a plain definition, so a host writes
    # `hardware.enableRedistributableFirmware = false;` and wins with no
    # mkForce. Before doing that on a graphical host, read the assertion in
    # gpu.nix: declining the firmware while emanix.hardware.gpu is set is the
    # black-screen combination, and the assertion is what stops it building.
    ./ioshi/hi-hardware/gpu.nix
    ./ioshi/hi-hardware/firmware.nix
  ];
}
