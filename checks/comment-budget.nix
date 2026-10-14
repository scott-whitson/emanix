# checks/comment-budget.nix — no comment block runs past 30 consecutive lines.
#
# docs/decisions/README.md sets the budgets (a file header 12 lines, a note on
# one binding 6). Those are targets for a writer; this enforces the one ceiling
# that is unambiguously over, because a block of 30 or more consecutive comment
# lines is an essay and an essay belongs in docs/decisions/.
#
# The threshold is deliberately loose. A tighter one would flag the 20-27 line
# blocks that are legitimately evidence — lib/themes.nix's palette rules,
# modules/firmware.nix's asymmetry argument — and a check that cries wolf gets
# disabled. 30 is above every block left after the 2026-10 tightening, and below
# every block that motivated it: checks/welcome-keys.nix was 58, lib/disk.nix and
# checks/template-host.nix were 36.
#
# Over budget means relocate, never delete. A measurement, a rejected alternative
# or an exit condition moves to docs/decisions/<slug>.md and the comment keeps the
# decision plus one link.
{ pkgs }:
let
  inherit (pkgs) lib;
  root = ./..;
  budget = 30;

  skipDirs = [ ".git" ".superpowers" "docs" "result" ];

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
              lib.optional (lib.hasSuffix ".nix" name) entry)
          (lib.attrNames (builtins.readDir dir));
    in
    go root;

  # Longest run of consecutive comment lines, via a fold carrying both the
  # current run and the best seen. A line counts as a comment when its first
  # non-blank character is `#`.
  longestRun = file:
    (lib.foldl'
      (acc: line:
        if lib.hasPrefix "#" (lib.trim line) then
          let cur = acc.cur + 1; in
          { inherit cur; best = if cur > acc.best then cur else acc.best; }
        else { cur = 0; inherit (acc) best; })
      { cur = 0; best = 0; }
      (lib.splitString "\n" (builtins.readFile file))).best;

  measured = map
    (f: {
      file = lib.removePrefix (toString root + "/") (toString f);
      run = longestRun f;
    })
    nixFiles;

  over = lib.filter (m: m.run > budget) measured;

  message = ''
    emanix-comment-budget: ${toString (builtins.length over)} file(s) hold a
    comment block longer than ${toString budget} consecutive lines.

    A block that long is an essay. The budgets are in docs/decisions/README.md;
    a measurement, a rejected alternative or an exit condition belongs in
    docs/decisions/<slug>.md, with the decision and one link left behind. Over
    budget means relocate, never delete.

    ${lib.concatStringsSep "\n" (map (m: "  ${m.file}: ${toString m.run} lines") over)}
  '';
in
pkgs.runCommand "emanix-comment-budget" { } (
  if over == [ ] then "touch $out" else throw message
)
