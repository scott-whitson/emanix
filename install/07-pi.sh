#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# Pi coding agent install + client config sync on workstation and server.
# Actual files live in dotfiles source tree and are stowed into ~/.pi.

ensure_node_npm() {
	if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
		return 0
	fi
	log "node/npm missing; installing nodejs + npm from apt"
	need_pkg nodejs npm
	if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
		die "node/npm still missing after apt install; check PATH and apt state"
	fi
}

ensure_node_npm

PI_AGENT_DIR="$HOME/.local/lib/node_modules/@earendil-works/pi-coding-agent"
PI_AGENT_CLI="$PI_AGENT_DIR/dist/cli.js"

if [[ ! -r "$PI_AGENT_CLI" ]] || ! timeout 5s node "$PI_AGENT_CLI" --version >/dev/null 2>&1; then
	log "installing pi coding agent via npm"
	npm install -g --prefix "$HOME/.local" --ignore-scripts @earendil-works/pi-coding-agent
else
	log "pi coding agent already installed and healthy: $PI_AGENT_CLI"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

printf '%s\n' "Pi config source: ${ROOT_DIR}"
printf '%s\n' "Ensure ~/.pi/agent/settings.json is stowed from dotfiles source."
printf '%s\n' "Set HONCHO_URL to http://datacore.scottwhitson.ts.net:8008 on both machines."
