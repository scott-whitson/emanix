#!/usr/bin/env bash
# install.sh — orchestrator that runs install/*.sh according to a profile.
#
# Usage:
#   ./install.sh [--profile <name>]
#   DOTFILES_PROFILE=wsl ./install.sh
#
# Profiles live under install/profiles/*.sh and define which numbered install
# scripts should run for the current environment.

set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
export DOTFILES

profile_arg=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--profile)
		[[ $# -ge 2 ]] || {
			echo "install.sh: --profile requires a value" >&2
			exit 2
		}
		profile_arg="$2"
		shift 2
		;;
	--profile=*)
		profile_arg="${1#*=}"
		shift
		;;
	-h | --help)
		echo "Usage: ./install.sh [--profile <name>]"
		echo "       DOTFILES_PROFILE=<name> ./install.sh"
		echo ""
		echo "Available profiles: server, desktop, wsl"
		exit 0
		;;
	*)
		echo "install.sh: unknown arg '$1'" >&2
		echo "Usage: ./install.sh [--profile <name>]" >&2
		exit 2
		;;
	esac
done

source "$DOTFILES/install/_common.sh"

profile="${profile_arg:-${DOTFILES_PROFILE:-$(default_dotfiles_profile)}}"
load_profile_manifest "$profile"

export PROFILE_NAME PROFILE_DESCRIPTION PROFILE_ENABLE_FRAGPAPER PROFILE_FRAGPAPER_SRC PROFILE_BASE_STOW_SKIP PROFILE_SERVICE_SKIP_PREFIXES PROFILE_SYNC_PULL_ONLY
export DOTFILES_PROFILE="$profile"

# Pull-only machines (e.g. the work WSL box) consume dotfiles but never push;
# dot-sync reads this marker. Profiles set PROFILE_SYNC_PULL_ONLY=1 to opt in.
dotfiles_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"
if [[ "${PROFILE_SYNC_PULL_ONLY:-0}" == 1 ]]; then
	mkdir -p "$dotfiles_cfg"
	touch "$dotfiles_cfg/pull-only"
else
	rm -f "$dotfiles_cfg/pull-only"
fi

printf '=== dotfiles bootstrap (%s) ===\n' "$profile"
if [[ -n "${PROFILE_DESCRIPTION:-}" ]]; then
	printf 'Profile: %s\n' "$PROFILE_DESCRIPTION"
fi

for script_name in "${PROFILE_SCRIPTS[@]}"; do
	script="$DOTFILES/install/${script_name}.sh"
	if [[ ! -f "$script" ]]; then
		echo "install.sh: missing script $script" >&2
		exit 1
	fi
	printf '\n>>> %s\n' "$(basename "$script")"
	bash "$script"
done

printf '\n=== Done! ===\n'
printf 'Manual steps:\n'
printf '  1. Log out and back in for zsh to take effect\n'
