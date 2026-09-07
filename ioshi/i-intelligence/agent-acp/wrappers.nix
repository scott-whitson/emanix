# The ACP adapter's runtime, split out from the Home Manager module so
# checks/agent-acp-wrapper.nix can build and RUN these with nothing but pkgs.
# A check that cannot execute the script it guards only guards its existence.
#
# The payload is imperative on purpose, following dotfiles' cpgw.nix: "Nix
# supplies the JVM and the units, not the payload." claude-agent-acp published
# 0.75.1 two days before this was written, and a pinned npmDepsHash would
# silently hold back Claude Code features behind a hash nobody remembers to
# bump. Nix supplies node and these wrappers; npm supplies the rest.
{ pkgs }:
let
  package = "@agentclientprotocol/claude-agent-acp";
  entryPath = "lib/node_modules/@agentclientprotocol/claude-agent-acp/dist/index.js";
in
{
  adapter = pkgs.writeShellScriptBin "claude-agent-acp" ''
    set -eu
    state="''${XDG_DATA_HOME:-$HOME/.local/share}/claude-agent-acp"
    entry="$state/${entryPath}"
    if [ ! -f "$entry" ]; then
      echo "claude-agent-acp: adapter payload is not installed at $entry" >&2
      echo "Run: claude-acp-update" >&2
      exit 127
    fi
    # node by store path, never the payload's own env-shebang: see
    # checks/agent-acp-wrapper.nix for why this is the whole point.
    exec ${pkgs.nodejs}/bin/node "$entry" "$@"
  '';

  updater = pkgs.writeShellScriptBin "claude-acp-update" ''
    set -eu
    state="''${XDG_DATA_HOME:-$HOME/.local/share}/claude-agent-acp"
    mkdir -p "$state"
    echo "Installing ${package} into $state" >&2
    exec ${pkgs.nodejs}/bin/npm install --global --prefix "$state" ${package}
  '';
}
