#!/usr/bin/env bash
# install/10-theme.sh — apply active theme (Wave 2 STUB; Wave 3 rewrites)
set -euo pipefail
source "$(dirname "$0")/_common.sh"
skip_unless_profile workstation

ACTIVE_THEME_FILE="$HOME/.config/dotfiles/active-theme"

# Wave 2 behavior: delegate to existing theme-switch if it's installed.
# Wave 3 replaces this with a real dot-theme-set invocation that understands
# themes/<name>/ directory layouts.

if [[ -f "$ACTIVE_THEME_FILE" ]]; then
    theme=$(<"$ACTIVE_THEME_FILE")
    log "active theme marker: $theme (Wave 2 stub — no-op; Wave 3 will apply)"
else
    log "no active theme set; Wave 3 will populate $ACTIVE_THEME_FILE"
fi

# Wave 2 intentional no-op: existing theme-switch is invoked manually via
# keybinds the user already has configured. Do not auto-run it here.
exit 0
