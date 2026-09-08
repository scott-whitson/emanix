# The ACP adapters' runtime, split out from the Home Manager module so
# checks/agent-acp-wrapper.nix can build and RUN these with nothing but pkgs.
# A check that cannot execute the script it guards only guards its existence.
#
# The payloads are imperative on purpose, following dotfiles' cpgw.nix: "Nix
# supplies the JVM and the units, not the payload." claude-agent-acp published
# 0.75.1 two days before this was written, and a pinned npmDepsHash would
# silently hold back Claude Code features behind a hash nobody remembers to
# bump. Nix supplies node and these wrappers; npm supplies the rest.
{ pkgs }:
let
  # One shape, two adapters, written as a function rather than copied twice.
  # The escaping here -- `''${' for a literal `${', node by store path -- is
  # exactly the kind of detail that drifts when it is duplicated, and the
  # difference is invisible until a daemon cannot start an agent.
  mkAcpAdapter =
    { command # the binary name Emacs resolves with `executable-find'
    , updateCommand # the companion that installs/refreshes the payload
    , package # the npm package
    , stateName # directory under XDG_DATA_HOME holding the payload
    , entry # the JS entry point, relative to the npm prefix
    , needs ? [ ] # executables the adapter itself spawns
    }:
    let
      # ''${HOME:-}, not $HOME: `set -u' would otherwise abort on "unbound
      # variable" before the friendly message ever runs, in exactly the
      # stripped environment (a systemd unit with no HOME) where that message
      # is the only clue anyone gets.
      stateExpr = ''"''${XDG_DATA_HOME:-''${HOME:-}/.local/share}/${stateName}"'';

      # An adapter that shells out to a CLI this distribution does not install
      # must say so itself. pi-coding-agent lives in the PERSONAL layer
      # (dotfiles/home/scott/default.nix), because which AI harness to run is a
      # personal choice -- so emanix must not pin its store path, and the only
      # honest alternative is to resolve it at runtime and fail loudly.
      needsChecks = pkgs.lib.concatMapStrings
        (bin: ''
          if ! command -v ${bin} >/dev/null 2>&1; then
            echo "${command}: ${bin} is not on PATH, and ${package} runs it as a subprocess" >&2
            exit 127
          fi
        '')
        needs;
    in
    {
      adapter = pkgs.writeShellScriptBin command ''
        set -eu
        state=${stateExpr}
        entry="$state/${entry}"
        if [ ! -f "$entry" ]; then
          echo "${command}: adapter payload is not installed at $entry" >&2
          echo "Run: ${updateCommand}" >&2
          exit 127
        fi
        ${needsChecks}
        # node by store path, never the payload's own env-shebang: see
        # checks/agent-acp-wrapper.nix for why this is the whole point.
        exec ${pkgs.nodejs}/bin/node "$entry" "$@"
      '';

      updater = pkgs.writeShellScriptBin updateCommand ''
        set -eu
        state=${stateExpr}
        mkdir -p "$state"
        echo "Installing ${package} into $state" >&2
        exec ${pkgs.nodejs}/bin/npm install --global --prefix "$state" ${package}
      '';
    };

  claude = mkAcpAdapter {
    command = "claude-agent-acp";
    updateCommand = "claude-acp-update";
    package = "@agentclientprotocol/claude-agent-acp";
    stateName = "claude-agent-acp";
    entry = "lib/node_modules/@agentclientprotocol/claude-agent-acp/dist/index.js";
  };

  # pi's ACP story is not Claude's. Claude has one official adapter on the
  # Agent SDK; pi has no first-party ACP mode at all (0.81/0.84 offer
  # `--mode rpc' and nothing else), and `pi-acp' is the one community adapter
  # actually published to npm -- it spawns `pi --mode rpc' and bridges. Its own
  # README calls it MVP-style: no filesystem or terminal delegation, MCP not
  # wired through. It is therefore expected to leave buffers stale exactly as
  # claude-agent-acp does, which is why the sync patch in emanix-agent-shell.el
  # is written against the event stream rather than against one agent.
  pi = mkAcpAdapter {
    command = "pi-acp";
    updateCommand = "pi-acp-update";
    package = "pi-acp";
    stateName = "pi-acp";
    entry = "lib/node_modules/pi-acp/dist/index.js";
    needs = [ "pi" ];
  };
in
{
  # `adapter'/`updater' keep their original names: checks/agent-acp-wrapper.nix
  # and the Home Manager module both already reference them.
  inherit (claude) adapter updater;
  piAdapter = pi.adapter;
  piUpdater = pi.updater;
}
