#!/usr/bin/env bash
# install/03-system.sh — user-level system config (Oh My Zsh, plugins, shell, pam warning)
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# --- Oh My Zsh ---
OMZ_DIR="$HOME/.oh-my-zsh"
if [[ ! -d "$OMZ_DIR/.git" ]]; then
	log "installing Oh My Zsh repo"
	clone_if_missing https://github.com/ohmyzsh/ohmyzsh.git "$OMZ_DIR"
else
	log "Oh My Zsh already installed"
fi

# --- Zsh plugins ---
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
clone_if_missing \
	https://github.com/zsh-users/zsh-autosuggestions.git \
	"$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone_if_missing \
	https://github.com/zsh-users/zsh-syntax-highlighting.git \
	"$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# --- Default shell ---
if [[ "$SHELL" != "$(command -v zsh)" ]]; then
	log "setting zsh as default shell for $USER"
	chsh -s "$(command -v zsh)" || warn "chsh failed; run manually: chsh -s \$(which zsh)"
fi

# --- pam_systemd_home sanity check ---
# Debian shape: warn if any PAM file still pulls in pam_systemd_home.
# We do NOT auto-edit /etc/pam.d/*; we only warn.
pam_hits="$(grep -RslE --exclude='*.dpkg-*' --exclude='*.bak' --exclude='*.old' --exclude='*~' '^\s*auth.*pam_systemd_home' /etc/pam.d 2>/dev/null || true)"
if [[ -n "$pam_hits" ]]; then
	warn "pam_systemd_home auth line is ACTIVE in:"
	printf '%s\n' "$pam_hits" | sed 's/^/  /'
	warn "  This may regress sudo/su behavior on this system."
	warn "  Comment out the line manually, then verify with: sudo true"
fi
