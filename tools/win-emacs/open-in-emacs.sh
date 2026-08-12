#!/usr/bin/env bash
# open-in-emacs.sh — WSL side of the Windows "open this file in Emacs" handler.
#
# Invoked as: wsl.exe -d whistle -e .../open-in-emacs.sh "C:\path\to\file.txt"
# (by open-in-emacs.vbs, which Explorer launches via a file association or the
# "Open in Emacs" context-menu verb — see install.sh).
#
# `wsl.exe -e` runs this WITHOUT a shell, which is the whole point: the Windows
# path arrives as a single argv entry, so there is no shell-quoting layer to get
# wrong. Desktop paths contain both spaces and a comma (OneDrive Known Folder
# Move puts Desktop under "OneDrive - Central Data Systems, Inc"), and that is
# exactly what breaks the usual `bash -c` recipes.
#
# No shell also means no login environment, so everything below is explicit.
set -u

# `wsl.exe -e` gives us no shell and therefore NO PATH: bash falls back to
# /usr/local/bin:/usr/bin:/bin, which on NixOS contains almost nothing. Verified
# the hard way — `date` and `tr` both silently vanished, and the missing `tr`
# made the frame count parse as 0, so every open created a NEW frame instead of
# reusing the existing one. Set PATH explicitly and avoid external commands
# entirely below (bash builtins only).
export PATH=/run/current-system/sw/bin:/etc/profiles/per-user/scott/bin:/usr/bin:/bin

EMACSCLIENT=/etc/profiles/per-user/scott/bin/emacsclient  # stable home-manager path
LOG="${HOME:-/home/scott}/.local/state/win-emacs.log"

# printf's %(...)T instead of date(1) — one less thing that can go missing.
log() { printf '%(%Y-%m-%d %H:%M:%S)T  %s\n' -1 "$*" >>"$LOG" 2>/dev/null; }

if [ $# -lt 1 ]; then
  log "ERROR no path argument"
  exit 64
fi

# Explorer hands us a Windows path; Emacs needs a Linux one.
if ! path=$(wslpath -u "$1" 2>/dev/null); then
  log "ERROR wslpath failed for: $1"
  exit 65
fi

# Frame creation needs a display; handing a file to an existing frame does not.
export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-0

# Does a graphical frame already exist? If so, reuse it — otherwise we must
# create one, and an -n-only call would silently queue the file into a daemon
# with nothing visible on screen.
frames=$("$EMACSCLIENT" -e '(length (seq-filter (lambda (f) (display-graphic-p f)) (frame-list)))' 2>/dev/null)
frames=${frames//[^0-9]/}   # builtin, not tr — see the PATH note above

if [ "${frames:-0}" -ge 1 ]; then
  # -a "" so a dead daemon gets started rather than erroring out.
  "$EMACSCLIENT" -a "" -n "$path"
  rc=$?
  log "reuse  frames=$frames rc=$rc  $path"
else
  "$EMACSCLIENT" -a "" -c -n "$path"
  rc=$?
  log "create frames=${frames:-0} rc=$rc  $path"
fi

exit $rc
