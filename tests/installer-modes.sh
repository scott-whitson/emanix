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

# --- Fresh-host bootstrap ----------------------------------------------------
# liveElisp defaults true, so ~/.config/emacs symlinks into a checkout. Nothing
# created that checkout, so a fresh host booted to a dangling Emacs config and
# an absent bin/ on PATH. The ISO already stages the consuming flake -- copying
# it needs no network, key or credential.
if grep -q '^copy_staged_flake() {' "$SCRIPT"; then
  echo "ok   installer defines copy_staged_flake to stage a consumer checkout"
else
  echo "FAIL installer does not define copy_staged_flake"
  fails=$((fails + 1))
fi
# Match the CALL site, not the definition: a call is the name followed by a
# space and a quoted argument; the definition line is `copy_staged_flake() {`
# -- name immediately followed by `(`, no space, no argument.
if grep -qE 'copy_staged_flake "' "$SCRIPT"; then
  echo "ok   copy_staged_flake is called, not merely defined"
else
  echo "FAIL copy_staged_flake is defined but never called"
  fails=$((fails + 1))
fi
# grep -qx treats the hostname as a regex: 'rafi.' matches 'rafik'.
if grep -q 'grep -qxF' "$SCRIPT"; then
  echo "ok   host matching is fixed-string"
else
  echo "FAIL host matching uses a regex, not a fixed string"
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

# --- Username / passwd safety -----------------------------------------------
# An empty USERNAME makes `passwd $USERNAME` run `passwd` bare in the chroot,
# which sets ROOT's password while the real account stays passwordless -- and
# the installer prints success. Assert the guard exists and is reached.
if grep -q 'validate_username' "$SCRIPT"; then
  echo "ok   installer validates the username"
else
  echo "FAIL installer has no validate_username"
  fails=$((fails + 1))
fi
if [ "$(grep -c 'validate_username' "$SCRIPT")" -ge 2 ]; then
  echo "ok   validate_username is called, not merely defined"
else
  echo "FAIL validate_username is defined but never called"
  fails=$((fails + 1))
fi
# The chroot command must quote the username.
if grep -q 'passwd \$USERNAME' "$SCRIPT"; then
  echo "FAIL username is unquoted in the passwd chroot command"
  fails=$((fails + 1))
else
  echo "ok   username is quoted into the passwd command"
fi

# The validator itself must reject the dangerous inputs and accept a real one.
# Sourced directly out of the script rather than re-implemented here, so this
# test tracks the actual behaviour, not a description of it.
if (
  # shellcheck disable=SC1090  # the "source" IS the thing under test
  source <(sed -n '/^validate_hostname()/,/^}/p' "$SCRIPT")
  # shellcheck disable=SC1090
  source <(sed -n '/^validate_username()/,/^}/p' "$SCRIPT")
  bad=0
  for u in "" " " "root; rm -rf /"; do
    if validate_username "$u"; then
      echo "FAIL validate_username accepted dangerous input '$u'"
      bad=1
    fi
  done
  if ! validate_username "testuser"; then
    echo "FAIL validate_username rejected a legitimate username 'testuser'"
    bad=1
  fi
  exit "$bad"
); then
  echo "ok   validate_username rejects empty/blank/hostile input and accepts a real name"
else
  fails=$((fails + 1))
fi

# --- Failure cleanup ---------------------------------------------------------
# Without this, a failed nixos-install leaves /mnt mounted and cryptroot open,
# and resolve_disk then SKIPS the target (it skips devices with mounted
# partitions) -- so the retry dies at "preflight failed: disk". The first run's
# failure makes the second impossible.
if grep -q "^trap .* EXIT" "$SCRIPT"; then
  echo "ok   installer has an EXIT trap"
else
  echo "FAIL installer has no EXIT trap"
  fails=$((fails + 1))
fi
#
# swapoff is in the list because disko's mount step runs swapon whenever
# lib/disk.nix emits a swap partition (swapSize != "0"), and resolve_disk skips
# any device whose `lsblk -no MOUNTPOINTS` prints something -- lsblk prints
# "[SWAP]". Unmounting without it leaves the retry just as blind, while the
# trap's message claims otherwise.
for needle in 'umount' 'cryptsetup close' 'swapoff -a'; do
  if grep -q "$needle" "$SCRIPT"; then
    echo "ok   cleanup performs: $needle"
  else
    echo "FAIL cleanup does not perform: $needle"
    fails=$((fails + 1))
  fi
done
# INSTALL_OK is set only at the very end, so passwd and the flake copy run with
# the trap armed AFTER nixos-install already succeeded. Their failure must not
# tell the operator to re-run an installer that would repartition a working
# machine -- cleanup_target has to branch on a second flag.
if grep -q 'SYSTEM_INSTALLED=1' "$SCRIPT" &&
   grep -q 'SYSTEM_INSTALLED" -eq 1' "$SCRIPT"; then
  echo "ok   cleanup's message distinguishes an installed system from a failed install"
else
  echo "FAIL a post-nixos-install failure still advises re-running the installer"
  fails=$((fails + 1))
fi
# It must NOT unmount on success -- the caller reboots from a mounted /mnt in
# some flows, and a trap that fires on the happy path is its own bug.
if grep -q 'INSTALL_OK' "$SCRIPT"; then
  echo "ok   cleanup is suppressed on success"
else
  echo "FAIL cleanup has no success guard"
  fails=$((fails + 1))
fi

# --- copy_staged_flake must stage a CHECKOUT, not a symlink ------------------
# Every assertion about copy_staged_flake above is a grep, and every one of
# them stayed green while the function was completely broken, because nothing
# ever executed it. On the ISO $REPO is /etc/emanix/flake, and NixOS renders a
# directory-source /etc entry as a SYMLINK to /etc/static/emanix/flake (the
# same shape as /etc/dbus-1). `[ -d ]` follows it and passes, `cp -a` implies
# -d and does not, so ~/dotfiles became a symlink to a path that does not exist
# on the installed system -- dangling, and "existing" enough that every later
# guard skipped it. So: RUN the function.
#
# Extracted by brace depth rather than `sed -n '/^name()/,/^}/p'`: that range
# never closes on a one-liner and keeps consuming to the next brace at column
# 0 (it already over-captures validate_username above). Written to a real file
# rather than sourced from a process substitution, so BASH_SOURCE[0] inside the
# function resolves to something realpath can follow.
extract_fn() { # name, file
  awk -v fn="$1" '
    !d && index($0, fn "() {") == 1 { d = 1; print; next }
    d {
      print
      t = $0; o = gsub(/[{]/, "", t)
      t = $0; c = gsub(/[}]/, "", t)
      d += o - c
      if (d <= 0) exit
    }
  ' "$2"
}

csf_dir="$(mktemp -d)"
# The store-mode fixture below is deliberately unwritable; make it removable
# again or the tmpdir leaks.
trap 'rm -rf "$stubdir"; chmod -R u+w "$csf_dir" 2>/dev/null; rm -rf "$csf_dir"' EXIT

extract_fn copy_staged_flake "$SCRIPT" > "$csf_dir/csf.sh"
if [ "$(grep -c . "$csf_dir/csf.sh")" -ge 10 ] && [ "$(tail -1 "$csf_dir/csf.sh")" = "}" ]; then
  echo "ok   copy_staged_flake extracts cleanly (brace-balanced, not over-captured)"
else
  echo "FAIL could not extract copy_staged_flake out of $SCRIPT"
  fails=$((fails + 1))
fi

# nixos-enter does not exist off-target, and the chown it runs is not what is
# under test here.
printf '#!/bin/sh\nexit 0\n' > "$stubdir/nixos-enter"
chmod +x "$stubdir/nixos-enter"

# The staged tree exactly as the ISO presents it: a nix-store-mode directory
# (dr-xr-xr-x / -r--r--r--) reached through a symlink.
mkdir -p "$csf_dir/store/emanix-flake/hosts"
echo '{ }'   > "$csf_dir/store/emanix-flake/flake.nix"
echo 'marker' > "$csf_dir/store/emanix-flake/hosts/README"
chmod -R a-w "$csf_dir/store/emanix-flake"
ln -s store/emanix-flake "$csf_dir/etc-emanix-flake"

mkdir -p "$csf_dir/target/home/testuser"
chmod 700 "$csf_dir/target/home/testuser"
# shellcheck disable=SC1091,SC2034,SC2329  # all four are read by the sourced function
(
  # shellcheck disable=SC1090  # the "source" IS the thing under test
  . "$csf_dir/csf.sh"
  say()  { :; }
  step() { :; }
  warn() { printf 'WARN %s\n' "$*"; }
  REPO="$csf_dir/etc-emanix-flake"
  EMANIX_TARGET_ROOT="$csf_dir/target"
  copy_staged_flake testuser
) > "$csf_dir/out.log" 2>&1

csf_dest="$csf_dir/target/home/testuser/dotfiles"
if [ -L "$csf_dest" ]; then
  printf '  FAIL copy_staged_flake staged a SYMLINK (-> %s), not a checkout\n' \
    "$(readlink "$csf_dest")"
  fails=$((fails + 1))
elif [ -d "$csf_dest" ] && [ -f "$csf_dest/flake.nix" ] &&
     [ "$(cat "$csf_dest/hosts/README" 2>/dev/null)" = marker ]; then
  printf '  ok   copy_staged_flake dereferences a symlinked $REPO into a real checkout\n'
else
  printf '  FAIL copy_staged_flake produced no readable checkout at %s:\n%s\n' \
    "$csf_dest" "$(cat "$csf_dir/out.log")"
  fails=$((fails + 1))
fi

# A store tree copies as r-xr-xr-x / r--r--r--, and `cp -a src/.` puts the
# SOURCE directory's mode on the destination too -- so install -d's 755 does
# not survive. Without the chmod the account cannot edit its own dotfiles or
# `git pull`. write_generated_flake already does this after its own store
# copy; this function used not to.
if [ -w "$csf_dest" ] && [ -w "$csf_dest/flake.nix" ]; then
  printf '  ok   the staged checkout is writable by its owner\n'
else
  printf '  FAIL the staged checkout is read-only -- store modes survived the copy\n'
  fails=$((fails + 1))
fi

# ...and the account's HOME must not be re-chmodded as a side effect of
# creating a directory inside it.
if [ "$(stat -c '%a' "$csf_dir/target/home/testuser")" = 700 ]; then
  printf '  ok   staging does not widen the account home directory\n'
else
  printf '  FAIL staging changed the home directory mode to %s\n' \
    "$(stat -c '%a' "$csf_dir/target/home/testuser")"
  fails=$((fails + 1))
fi

# ...and the distro-itself guard must fire for the case that actually SHIPS.
# The guard used to compare $REPO against the tree this script was run out of,
# which only ever catches a maintainer running from a clone -- on an ISO the
# script is in /nix/store/.../bin and that comparison can never match. Yet
# installer/iso.nix defaults emanix.installer.flake to `../.`, the distro
# itself, and interactive mode requires a flake carrying templates/default,
# which only the distro has. The stock-ISO interactive install is therefore
# exactly where $REPO IS the distro. Detection is by CONTENT for that reason,
# and this asserts the shipped shape, not the maintainer one.
mkdir -p "$csf_dir/distro/templates/default" "$csf_dir/distro/lib" \
         "$csf_dir/distro/installer" "$csf_dir/target2/home/testuser"
echo '{ }' > "$csf_dir/distro/flake.nix"
echo '{ }' > "$csf_dir/distro/templates/default/flake.nix"
echo '{ }' > "$csf_dir/distro/lib/disk.nix"
echo '#!/usr/bin/env bash' > "$csf_dir/distro/installer/fresh-emanix-install"
# shellcheck disable=SC1091,SC2034,SC2329  # all four are read by the sourced function
(
  # shellcheck disable=SC1090  # the "source" IS the thing under test
  . "$csf_dir/csf.sh"
  say()  { :; }
  step() { :; }
  warn() { printf 'WARN %s\n' "$*"; }
  REPO="$csf_dir/distro"
  EMANIX_TARGET_ROOT="$csf_dir/target2"
  copy_staged_flake testuser
) > "$csf_dir/out2.log" 2>&1

if [ -e "$csf_dir/target2/home/testuser/dotfiles" ] ||
   [ -L "$csf_dir/target2/home/testuser/dotfiles" ]; then
  printf '  FAIL a distro-shaped $REPO was staged into ~/dotfiles anyway\n'
  fails=$((fails + 1))
elif grep -qi 'distro itself' "$csf_dir/out2.log"; then
  printf '  ok   a distro-shaped $REPO is detected by content and skipped, with a reason\n'
else
  printf '  FAIL distro-shaped $REPO was skipped without saying why:\n%s\n' \
    "$(cat "$csf_dir/out2.log")"
  fails=$((fails + 1))
fi

# The converse: a CONSUMING flake (no templates/default) must still be staged.
# That is asserted by the symlink fixture above, whose tree carries no
# templates/ at all and does get copied -- if the content check ever widened
# into "any flake", that assertion goes red rather than this one.

# --- passwd must be RETRIED, not run once ------------------------------------
# The empty-username guard asserted above closes the path INTO passwd. This
# closes its outcome: the account is created under --no-root-password, so root
# is locked, and a passwd that fails (mismatched confirmations, Ctrl-D, a
# chroot problem) used to abort the whole run under set -e and leave a machine
# whose only account has no password -- the same end state, through a different
# door. Behavioural, not a grep: the block is extracted and driven against a
# stub nixos-enter that fails a controlled number of times.
# Anchor accepts `say` OR `step`: the stage announcers are interchangeable and
# renaming one broke this extraction silently once (2026-09-05) -- the block
# came out empty and every assertion below it "passed" vacuously until the
# brace/`done` check caught it.
sed -n '/^\(say\|step\) "Set a password/,/^done$/p' "$SCRIPT" > "$csf_dir/passwd-block.sh"
pw_extracted=0
if grep -q 'passwd_tries' "$csf_dir/passwd-block.sh" &&
   [ "$(tail -1 "$csf_dir/passwd-block.sh")" = "done" ]; then
  pw_extracted=1
  echo "ok   the passwd block extracts cleanly and is a loop"
else
  echo "FAIL passwd is still a single un-retried command (or could not be extracted)"
  fails=$((fails + 1))
fi

# GATED on a clean extraction, and not merely for tidiness: if the block ever
# stops ending in `done`, the sed range above runs to EOF and drags in the tail
# of the installer -- including its `reboot`. The harness stubs reboot as well,
# but a range that did not close is not something to execute at all.
pw_harness="$csf_dir/passwd-harness.sh"
{
  echo 'set -euo pipefail'
  echo 'say()  { :; }'
  # `step` is the numbered variant of `say`; an extracted block may use either.
  # Stub both, or the harness dies "step: command not found" and every
  # assertion below reads as a defect in the code under test. That happened on
  # 2026-09-05 when the passwd stage was renamed say -> step.
  echo 'step() { :; }'
  echo 'warn() { printf "WARN %s\n" "$*"; }'
  echo 'die()  { printf "DIE %s\n" "$*"; exit 1; }'
  echo 'USERNAME=testuser; FLAKE_HOST=testbox; n=0'
  # Shadows the real nixos-enter: fails until the n-th call.
  echo 'nixos-enter() { n=$((n + 1)); [ "$n" -ge "$SUCCEED_ON" ]; }'
  echo 'reboot() { printf "REFUSED-REBOOT\n"; exit 90; }'
  cat "$csf_dir/passwd-block.sh"
  echo 'printf "SURVIVED attempts=%s\n" "$n"'
} > "$pw_harness"

pw_out=""; pw_rc=0
[ "$pw_extracted" = 1 ] && { pw_out="$(SUCCEED_ON=1 bash "$pw_harness" 2>&1)"; pw_rc=$?; }
if [ "$pw_extracted" = 1 ] && [ "$pw_rc" = 0 ] && grep -q 'SURVIVED attempts=1' <<<"$pw_out" &&
   ! grep -q WARN <<<"$pw_out"; then
  echo "  ok   passwd succeeding first time neither warns nor re-prompts"
else
  printf '  FAIL passwd first-time success misbehaves (rc %s):\n%s\n' "$pw_rc" "$pw_out"
  fails=$((fails + 1))
fi

pw_out=""; pw_rc=0
[ "$pw_extracted" = 1 ] && { pw_out="$(SUCCEED_ON=2 bash "$pw_harness" 2>&1)"; pw_rc=$?; }
if [ "$pw_extracted" = 1 ] && [ "$pw_rc" = 0 ] && grep -q 'SURVIVED attempts=2' <<<"$pw_out"; then
  echo "  ok   a failed passwd re-prompts instead of aborting an installed machine"
else
  printf '  FAIL a failed passwd still aborts the install (rc %s):\n%s\n' "$pw_rc" "$pw_out"
  fails=$((fails + 1))
fi

# ...and it must be BOUNDED, with recovery instructions rather than the generic
# trap message: an unattended console that keeps failing has to stop and say
# something the operator can act on.
pw_out=""; pw_rc=0
[ "$pw_extracted" = 1 ] && { pw_out="$(SUCCEED_ON=99 bash "$pw_harness" 2>&1)"; pw_rc=$?; }
if [ "$pw_extracted" = 1 ] && [ "$pw_rc" = 1 ] && grep -q 'SURVIVED' <<<"$pw_out"; then
  echo "  FAIL passwd retries are unbounded"
  fails=$((fails + 1))
elif [ "$pw_extracted" = 1 ] && [ "$pw_rc" = 1 ] && grep -q 'IS INSTALLED' <<<"$pw_out" &&
     grep -q 'nixos-enter --root /mnt -c' <<<"$pw_out"; then
  echo "  ok   passwd gives up bounded, and names the machine installed plus the repair command"
else
  printf '  FAIL exhausted passwd retries gave no actionable recovery (rc %s):\n%s\n' \
    "$pw_rc" "$pw_out"
  fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && { echo "installer-modes: all good."; exit 0; }
echo "installer-modes: $fails failure(s)."; exit 1
