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

stow_conflicts() {
	local pkg="$1" conflicts=0
	# Collect target directories that stow would create, deepest first,
	# so we can remove existing non-stow directories before stow runs.
	local dirs_to_clean=()
	while IFS= read -r -d '' file; do
		rel="${file#base/$pkg/}"
		target="$HOME/$rel"
		if [[ -e "$target" ]] && [[ ! -L "$target" ]]; then
			if [[ -d "$target" ]]; then
				dirs_to_clean+=("$target")
			else
				backup="$target.pre-stow.$(date +%s)"
				log "backing up existing $target to $(basename "$backup")"
				mv "$target" "$backup"
				conflicts=$((conflicts + 1))
			fi
		elif [[ -L "$target" ]]; then
			rm -f "$target"
		fi
	done < <(find "base/$pkg" -type f -print0)
	# Remove conflicting directories deepest-first so parents can be recreated.
	local sorted
	sorted=$(printf '%s\n' "${dirs_to_clean[@]}" | awk '{print length, $0}' | sort -rn | cut -d' ' -f2-)
	while IFS= read -r dir; do
		[[ -z "$dir" ]] && continue
		log "removing existing directory $dir for stow"
		rm -rf "$dir"
	done <<< "$sorted"
	return $conflicts
}

for pkg_path in base/*/; do
	pkg_name="$(basename "$pkg_path")"

	if skip_pkg "$pkg_name"; then
		log "skipping $pkg_name per profile"
		continue
	fi

	stow_conflicts "$pkg_name"

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
