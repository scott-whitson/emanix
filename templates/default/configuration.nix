# Minimal host config. Everything opinionated is the distribution's job; this
# file holds only what emanix cannot know.
{ config, lib, ... }:
{
  # emanix.gui and emanix.src.liveElisp are Home Manager options
  # (ioshi/i-intelligence/theme.nix), not NixOS ones — this module is spliced
  # into extraModules, which are NixOS modules, so they must be set through
  # home-manager.users.<username> rather than at the top level.
  # config.emanix.username is the NixOS-level option mkHost sets from its own
  # `username` argument, so it names the right user without this file having
  # to repeat it. Both are set in ONE attrset here rather than as two
  # separate dotted-path assignments — Nix rejects two attrpaths that share
  # the same `${...}`-interpolated segment ("dynamic attribute ... already
  # defined"), since it cannot tell statically that they name the same key.
  home-manager.users.${config.emanix.username}.emanix = {
    gui = true;

    # This host has no emanix checkout (that only exists on machines that
    # cloned the distro to hack on it), so the live-elisp symlinks that
    # option defaults to would dangle:
    # ~/.config/emacs/{config.el,fallback.el,init.el,lisp} would point into a
    # $HOME/projects/emanix that was never created — no welcome buffer, no
    # keybindings, no fallback. See ioshi/i-intelligence/theme.nix's own doc
    # for src.liveElisp: "Disable on hosts with no checkout." Copied into the
    # store instead; edits need a rebuild, which is the correct trade for a
    # generated host.
    src.liveElisp = false;
  };

  # Opt in to autologin only if this machine's disk is encrypted. Without
  # encryption, autologin means physical access alone yields a logged-in
  # session — see ioshi/i-intelligence/ewm.nix for why this is the host's
  # decision and not the distribution's.
  # services.getty.autologinUser = "youruser";

  # disko lays out an EF00 ESP at /boot (via emanix.lib.mkDisk, emanix's
  # lib/disk.nix) and the installer warns when Secure Boot is on that
  # systemd-boot is unsigned — so
  # systemd-boot, not grub, is the loader a generated host actually gets.
  # Neither emanix nor the template set a bootloader anywhere else; without
  # this a generated host fails NixOS's own assertion ("You must set the
  # option `boot.loader.grub.devices'") after the disk has already been
  # partitioned.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;
  time.timeZone = lib.mkDefault "UTC";
  system.stateVersion = "26.11";
}
