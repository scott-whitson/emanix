# The GPU Emacs: Emacs 31.1 with EWM's native Wayland (pwayl) + Skia backend,
# built from the EWM fork's `wayland-31` branch.
#
# It lives in emacs/ rather than inside a host's config because two tiers need
# the SAME derivation: the NixOS tier builds the compositor's Emacs
# (modules/ewm.nix) and hands this base to emacs/packages.nix, and a second
# copy of this expression anywhere else would quietly give the fleet two
# Emacsen that differ by more than their backend.
#
# Two things this file has to get right:
#
# 1. `emacs31` does not exist in the channel. nixpkgs 26.05 ships Emacs 30.2
#    with no emacs31 attribute, while EWM's nix/emacs.nix is a callPackage that
#    takes one. emacs-overlay's `emacs-unstable` is 31.1 built from the same
#    release branch, so that is what goes in — and the fork replaces `src`
#    anyway, so emacs31 only ever supplies the recipe, the flags and the
#    dependency set. Verified: pkgs.emacs31.name errors on this pin,
#    pkgs.emacs-unstable.version is "31.1", pkgs.emacs.version is "30.2".
#
# 2. The passthru package set must be re-pointed at this build. ewm.nix calls
#    `.override` on emacs-unstable, which re-runs the base recipe, so the
#    `pkgs` emacs-overlay reconnected in mkGitEmacs still refers to the
#    un-patched base: `pwayl.pkgs.emacs` is an X11 Emacs, not this one. That
#    matters because emacs/packages.nix builds the distro's Emacs through
#    `emacsPackagesFor base`, and ewm's own nix/default.nix builds ewm.el with
#    `emacsPackage.pkgs.trivialBuild`: without the reconnect, ewm.el is
#    byte-compiled by the other Emacs and a second full Emacs build lands in
#    every host's closure. The reconnect is the same shape emacs-overlay uses
#    for its own build. Verified: fixed.pkgs.emacs.drvPath becomes this
#    derivation, and the resulting closure references only the pwayl output.
#
# Upstream's `programs.ewm.withSkia` is NOT used here and must not be: it
# defaults emacsPackage to `emacs31-pwayl.pkgs.withPackages`, i.e. to that same
# un-patched base, so it installs an X11 Emacs 31.1 rather than a pwayl one.
# See docs/decisions/gpu-emacs.md.
{ pkgs, ewm, ... }:

let
  raw = pkgs.callPackage "${ewm}/nix/emacs.nix" {
    emacs31 = pkgs.emacs-unstable;
  };

  # The self-reference is deliberate: it is what makes the package set and the
  # binary the same derivation.
  pwayl = raw.overrideAttrs (old: {
    passthru = (old.passthru or { }) // {
      pkgs = pkgs.emacsPackagesFor pwayl;
    };
  });
in
pwayl
