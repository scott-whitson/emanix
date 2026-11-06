#!/usr/bin/env bash
# tests/gitconfig-writable.sh — the global git config must be writable, and
# still be emanix's defaults.
#
# home/git.nix manages ~/.config/git/config through home-manager, which makes it
# a read-only symlink into the store. `git config --global` writes the XDG file
# when it exists and ~/.gitconfig does NOT, so on a fresh host the write hit the
# store and failed with "could not lock config file ... Read-only file system"
# -- which is what broke `gh auth login` setting up its credential helper.
#
# The fix creates a writable ~/.gitconfig that INCLUDES the managed file. Two
# things about that are easy to get wrong, and this test pins both:
#
#   1. The include is not decoration. Git reads ONE global file: ~/.gitconfig
#      when it exists, and only the XDG one when it does not (git 2.54.0). A
#      bare ~/.gitconfig silently drops every emanix default, so a missing
#      include has to fail here rather than in someone's shell.
#   2. Readers that pass `--global` do not follow includes. That is a real
#      ceiling (home/git.nix carries a ponytail note for it), so the test
#      asserts it rather than pretending it is not there.
#
# Runs against a scratch HOME with a simulated read-only managed config, so it
# needs no store, no network and no root.
set -uo pipefail

fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() {
  printf 'FAIL %s\n' "$1"
  fails=$((fails + 1))
}

tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

home="$tmp/home"
mkdir -p "$home/.config/git"
managed="$home/.config/git/config"
printf '[probe]\n\tmanaged = from-managed-file\n\tclash = managed\n' > "$managed"

# A store symlink is unwritable because its DIRECTORY is unwritable, so that is
# what gets simulated: the file stays readable, the directory refuses writes.
chmod 555 "$home/.config/git"

git_in() {
  # XDG_CONFIG_HOME is unset so $HOME decides where the XDG file is; otherwise a
  # developer's own environment would point the test at their real config.
  env -u XDG_CONFIG_HOME HOME="$home" GIT_CONFIG_NOSYSTEM=1 git "$@"
}

# --- before: the failure this fix exists for ---------------------------------
if git_in config --global probe.before 1 >/dev/null 2>&1; then
  bad "writing the global config succeeded against a read-only managed file (the bug is not reproduced by this fixture)"
else
  ok "with no ~/.gitconfig, a global write fails against the read-only managed file"
fi

if git_in config --global --get probe.managed >/dev/null 2>&1; then
  ok "the managed file is still readable (the fixture is read-only, not broken)"
else
  bad "the fixture's managed file is unreadable, so nothing below tests anything"
fi

# --- the fix: exactly what home/git.nix's activation writes -------------------
printf '%s\n' \
  '# Yours: git and anything else is free to write here.' \
  '[include]' \
  '	path = ~/.config/git/config' > "$home/.gitconfig"
chmod 600 "$home/.gitconfig"

# The generator itself, which the copy above cannot check: '%s' does not expand
# \t, so the escape in git.nix writes a literal backslash-t and git refuses the
# file ("bad config line 6"). The hand-written copy used to hide exactly that.
repo="$(cd "$(dirname "$0")/.." && pwd)"
if grep -qF "'\tpath" "$repo/home/git.nix"; then
  bad "home/git.nix seeds a literal backslash-t; printf '%s' never expands it"
else
  ok "home/git.nix seeds the include path with a real tab"
fi

if git_in config --global probe.after 1 >/dev/null 2>&1; then
  ok "with ~/.gitconfig present, a global write succeeds"
else
  bad "a global write still fails with ~/.gitconfig present -- the fix does not fix it"
fi

origin="$(git_in config --global --show-origin --get probe.after 2>/dev/null | cut -f1)"
case "$origin" in
  *".gitconfig") ok "the write landed in the writable ~/.gitconfig ($origin)" ;;
  *) bad "the write did not land in ~/.gitconfig (origin: ${origin:-none})" ;;
esac

# --- the include is load-bearing ---------------------------------------------
if [ "$(git_in config --get probe.managed)" = "from-managed-file" ]; then
  ok "emanix's managed defaults still apply through a normal lookup"
else
  bad "the managed defaults are gone: the created ~/.gitconfig is shadowing them (missing include)"
fi

if [ "$(git_in config --global --includes --get probe.managed)" = "from-managed-file" ]; then
  ok "--global plus --includes reaches the managed defaults"
else
  bad "--global --includes does not reach the managed defaults"
fi

# The ceiling, asserted so it cannot be mistaken for a bug later.
if [ -z "$(git_in config --global --get probe.managed)" ]; then
  ok "the documented ceiling holds: plain --global does not follow includes"
else
  bad "plain --global now follows includes -- the ponytail note in home/git.nix is stale"
fi

# --- and the writable file wins, which is the point of it being writable -----
printf '[probe]\n\tclash = writable\n' >> "$home/.gitconfig"
if [ "$(git_in config --get probe.clash)" = "writable" ]; then
  ok "a value in the writable file wins over the managed one"
else
  bad "the managed file wins over the writable one, so tools cannot override defaults"
fi

chmod -R u+w "$tmp" 2>/dev/null
if [ "$fails" -eq 0 ]; then
  echo "gitconfig-writable: all good."
  exit 0
fi
printf 'gitconfig-writable: %s failure(s).\n' "$fails"
exit 1
