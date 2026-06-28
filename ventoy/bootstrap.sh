#!/usr/bin/env bash
# ventoy/bootstrap.sh — portable first-run installer
#
# Flow:
#   1. Read GitHub PAT from .pat file on this USB (or prompt)
#   2. Prompt for profile (desktop / server / wsl; default desktop)
#   3. Clone dotfiles from GitHub
#   4. Run ./install.sh --profile <name>
#
# USB layout:
#   ventoy/
#   ├── bootstrap.sh      # this script
#   ├── .pat              # GitHub personal access token (chmod 600)
#   └── README.md
#
# Usage:
#   ./bootstrap.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${TARGET_DIR:-$HOME/dotfiles}"
PROFILE=""
PAT_FILE="${SCRIPT_DIR}/.pat"

msg() { printf '\033[1;34m[ventoy]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ventoy]\033[0m %s\n' "$*" >&2; }
die() {
	printf '\033[1;31m[ventoy]\033[0m %s\n' "$*" >&2
	exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
	cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --profile <name>    desktop | server | wsl (default: prompt)
  --target <dir>      install dotfiles into (default: ~/dotfiles)
  -h, --help          show help
EOF
}

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
	case "$1" in
	--profile)
		PROFILE="$2"
		shift 2
		;;
	--target)
		TARGET_DIR="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		die "unknown arg: $1"
		;;
	esac
done

msg "Ventoy bootstrap starting"

# --- Prerequisites ---
for bin in curl git ssh; do
	have "$bin" || die "missing required tool: $bin (install via your package manager)"
done

# --- Read PAT ---
GITHUB_PAT=""
if [[ -f "$PAT_FILE" ]]; then
	GITHUB_PAT="$(cat "$PAT_FILE")"
	msg "read GitHub PAT from .pat"
else
	warn "no .pat file found at $PAT_FILE"
	warn "get a PAT at https://github.com/settings/tokens"
	read -rsp 'GitHub PAT: ' GITHUB_PAT
	echo
	[[ -n "$GITHUB_PAT" ]] || die "PAT is required"
fi

# --- Profile selection ---
if [[ -z "$PROFILE" ]]; then
	echo ""
	echo "Select profile:"
	echo "  1) desktop  — full workstation with Hyprland"
	echo "  2) server   — headless Debian server"
	echo "  3) wsl      — Debian under Windows"
	echo ""
	read -rp 'Profile [1]: ' choice
	case "${choice:-1}" in
	1) PROFILE="desktop" ;;
	2) PROFILE="server" ;;
	3) PROFILE="wsl" ;;
	*) PROFILE="desktop" ;;
	esac
fi

case "$PROFILE" in
desktop | server | wsl) ;;
*)
	die "unknown profile: $PROFILE (expected desktop, server, or wsl)"
	;;
esac
msg "profile: $PROFILE"

# --- Clone dotfiles ---
CLONE_URL="https://${GITHUB_PAT}@github.com/scott-whitson/dotfiles.git"

if [[ -d "$TARGET_DIR/.git" ]]; then
	msg "dotfiles already present at $TARGET_DIR; pulling latest"
	cd "$TARGET_DIR"
	git pull --ff-only origin main || warn "pull failed; continuing with existing copy"
else
	if [[ -e "$TARGET_DIR" ]]; then
		warn "existing $TARGET_DIR is not a git repo; moving aside"
		mv "$TARGET_DIR" "$TARGET_DIR.pre-ventoy.$(date +%Y%m%d%H%M%S)"
	fi
	msg "cloning dotfiles from GitHub"
	git clone "$CLONE_URL" "$TARGET_DIR"
fi

# --- Run installer ---
msg "running install.sh --profile $PROFILE"
cd "$TARGET_DIR"
exec ./install.sh --profile "$PROFILE"
