#!/usr/bin/env bash
# install/06-tools.sh — uv tools/, window-picker build, Node, kickstart.nvim bootstrap
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

ensure_fragpaper_font() {
	local want=/usr/share/fonts/TTF/DejaVuSansMono.ttf
	local have=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf
	if [[ -e "$want" ]]; then
		return 0
	fi
	if [[ -r "$have" ]]; then
		log "creating fragpaper font path shim"
		sudo install -d /usr/share/fonts/TTF
		sudo ln -sf "$have" "$want"
	fi
}

# --- fragpaper source clone + install ---
# Source lives in ~/projects/fragpaper (local repo); installed runtime lands in ~/.local/opt/fragpaper.
# Shaders are copied into ~/.local/share/fragpaper/shaders so launcher never depends on repo checkout.
FRAGPAPER_SRC="${FRAGPAPER_SRC:-$HOME/projects/fragpaper}"
FRAGPAPER_OPT="${FRAGPAPER_OPT:-$HOME/.local/opt/fragpaper}"
FRAGPAPER_SHARE="${FRAGPAPER_SHARE:-$HOME/.local/share/fragpaper}"
FRAGPAPER_REPO="${FRAGPAPER_REPO:-https://github.com/scott-whitson/fragpaper.git}"

if [[ -d "$FRAGPAPER_SRC/.git" ]]; then
	log "fragpaper source already present at $FRAGPAPER_SRC"
else
	log "fragpaper source missing; cloning into $FRAGPAPER_SRC"
	mkdir -p "$(dirname "$FRAGPAPER_SRC")"
	if ! clone_if_missing "$FRAGPAPER_REPO" "$FRAGPAPER_SRC"; then
		warn "fragpaper clone failed; skipping optional fragpaper install"
		FRAGPAPER_SRC=""
	fi
fi

if [[ -n "$FRAGPAPER_SRC" && -d "$FRAGPAPER_SRC" ]]; then
	ensure_fragpaper_font
	log "building fragpaper release"
	if (cd "$FRAGPAPER_SRC" && cargo build --release --locked); then
		install -d -m 0755 "$FRAGPAPER_OPT/bin" "$FRAGPAPER_SHARE/shaders"
		install -m 0755 "$FRAGPAPER_SRC/target/release/fragpaper" "$FRAGPAPER_OPT/bin/fragpaper"
		if [[ -d "$FRAGPAPER_SRC/shaders" ]]; then
			rsync -a --delete "$FRAGPAPER_SRC/shaders/" "$FRAGPAPER_SHARE/shaders/"
		else
			warn "fragpaper shaders dir missing; keeping existing shader assets"
		fi
	else
		warn "fragpaper build failed; skipping optional fragpaper install"
	fi
fi

# --- Build tools/window-picker (Rust binary) ---
WP_DIR="$DOTFILES/tools/window-picker"
WP_BIN="$WP_DIR/target/release/window-picker"
if [[ -d "$WP_DIR" ]]; then
	if [[ ! -x "$WP_BIN" ]]; then
		log "building window-picker (Rust release)"
		if ! (cd "$WP_DIR" && cargo build --release); then
			warn "window-picker build failed; skipping optional binary"
		fi
	else
		log "window-picker already built"
	fi
fi

# --- Node for npm global tools like pi ---
if ! command -v node &>/dev/null; then
	warn "node missing; install nodejs via apt in 01-core.sh"
fi
if ! command -v npm &>/dev/null; then
	warn "npm missing; install npm via apt in 01-core.sh"
fi

# --- kickstart.nvim bootstrap ---
NVIM_DIR="$HOME/.config/nvim"
KICKSTART_URL="https://github.com/nvim-lua/kickstart.nvim.git"
# NOTE: once Scott forks kickstart on his own GitHub, swap the URL above for
# his fork's clone URL. The fork is the intended long-term source.

if [[ ! -d "$NVIM_DIR" ]] || [[ -z "$(ls -A "$NVIM_DIR" 2>/dev/null)" ]]; then
	log "cloning kickstart.nvim to $NVIM_DIR"
	if ! GIT_TERMINAL_PROMPT=0 clone_if_missing "$KICKSTART_URL" "$NVIM_DIR"; then
		warn "kickstart clone failed; skipping optional nvim bootstrap"
	fi
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
		printf '\n-- Dotfiles theme opt-in (see themes/*/nvim.lua)\n%s\n' "$OPT_IN_LINE" >>"$INIT_LUA"
	else
		log "theme opt-in line already present in init.lua"
	fi
else
	warn "no init.lua at $INIT_LUA; theme opt-in not injected"
fi
