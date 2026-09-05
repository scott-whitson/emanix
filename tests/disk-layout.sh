#!/usr/bin/env bash
# Guards lib/disk.nix against drift. The fixtures are the layouts Gate 1
# proved byte-identical to the two hand-written disko files in the consuming
# flake (see docs/superpowers/specs/2026-09-04-hardware-layer-design.md).
# They are golden files: a diff here means the generator changed, which for a
# disk layout means every future install partitions differently.
#
# Run by hand: ./tests/disk-layout.sh
#
# Also run automatically: checks/disk-layout.nix does the same fixture diff and
# the same literal assertions on every `nix flake check`, because until it
# existed this script was the layout's only regression guard and nothing
# invoked it. This script keeps the cases the derivation cannot have -- the
# negative control, the ext4 branch and the rejection cases all want a fresh
# `nix eval`, and there is no nested nix in a build sandbox.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISK="$SELF_DIR/../lib/disk.nix"
fails=0

# The fixtures below are pinned to these exact byte counts. Step 4 of the
# task brief generates both fixtures FROM lib/disk.nix, and the checks below
# compare lib/disk.nix against those same fixtures -- which on its own would
# be circular: a mistranscribed layout would produce a self-consistent wrong
# fixture that still passes. These two counts are the guard against that.
# They are an EXTERNAL measurement, obtained by diffing this exact generator
# against two hand-written disko files in a separate (dotfiles) repo, before
# any of this code was written -- they do not come from the fixtures they
# check. If a freshly generated fixture does not match, the layout was
# transcribed wrongly; fix lib/disk.nix, do not re-baseline these numbers.
#
# They are NO LONGER the only guard, and they never should have been: a byte
# count is a four-digit checksum, and the edits that matter here are
# length-preserving. type = "EF00" -> "8300" (a /boot that is not an EFI System
# Partition), fmask=0077 -> fmask=0000, mountpoint "/nix" -> "/var", size "1G"
# -> "9G" all regenerate to a fixture of exactly this size and still pass. So
# tests/disk-layout-literals.py names those values structurally and runs over
# both the generated output and the committed fixture -- the first catches
# drift, the second catches a re-baseline from a broken generator. The byte
# counts stay because they remain the external evidence of faithful
# transcription, which the literals are not.
EXPECT_RAFIK_BYTES=2417
EXPECT_DATACORE_BYTES=2522

check_fixture_size() {
  local path="$1" expect="$2" got
  if [ ! -f "$path" ]; then
    echo "FAIL fixture-size $(basename "$path"): file does not exist"
    fails=$((fails + 1))
    return
  fi
  got="$(wc -c < "$path")"
  got="${got// /}"
  if [ "$got" -eq "$expect" ]; then
    echo "ok   fixture-size $(basename "$path") ($got bytes)"
  else
    echo "FAIL fixture-size $(basename "$path"): expected $expect bytes, got $got"
    fails=$((fails + 1))
  fi
}

check_fixture_size "$SELF_DIR/fixtures/disk-rafik.json" "$EXPECT_RAFIK_BYTES"
check_fixture_size "$SELF_DIR/fixtures/disk-datacore.json" "$EXPECT_DATACORE_BYTES"

# The committed fixtures, by name rather than by length. A fixture regenerated
# from a broken lib/disk.nix passes every diff below (they are compared against
# that same generator) and every byte count above; this is what stops it.
check_literals() { # label, json path
  if python3 "$SELF_DIR/disk-layout-literals.py" "$1" "$2"; then :; else
    fails=$((fails + 1))
  fi
}

check_literals fixture-rafik "$SELF_DIR/fixtures/disk-rafik.json"
check_literals fixture-datacore "$SELF_DIR/fixtures/disk-datacore.json"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

ev() {
  # Both stderr streams are dropped: an expression that fails to evaluate --
  # which the mkdisk-rejects cases below do ON PURPOSE -- yields no stdout, and
  # json.tool then complains about empty input. Empty output IS the signal
  # every caller here checks for.
  nix eval --impure --json --expr "$1" 2>/dev/null \
    | python3 -m json.tool --sort-keys 2>/dev/null
}

check() {
  local name="$1" expr="$2" fixture="$SELF_DIR/fixtures/$3"
  local got
  got="$(ev "$expr")"
  if [ -z "$got" ]; then
    echo "FAIL $name: expression did not evaluate"
    fails=$((fails + 1))
    return
  fi
  if diff -u "$fixture" <(printf '%s\n' "$got") > /dev/null; then
    echo "ok   $name ($(wc -c < "$fixture") bytes)"
  else
    echo "FAIL $name: differs from $fixture"
    diff -u "$fixture" <(printf '%s\n' "$got") | head -40
    fails=$((fails + 1))
  fi
}

# LUKS + btrfs + no swap.
check "luks-btrfs-noswap" \
  "((import $DISK { device = \"/dev/nvme0n1\"; luks = true; filesystem = \"btrfs\"; swapSize = \"0\"; }) {}).disko.devices" \
  disk-rafik.json

# Plain btrfs + swap + an extra subvolume.
check "btrfs-swap-extrasubvol" \
  "((import $DISK { device = \"/dev/nvme0n1\"; luks = false; filesystem = \"btrfs\"; swapSize = \"16G\"; extraSubvolumes.\"@srv-data\" = { mountpoint = \"/home/srv-data\"; mountOptions = [ \"compress=zstd\" ]; }; }) {}).disko.devices" \
  disk-datacore.json

# Negative control: the comparison must be capable of failing. If flipping
# luks still matches the LUKS fixture, the test proves nothing.
neg="$(ev "((import $DISK { device = \"/dev/nvme0n1\"; luks = false; filesystem = \"btrfs\"; swapSize = \"0\"; }) {}).disko.devices")"
if [ -n "$neg" ] && ! diff -q "$SELF_DIR/fixtures/disk-rafik.json" <(printf '%s\n' "$neg") > /dev/null; then
  echo "ok   negative-control (luks flip differs, as it must)"
else
  echo "FAIL negative-control: comparison is vacuous"
  fails=$((fails + 1))
fi

# ext4 must reach the non-btrfs branch rather than silently producing btrfs.
if ev "((import $DISK { device = \"/dev/vda\"; filesystem = \"ext4\"; }) {}).disko.devices" \
     | grep -q '"format": "ext4"'; then
  echo "ok   ext4-branch"
else
  echo "FAIL ext4-branch: ext4 did not produce an ext4 root"
  fails=$((fails + 1))
fi

# extraSubvolumes retuning an EXISTING key, which is what lib/disk.nix's
# comment has always invited and what `//` could not deliver: `//` replaces the
# whole "@" attrset, so a consumer setting only mountOptions silently loses
# `mountpoint = "/"`. disko then creates the subvolume, mounts nothing at /,
# and nixos-install fails with "The `fileSystems' option does not specify your
# root file system" -- after destroy and format. This case did not exist, which
# is why that shipped.
collision="$(ev "((import $DISK { device = \"/dev/nvme0n1\"; luks = false; filesystem = \"btrfs\"; swapSize = \"0\"; extraSubvolumes.\"@\" = { mountOptions = [ \"compress=zstd\" \"noatime\" ]; }; }) {}).disko.devices")"
if [ -z "$collision" ]; then
  echo "FAIL extrasubvol-collision: expression did not evaluate"
  fails=$((fails + 1))
else
  printf '%s\n' "$collision" > "$tmpdir/collision.json"
  # The literals script asserts @ -> "/" structurally, alongside every other
  # load-bearing value; the greps below state this specific regression in the
  # test's own words, so a failure names it.
  check_literals collision "$tmpdir/collision.json"
  if grep -A 6 '"@":' "$tmpdir/collision.json" | grep -q '"mountpoint": "/"'; then
    echo "ok   extrasubvol-collision (retuning @ keeps mountpoint /)"
  else
    echo "FAIL extrasubvol-collision: retuning @ dropped mountpoint /"
    fails=$((fails + 1))
  fi
  if grep -A 6 '"@":' "$tmpdir/collision.json" | grep -q '"noatime"'; then
    echo "ok   extrasubvol-collision (the consumer's mountOptions won)"
  else
    echo "FAIL extrasubvol-collision: the consumer's mountOptions did not win"
    fails=$((fails + 1))
  fi
fi

# swapSize and filesystem are validated by lib/disk.nix ITSELF, so a consuming
# flake calling mkDisk directly -- never through the installer prompt -- cannot
# reach disko with a value that only fails after the disk is gone. "0G" is the
# case this exists for: it passed the installer's old regex, took the swap
# branch, and emitted a zero-length partition.
reject() { # label, extra args
  if [ -n "$(ev "((import $DISK { device = \"/dev/vda\"; $2 }) {}).disko.devices")" ]; then
    echo "FAIL mkdisk-rejects $1: it evaluated instead of being rejected"
    fails=$((fails + 1))
  else
    echo "ok   mkdisk-rejects $1"
  fi
}

reject 'swapSize 0G' 'swapSize = "0G";'
reject 'swapSize 0M' 'swapSize = "0M";'
reject 'filesystem brtfs' 'filesystem = "brtfs";'
reject 'filesystem BTRFS' 'filesystem = "BTRFS";'

# ... and the positive controls, so the four above are not passing because the
# expression is broken for every input.
for good in 'swapSize = "0";' 'swapSize = "8G";' 'swapSize = "512M";' 'filesystem = "ext4";'; do
  if [ -n "$(ev "((import $DISK { device = \"/dev/vda\"; $good }) {}).disko.devices")" ]; then
    echo "ok   mkdisk-accepts $good"
  else
    echo "FAIL mkdisk-accepts: '$good' was rejected"
    fails=$((fails + 1))
  fi
done

if [ "$fails" -eq 0 ]; then echo "PASS"; else echo "$fails failure(s)"; fi
exit "$fails"
