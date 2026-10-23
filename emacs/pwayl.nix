# The GPU Emacs: Emacs 31.1 with EWM's native Wayland (pwayl) + Skia backend,
# from EWM's fork, and the EWM tier's base. The only place this expression
# exists, so modules/ewm.nix and emacs/packages.nix build one derivation.
#
# `emacs31` is not in the channel (26.05 ships 30.2), so emacs-overlay's
# `emacs-unstable` supplies the recipe, flags and deps; the fork replaces `src`.
#
# The reconnect below is load-bearing: ewm's nix/emacs.nix calls `.override`, so
# emacs-overlay's reconnected `pkgs` still names the un-patched base, and ewm
# builds ewm.el through `emacsPackage.pkgs.trivialBuild`. Upstream's
# `programs.ewm.withSkia` must not be used: it names that same base.
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
