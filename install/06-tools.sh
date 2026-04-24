#!/usr/bin/env bash
# install/06-tools.sh — uv tools/, window-picker build, nvm+Node, kickstart.nvim bootstrap
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# --- uv sync the tools/ project ---
if [[ -f "$DOTFILES/tools/pyproject.toml" ]]; then
    log "uv sync tools/"
    (cd "$DOTFILES/tools" && uv sync --quiet)
else
    warn "tools/pyproject.toml not found; skipping uv sync"
fi

# Wrapper scripts are expected at $DOTFILES/base/bin/.local/bin/ (stowed later).
# The tools/ project exposes them via uv-managed entry points; no symlinks needed
# beyond what base/bin/ already provides.

# --- Build tools/window-picker (Rust binary) — workstation only ---
if profile_is workstation; then
    WP_DIR="$DOTFILES/tools/window-picker"
    WP_BIN="$WP_DIR/target/release/window-picker"
    if [[ -d "$WP_DIR" ]]; then
        if [[ ! -x "$WP_BIN" ]]; then
            log "building window-picker (Rust release)"
            (cd "$WP_DIR" && cargo build --release)
        else
            log "window-picker already built"
        fi
    fi
fi

# --- nvm + Node LTS (Claude Code is an npm package, needs Node) ---
export NVM_DIR="$HOME/.nvm"
if [[ ! -d "$NVM_DIR" ]]; then
    log "installing nvm"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi
# shellcheck source=/dev/null
. "$NVM_DIR/nvm.sh"
if ! command -v node &>/dev/null; then
    log "installing Node LTS via nvm"
    nvm install --lts
fi

# --- kickstart.nvim bootstrap ---
NVIM_DIR="$HOME/.config/nvim"
KICKSTART_URL="https://github.com/nvim-lua/kickstart.nvim.git"
# NOTE: once Scott forks kickstart on his own GitHub, swap the URL above for
# his fork's clone URL. The fork is the intended long-term source.

if [[ ! -d "$NVIM_DIR" ]] || [[ -z "$(ls -A "$NVIM_DIR" 2>/dev/null)" ]]; then
    log "cloning kickstart.nvim to $NVIM_DIR"
    git clone "$KICKSTART_URL" "$NVIM_DIR"
else
    log "nvim config directory already exists; skipping kickstart clone"
fi

# Ensure the theme opt-in line is present at the end of init.lua.
# Idempotent: only appends if the line isn't already there.
INIT_LUA="$NVIM_DIR/init.lua"
OPT_IN_LINE="pcall(require, 'dotfiles-theme')"
if [[ -f "$INIT_LUA" ]]; then
    if ! grep -qF "$OPT_IN_LINE" "$INIT_LUA"; then
        log "appending theme opt-in to $INIT_LUA"
        printf '\n-- Dotfiles theme opt-in (see themes/*/nvim.lua)\n%s\n' "$OPT_IN_LINE" >> "$INIT_LUA"
    else
        log "theme opt-in line already present in init.lua"
    fi
else
    warn "no init.lua at $INIT_LUA; theme opt-in not injected"
fi
