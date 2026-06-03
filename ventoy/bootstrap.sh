#!/usr/bin/env bash
# ventoy/bootstrap.sh — portable first-run installer for Debian machines
#
# Use this from Ventoy USB or any removable media that carries a dotfiles copy.
# Optional layout on the USB:
#   ventoy/
#     bootstrap.sh
#     README.md
#     dotfiles/        # optional local mirror of the repo
#
# Flow:
#   1. Join Headscale (optional skip via --no-headscale)
#   2. Get dotfiles from datacore or local USB copy
#   3. Run dotfiles ./bootstrap.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${TARGET_DIR:-$HOME/dotfiles}"
REMOTE_REPO="${REMOTE_REPO:-scott@datacore:~/projects/dotfiles}"
LOCAL_SOURCE="${LOCAL_SOURCE:-$SCRIPT_DIR/dotfiles}"
HEADSCALE_LOGIN_SERVER="${HEADSCALE_LOGIN_SERVER:-}"
HEADSCALE_AUTHKEY="${HEADSCALE_AUTHKEY:-}"
TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-$(hostname -s)}"
JOIN_HEADSCALE=1

msg() { printf '\033[1;34m[ventoy]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ventoy]\033[0m %s\n' "$*" >&2; }
die() {
	printf '\033[1;31m[ventoy]\033[0m %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --target DIR          Install dotfiles into DIR (default: ~/dotfiles)
  --remote URL          Dotfiles clone URL (default: scott@datacore:~/projects/dotfiles)
  --source DIR          Local dotfiles copy on USB (default: $SCRIPT_DIR/dotfiles)
  --login-server URL    Headscale login server URL
  --authkey KEY         Headscale auth key
  --no-headscale        Skip Headscale join step
  -h, --help            Show help
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--target)
		TARGET_DIR="$2"
		shift 2
		;;
	--remote)
		REMOTE_REPO="$2"
		shift 2
		;;
	--source)
		LOCAL_SOURCE="$2"
		shift 2
		;;
	--login-server)
		HEADSCALE_LOGIN_SERVER="$2"
		shift 2
		;;
	--authkey)
		HEADSCALE_AUTHKEY="$2"
		shift 2
		;;
	--no-headscale)
		JOIN_HEADSCALE=0
		shift
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

have_tailscale() {
	command -v tailscale >/dev/null 2>&1
}

ensure_tailscale() {
	if have_tailscale; then
		return 0
	fi
	if ! command -v apt >/dev/null 2>&1; then
		die "tailscale missing and apt unavailable"
	fi
	msg "tailscale missing; installing via apt"
	sudo apt update
	sudo apt install -y tailscale
}

ensure_git() {
	if command -v git >/dev/null 2>&1; then
		return 0
	fi
	if ! command -v apt >/dev/null 2>&1; then
		die "git missing and apt unavailable"
	fi
	msg "git missing; installing git + openssh-client via apt"
	sudo apt update
	sudo apt install -y git openssh-client
}

tailscale_running() {
	have_tailscale || return 1
	tailscale status --json 2>/dev/null | grep -q '"BackendState":"Running"'
}

join_headscale() {
	[[ "$JOIN_HEADSCALE" -eq 1 ]] || {
		warn "Skipping Headscale join (--no-headscale)"
		return 0
	}

	ensure_tailscale

	if [[ -z "$HEADSCALE_LOGIN_SERVER" ]]; then
		read -rp "Headscale login server URL: " HEADSCALE_LOGIN_SERVER
	fi
	[[ -n "$HEADSCALE_LOGIN_SERVER" ]] || die "Headscale login server required"

	if [[ -z "$HEADSCALE_AUTHKEY" ]]; then
		read -rsp "Headscale auth key: " HEADSCALE_AUTHKEY
		echo
	fi
	[[ -n "$HEADSCALE_AUTHKEY" ]] || die "Headscale auth key required"

	if tailscale_running; then
		warn "tailscale backend already running; reconfiguring to Headscale"
	fi

	msg "Joining Headscale as $TAILSCALE_HOSTNAME"
	sudo tailscale up --reset \
		--login-server="$HEADSCALE_LOGIN_SERVER" \
		--authkey="$HEADSCALE_AUTHKEY" \
		--hostname="$TAILSCALE_HOSTNAME"
}

prepare_target_dir() {
	if [[ -d "$TARGET_DIR/.git" ]]; then
		msg "dotfiles already present at $TARGET_DIR"
		return 0
	fi
	if [[ -e "$TARGET_DIR" ]]; then
		local backup="$TARGET_DIR.pre-ventoy.$(date +%Y%m%d%H%M%S)"
		warn "existing $TARGET_DIR is not a git repo; moving aside to $(basename "$backup")"
		mv "$TARGET_DIR" "$backup"
	fi
	mkdir -p "$(dirname "$TARGET_DIR")"
}

acquire_dotfiles() {
	if [[ -d "$TARGET_DIR/.git" ]]; then
		return 0
	fi

	prepare_target_dir

	if [[ -d "$LOCAL_SOURCE/.git" ]]; then
		msg "Copying dotfiles from USB mirror at $LOCAL_SOURCE"
		cp -a "$LOCAL_SOURCE" "$TARGET_DIR"
		return 0
	fi

	ensure_git

	msg "Cloning dotfiles from datacore"
	if git clone "$REMOTE_REPO" "$TARGET_DIR"; then
		return 0
	fi

	if [[ -d "$LOCAL_SOURCE/.git" ]]; then
		warn "datacore clone failed; falling back to USB mirror"
		rm -rf "$TARGET_DIR"
		cp -a "$LOCAL_SOURCE" "$TARGET_DIR"
		return 0
	fi

	die "could not acquire dotfiles from datacore or USB mirror"
}

run_dotfiles_bootstrap() {
	[[ -x "$TARGET_DIR/bootstrap.sh" ]] || die "bootstrap.sh missing in $TARGET_DIR"
	msg "Bootstrapping dotfiles in $TARGET_DIR"
	cd "$TARGET_DIR"
	./bootstrap.sh
}

msg "Ventoy bootstrap starting"
join_headscale
acquire_dotfiles
run_dotfiles_bootstrap
msg "Ventoy bootstrap complete"
