# checks/check-index.nix — every check is named in WALKTHROUGH.md's table.
#
# A check nobody can find is a check nobody runs, and a table that names a
# renamed check is a dead pointer. This asserts the two agree, so adding a check
# without documenting it fails the build. Same reasoning as `fleet-ports` in the
# consuming repository: one table, and a check that the readers still read it.
{ pkgs }:
let
  inherit (pkgs) lib;
  root = ./..;

  # The checks that are not a file in checks/: they are inline in flake.nix.
  inline = [ "role-workstation" "role-server" "role-wsl" "palette-contrast" ];

  # Files in checks/ that are not checks. `stub-hardware.nix` is the fixture the
  # role-* checks compose a throwaway host against, not a check in its own right.
  fixtures = [ "stub-hardware" ];

  fromFiles =
    map (n: lib.removeSuffix ".nix" n)
      (lib.filter (n: lib.hasSuffix ".nix" n && !(lib.elem (lib.removeSuffix ".nix" n) fixtures))
        (builtins.attrNames (builtins.readDir (root + "/checks"))));

  expected = fromFiles ++ inline;

  doc = builtins.readFile (root + "/WALKTHROUGH.md");
  missing = lib.filter (n: !(lib.hasInfix "`${n}`" doc)) expected;

  message = ''
    emanix-check-index: ${toString (builtins.length missing)} check(s) are not
    named in WALKTHROUGH.md's table.

    The table is what a reader trusts, so a check outside it is a check nobody
    finds. Add a row, or fix the name it uses:

    ${lib.concatStringsSep "\n" (map (n: "  ${n}") missing)}
  '';
in
pkgs.runCommand "emanix-check-index" { } (
  if missing == [ ] then "touch $out" else throw message
)
