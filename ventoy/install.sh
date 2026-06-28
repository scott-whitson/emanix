#!/usr/bin/env bash
# install.sh — fresh-machine bootstrap: pull dotfiles from GitHub, then install.
#
# Breaks the cold-start chicken-and-egg (a fresh box has no SSH key, so it can't
# clone the private repo) with a READ-ONLY fine-grained GitHub PAT used over
# HTTPS for the first clone only. The dotfiles contain no secrets, so the token's
# blast radius is read-only access to config — safe to store on the USB.
#
# Token resolution order:
#   1. $GITHUB_TOKEN environment variable
#   2. a `github-token` file next to this script (on the USB; gitignored)
#   3. interactive prompt (the web path: curl -fsSL https://scottwhitson.com/install | bash)
#
# After the clone, origin is switched to the clean SSH URL so future push/pull
# uses keys (run `dot-github-key` once to provision a key on machines that
# author config). install.sh itself does not pull, so no key is needed yet.
#
# Usage:
#   ./install.sh [--profile <server|desktop|wsl>]   # USB / local
#   curl -fsSL https://scottwhitson.com/install | bash
set -euo pipefail

OWNER_REPO="scott-whitson/dotfiles"
REPO_SSH="git@github.com:${OWNER_REPO}.git"
TARGET="${TARGET:-$HOME/dotfiles}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "$PWD")"

msg()  { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install]\033[0m %s\n' "$*" >&2; exit 1; }

# --- prerequisites ---
if ! command -v git >/dev/null 2>&1; then
	msg "installing git + ca-certificates"
	sudo apt-get update -y && sudo apt-get install -y git ca-certificates
fi

# --- resolve the read-only token ---
token="${GITHUB_TOKEN:-}"
if [[ -z "$token" && -f "$SCRIPT_DIR/github-token" ]]; then
	token="$(tr -d '[:space:]' < "$SCRIPT_DIR/github-token")"
	msg "using token from $SCRIPT_DIR/github-token"
fi
if [[ -z "$token" ]]; then
	read -rsp 'GitHub read-only token (fine-grained, contents:read): ' token
	echo
fi
[[ -n "$token" ]] || die "no GitHub token provided (env GITHUB_TOKEN, github-token file, or prompt)"

# --- clone over HTTPS + token (no SSH key needed) ---
if [[ -d "$TARGET/.git" ]]; then
	msg "dotfiles already present at $TARGET — leaving as-is"
else
	[[ -e "$TARGET" ]] && die "$TARGET exists but is not a git repo; move it aside first"
	msg "cloning $OWNER_REPO over HTTPS (read-only token)"
	git clone "https://oauth2:${token}@github.com/${OWNER_REPO}.git" "$TARGET"
	# Don't persist the token in .git/config — switch to the clean SSH URL.
	git -C "$TARGET" remote set-url origin "$REPO_SSH"
	msg "origin set to $REPO_SSH (run dot-github-key to provision a key for push)"
fi

# --- run the profile installer (auto-detects host -> profile) ---
msg "running install.sh"
cd "$TARGET"
exec ./install.sh "$@"
