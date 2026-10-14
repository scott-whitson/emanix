# checks/decisions-index.nix — every decision record is linked from the index.
#
# A record missing from docs/decisions/README.md is invisible, and an index entry
# pointing at a renamed record is a dead pointer — the same defect class as the
# retired directory names, which have their own check. This asserts the
# record -> index direction; the reverse (an index entry with no record) is not
# checked, because it needs link parsing and the cost of that is not worth it.
{ pkgs }:
let
  inherit (pkgs) lib;
  dir = ./../docs/decisions;

  records = lib.filter (n: n != "README.md" && lib.hasSuffix ".md" n)
    (builtins.attrNames (builtins.readDir dir));

  index = builtins.readFile (dir + "/README.md");
  missing = lib.filter (n: !(lib.hasInfix "(${n})" index)) records;

  message = ''
    emanix-decisions-index: ${toString (builtins.length missing)} record(s) are
    not linked from docs/decisions/README.md.

    A record outside the index is a record nobody reads. Add a row to that
    file's "Records" table:

    ${lib.concatStringsSep "\n" (map (n: "  docs/decisions/${n}") missing)}
  '';
in
pkgs.runCommand "emanix-decisions-index" { } (
  if missing == [ ] then "touch $out" else throw message
)
