#!/usr/bin/env bash
# install.sh — register the WSL Emacs as a Windows file handler.
#
#   ./install.sh            install (idempotent — safe to re-run)
#   ./install.sh uninstall  remove every key this script creates
#   ./install.sh status     show what is currently registered
#
# All writes are under HKCU: no admin, no machine-wide changes.
#
# Two registration mechanisms, because Windows has two:
#   1. A ProgID + per-extension association. NOTE: on build 26200 this does not
#      make double-click silently work. Verified — ShellExecute showed the
#      "How do you want to open this file?" picker even for an extension with
#      NO UserChoice and a valid HKCR association. Modern Windows wants the user
#      to confirm the handler, and only then writes the (protected) UserChoice.
#      So what this buys you is "Emacs (WSL)" APPEARING in that picker; one
#      "Always use this app" click per extension makes it permanent.
#   2. A `*\shell` verb -> "Open in Emacs" for ANY file. This one works with no
#      confirmation step at all, and is the reliable half.
#      On Windows 11 (build 26200 here) a legacy verb is demoted into the
#      "Show more options" submenu, i.e. Shift+right-click. Getting into the
#      top-level menu needs a signed MSIX package implementing IExplorerCommand
#      — deliberately out of scope.
#
# UserChoice, the thing that makes naive versions of this fail silently:
# HKCU\...\Explorer\FileExts\<ext>\UserChoice overrides the ProgID association
# and is hash-protected, so it cannot be forged. Where one exists we delete it
# (user-deletable, and Windows falls back to the ProgID) — but only for the
# extensions listed in CONTESTED_TAKE below. Everything else is left alone.
set -uo pipefail

REG='/mnt/c/Windows/System32/reg.exe'
PWSH='/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WIN_DIR_U='/mnt/c/Users/swhitson.CENTRALDATA/AppData/Local/EmacsWSL'
WIN_DIR_W='C:\Users\swhitson.CENTRALDATA\AppData\Local\EmacsWSL'
VBS_W="$WIN_DIR_W\\open-in-emacs.vbs"
COMMAND="C:\\Windows\\System32\\wscript.exe \"$VBS_W\" \"%1\""

PROGID='EmacsWSL.File'
APPKEY='open-in-emacs.vbs'   # HKCU\Software\Classes\Applications\<this>

# Unclaimed extensions — a plain association takes effect immediately.
FREE=(.md .org .json .yaml .yml .toml .conf .el .nix .js .sql)

# Claimed by a Notepad-class text editor; swapping in Emacs is the point.
CONTESTED_TAKE=(.txt .log .ini)

# Claimed by something that is NOT just a text editor. Left alone on purpose:
#   .csv -> Excel        .py -> VS Code
#   .sh  -> Git Bash (double-click RUNS it)
#   .ts  -> media player (.ts is also an MPEG transport stream)
# To take one anyway, add it to CONTESTED_TAKE and re-run.

die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }
reg_add() { "$REG" add "$1" "${@:2}" /f >/dev/null || die "reg add failed: $1"; }

case "${1:-install}" in

install)
  [ -f "$SRC_DIR/open-in-emacs.vbs" ] || die "open-in-emacs.vbs missing from $SRC_DIR"
  chmod +x "$SRC_DIR/open-in-emacs.sh"

  # 1. Deploy the launcher to the Windows side. It must live on C: so Explorer
  #    can read it while the distro is stopped.
  mkdir -p "$WIN_DIR_U" || die "cannot create $WIN_DIR_U"
  cp "$SRC_DIR/open-in-emacs.vbs" "$WIN_DIR_U/open-in-emacs.vbs" || die 'copy failed'
  cp "$SRC_DIR/refresh-assoc.ps1" "$WIN_DIR_U/refresh-assoc.ps1" || die 'copy failed'

  # 2. The ProgID every association points at.
  reg_add "HKCU\\Software\\Classes\\$PROGID" /ve /t REG_SZ /d 'Text file (WSL Emacs)'
  reg_add "HKCU\\Software\\Classes\\$PROGID\\shell\\open\\command" /ve /t REG_SZ /d "$COMMAND"

  # 3. An Applications entry, so "Open with > Choose another app" lists Emacs.
  #    This is the manual escape hatch for any UserChoice-locked extension.
  reg_add "HKCU\\Software\\Classes\\Applications\\$APPKEY" /v FriendlyAppName /t REG_SZ /d 'Emacs (WSL)'
  reg_add "HKCU\\Software\\Classes\\Applications\\$APPKEY\\shell\\open\\command" /ve /t REG_SZ /d "$COMMAND"

  # 4. Catch-all context-menu verb for every file type.
  reg_add 'HKCU\Software\Classes\*\shell\OpenInEmacs' /ve /t REG_SZ /d 'Open in Emacs'
  reg_add 'HKCU\Software\Classes\*\shell\OpenInEmacs\command' /ve /t REG_SZ /d "$COMMAND"

  # 5. Per-extension associations.
  for ext in "${FREE[@]}"; do
    reg_add "HKCU\\Software\\Classes\\$ext" /ve /t REG_SZ /d "$PROGID"
    printf '  associated  %s\n' "$ext"
  done

  # Extensions with an existing UserChoice need one manual GUI step. We still
  # write the ProgID association (it becomes the fallback if UserChoice is ever
  # reset by Windows), but it will not take effect until UserChoice is replaced.
  manual=()
  for ext in "${CONTESTED_TAKE[@]}"; do
    reg_add "HKCU\\Software\\Classes\\$ext" /ve /t REG_SZ /d "$PROGID"
    if "$REG" query "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\FileExts\\$ext\\UserChoice" >/dev/null 2>&1; then
      manual+=("$ext")
      printf '  associated  %s (pending — UserChoice still wins)\n' "$ext"
    else
      printf '  associated  %s\n' "$ext"
    fi
  done

  "$PWSH" -NoProfile -ExecutionPolicy Bypass -File "$WIN_DIR_W\\refresh-assoc.ps1" >/dev/null 2>&1 \
    && echo '  Explorer notified of association change' \
    || echo '  NOTE: could not notify Explorer — log off/on if associations look stale'

  if [ ${#manual[@]} -gt 0 ]; then
    cat <<EOF

One manual step for: ${manual[*]}
These carry a UserChoice key that Windows protects with a Deny ACE (verified:
reg delete returns "Access is denied"), so no script can reassign them. It is
an anti-hijack measure — do NOT work around it by rewriting the key's ACL;
that is the exact pattern EDR flags as association hijacking.

Supported route, once per extension:
  right-click a file > Open with > Choose another app
    > "Emacs (WSL)"  (the Applications entry above puts it in this list)
    > check "Always use this app"
EOF
  fi
  echo 'done.'
  ;;

uninstall)
  for ext in "${FREE[@]}" "${CONTESTED_TAKE[@]}"; do
    # Only remove the association if it is still ours.
    cur=$("$REG" query "HKCU\\Software\\Classes\\$ext" /ve 2>/dev/null | tr -d '\000\r' | awk '/REG_SZ/{print $NF}')
    if [ "$cur" = "$PROGID" ]; then
      "$REG" delete "HKCU\\Software\\Classes\\$ext" /f >/dev/null 2>&1 \
        && printf '  removed  %s\n' "$ext"
    fi
  done
  "$REG" delete 'HKCU\Software\Classes\*\shell\OpenInEmacs' /f >/dev/null 2>&1 && echo '  removed  context-menu verb'
  "$REG" delete "HKCU\\Software\\Classes\\$PROGID" /f >/dev/null 2>&1 && echo "  removed  $PROGID"
  "$REG" delete "HKCU\\Software\\Classes\\Applications\\$APPKEY" /f >/dev/null 2>&1 && echo '  removed  Applications entry'
  # Notify Explorer BEFORE deleting the directory the script lives in, and via
  # its Windows path — powershell.exe cannot take a /home/... path.
  "$PWSH" -NoProfile -ExecutionPolicy Bypass -File "$WIN_DIR_W\\refresh-assoc.ps1" >/dev/null 2>&1
  rm -rf "$WIN_DIR_U" && echo "  removed  $WIN_DIR_W"
  echo 'uninstalled. Windows will fall back to its own defaults.'
  ;;

status)
  printf 'launcher: '; [ -f "$WIN_DIR_U/open-in-emacs.vbs" ] && echo "$VBS_W" || echo 'NOT DEPLOYED'
  printf 'command:  '; "$REG" query "HKCU\\Software\\Classes\\$PROGID\\shell\\open\\command" /ve 2>/dev/null | tr -d '\000\r' | sed -n 's/.*REG_SZ *//p' || echo 'NOT REGISTERED'
  printf 'verb:     '; "$REG" query 'HKCU\Software\Classes\*\shell\OpenInEmacs' /ve >/dev/null 2>&1 && echo 'registered' || echo 'NOT REGISTERED'
  echo 'extensions:'
  for ext in "${FREE[@]}" "${CONTESTED_TAKE[@]}"; do
    cur=$("$REG" query "HKCU\\Software\\Classes\\$ext" /ve 2>/dev/null | tr -d '\000\r' | awk '/REG_SZ/{print $NF}')
    uc=$("$REG" query "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\FileExts\\$ext\\UserChoice" /v ProgId 2>/dev/null | tr -d '\000\r' | awk '/ProgId/{print $NF}')
    printf '  %-7s progid=%-16s userchoice=%s\n' "$ext" "${cur:-<none>}" "${uc:-<none>}"
  done
  ;;

*) die "unknown mode: $1 (install | uninstall | status)" ;;
esac
