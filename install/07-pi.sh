#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# Pi coding agent install + client config sync on workstation and datacore.
# Actual files live in dotfiles source tree and are stowed into ~/.pi.

if ! command -v npm &>/dev/null; then
	die "npm missing; install nodejs npm in 01-core.sh"
fi

if ! command -v pi &>/dev/null; then
	log "installing pi coding agent via npm"
	npm install -g --prefix "$HOME/.local" --ignore-scripts @earendil-works/pi-coding-agent
else
	log "pi already on PATH: $(pi --version 2>&1 | head -1)"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

printf '%s\n' "Pi config source: ${ROOT_DIR}"
printf '%s\n' "Ensure ~/.pi/agent/settings.json is stowed from dotfiles source."
printf '%s\n' "Set HONCHO_URL to http://datacore.scottwhitson.ts.net:8008 on both machines."
