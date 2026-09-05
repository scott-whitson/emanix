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
#
#    Fixture choice: this MUST be a name that actually appears in
#    `nixosConfigurations` (i.e. `nix eval .#nixosConfigurations --apply
#    builtins.attrNames`), or the assertion silently tests the interactive
#    branch instead of the pre-staged one it claims to guard. `installer` is
#    the one real nixosConfigurations output in this repo, so it is used
#    here. Do NOT use `checkhost` — that string is only a `hostName` value
#    passed to `mkHost` inside checks/'s `evalRole`; it is not a flake
#    output and will never appear in `known_hosts()`. --check-only never
#    touches a disk, so naming a non-installable config costs nothing.
out="$("$SCRIPT" installer --check-only 2>&1)"; rc=$?
check "known-host (installer) --check-only reaches the preflight, i.e. takes the pre-staged path" 1 "$rc"
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

# --- Graphics prompt ----------------------------------------------------------
# The GPU answer reaches a Nix string literal in a heredoc, exactly like
# SWAPSIZE, and exactly like SWAPSIZE it is validated at the prompt. An
# unvalidated value here produces a host.nix that does not parse, on a code
# path that has already committed to wiping a disk.
if grep -q 'validate_gpu' "$SCRIPT"; then
  echo "ok   installer validates the graphics answer"
else
  echo "FAIL installer has no validate_gpu"
  fails=$((fails + 1))
fi

# null is a Nix keyword, not a string: `gpu = "null";` would typecheck as a
# string and fail the enum at eval, long after the disk is gone. The script
# writes `gpu = ${gpu_nix};`, so assert on how gpu_nix is BUILT -- grepping for
# a literal `gpu = null;` would search for a string the script never contains
# and fail unconditionally.
if grep -q 'gpu_nix="null"' "$SCRIPT"; then
  echo "ok   installer writes bare null, not the string \"null\""
else
  echo "FAIL installer does not emit a bare null for gpu"
  fails=$((fails + 1))
fi

# lspci only picks the DEFAULT. If the script can reach a disk-wiping path
# without the user having seen the question, the distinction between asking
# and guessing has been lost.
if grep -q 'read -rp "Graphics' "$SCRIPT"; then
  echo "ok   graphics is asked, not merely detected"
else
  echo "FAIL graphics is not presented as a question"
  fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && { echo "installer-modes: all good."; exit 0; }
echo "installer-modes: $fails failure(s)."; exit 1
