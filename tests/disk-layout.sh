#!/usr/bin/env bash
# Guards lib/disk.nix against drift. The fixtures are the layouts Gate 1
# proved byte-identical to the two hand-written disko files in the consuming
# flake (see docs/superpowers/specs/2026-09-04-hardware-layer-design.md).
# They are golden files: a diff here means the generator changed, which for a
# disk layout means every future install partitions differently.
#
# Run by hand: ./tests/disk-layout.sh
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

ev() {
  nix eval --impure --json --expr "$1" 2>/dev/null | python3 -m json.tool --sort-keys
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

if [ "$fails" -eq 0 ]; then echo "PASS"; else echo "$fails failure(s)"; fi
exit "$fails"
