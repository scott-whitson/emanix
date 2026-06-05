#!/usr/bin/env bash
# install/06-tools.sh — uv tools/, window-picker build, Node, kickstart.nvim bootstrap
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# --- uv sync the tools/ project ---
if [[ -f "$DOTFILES/tools/pyproject.toml" ]]; then
	log "uv sync tools/"
	(cd "$DOTFILES/tools" && uv sync --quiet --locked)
else
	warn "tools/pyproject.toml not found; skipping uv sync"
fi

# Wrapper scripts are expected at $DOTFILES/base/bin/.local/bin/ (stowed later).
# The tools/ project exposes them via uv-managed entry points; no symlinks needed
# beyond what base/bin/ already provides.

# --- fragpaper source clone + install ---
# Canonical development lives in ~/projects/fragpaper on datacore.
# Runtime desktops keep fragpaper as an installed product and cache the
# checkout under ~/.local/share/fragpaper instead of ~/projects.
HOST_NAME="${HOSTNAME%%.*}"
FRAGPAPER_RUNTIME_SRC="$HOME/.local/share/fragpaper"
FRAGPAPER_PROJECT_SRC="$HOME/projects/fragpaper"
if [[ -z "${FRAGPAPER_SRC:-}" ]]; then
	if [[ "$HOST_NAME" == "datacore" ]]; then
		FRAGPAPER_SRC="$FRAGPAPER_PROJECT_SRC"
	else
		FRAGPAPER_SRC="$FRAGPAPER_RUNTIME_SRC"
	fi
fi
FRAGPAPER_OPT="${FRAGPAPER_OPT:-$HOME/.local/opt/fragpaper}"
FRAGPAPER_REPO="${FRAGPAPER_REPO:-https://github.com/scott-whitson/fragpaper.git}"

repo_fingerprint() {
	local root="$1"
	{
		git -C "$root" rev-parse HEAD 2>/dev/null || printf 'missing'
		printf '\n'
		git -C "$root" status --porcelain --untracked-files=all 2>/dev/null || true
	} | cksum | awk '{print $1}'
}

tree_fingerprint() {
	local root="$1"
	{
		find "$root" -type f ! -path "$root/target/*" ! -name '.build-state' -print0 | sort -z | xargs -0 cksum
	} | cksum | awk '{print $1}'
}

if [[ "$HOST_NAME" != "datacore" ]] && [[ -z "${FRAGPAPER_SRC:-}" || "$FRAGPAPER_SRC" == "$FRAGPAPER_RUNTIME_SRC" ]]; then
	if [[ -d "$FRAGPAPER_PROJECT_SRC/.git" ]]; then
		if [[ -d "$FRAGPAPER_RUNTIME_SRC/.git" ]]; then
			log "removing stale fragpaper checkout from ~/projects on runtime desktop"
			rm -rf "$FRAGPAPER_PROJECT_SRC"
		else
			log "migrating fragpaper checkout from ~/projects to ~/.local/share/fragpaper"
			mkdir -p "$(dirname "$FRAGPAPER_RUNTIME_SRC")"
			if mv "$FRAGPAPER_PROJECT_SRC" "$FRAGPAPER_RUNTIME_SRC"; then
				:
			else
				warn "fragpaper migration failed; skipping optional fragpaper install"
				FRAGPAPER_SRC=""
			fi
		fi
	fi
	FRAGPAPER_SRC="$FRAGPAPER_RUNTIME_SRC"
fi

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
	FRAGPAPER_BIN="$FRAGPAPER_OPT/bin/fragpaper"
	FRAGPAPER_STAMP="$FRAGPAPER_OPT/.build-state"
	FRAGPAPER_STATE="$(repo_fingerprint "$FRAGPAPER_SRC")"
	if [[ -x "$FRAGPAPER_BIN" ]] && [[ -f "$FRAGPAPER_STAMP" ]] && [[ "$(cat "$FRAGPAPER_STAMP" 2>/dev/null)" == "$FRAGPAPER_STATE" ]]; then
		log "fragpaper already built at state $FRAGPAPER_STATE"
	else
		log "building fragpaper release"
		if (cd "$FRAGPAPER_SRC" && cargo build --release --locked); then
			install -d -m 0755 "$FRAGPAPER_OPT/bin"
			install -m 0755 "$FRAGPAPER_SRC/target/release/fragpaper" "$FRAGPAPER_BIN"
			printf '%s\n' "$FRAGPAPER_STATE" >"$FRAGPAPER_STAMP"
		else
			warn "fragpaper build failed; skipping optional fragpaper install"
		fi
	fi
fi

# --- Build tools/window-picker (Rust binary) ---
WP_DIR="$DOTFILES/tools/window-picker"
WP_BIN="$WP_DIR/target/release/window-picker"
if [[ -d "$WP_DIR" ]]; then
	if ! pkg-config --exists gtk4-layer-shell-0; then
		warn "gtk4-layer-shell dev package missing; skipping optional window-picker build"
	elif [[ -x "$WP_BIN" ]] && [[ -f "$WP_DIR/.build-state" ]] && [[ "$(cat "$WP_DIR/.build-state" 2>/dev/null)" == "$(tree_fingerprint "$WP_DIR")" ]]; then
		log "window-picker already built at current tree state"
	else
		WP_STAMP="$WP_DIR/.build-state"
		WP_STATE="$(tree_fingerprint "$WP_DIR")"
		log "building window-picker (Rust release)"
		if (cd "$WP_DIR" && cargo build --release --locked); then
			printf '%s\n' "$WP_STATE" >"$WP_STAMP"
		else
			warn "window-picker build failed; skipping optional binary"
		fi
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
