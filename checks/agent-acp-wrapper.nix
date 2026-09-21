# The Emacs daemon runs under systemd with a minimal PATH. An adapter that
# resolves `node' through PATH -- or relies on the payload's own
# `#!/usr/bin/env node' shebang -- works in a terminal and dies in the daemon.
# That is the same trap emacs/config.el:786 documents for ~/.local/bin/claude,
# and it is invisible until the day you need the agent.
#
# So this check does not read the wrapper, it RUNS it. Both wrappers: they come
# from one generator, and a generator is exactly the thing that can be correct
# for its first caller and wrong for its second.
{ pkgs, ... }:
let
  wrappers = import ../agent-acp/wrappers.nix { inherit pkgs; };
in
pkgs.runCommand "agent-acp-wrapper" { } ''
  export HOME=$(mktemp -d)
  export XDG_DATA_HOME="$HOME/.local/share"

  check_adapter() {
    adapter="$1"
    name="$2"
    fix="$3"

    # 1. node must be a store path, not a PATH lookup.
    if ! grep -q '/nix/store/.*/bin/node' "$adapter"; then
      echo "$name does not exec a store-pinned node" >&2
      exit 1
    fi
    if grep -qE 'env node|exec node ' "$adapter"; then
      echo "$name resolves node through PATH" >&2
      exit 1
    fi

    # 2. With no payload installed it must fail loudly and name the fix, rather
    #    than emitting a node error about a missing file.
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

  # 3. The pi adapter spawns `pi', which this DISTRIBUTION does not install --
  #    pi-coding-agent is a personal-layer choice. So the wrapper must resolve
  #    it at runtime and refuse with an explanation, never pin a store path and
  #    never let node fail with something about a missing subprocess.
  if grep -q '/nix/store/.*/bin/pi ' ${wrappers.piAdapter}/bin/pi-acp; then
    echo "pi-acp pins pi by store path; pi belongs to the personal layer" >&2
    exit 1
  fi
  if ! grep -q 'command -v pi ' ${wrappers.piAdapter}/bin/pi-acp; then
    echo "pi-acp does not check that pi is on PATH before running" >&2
    exit 1
  fi

  touch $out
''
