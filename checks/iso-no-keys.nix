# checks/iso-no-keys.nix — no key material can reach the store through the ISO.
#
# An image is assembled from /nix/store, which is world readable (mode 0555:
# every local user can read every path) and whose `environment.etc` entries are
# symlinks into it. So "the ISO carries the host keys" is the same statement as
# "the host keys are published": there is no permission bit, order of options or
# filter that stages a private key into a NixOS image without a world-readable
# copy of it existing on the build machine and in every image built from that
# closure.
#
# This module did it anyway until 2026-11-02 — the private host key halves and a
# REUSABLE tailnet preauthkey, both through `builtins.path`, both mounted via
# `environment.etc`, both world readable, both also inside the published image.
# The fix was deletion, not hardening, so this is the guard that keeps it
# deleted: docs/decisions/keys-never-in-the-store.md.
#
# Evaluated rather than built. The PR gate runs `nix flake check --no-build`, so
# a guard that only fires when somebody builds an ISO would be discovered months
# later, by whoever next built one — which is how the original defect survived
# review in the first place.
{ pkgs, ... }:
let
  inherit (pkgs) lib;
  root = ./..;

  # Comment lines are dropped before matching. Naming the removed paths in a
  # comment is how the next reader learns why they are gone, and a check that
  # forbids the explanation gets dropped instead of the keys.
  codeLines = file:
    lib.filter (l: !(lib.hasPrefix "#" (lib.trim l)))
      (lib.splitString "\n" (builtins.readFile file));

  iso = codeLines (root + "/installer/iso.nix");
  installer = codeLines (root + "/installer/fresh-emanix-install");

  isoText = lib.concatStringsSep "\n" iso;
  installerText = lib.concatStringsSep "\n" installer;

  # `builtins.path` is the copy-into-the-store primitive. Exactly one call site
  # is allowed: the flake. A second one is a second thing the image carries, and
  # whatever it is, nobody has argued for it here.
  copiesIntoStore = lib.count (l: lib.hasInfix "builtins.path" l) iso;

  offences =
    lib.optional (copiesIntoStore != 1)
      "installer/iso.nix copies ${toString copiesIntoStore} paths into the store; exactly one (the flake) is allowed"
    ++ lib.optional (lib.hasInfix "keysDir" isoText)
      "installer/iso.nix names keysDir again"
    ++ lib.optional (lib.hasInfix "tailscale-authkey" isoText)
      "installer/iso.nix stages a tailnet authkey again"
    ++ lib.optional (lib.hasInfix "emanix/keys" isoText)
      "installer/iso.nix mounts a keys directory again"
    ++ lib.optional (lib.hasInfix "emanix/keys" installerText)
      "the installer reads a keys directory out of the image again";
in
pkgs.runCommand "emanix-iso-no-keys" { } (
  if offences == [ ] then "touch $out" else
  throw ''
    emanix-iso-no-keys: key material is being routed through the installer image.

    /nix/store is world readable, so a key in an image is a key published. Keys
    belong on a removable medium, read at install time from <repo>-keys/ beside
    the repo, or typed at the prompt. See
    docs/decisions/keys-never-in-the-store.md.

    ${lib.concatStringsSep "\n" (map (o: "  ${o}") offences)}
  ''
)
