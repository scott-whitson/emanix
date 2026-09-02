#!/usr/bin/env bash
# Guards the mode boundary. The pre-staged path is what the existing fleet
# depends on, and it is exactly what a refactor of the interactive path would
# silently swallow — so it is asserted here rather than trusted.
#
# Run by hand: ./tests/installer-modes.sh
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/../installer/fresh-emanix-install"
fails=0

check() { # description, expected-exit, actual-exit
  if [ "$2" = "$3" ]; then
    printf '  ok   %s\n' "$1"
  else
    printf '  FAIL %s (expected exit %s, got %s)\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

# 1. A host that exists in the flake still takes the pre-staged path, and
#    --check-only still exits non-zero when its preflight is unsatisfiable
#    off-target (no UEFI, no staged key). What matters is that it reports a
#    PREFLIGHT failure, not an unknown-host one.
out="$("$SCRIPT" checkhost --check-only 2>&1)"; rc=$?
check "known-host --check-only reaches the preflight" 1 "$rc"
if grep -q "check-only: missing:" <<<"$out"; then
  printf '  ok   known-host prints the preflight checklist\n'
else
  printf '  FAIL known-host did not reach the preflight:\n%s\n' "$out"
  fails=$((fails + 1))
fi

# 2. No argument must NOT die with a usage error any more — it enters
#    interactive mode. Off-target it still fails, but for a preflight reason.
out="$("$SCRIPT" --check-only 2>&1)"; rc=$?
if grep -q "usage:" <<<"$out"; then
  printf '  FAIL no-argument still dies with a usage error\n'
  fails=$((fails + 1))
else
  printf '  ok   no-argument no longer a usage error\n'
fi

# 3. An unknown host name must be treated as a NEW host name, not an error.
out="$("$SCRIPT" brandnewbox --check-only 2>&1)"; rc=$?
if grep -qi "unknown host\|not found in the flake" <<<"$out"; then
  printf '  FAIL unknown host rejected instead of being generated\n'
  fails=$((fails + 1))
else
  printf '  ok   unknown host accepted as a new host name\n'
fi

# 4. Hostname validation must reject an RFC 1123 violation.
out="$("$SCRIPT" "Not_A_Host" --check-only 2>&1)"; rc=$?
check "invalid hostname rejected" 1 "$rc"
if grep -qi "hostname" <<<"$out"; then
  printf '  ok   invalid hostname names the problem\n'
else
  printf '  FAIL invalid hostname error did not mention the hostname:\n%s\n' "$out"
  fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && { echo "installer-modes: all good."; exit 0; }
echo "installer-modes: $fails failure(s)."; exit 1
