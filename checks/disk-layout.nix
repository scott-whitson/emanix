# The disk layout, checked on every `nix flake check` rather than whenever
# someone remembers to run tests/disk-layout.sh.
#
# That script was the layout's ONLY regression guard, and nothing invoked it.
# For a generator whose output partitions a disk -- destroy before format, so a
# mistake is discovered with the data already gone -- "a human remembers to run
# it" is not a guard.
#
# Same shape as the palette-contrast check: the data is serialized at EVAL time
# with builtins.toJSON and the assertions run inside the derivation. There is
# no nested nix in a build sandbox, so `nix eval` (which the shell script uses)
# is not available here; toJSON is how the evaluated layout crosses into the
# build.
#
# Two assertions per case, and they guard different failures:
#
#   1. diff against the COMMITTED fixture. Catches the generator drifting.
#   2. tests/disk-layout-literals.py over both sides. Catches the fixture being
#      re-baselined from a broken generator -- the fixtures are produced by the
#      code under test, so a diff alone is circular, and the byte counts that
#      were the previous answer are blind to length-preserving edits
#      (EF00 -> 8300, fmask=0077 -> fmask=0000, "/nix" -> "/var").
#
# EVALUATED AND BUILT, unlike the role checks: this derivation is a python
# script over two small JSON files. It realizes nothing but python3.
{ pkgs, ... }:
let
  mkDisk = import ../lib/disk.nix;

  # mkDisk returns a NixOS module (a function ignoring its argument); applying
  # it to {} is what the module system would do.
  devicesFor = args: ((mkDisk args) { }).disko.devices;

  json = name: args: pkgs.writeText "emanix-disk-${name}.json"
    (builtins.toJSON (devicesFor args));

  # The same two layouts tests/disk-layout.sh pins, and for the same reason:
  # Gate 1 proved them byte-identical to two hand-written disko files.
  rafik = json "rafik" {
    device = "/dev/nvme0n1";
    luks = true;
    filesystem = "btrfs";
    swapSize = "0";
  };
  datacore = json "datacore" {
    device = "/dev/nvme0n1";
    luks = false;
    filesystem = "btrfs";
    swapSize = "16G";
    extraSubvolumes."@srv-data" = {
      mountpoint = "/home/srv-data";
      mountOptions = [ "compress=zstd" ];
    };
  };

  # extraSubvolumes retuning an EXISTING key. `//` would replace the whole "@"
  # attrset and drop `mountpoint = "/"`, which disko discovers only after it
  # has destroyed and formatted the disk. No fixture -- the literals script is
  # the assertion, and it requires @ -> "/".
  collision = json "collision" {
    device = "/dev/nvme0n1";
    luks = false;
    filesystem = "btrfs";
    swapSize = "0";
    extraSubvolumes."@" = { mountOptions = [ "compress=zstd" "noatime" ]; };
  };
in
pkgs.runCommand "emanix-disk-layout" { } ''
  py=${pkgs.python3}/bin/python3
  lit=${../tests/disk-layout-literals.py}
  fail=0

  # The fixtures are `nix eval --json | python3 -m json.tool --sort-keys`
  # output; normalize builtins.toJSON the same way before diffing, or every
  # comparison fails on key order and whitespace rather than on content.
  norm() { "$py" -m json.tool --sort-keys < "$1" > "$2"; }

  norm ${rafik} rafik.json
  norm ${datacore} datacore.json
  norm ${collision} collision.json

  for c in rafik datacore; do
    if diff -u ${../tests/fixtures}/disk-$c.json $c.json; then
      echo "ok   fixture $c"
    else
      echo "FAIL fixture $c: lib/disk.nix no longer produces the committed layout" >&2
      fail=1
    fi
    "$py" "$lit" "fixture-$c" ${../tests/fixtures}/disk-$c.json || fail=1
    "$py" "$lit" "generated-$c" $c.json || fail=1
  done

  "$py" "$lit" collision collision.json || fail=1

  [ "$fail" -eq 0 ] || { echo "emanix-disk-layout: failed" >&2; exit 1; }
  echo ok > $out
''
