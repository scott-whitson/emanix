#!/usr/bin/env bash
# Asserts that a broken config.el cannot take the desktop down.
#
# Both faults tested here really happened on 2026-08-10 and both cost the top
# bar, s-d and window navigation:
#   - a read-time failure  (unbalanced paren -> "End of file during parsing")
#   - a load-time failure  (a bare require that signalled)
#
# Everything runs in emacs --batch against a temp directory. Never point this
# at ~/.config/emacs, and never use emacsclient: a live EWM session is the
# user's desktop.
set -uo pipefail

EMACS="${EMACS:-emacs}"
SRC="$(cd "$(dirname "$0")/.." && pwd)/ioshi/i-intelligence/emacs"
FAILURES=0

PROBE='(message "PROBE fellback=%s modeline=%s launch=%s ewmgoto=%s theme=%s"
         (if scott/init-error "yes" "no")
         (fboundp (quote scott/modeline-mode))
         (fboundp (quote scott/launch-app))
         (fboundp (quote scott/ewm--goto))
         (if custom-enabled-themes "yes" "no"))'

layout() {  # $1 = destination dir; build a deployed-shaped config tree
  mkdir -p "$1"
  cp "$SRC/init.el" "$SRC/config.el" "$SRC/fallback.el" "$1/"
  cp -r "$SRC/lisp" "$1/lisp"
}

probe() {   # $1 = init dir
  # --batch implies noninteractive, which forces init-file-user to nil
  # (see startup.el), so Emacs never auto-loads init.el the way it does
  # in a real interactive/daemon start. --init-directory alone doesn't
  # change that. Load it explicitly with -l to exercise the real loader.
  timeout 240 "$EMACS" --batch --init-directory "$1" -l "$1/init.el" --eval "$PROBE" 2>&1 \
    | grep '^PROBE' | tail -1
}

check() {   # $1 = label, $2 = expected substring, $3 = actual
  if [[ "$3" == *"$2"* ]]; then
    echo "  PASS  $1"
  else
    echo "  FAIL  $1"
    echo "        expected to contain: $2"
    echo "        got:                 $3"
    FAILURES=$((FAILURES + 1))
  fi
}

echo "1. healthy path — must be unchanged, and must NOT report a fallback"
D=$(mktemp -d); layout "$D"
R=$(probe "$D")
check "healthy: no fallback"   "fellback=no"  "$R"
check "healthy: modeline"      "modeline=t"   "$R"
check "healthy: launcher"      "launch=t"     "$R"
check "healthy: ewm commands"  "ewmgoto=t"    "$R"
check "healthy: theme"         "theme=yes"    "$R"

echo "2. read-time failure — unbalanced paren (the 2026-08-10 morning fault)"
D=$(mktemp -d); layout "$D"
printf '\n(when t\n' >> "$D/config.el"   # deliberately unclosed
R=$(probe "$D")
check "paren: fell back"       "fellback=yes" "$R"
check "paren: modeline"        "modeline=t"   "$R"
check "paren: launcher"        "launch=t"     "$R"
check "paren: ewm commands"    "ewmgoto=t"    "$R"

echo "3. load-time failure — a require that signals (the evening fault)"
D=$(mktemp -d); layout "$D"
python3 - "$D/config.el" <<'PY'
import sys
p = sys.argv[1]; lines = open(p).read().split("\n")
lines.insert(1, "(require 'a-package-that-does-not-exist)")
open(p, "w").write("\n".join(lines))
PY
R=$(probe "$D")
check "require: fell back"     "fellback=yes" "$R"
check "require: modeline"      "modeline=t"   "$R"
check "require: launcher"      "launch=t"     "$R"
check "require: ewm commands"  "ewmgoto=t"    "$R"

echo
if (( FAILURES == 0 )); then
  echo "init-guard: all checks passed"
else
  echo "init-guard: $FAILURES check(s) failed"
  exit 1
fi
