#!/usr/bin/env bash
# install/08-stow-base.sh — stow every base/* package
set -euo pipefail
source "$(dirname "$0")/_common.sh"

BASE_STASHED=0
if [[ -n "$(git -C "$DOTFILES" status --porcelain --untracked-files=all -- base/)" ]]; then
	log "saving base/ edits before stow"
	git -C "$DOTFILES" stash push -u -m "auto base/ pre-stow" -- base/ >/dev/null
	BASE_STASHED=1
fi

log "stowing base/* packages"
cd "$DOTFILES"

skip_pkg() {
	local pkg="$1"
	for skipped in ${PROFILE_BASE_STOW_SKIP:-}; do
		[[ "$skipped" == "$pkg" ]] && return 0
	done
	return 1
}

for pkg_path in base/*/; do
	pkg_name="$(basename "$pkg_path")"

	if skip_pkg "$pkg_name"; then
		log "skipping $pkg_name per profile"
		continue
	fi

	if [[ "$pkg_name" == "git" ]]; then
		local_gitconfig_local="$HOME/.gitconfig.local"
		local_gitignore="$HOME/.config/git/ignore"
		if [[ -e "$local_gitconfig_local" ]]; then
			if [[ ! -L "$local_gitconfig_local" ]]; then
				backup="$local_gitconfig_local.pre-stow.$(date +%s)"
				log "backing up existing ~/.gitconfig.local to $(basename "$backup")"
				mv "$local_gitconfig_local" "$backup"
			else
				rm -f "$local_gitconfig_local"
			fi
		fi
		if [[ -e "$local_gitignore" ]] && [[ ! -L "$local_gitignore" ]]; then
			backup="$local_gitignore.pre-stow.$(date +%s)"
			log "backing up existing ~/.config/git/ignore to $(basename "$backup")"
			mv "$local_gitignore" "$backup"
		fi
	fi

	# --adopt absorbs existing files at $HOME so stow can succeed on fresh
	# installs (Oh My Zsh drops a default .zshrc, etc.); the git checkout
	# below restores the repo's intended content.
	stow -d base -t "$HOME" --no-folding --adopt "$pkg_name" 2>/dev/null ||
		stow -d base -t "$HOME" --no-folding "$pkg_name"
done

# Reset repo copy, then restore any saved base/ edits so install can continue
# without manual stashing.
git checkout -- base/
if [[ "$BASE_STASHED" -eq 1 ]]; then
	log "restoring saved base/ edits"
	if git -C "$DOTFILES" stash apply >/dev/null; then
		git -C "$DOTFILES" stash drop >/dev/null
	else
		warn "could not auto-restore base/ stash; leaving stash in place"
	fi
fi

# Ensure git config include link exists even if stow/adopt behavior varied.
if [[ -f "$DOTFILES/base/git/.gitconfig.local" ]]; then
	ln -sfn "$DOTFILES/base/git/.gitconfig.local" "$HOME/.gitconfig.local"
fi
