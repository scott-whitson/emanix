# Cheap greps over one file, run on every `nix flake check' rather than whenever
# someone remembers to look.
#
# Each grep guards a failure that is SILENT in practice. A missing autoload
# gives you a keybinding that reports a void function only when you press it.
# A top-level `require' of agent-shell would break checks/agent-shell-sync.nix,
# but only there, so it would look fine on a real host. And the two mixed key
# styles in the tool-call payload fail by matching nothing at all.
#
# Evaluated, never built: every assertion is `throw'n at EVALUATION time, so
# `nix flake check --no-build' -- the pull-request gate -- sees it fail. An
# `exit 1' in a build script could not. Same idiom as checks/retired-names.nix.
{ pkgs, ... }:
let
  inherit (pkgs) lib;

  src = ../emacs/lisp/emanix-agent-shell.el;
  text = builtins.readFile src;
  lines = lib.splitString "\n" text;

  # `builtins.match' anchors its pattern at BOTH ends: an unanchored pattern is
  # written `.*pattern.*' here, and one that began with `^' is written without
  # the leading `.*'. The result is null when the line does not match.
  lineMatches = re: line: builtins.match re line != null;
  anyLineMatches = re: lib.any (lineMatches re) lines;

  # sed 's/;.*//': drop everything from the first `;' on each line, and keep a
  # line with no `;' whole. `[^;]*' cannot cross the first `;', so the single
  # capture group is exactly the text sed would have left behind.
  stripComment = line:
    let m = builtins.match "([^;]*);.*" line;
    in if m == null then line else builtins.head m;
  stripped = lib.concatStringsSep "\n" (map stripComment lines);

  # grep -oF "'path" | wc -l. `builtins.split' finds every occurrence itself and
  # yields one string piece between them, so the count is pieces minus one. It
  # matches left to right without overlap, exactly as grep -o counts; a
  # character-by-character walk in Nix would exceed the call-depth limit on a
  # file this size.
  pathCount = builtins.length (lib.splitString "'path" stripped) - 1;

  readsForm = form: {
    ok = lib.hasInfix form text;
    message = "emanix-agent-shell.el no longer reads the tool call via ${form}";
  };

  problems = [
    # 1. No absolute home path, ever. The distro cannot know the operator's name.
    {
      ok = !(anyLineMatches ''.*"/home/[a-z].*'');
      message = "emanix-agent-shell.el contains an absolute home path";
    }

    # 2. No top-level require of agent-shell. It must stay loadable under the
    #    bare batch Emacs that runs the unit tests.
    {
      ok = !(anyLineMatches ''\(require .agent-shell.*'');
      message = "emanix-agent-shell.el requires agent-shell at top level; use with-eval-after-load";
    }

    # 3. The adapter is found on PATH, never hardcoded to a store path: config.el
    #    is out-of-store live elisp and cannot interpolate nix.
    {
      ok = !(lib.hasInfix ''"/nix/store'' text);
      message = "emanix-agent-shell.el hardcodes a store path";
    }
  ]
  # 4. Every branch of the path extractor must still be READ, not merely
  #    mentioned.
  #
  #    This used to grep for the bare keywords ':raw-input', ':locations',
  #    ':diffs', ':content'. Three of those four could not fail: the function's
  #    own docstring names `:locations', `:raw-input' and `:diffs' in prose, so
  #    deleting the entire `(dolist (d (map-elt tool-call :diffs)) ...)' form
  #    left this check green. Grep for the CODE FORM instead -- prose cannot
  #    satisfy `(map-elt tool-call :diffs)'. And `:file', the key actually read
  #    out of each diff, was guarded by nothing at all; it is guarded now.
  #
  #    These are the literal forms in emanix/agent-shell--tool-call-paths. If
  #    that function is legitimately refactored (renamed locals, a different
  #    accessor), update the strings here deliberately -- do not delete them.
  ++ (map readsForm [
    "(map-elt tool-call :diffs)"
    "(map-elt tool-call :locations)"
    "(map-elt tool-call :content)"
    "(:raw-input file_path)"
    "(map-elt d :file)"
  ])
  ++ [
    # 4b. 'path is read from TWO separate branches (:locations and :content),
    #     each a vector of symbol-keyed alists. A presence-only grep cannot
    #     distinguish one branch from two, so deleting the :content branch
    #     outright would still satisfy every string above -- the check would
    #     pass while the regression shipped. Count the occurrences instead.
    #
    #     Counted over comment-stripped source, for the same reason as 4: the
    #     docstring above the function is free to discuss 'path, and a count
    #     that prose can inflate is a count that cannot fail. The strip drops
    #     everything from the first `;' on each line, which is a safety measure
    #     rather than an exact elisp tokeniser -- the module does contain a `;'
    #     inside a docstring, so a line can be truncated early. Stripping can
    #     therefore only ever UNDERCOUNT, which fails RED and never GREEN: the
    #     direction a guard may be wrong in.
    {
      ok = pathCount >= 2;
      message = "emanix-agent-shell.el reads 'path in fewer than 2 code branches (found ${toString pathCount}); the :locations and :content branches must each read it";
    }

    # 4c. The Claude wrapper C-c C-' is bound to. config.el names
    #     `emanix/agent-shell-claude' and this module is the only definition
    #     site, so losing it costs the primary agent keybinding -- and does so
    #     silently, because config.el requires this feature with :no-error.
    #
    #     `defun' specifically, not merely the symbol: the docstring and
    #     config.el's own comment both name it, so a presence grep would survive
    #     the function being deleted. The wrapper's BEHAVIOUR (that it honours
    #     the prompted directory) is unit-tested in checks/agent-shell-sync.nix
    #     instead, where a batch Emacs can actually call it.
    {
      ok = lib.hasInfix "(defun emanix/agent-shell-claude " text;
      message = "emanix-agent-shell.el no longer defines emanix/agent-shell-claude, which config.el binds to C-c C-'";
    }

    # 4d. The sleep-inhibit latch must still be INSTALLED, not merely defined.
    #     checks/agent-shell-sync.nix unit-tests the function, and would keep
    #     passing with the `advice-add' deleted -- the tests call it directly.
    #     Losing the installation is silent by nature: the only symptom is the
    #     echo-area message storm coming back on hosts where logind refuses to
    #     inhibit, which no check can observe from a build sandbox.
    {
      ok = lib.hasInfix "advice-add 'system-sleep-block-sleep" text;
      message = "emanix-agent-shell.el no longer installs emanix/agent-shell--sleep-block-latch on system-sleep-block-sleep";
    }
  ]
  # 5. The three commands the keybindings name must be autoloaded.
  ++ (map
    (cmd: {
      ok = lib.hasInfix "autoload '${cmd}" text;
      message = "emanix-agent-shell.el does not autoload ${cmd}";
    })
    [
      "agent-shell-anthropic-start-claude-code"
      "agent-shell-pi-start-agent"
      "agent-shell-send-region"
    ]);

  failures = builtins.filter (p: !p.ok) problems;

  message = ''
    emanix-agent-shell-glue: ${toString (builtins.length failures)}
    assertion(s) over emanix-agent-shell.el fail, so evaluation stops here
    rather than building:

    ${lib.concatStringsSep "\n" (map (p: "  - ${p.message}") failures)}
  '';
in
if failures != [ ] then
  throw message
else
  pkgs.runCommand "agent-shell-glue-sane" { } "touch $out"
