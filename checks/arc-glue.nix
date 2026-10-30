# Guards the defect that motivated arc: the distro cannot know the operator's
# username, so a hardcoded /home/<user> path in shipped elisp silently indexes
# nothing while the assistant keeps answering from the Emacs manuals and looks
# perfectly healthy doing it. That is exactly how the previous assistant ran
# for six weeks.
#
# Cheap on purpose: a handful of greps over one file, no Emacs closure.
#
# Every assertion below is decided at EVALUATION time and `throw'n there, not
# `exit 1'ed inside a build script. The gate that protects main is
# `nix flake check --no-build', which builds nothing, so a failing build
# script can never fail it. Same idiom as checks/retired-names.nix.
{ pkgs, ... }:
let
  inherit (pkgs) lib;

  src = ../emacs/lisp/emanix-arc.el;
  text = builtins.readFile src;
  lines = lib.splitString "\n" text;

  # `builtins.match' anchors its pattern at BOTH ends, so an unanchored
  # `grep -E' pattern is written `.*pattern.*' here, and one that began with
  # `^' is written WITHOUT the leading `.*' -- the anchor is already there.
  # The result is null when the pattern does not match the line.
  lineMatches = re: line: builtins.match re line != null;
  anyLineMatches = re: lib.any (lineMatches re) lines;

  # `grep -q' and `grep -qF' are both fixed-string searches here.
  defines = name: {
    ok = lib.hasInfix name text;
    message = "emanix-arc.el no longer defines ${name}";
  };

  problems = [
    # 1. No absolute home path, ever. Derive from $HOME.
    {
      ok = !(anyLineMatches ''.*"/home/[a-z].*'');
      message = ''emanix-arc.el contains an absolute home path; derive it from $HOME'';
    }

    # 2. The distro is emanix. arc's own upstream defaults still carry the
    #    pre-rename name and point at a projects directory that exists on no
    #    host here, which is precisely why this file overrides them. The old
    #    name reappearing means that override has drifted back.
    {
      ok = !(lib.hasInfix "eminix" text);
      message = "emanix-arc.el mentions the pre-rename distro name; it is emanix now";
    }
  ]
  # 3. The full corpus must still be enabled. Drop that line and arc quietly
  #    enables only the Emacs manuals -- no error, no warning, and an oracle
  #    that knows nothing about this machine and sounds fine.
  ++ (map defines [ "arc-enabled-collections" "arc-ui-capture-function" ])
  ++ [
    # 3b. The plan is arc's own now. A collection upstream retired (dotfiles,
    #     emanix: both folded into `home`) named here again would build a
    #     corpus arc's scope presets do not reach, and they would match nothing.
    {
      ok = !(anyLineMatches ''.*\("(dotfiles|emanix)" *\..*'');
      message = "emanix-arc.el names a collection arc retired; it is `home' now";
    }
  ]
  # 4. The distro owns the ARC key contract. The old package's command map
  #    disappears with the prose-answer layer, so Emanix must bind its own map
  #    and own the retrieval wrapper while retaining the pinned-package
  #    fallback. The `defines' greps keep the four names; the next two pin the
  #    map binding and the optional search UI.
  ++ (map defines [
    "emanix/arc-search"
    "emanix/arc-search-vault"
    "emanix/arc-search-options"
    "emanix/arc-command-map"
  ])
  ++ [
    {
      ok = !(lib.hasInfix ''(keymap-set global-map "C-c i" arc-command-map)'' text);
      message = "emanix-arc.el binds ARC's internal command map directly";
    }
    {
      ok = lib.hasInfix ''(require 'arc-search-ui nil :no-error)'' text;
      message = "emanix-arc.el no longer keeps the newer search UI optional";
    }
  ];

  failures = builtins.filter (p: !p.ok) problems;

  message = ''
    emanix-arc-glue: ${toString (builtins.length failures)} assertion(s)
    over emanix-arc.el fail, so evaluation stops here rather than building:

    ${lib.concatStringsSep "\n" (map (p: "  - ${p.message}") failures)}
  '';
in
if failures != [ ] then throw message else pkgs.runCommand "arc-glue-sane" { } "touch $out"
