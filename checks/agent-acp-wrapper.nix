# The Emacs daemon runs under systemd with a minimal PATH. An adapter that
# resolves `node' through PATH -- or relies on the payload's own
# `#!/usr/bin/env node' shebang -- works in a terminal and dies in the daemon.
# That is the same trap that hides ~/.local/bin/claude from the daemon
# (see the adapter lookup in emacs/lisp/emanix-agent-shell.el),
# and it is invisible until the day you need the agent.
#
# SPLIT BY WHAT THE ASSERTION NEEDS:
#
#   * The invariant greps below are decided at EVALUATION time and `throw'n
#     there, so `nix flake check --no-build' -- the gate that runs on every
#     pull request -- reports a broken wrapper without building it. Same idiom
#     as checks/retired-names.nix.
#   * The behavioural assertions can only fail when the check is BUILT: they
#     run each wrapper with no payload and require a non-zero exit whose
#     message names the repair command. Execution cannot happen at evaluation,
#     so they stay in the runCommand below.
#
# The greps read the wrapper SOURCE TEXT at evaluation, not a built file:
# pkgs.writeShellScriptBin returns a derivation that carries its script as
# `.text', so `wrappers.piAdapter.text' is the same text the built
# /bin/pi-acp holds. Reading the built path instead would be
# import-from-derivation, which docs/decisions/ewm-patches.md records this
# repository removing -- it makes `--no-build' unable to evaluate the flake.
#
# Both wrappers are checked: they come from one generator, and a generator is
# exactly the thing that can be correct for its first caller and wrong for its
# second.
{ pkgs, ... }:
let
  inherit (pkgs) lib;

  wrappers = import ../agent-acp/wrappers.nix { inherit pkgs; };
  claudeScript = wrappers.adapter.text;
  piScript = wrappers.piAdapter.text;

  # `builtins.match' anchors its pattern at BOTH ends, so a search is written
  # `.*pattern.*' and an alternation must be parenthesised to stay a search.
  lineMatches = re: s: builtins.match re s != null;

  # check_adapter's two greps, run against both adapters.
  nodeProblems = name: script: [
    # 1. node must be a store path, not a PATH lookup.
    {
      ok = lineMatches ''.*/nix/store/.*/bin/node.*'' script;
      message = "${name} does not exec a store-pinned node";
    }
    {
      ok = !(lineMatches ''.*(env node|exec node ).*'' script);
      message = "${name} resolves node through PATH";
    }
  ];

  # 3. The pi adapter spawns `pi', which this DISTRIBUTION does not install --
  #    pi-coding-agent is a personal-layer choice. So the wrapper must resolve
  #    it at runtime and refuse with an explanation, never pin a store path and
  #    never let node fail with something about a missing subprocess.
  piProblems = [
    {
      ok = !(lineMatches ''.*/nix/store/.*/bin/pi .*'' piScript);
      message = "pi-acp pins pi by store path; pi belongs to the personal layer";
    }
    {
      ok = lineMatches ''.*command -v pi .*'' piScript;
      message = "pi-acp does not check that pi is on PATH before running";
    }
  ];

  problems =
    nodeProblems "claude-agent-acp" claudeScript
    ++ nodeProblems "pi-acp" piScript
    ++ piProblems;

  failures = builtins.filter (p: !p.ok) problems;

  message = ''
    emanix-agent-acp-wrapper: ${toString (builtins.length failures)}
    assertion(s) over the generated ACP adapters fail, so evaluation stops
    here rather than building:

    ${lib.concatStringsSep "\n" (map (p: "  - ${p.message}") failures)}
  '';
in
if failures != [ ] then
  throw message
else
  pkgs.runCommand "agent-acp-wrapper" { } ''
    # The behavioural half, and the only part left that the PR gate cannot
    # see: it needs the wrapper EXECUTED, which evaluation cannot do. The
    # invariant greps it used to carry are decided above.
    export HOME=$(mktemp -d)
    export XDG_DATA_HOME="$HOME/.local/share"

    check_adapter() {
      adapter="$1"
      name="$2"
      fix="$3"

      # With no payload installed it must fail loudly and name the fix, rather
      # than emitting a node error about a missing file.
      set +e
      msg=$("$adapter" --version 2>&1)
      rc=$?
      set -e
      if [ "$rc" -eq 0 ]; then
        echo "$name reported success with no payload installed" >&2
        exit 1
      fi
      case "$msg" in
        *"$fix"*) : ;;
        *) echo "$name did not name its fix ($fix); it said: $msg" >&2; exit 1 ;;
      esac
    }

    check_adapter ${wrappers.adapter}/bin/claude-agent-acp claude-agent-acp claude-acp-update
    check_adapter ${wrappers.piAdapter}/bin/pi-acp pi-acp pi-acp-update

    touch $out
  ''
