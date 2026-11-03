# The welcome buffer is the first thing a new user reads, so a key it
# advertises that does not exist is worse than no buffer at all.
#
# This guards the failure that actually happened to the docs: emanix.net
# published an assistant that was no longer there. Nothing detected it because
# nothing compared what the docs claimed against what the code did.
#
# It does NOT generate the buffer from the bindings, and deliberately so. Two
# thirds of the documented super-key surface is EWM upstream's keymap in the
# ewm input, not in this repo; fallback.el is a second, intentional definition
# site; and the manual's rows aggregate many bindings each while its prose
# explains rather than lists. Generation would have to discard all of that.
# Checking is cheap and loses nothing.
#
# Evaluated, never built. Every assertion is `throw'n at EVALUATION time so
# `nix flake check --no-build' -- the gate that runs on every pull request --
# reports it; an `exit 1' inside a build script could not. Same idiom as
# checks/retired-names.nix. The extraction `grep -oE' is a scanner here
# because Nix has no find-all regex.
{ pkgs, ... }:
let
  inherit (pkgs) lib;

  welcomeSrc = ../emacs/lisp/emanix-welcome.el;
  welcome = builtins.readFile welcomeSrc;
  welcomeLines = lib.splitString "\n" welcome;

  # The two files a live binding form may sit in. config.el is the distro's
  # own; fallback.el is a second, intentional definition site.
  bindingTexts = [
    (builtins.readFile ../emacs/config.el)
    (builtins.readFile ../emacs/fallback.el)
  ];

  # `builtins.match' anchors its pattern at BOTH ends, so `.*pattern.*' is an
  # unanchored search and the result is null when the line does not match.
  lineMatches = re: line: builtins.match re line != null;
  anyLineMatches = re: ls: lib.any (lineMatches re) ls;

  # 3. Every C-* key the buffer advertises must be bound by a LIVE binding form
  #    in the shipped elisp. EWM's own super-keys are not checked: they live in
  #    the ewm input, which this repo cannot see.
  #
  #    The extraction pattern reaches a lowercase prefix plus one
  #    lowercase-or-`?' token and no further -- a digit, an uppercase letter or
  #    a chord like `C-c C-i' is not extracted and will not be seen. Widen it,
  #    and re-run the fail/pass drill, before trusting it on such a row.
  #
  #    KNOWN RESIDUAL GAP: a real code line whose own trailing comment contains
  #    a complete binding shape still matches, because nothing here can tell
  #    where a line's code ends and its comment begins. Nothing in this tree
  #    does that today; closing it needs parsing, not pattern matching.
  #
  #    The four traps found while writing this -- the brief's regex, the
  #    word-splitting loop, substring membership, and a commented-out binding --
  #    are in docs/decisions/welcome-keys-check.md.
  #
  #    grep -oE reimplemented WITHOUT a per-character recursion. Nix has no tail
  #    calls, and one frame per character put this within ~1200 frames of
  #    max-call-depth (10000) on an 8769-character buffer that is expected to
  #    grow -- checks/agent-shell-glue.nix chose builtins.split over a character
  #    walk for the same reason.
  #
  #    Splitting on `C-' is the same leftmost, non-overlapping scan: a key can
  #    only begin where `C-' appears, the pattern is anchored at the start of
  #    each segment, and no key contains a second `C-' to overlap. The trailing
  #    `.*' is what lets `builtins.match' anchor at the start while its one
  #    capture group returns the key alone.
  scanKeys = s:
    lib.concatMap
      (seg:
        let m = builtins.match "(C-[a-z] [a-z?]).*" ("C-" + seg); in
        lib.optional (m != null) (builtins.head m))
      (lib.splitString "C-" s);

  keys = builtins.sort builtins.lessThan (lib.unique (scanKeys welcome));

  # Emacs's own default bindings are exempt: the buffer legitimately points at
  # built-ins, and emanix does not bind these and never should, so demanding a
  # binding form for them would fail on correct code. Deliberately tiny, and NOT
  # an escape hatch -- see docs/decisions/welcome-keys-check.md.
  builtinKeys = [ "C-h i" "C-h b" "C-h k" "C-h f" "C-h v" "C-h m" ];
  advertisedKeys = lib.subtractLists builtinKeys keys;

  # The only regex metacharacter the extraction pattern can hand back is the
  # `?' of a second-token `?', so escaping that one keeps the key literal
  # inside the binding pattern below.
  literalKey = key: lib.replaceStrings [ "?" ] [ "\\?" ] key;

  # Commenting a binding out is the likeliest way one disappears, so a line
  # whose first non-blank character is `;' is dropped before matching, the way
  # the shell's `grep -vE' dropped it. The remaining line must then carry both a
  # binding form and the QUOTED key: a bare mention in prose -- "C-u C-c t =
  # new terminal" -- does not count.
  codeLines = t:
    builtins.filter (l: !(lib.hasPrefix ";" (lib.trim l))) (lib.splitString "\n" t);

  bindingPattern = key:
    ''.*(global-set-key|keymap-global-set|keymap-set|define-key|bind-key)[^"]*"${literalKey key}".*'';

  problems = [
    # 1. No absolute home path. Same rule as checks/agent-shell-glue.nix, same
    #    reason.
    {
      ok = !(anyLineMatches ''.*"/home/[a-z].*'' welcomeLines);
      message = ''emanix-welcome.el contains an absolute home path; derive it from $HOME'';
    }

    # 2. The pre-rename name must not reappear.
    {
      ok = !(lib.hasInfix "eminix" welcome);
      message = "emanix-welcome.el mentions the pre-rename distro name; it is emanix now";
    }
  ]
  # An empty extraction is a guard that has stopped seeing its subject, not a
  # clean bill of health -- if the buffer's render format ever changes so the
  # pattern matches nothing, the per-key assertions below must not be allowed
  # to pass by iterating zero times.
  ++ [
    {
      ok = keys != [ ];
      message = "emanix-welcome.el: no C-* keys were extracted from the buffer text; the extraction pattern no longer matches this file's format";
    }
  ]
  ++ map
    (key: {
      ok = lib.any (t: anyLineMatches (bindingPattern key) (codeLines t)) bindingTexts;
      message = "emanix-welcome.el advertises '${key}' but no live binding form in config.el or fallback.el sets it";
    })
    advertisedKeys
  ++ [
    # 4. The buffer must still name the site. It is the only manual there is,
    #    and a welcome buffer that does not point at it orphans the reader.
    {
      ok = lib.hasInfix "emanix.net" welcome;
      message = "emanix-welcome.el no longer points at emanix.net";
    }
  ]
  # 5. The runtime probes must still be there. Replace either with a constant
  #    and the buffer starts telling a stranger about a path they do not have.
  ++ (map
    (name: {
      ok = lib.hasInfix name welcome;
      message = "emanix-welcome.el no longer defines ${name}";
    })
    [ "emanix-welcome--config-repo" "emanix-welcome--dismissed-file" ]);

  failures = builtins.filter (p: !p.ok) problems;

  message = ''
    emanix-welcome-keys: ${toString (builtins.length failures)} assertion(s)
    over emanix-welcome.el fail, so evaluation stops here rather than building:

    ${lib.concatStringsSep "\n" (map (p: "  - ${p.message}") failures)}
  '';
in
if failures != [ ] then throw message else pkgs.runCommand "emanix-welcome-keys" { } "touch $out"
