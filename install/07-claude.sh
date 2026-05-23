#!/usr/bin/env bash
# install/07-claude.sh — AI coding CLI (pi + Claude Code) + agent-skills sanity check
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# --- Claude Code CLI (npm global) ---
# nvm must have placed node on PATH by way of 06-tools.sh sourcing nvm.sh.
# Re-source here to be safe when this script is run standalone.
export NVM_DIR="$HOME/.nvm"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"
fi

if ! command -v claude &>/dev/null; then
    log "installing Claude Code CLI via npm"
    npm install -g @anthropic-ai/claude-code
else
    log "Claude Code already on PATH: $(claude --version 2>&1 | head -1)"
fi

# --- Pi coding agent ---
if ! command -v pi &>/dev/null; then
    log "installing pi coding agent via npm"
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent
else
    log "pi already on PATH: $(pi --version 2>&1 | head -1)"
fi

# --- agent-skills sanity check ---
AGENT_SKILLS_DIR="$HOME/projects/agent-skills"
if [[ ! -d "$AGENT_SKILLS_DIR/.git" ]]; then
    warn "$AGENT_SKILLS_DIR is not a git repo."
    warn "  Clone it manually once (repo URL is user-specific):"
    warn "    mkdir -p $HOME/projects"
    warn "    git clone <your-agent-skills-url> $AGENT_SKILLS_DIR"
else
    log "agent-skills present at $AGENT_SKILLS_DIR"
fi
