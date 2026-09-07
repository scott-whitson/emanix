# The Emacs daemon runs under systemd with a minimal PATH. An adapter that
# resolves `node' through PATH -- or relies on the payload's own
# `#!/usr/bin/env node' shebang -- works in a terminal and dies in the daemon.
# That is the same trap emacs/config.el:786 documents for ~/.local/bin/claude,
# and it is invisible until the day you need the agent.
#
# So this check does not read the wrapper, it RUNS it.
{ pkgs, ... }:
let
  wrappers = import ../ioshi/i-intelligence/agent-acp/wrappers.nix { inherit pkgs; };
in
pkgs.runCommand "agent-acp-wrapper" { } ''
  adapter=${wrappers.adapter}/bin/claude-agent-acp

  # 1. node must be a store path, not a PATH lookup.
  if ! grep -q '/nix/store/.*/bin/node' "$adapter"; then
    echo "claude-agent-acp does not exec a store-pinned node" >&2
    exit 1
  fi
  if grep -qE 'env node|exec node ' "$adapter"; then
    echo "claude-agent-acp resolves node through PATH" >&2
    exit 1
  fi

  # 2. With no payload installed it must fail loudly and name the fix, rather
  #    than emitting a node error about a missing file.
  export HOME=$(mktemp -d)
  export XDG_DATA_HOME="$HOME/.local/share"
  set +e
  msg=$("$adapter" --version 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "adapter reported success with no payload installed" >&2
    exit 1
  fi
  case "$msg" in
    *claude-acp-update*) : ;;
    *) echo "adapter did not name its fix; it said: $msg" >&2; exit 1 ;;
  esac

  touch $out
''
