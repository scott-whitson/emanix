#!/usr/bin/env bash
# install/10-theme.sh — apply active theme via dot-theme-set
set -euo pipefail
source "$(dirname "$0")/_common.sh"

ACTIVE_THEME_FILE="$HOME/.config/dotfiles/active-theme"
DEFAULT_THEME="catppuccin-mocha"

# First run: no active-theme marker. Apply the default.
if [[ ! -f "$ACTIVE_THEME_FILE" ]]; then
	log "no active theme set; applying default ($DEFAULT_THEME)"
	"$DOTFILES/bin/dot-theme-set" "$DEFAULT_THEME"
	exit 0
fi

# Re-install: re-apply whatever the active marker says.
active=$(<"$ACTIVE_THEME_FILE")
if [[ -d "$DOTFILES/themes/$active" ]]; then
	log "re-applying active theme: $active"
	"$DOTFILES/bin/dot-theme-set" "$active"
else
	warn "active-theme marker says '$active' but themes/$active/ not found"
	warn "applying default ($DEFAULT_THEME) instead"
	"$DOTFILES/bin/dot-theme-set" "$DEFAULT_THEME"
fi
