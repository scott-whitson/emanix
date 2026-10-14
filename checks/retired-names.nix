# checks/retired-names.nix — the rename, enforced.
#
# On 2026-08-30 the three-concern tree was renamed: `i-intelligence/` became
# `home/`, and `os-system/` + `hi-hardware/` became `modules/`. The README
# records why, and says of the old naming that it "was a boundary nothing
# enforced". The rename that replaced it had the same hole — nine comments in
# live files went on naming the retired directories as if they were current
# paths, and a comment cannot fail a build. This one does.
#
# Scope, deliberately narrow:
#   - `.nix` files only. README.md and WALKTHROUGH.md name the old directories
#     on purpose, to explain why they are gone; forbidding the words outright
#     would forbid the record of the decision.
#   - `docs/` is excluded. docs/superpowers/** is a frozen archive of the
#     system as it was, and rewriting history there destroys the evidence this
#     check exists to protect.
#   - this file is excluded, because it holds the names on purpose.
{ pkgs }:
let
  inherit (pkgs) lib;

  retired = [ "i-intelligence" "os-system" "hi-hardware" ];
  skipDirs = [ ".git" ".superpowers" "docs" "result" ];
  root = ./..;

  nixFiles =
    let
      go = dir:
        lib.concatMap
          (name:
            let
              entry = dir + "/${name}";
              kind = (builtins.readDir dir).${name};
            in
            if kind == "directory" then
              lib.optionals (!(lib.elem name skipDirs)) (go entry)
            else
              lib.optional
                (lib.hasSuffix ".nix" name && name != "retired-names.nix")
                entry)
          (lib.attrNames (builtins.readDir dir));
    in
    go root;

  relative = file: lib.removePrefix (toString root + "/") (toString file);

  hits = lib.concatMap
    (file:
      let
        lines = lib.splitString "\n" (builtins.readFile file);
        perLine = lib.imap0
          (i: line:
            map (name: "  ${relative file}:${toString (i + 1)}  ${name}")
              (builtins.filter (name: lib.hasInfix name line) retired))
          lines;
      in
      lib.concatLists perLine)
    nixFiles;

  message = ''
    emanix-retired-names: ${toString (builtins.length hits)} reference(s) to a
    retired directory name in live Nix code.

    i-intelligence/ -> home/ ; os-system/ and hi-hardware/ -> modules/
    (renamed 2026-08-30 — see README.md, "How the config is organised")

    Comments must point at README.md's "How the config is organised" rather
    than name the old directory. These lines do:

    ${lib.concatStringsSep "\n" hits}
  '';
in
pkgs.runCommand "emanix-retired-names" { } (
  if hits == [ ] then "touch $out" else throw message
)
