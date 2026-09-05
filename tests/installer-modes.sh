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
# These were three greps, in a file whose other tests execute the script. A
# grep for `validate_gpu` matches the function DEFINITION, so deleting the CALL
# -- the only thing that stops an unvalidated value reaching the heredoc --
# left the test green. Both new functions are pure and self-contained, so they
# can be sourced out and CALLED. Only the third assertion below is still a
# grep, because reaching the prompt means driving an interactive script that
# wipes a disk.
#
# Sourcing by sed range rather than sourcing the whole script: the script runs
# argument parsing at top level and would exit.
# shellcheck disable=SC1090  # the "source" IS the thing under test
source <(sed -n '/^validate_gpu()/,/^}/p' "$SCRIPT")
# shellcheck disable=SC1090
source <(sed -n '/^detect_gpu_default()/,/^}/p' "$SCRIPT")
# shellcheck disable=SC1090
source <(sed -n '/^validate_swapsize()/,/^}/p' "$SCRIPT")

if ! declare -F validate_gpu >/dev/null || ! declare -F detect_gpu_default >/dev/null \
   || ! declare -F validate_swapsize >/dev/null; then
  echo "FAIL could not source the validators out of $SCRIPT (did they get renamed?)"
  fails=$((fails + 1))
fi

accepts() { # function, value, label
  if "$1" "$2"; then
    printf '  ok   %s accepts %s\n' "$1" "$3"
  else
    printf '  FAIL %s rejected %s, which is valid\n' "$1" "$3"
    fails=$((fails + 1))
  fi
}

rejects() { # function, value, label
  if "$1" "$2"; then
    printf '  FAIL %s accepted %s, which must be rejected\n' "$1" "$3"
    fails=$((fails + 1))
  else
    printf '  ok   %s rejects %s\n' "$1" "$3"
  fi
}

# 5. The GPU answer reaches a Nix string literal in a heredoc, exactly like
#    SWAPSIZE. An unvalidated value produces a host.nix that does not parse, on
#    a code path that has already committed to wiping a disk.
accepts validate_gpu none none
accepts validate_gpu amd amd
accepts validate_gpu intel intel
rejects validate_gpu nvidia nvidia
rejects validate_gpu "" "the empty string"
rejects validate_gpu "amd; rm -rf /" "an injected command"
rejects validate_gpu AMD "AMD (wrong case)"

# 6. "0G" is the swap case that motivated the tightening: `^(0|[0-9]+[MG])$`
#    accepted it, mkDisk's no-swap sentinel is the exact string "0", so "0G"
#    took the swap branch and emitted a ZERO-LENGTH partition -- discovered
#    after disko had already destroyed the disk.
accepts validate_swapsize 0 "0 (the no-swap sentinel)"
accepts validate_swapsize 8G 8G
accepts validate_swapsize 512M 512M
rejects validate_swapsize 0G 0G
rejects validate_swapsize 0M 0M
rejects validate_swapsize 00G 00G
rejects validate_swapsize "" "the empty string"
rejects validate_swapsize 8 "8 (no unit)"

# 7. detect_gpu_default's mapping, against a stub lspci on $PATH. Behaviour,
#    not a grep: the both-vendors case in particular used to fall through an
#    ordered `case` to `amd`, which is wrong for the machine that actually
#    produces it (an Intel iGPU driving the panel beside a discrete AMD card --
#    the compositor comes up on i915).
stubdir="$(mktemp -d)"
trap 'rm -rf "$stubdir"' EXIT
PATH="$stubdir:$PATH"

detects() { # lspci-output, expected, label
  printf '#!/bin/sh\nprintf %%s "%s"\n' "$1" > "$stubdir/lspci"
  chmod +x "$stubdir/lspci"
  got="$(detect_gpu_default 2>/dev/null)"
  if [ "$got" = "$2" ]; then
    printf '  ok   detect_gpu_default: %s -> %s\n' "$3" "$2"
  else
    printf '  FAIL detect_gpu_default: %s -> expected %s, got %s\n' "$3" "$2" "$got"
    fails=$((fails + 1))
  fi
}

detects '00:02.0 VGA compatible controller [0300]: Advanced Micro Devices [1002:15bf]' \
  amd "AMD only"
detects '00:02.0 VGA compatible controller [0300]: Intel Corporation [8086:9a49]' \
  intel "Intel only"
detects '00:01.0 VGA compatible controller [0300]: NVIDIA Corporation [10de:1f95]' \
  none "NVIDIA only (matches neither arm)"
detects '' none "no display controller at all"
detects '00:02.0 VGA compatible controller [0300]: Intel Corporation [8086:9a49]
01:00.0 VGA compatible controller [0300]: Advanced Micro Devices [1002:73df]' \
  none "both vendors present"
detects '00:02.0 VGA compatible controller [0300]: Intel Corporation [8086:9a49]
01:00.0 3D controller [0302]: NVIDIA Corporation [10de:1f95]' \
  intel "Intel + NVIDIA is still Intel"

# ... and the both-vendors case must SAY so, on stderr, or the user is being
# handed `none` with no explanation of why their AMD card was not chosen.
printf '#!/bin/sh\nprintf %%s "VGA compatible controller [8086:9a49]\\nVGA compatible controller [1002:73df]"\n' > "$stubdir/lspci"
chmod +x "$stubdir/lspci"
if detect_gpu_default 2>&1 >/dev/null | grep -qi 'two gpu vendors'; then
  printf '  ok   both-vendors prints an explanation (on stderr, not stdout)\n'
else
  printf '  FAIL both-vendors did not explain itself\n'
  fails=$((fails + 1))
fi

# 8. null is a Nix keyword, not a string: `gpu = "null";` would typecheck as a
#    string and fail the enum at eval, long after the disk is gone. Still a
#    grep -- reaching write_generated_flake behaviourally means running an
#    installer -- but it asserts on how gpu_nix is BUILT, since the script
#    never contains a literal `gpu = null;`.
if grep -q 'gpu_nix="null"' "$SCRIPT"; then
  echo "  ok   installer writes bare null, not the string \"null\""
else
  echo "  FAIL installer does not emit a bare null for gpu"
  fails=$((fails + 1))
fi

# 9. lspci only picks the DEFAULT. If the script can reach a disk-wiping path
#    without the user having seen the question, the distinction between asking
#    and guessing has been lost. A grep for the same reason as 8.
if grep -q 'read -rp "Graphics' "$SCRIPT"; then
  echo "  ok   graphics is asked, not merely detected"
else
  echo "  FAIL graphics is not presented as a question"
  fails=$((fails + 1))
fi

# 10. The validators must actually be CALLED, not merely defined -- which is
#     what the previous version of this section failed to check. Both are
#     called twice: at the prompt, and defensively in write_generated_flake
#     just before the heredoc.
for fn in validate_gpu validate_swapsize; do
  # Count CALLS, not the definition: the definition line is `fn() {`, a call
  # line is indented and immediately followed by a quoted argument.
  calls="$(grep -c "^[[:space:]]\{1,\}$fn \"" "$SCRIPT")"
  if [ "$calls" -ge 2 ]; then
    printf '  ok   %s is called at %s call sites, not just defined\n' "$fn" "$calls"
  else
    printf '  FAIL %s has %s call sites; the prompt and the generator must both validate\n' "$fn" "$calls"
    fails=$((fails + 1))
  fi
done

# --- Target-disk cross-check -------------------------------------------------
# The prompt says "This ERASES $DISK", but disko is invoked with --flake and
# never with $DISK: it erases whatever disko.devices.disk.main.device says. The
# cross-check that reconciles the two MUST read the flake, not a file path that
# a consuming repo is free to move (it already did, on 2026-09-05, which is how
# this was found).
if grep -q 'ioshi/hi-hardware/disko/\$FLAKE_HOST\.nix' "$SCRIPT"; then
  echo "FAIL cross-check still greps a hardcoded consumer file path"
  fails=$((fails + 1))
else
  echo "ok   cross-check does not depend on a consumer's file layout"
fi

# It must ask the FLAKE for the device disko will use.
if grep -q 'config\.disko\.devices\.disk\.main\.device' "$SCRIPT"; then
  echo "ok   cross-check resolves the device from the flake"
else
  echo "FAIL cross-check does not resolve the device from the flake"
  fails=$((fails + 1))
fi

# A mismatch must be FATAL. A warn+continue on the step before a wipe is a
# prompt the user has been trained to accept.
if awk '/declared.*!=.*DISK|DISK.*!=.*declared/,/fi/' "$SCRIPT" | grep -q '\bdie\b'; then
  echo "ok   a device mismatch is fatal"
else
  echo "FAIL a device mismatch does not call die"
  fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && { echo "installer-modes: all good."; exit 0; }
echo "installer-modes: $fails failure(s)."; exit 1
