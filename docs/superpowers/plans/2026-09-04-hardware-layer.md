# emanix Hardware Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move hardware bring-up out of a personal repo and into emanix, so the
distribution can install itself on a machine it has never seen.

**Architecture:** emanix gains a thin `ioshi/hi-hardware/` layer (a GPU option
that drives `boot.initrd.kernelModules` for EWM's tty1 DRM-master race, and a
firmware default), takes `nixos-hardware` as an input, and promotes the
parameterized disk layout out of `templates/default/` into `lib.mkDisk`.
Hardware *discovery* stays `nixos-generate-config`. dotfiles keeps every choice
(peripherals, timezone, keys) and loses only machine facts.

**Tech Stack:** Nix flakes, NixOS modules, disko, home-manager, bash (installer
and tests).

**Spec:** `docs/superpowers/specs/2026-09-04-hardware-layer-design.md`

## Global Constraints

- **Two repos.** Tasks 1–5 are in `~/projects/emanix`; Tasks 6–7 are in
  `~/dotfiles`. Every task states its repo. Do not cross without being told to.
- **No `Co-Authored-By` trailers in any commit, ever.**
- **`role` is the only axis.** Do not introduce a `shape` option, field, or
  argument anywhere.
- **Nothing personal enters emanix.** No hostname, username, timezone, SSH key,
  device path, or peer name from Scott's fleet. The distro's own checks use
  `checkhost`/`checkuser` for this reason.
- **Neither `hardwareModule` nor `gpu` becomes an argument to `mkHost`.** mkHost
  stays a composer. Adding hardware arguments re-introduces the dispatch that
  was deliberately deleted (see `lib/mkHost.nix`'s own header).
- **Flake eval cannot see untracked files.** `git add` every new file before
  running `nix build`, `nix eval`, or `nix flake check`, or the change is
  invisible to the evaluator.
- **`nix flake check` evaluates but never builds** (`unsafeDiscardStringContext`
  in `flake.nix`). Do not "fix" a check by realizing its derivation — the
  workstation role pulls EWM, whose closure can take down a WSL host.
- **rafik is a running machine until its reinstall.** Tasks 1–6 must not change
  what rafik boots. Task 7 is the only one that does, and it runs on
  reinstall day.
- **GPU values are `"amd" | "intel" | null`.** `intel` ships labelled
  reasoned-not-verified. NVIDIA is out of scope — do not add it.
- **Gate 1 is already passed** (spec, "Verification"). `mkDisk` reproduces
  rafik's committed layout at **2417 bytes** of evaluated `disko.devices`, and
  datacore's at **2522 bytes**. Those two numbers are load-bearing in Task 1.

---

### Task 1: `lib/disk.nix` and the `lib.mkDisk` export

**Repo:** `~/projects/emanix`

**Files:**
- Create: `lib/disk.nix`
- Create: `tests/disk-layout.sh`
- Create: `tests/fixtures/disk-rafik.json`, `tests/fixtures/disk-datacore.json`
- Modify: `flake.nix` (the `lib` output, currently `lib = { inherit mkHost; };`)

**Interfaces:**
- Consumes: nothing.
- Produces: `emanix.lib.mkDisk`, a function
  `{ device, luks ? false, filesystem ? "btrfs", swapSize ? "0", extraSubvolumes ? { } } -> (_: { disko.devices.disk.main = …; })`.
  It returns a **NixOS module** (a function ignoring its argument), not a bare
  attrset, so a consumer drops it straight into a module list. Tasks 4 and 6
  both call it.

**Why the fixtures are honest:** they lock in that the layout does not drift.
They do not prove the layout is correct — Gate 1 did that, by diffing this
exact generator against dotfiles' two hand-written disko files while rafik was
running. That proof is recorded in the spec and is not re-run here, because
emanix must not read dotfiles.

- [ ] **Step 1: Write the failing test**

Create `tests/disk-layout.sh`:

```bash
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
```

Make it executable: `chmod +x tests/disk-layout.sh`

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/disk-layout.sh`
Expected: every check FAILs — `lib/disk.nix` does not exist yet, so `ev`
returns empty and each `check` reports "expression did not evaluate". Exit
status non-zero.

- [ ] **Step 3: Write `lib/disk.nix`**

```nix
# The emanix disk layout, parameterized.
#
# Promoted out of templates/default/disko.nix, which is where it lived while
# the only consumer was a generated host. It is the DISTRIBUTION's opinion
# about how a disk should be laid out — an ESP at /boot, optional swap, one
# root partition, btrfs subvolumes, optionally wrapped in LUKS. What machine
# it is applied to stays the consumer's fact: this function takes `device`
# rather than knowing one.
#
# Returns a NixOS MODULE (a function ignoring its argument), so a consumer can
# drop the result straight into a module list beside disko.nixosModules.disko.
#
# LUKS wraps the filesystem rather than replacing it, so the two knobs are
# independent: ext4-on-LUKS and bare btrfs are both reachable.
{ device
, luks ? false
, filesystem ? "btrfs"
, swapSize ? "0"
, extraSubvolumes ? { }
}:
let
  baseSubvolumes = {
    "@" = { mountpoint = "/"; mountOptions = [ "compress=zstd" ]; };
    "@nix" = { mountpoint = "/nix"; mountOptions = [ "compress=zstd" "noatime" ]; };
    "@home" = { mountpoint = "/home"; mountOptions = [ "compress=zstd" ]; };
  };

  rootContent =
    if filesystem == "btrfs" then {
      type = "btrfs";
      extraArgs = [ "-f" ];
      # extraSubvolumes wins on a key collision, so a consumer can retune "@"
      # rather than only add beside it.
      subvolumes = baseSubvolumes // extraSubvolumes;
    } else {
      type = "filesystem";
      format = "ext4";
      mountpoint = "/";
    };

  rootPartition =
    if luks then {
      type = "luks";
      name = "cryptroot";
      settings.allowDiscards = true;
      content = rootContent;
    } else rootContent;
in
_: {
  disko.devices.disk.main = {
    type = "disk";
    inherit device;
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "fmask=0077" "dmask=0077" ];
          };
        };
      } // (if swapSize == "0" then { } else {
        swap = {
          size = swapSize;
          content = { type = "swap"; };
        };
      }) // {
        root = {
          size = "100%";
          content = rootPartition;
        };
      };
    };
  };
}
```

- [ ] **Step 4: Generate the two fixtures and check their sizes**

```bash
mkdir -p tests/fixtures
gen() { nix eval --impure --json --expr "$1" | python3 -m json.tool --sort-keys; }

gen '((import '"$PWD"'/lib/disk.nix { device = "/dev/nvme0n1"; luks = true; filesystem = "btrfs"; swapSize = "0"; }) {}).disko.devices' \
  > tests/fixtures/disk-rafik.json

gen '((import '"$PWD"'/lib/disk.nix { device = "/dev/nvme0n1"; luks = false; filesystem = "btrfs"; swapSize = "16G"; extraSubvolumes."@srv-data" = { mountpoint = "/home/srv-data"; mountOptions = [ "compress=zstd" ]; }; }) {}).disko.devices' \
  > tests/fixtures/disk-datacore.json

wc -c tests/fixtures/disk-rafik.json tests/fixtures/disk-datacore.json
```

Expected, and this is the check that matters: **2417** bytes for
`disk-rafik.json` and **2522** for `disk-datacore.json`. These are the sizes
Gate 1 measured against the hand-written files. A different number means
`lib/disk.nix` was transcribed wrongly — stop and diff against the spec rather
than re-baselining the fixture.

- [ ] **Step 5: Run the test to verify it passes**

Run: `./tests/disk-layout.sh`
Expected:
```
ok   luks-btrfs-noswap (2417 bytes)
ok   btrfs-swap-extrasubvol (2522 bytes)
ok   negative-control (luks flip differs, as it must)
ok   ext4-branch
PASS
```

- [ ] **Step 6: Export it from the flake**

In `flake.nix`, replace:

```nix
      # The host composer, parameterized: { hostName, role, username, hardware, extraModules }
      lib = { inherit mkHost; };
```

with:

```nix
      # The host composer and the disk layout, both parameterized.
      # mkHost:  { hostName, role, username, hardware, extraModules, homeModules }
      # mkDisk:  { device, luks, filesystem, swapSize, extraSubvolumes }
      #
      # mkDisk is the distro's opinion about disk SHAPE; the consumer still
      # supplies the device and the options, so "disko configurations are
      # defined by consumers" holds — they just stop retyping the layout.
      lib = { inherit mkHost; mkDisk = import ./lib/disk.nix; };
```

- [ ] **Step 7: Verify the export resolves and the flake still checks**

```bash
git add lib/disk.nix tests/disk-layout.sh tests/fixtures flake.nix
nix eval --impure --json --expr \
  '((builtins.getFlake (toString ./.)).lib.mkDisk { device = "/dev/vda"; }) {}' \
  | head -c 200; echo
nix flake check 2>&1 | tail -20
```
Expected: the eval prints a `disko.devices` fragment; `nix flake check` reports
no errors. (`git add` first — flake eval cannot see untracked files.)

- [ ] **Step 8: Commit**

```bash
git add lib/disk.nix tests/disk-layout.sh tests/fixtures flake.nix
git commit -m "feat(lib): add mkDisk, the parameterized disk layout

Promoted out of templates/default/disko.nix, which is where it lived while a
generated host was its only consumer, and given extraSubvolumes so a layout
with an extra subvolume is expressible.

tests/disk-layout.sh guards it against drift with golden fixtures, a negative
control (a vacuous comparison is worse than no test) and an ext4-branch case.
The fixtures are the layouts Gate 1 proved byte-identical to the two
hand-written disko files in the consuming flake: 2417 and 2522 bytes."
```

---

### Task 2: `ioshi/hi-hardware/` — the GPU option and the firmware default

**Repo:** `~/projects/emanix`

**Files:**
- Create: `ioshi/hi-hardware/gpu.nix`
- Create: `ioshi/hi-hardware/firmware.nix`
- Create: `checks/hardware-gpu.nix`
- Modify: `emanix.nix` (the `imports` list at the end of the file)
- Modify: `flake.nix` (`checks.${system}`, beside `template-host`)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: the NixOS-tier option `emanix.hardware.gpu`, of type
  `types.nullOr (types.enum [ "amd" "intel" ])`, default `null`. Tasks 4 and 7
  set it. When `"amd"` it appends `"amdgpu"` to `boot.initrd.kernelModules`;
  when `"intel"`, `"i915"`; when `null` it contributes nothing.

- [ ] **Step 1: Write the failing test**

Create `checks/hardware-gpu.nix`:

```nix
# emanix.hardware.gpu drives boot.initrd.kernelModules, and the failure mode
# when it is wrong is a black screen on a machine with no other console. So
# each value is asserted here rather than trusted to review.
#
# Note kernelModules, NOT availableKernelModules: nixos-generate-config writes
# the latter (modules PERMITTED in the initrd) and never the former (modules
# FORCED to load). EWM needs the forced form, which is the whole reason this
# option exists — see ioshi/hi-hardware/gpu.nix.
{ pkgs, mkHost, ... }:
let
  initrdModulesFor = gpu:
    (mkHost {
      hostName = "checkhost";
      role = "workstation";
      username = "checkuser";
      hardware = ./stub-hardware.nix;
      extraModules = [{ emanix.hardware.gpu = gpu; }];
      homeModules = [{ }];
    }).config.boot.initrd.kernelModules;

  amd = initrdModulesFor "amd";
  intel = initrdModulesFor "intel";
  none = initrdModulesFor null;

  has = m: xs: builtins.elem m xs;

  results = [
    { name = "amd-loads-amdgpu"; ok = has "amdgpu" amd; }
    { name = "amd-omits-i915"; ok = !(has "i915" amd); }
    { name = "intel-loads-i915"; ok = has "i915" intel; }
    { name = "intel-omits-amdgpu"; ok = !(has "amdgpu" intel); }
    { name = "null-loads-neither"; ok = !(has "amdgpu" none) && !(has "i915" none); }
  ];

  failures = builtins.filter (r: !r.ok) results;
in
if failures == [ ] then
  pkgs.runCommand "emanix-hardware-gpu" { } "echo ok > $out"
else
  throw ("emanix.hardware.gpu is wired wrong: "
    + builtins.concatStringsSep ", " (map (r: r.name) failures))
```

Wire it into `flake.nix`, in `checks.${system}`, immediately after the
`template-host` entry:

```nix
          # emanix.hardware.gpu's effect on the initrd, checked per value.
          # See checks/hardware-gpu.nix.
          hardware-gpu = import ./checks/hardware-gpu.nix { inherit pkgs mkHost; };
```

- [ ] **Step 2: Run it to verify it fails**

```bash
git add checks/hardware-gpu.nix flake.nix
nix flake check 2>&1 | tail -20
```
Expected: FAIL — `The option 'emanix.hardware.gpu' does not exist`. The option
has not been declared yet.

- [ ] **Step 3: Write `ioshi/hi-hardware/gpu.nix`**

```nix
# What EWM needs from a GPU.
#
# EWM launches from tty1 autologin at boot and loses the DRM-master race
# against late GPU bring-up, so the driver must be in the INITRD, forced to
# load. This was verified on zord-old with amdgpu, and the same comment used to
# be written twice — once per machine — in a personal repo, which is what
# identified it as a fact about the compositor rather than about a ThinkPad.
#
# boot.initrd.kernelModules, not availableKernelModules: the latter only
# PERMITS a module in the initrd, and nixos-generate-config already writes it.
# Nothing generate-config produces forces the load, which is why this option
# cannot be derived from a generated hardware-configuration.nix.
#
# NixOS tier, not Home Manager: it drives boot.*, which HM cannot reach.
#
# amd:   verified (zord-old, and both AMD machines in the author's fleet).
# intel: REASONED, NOT VERIFIED. The DRM-master race is a property of starting
#        a compositor before userspace has settled, not a property of amdgpu,
#        and i915 is the equivalent module. Applying a verified mechanism to a
#        second driver is a different act from inventing a config, but it is
#        not a test. If you have an Intel machine and this is wrong, say so.
# nvidia: deliberately absent. Wayland plus the proprietary driver is a
#        project, not a line, and shipping a guess here would be a claim the
#        distribution cannot back.
{ config, lib, ... }:

let
  cfg = config.emanix.hardware;
  moduleFor = { amd = "amdgpu"; intel = "i915"; };
in
{
  options.emanix.hardware.gpu = lib.mkOption {
    type = lib.types.nullOr (lib.types.enum [ "amd" "intel" ]);
    default = null;
    example = "amd";
    description = ''
      Graphics driver to force-load in the initrd, so a compositor started
      from tty1 does not lose the DRM-master race. null contributes nothing,
      which is correct for a headless or virtualised host.
    '';
  };

  config = lib.mkIf (cfg.gpu != null) {
    boot.initrd.kernelModules = [ moduleFor.${cfg.gpu} ];
  };
}
```

- [ ] **Step 4: Write `ioshi/hi-hardware/firmware.nix`**

```nix
# Redistributable firmware, on by default.
#
# Without it, wifi does not come up on a large fraction of real laptops — the
# author's own two included, where nixos-hardware notably does NOT set it
# (verified: dropping it left the option false). A distribution whose installer
# completes and then cannot reach a network has not installed anything.
#
# Debian settled this same question the same way when it moved non-free
# firmware into the default installer media.
#
# mkDefault, not a plain definition: this is the distribution's opinion, and a
# host that would rather ship only free firmware overrides it without needing
# mkForce.
{ lib, ... }:

{
  hardware.enableRedistributableFirmware = lib.mkDefault true;
}
```

- [ ] **Step 5: Import both from `emanix.nix`**

In `emanix.nix`, replace:

```nix
  imports = [
    ./ioshi/os-system/base.nix
    ./ioshi/os-system/firstboot.nix
    ./ioshi/os-system/init.nix
  ];
```

with:

```nix
  imports = [
    ./ioshi/os-system/base.nix
    ./ioshi/os-system/firstboot.nix
    ./ioshi/os-system/init.nix
    # hi-hardware — the machine-facing tier. Imported by EVERY host, not only
    # graphical ones: gpu.nix declares an option that defaults to null and
    # contributes nothing until set, so a headless or WSL host carries the
    # declaration and none of the effect. Gating the import on a role would
    # mean `emanix.hardware.gpu` did not exist on hosts that merely have not
    # set it, which is a worse error message than a no-op.
    ./ioshi/hi-hardware/gpu.nix
    ./ioshi/hi-hardware/firmware.nix
  ];
```

- [ ] **Step 6: Run the check to verify it passes**

```bash
git add ioshi/hi-hardware/gpu.nix ioshi/hi-hardware/firmware.nix emanix.nix
nix flake check 2>&1 | tail -20
```
Expected: no errors. All five `hardware-gpu` assertions hold, and the three
existing `role-*` evaluations still pass (they now carry the new option at its
`null` default, contributing nothing).

- [ ] **Step 7: Confirm the firmware default is actually reaching a host**

```bash
nix eval --impure --raw --expr '
  let f = builtins.getFlake (toString ./.); in
  builtins.toJSON ((f.lib.mkHost {
    hostName = "checkhost"; role = "server"; username = "checkuser";
    hardware = ./checks/stub-hardware.nix; homeModules = [{}];
  }).config.hardware.enableRedistributableFirmware)'
```
Expected: `true`. A `false` here means the import did not land — mkDefault
losing to something is exactly the failure this step exists to catch.

- [ ] **Step 8: Commit**

```bash
git add ioshi/hi-hardware/gpu.nix ioshi/hi-hardware/firmware.nix \
        checks/hardware-gpu.nix emanix.nix flake.nix
git commit -m "feat(hi-hardware): own GPU bring-up and the firmware default

The EWM DRM-master race comment was written verbatim in two machine files in
a personal repo, which is what identified it as a fact about the compositor
rather than about a ThinkPad. It is now stated once, as an option, with the
initrd/availableKernelModules distinction spelled out: generate-config writes
the latter and never the former, so this cannot be derived from a generated
hardware-configuration.nix.

intel ships labelled reasoned-not-verified. nvidia is deliberately absent.

checks/hardware-gpu.nix asserts all three values, including that each omits
the other's module -- an option that loaded both would still pass a
does-it-contain test."
```

---

### Task 3: `nixos-hardware` as an emanix input

**Repo:** `~/projects/emanix`

**Files:**
- Modify: `flake.nix` (the `inputs` block; `nixos-wsl` is the last entry today)

**Interfaces:**
- Consumes: nothing.
- Produces: `emanix.inputs.nixos-hardware.nixosModules.<name>`, reachable by any
  consuming flake. Task 7 uses it. emanix does **not** re-wrap these under a
  namespace of its own — that would be a second name per machine, free to drift
  from upstream's.

- [ ] **Step 1: Add the input**

In `flake.nix`, after the `nixos-wsl` input, add:

```nix
    # The machine database — over 400 per-model modules. Carried by the
    # DISTRIBUTION rather than by each consumer: which tuning a ThinkPad needs
    # is not a personal fact, and a consumer that has to add this input itself
    # cannot use the template's `hardwareModule` field at all.
    #
    # Deliberately NOT auto-selected. nixos-hardware ships no DMI machinery and
    # its names are not a convention (lenovo-thinkpad-t14-amd-gen5 vs
    # framework-13-7040-amd vs hp-laptop-15s-fq1xxx); a prototype matcher
    # resolved 2 of 6 realistic machines. Hardware discovery is
    # nixos-generate-config. See the spec's "Why there is no hardware
    # auto-detection".
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
    };
```

Note there is **no** `inputs.nixpkgs.follows` line: `nixos-hardware` declares no
`nixpkgs` input to follow. Adding one is an error, not a tidy-up.

- [ ] **Step 2: Lock it and verify it resolves**

```bash
git add flake.nix
nix flake lock
git add flake.lock
nix eval --impure --json --expr \
  'builtins.attrNames (builtins.getFlake (toString ./.)).inputs.nixos-hardware.nixosModules' \
  | python3 -c 'import json,sys; a=json.load(sys.stdin); print(len(a), "modules"); print("lenovo-thinkpad-t14-amd-gen5" in a)'
```
Expected: a module count in the low 400s, then `True`. The named module is the
one rafik needs in Task 7; if it is absent, stop — the input resolved to
something unexpected.

- [ ] **Step 3: Confirm nothing else moved**

```bash
nix flake check 2>&1 | tail -20
```
Expected: no errors. An unused input must not change any evaluation. If a
`role-*` check moved, something is importing nixos-hardware implicitly and that
needs explaining before proceeding.

- [ ] **Step 4: Commit**

```bash
git add flake.nix flake.lock
git commit -m "feat(flake): take nixos-hardware as an input

Carried by the distribution rather than by each consumer: which tuning a
ThinkPad needs is not a personal fact, and a consumer that must add the input
itself cannot use the template's hardwareModule field at all.

Not followed to nixpkgs -- nixos-hardware declares no nixpkgs input. Not
auto-selected either: it ships no DMI machinery, its names are not a
convention, and a prototype matcher resolved 2 of 6 realistic machines."
```

---

### Task 4: The template consumes `mkDisk`, and gains `gpu`

**Repo:** `~/projects/emanix`

**Files:**
- Delete: `templates/default/disko.nix`
- Modify: `templates/default/host.nix`
- Modify: `templates/default/flake.nix`
- Modify: `templates/default/README.md`
- Modify: `checks/template-host.nix:47` (the `import ../templates/default/disko.nix` line)

**Interfaces:**
- Consumes: `emanix.lib.mkDisk` (Task 1); `emanix.hardware.gpu` (Task 2);
  `emanix.inputs.nixos-hardware` (Task 3).
- Produces: a `host.nix` fixture shape with two new fields, `gpu` and
  `hardwareModule`, which Task 5's installer writes.

- [ ] **Step 1: Update the check first, and watch it fail**

In `checks/template-host.nix`, extend the fixture:

```nix
  fixture = {
    hostName = "templatehost";
    device = "/dev/vda";
    luks = false;
    filesystem = "btrfs";
    swapSize = "0";
    gpu = "amd";
    hardwareModule = null;
  };
```

and replace the disko module line:

```nix
          (import ../templates/default/disko.nix { host = fixture; })
```

with:

```nix
          (import ../lib/disk.nix {
            inherit (fixture) device luks filesystem swapSize;
          })
          { emanix.hardware.gpu = fixture.gpu; }
```

Run: `git add checks/template-host.nix && nix flake check 2>&1 | tail -20`
Expected: PASSES already (both `lib/disk.nix` and the option exist from Tasks
1–2). This step is the check catching up to the template, not a red test —
`templates/default/disko.nix` is now unreferenced by the check, which is what
lets Step 2 delete it safely.

- [ ] **Step 2: Delete the promoted file**

```bash
git rm templates/default/disko.nix
```

- [ ] **Step 3: Update `templates/default/host.nix`**

```nix
# The other machine-specific fact, alongside `username` in flake.nix (sed'd
# in by fresh-emanix-install during an interactive install, since mkHost
# takes it as a top-level argument rather than a value read out of a host
# module). Everything else in the template is static and reads from here.
# Edit it by hand and rebuild.
{
  hostName = "emanix";
  device = "/dev/vda";
  luks = false;
  filesystem = "btrfs";
  swapSize = "0";

  # Graphics driver to force-load in the initrd. The installer asks and sets
  # this; null is correct for a headless or virtualised host. A graphical host
  # with the wrong value here boots to a black screen, because a compositor
  # started from tty1 loses the DRM-master race — see emanix's
  # ioshi/hi-hardware/gpu.nix.
  gpu = null;

  # OPTIONAL. The name of a nixos-hardware module for this exact machine, e.g.
  # "lenovo-thinkpad-t14-amd-gen5". Leave null unless you know yours: emanix
  # does not guess, because nixos-hardware's names are not a convention and
  # guessing wrong before a disk is wiped is worse than not guessing. Browse
  # https://github.com/NixOS/nixos-hardware for the list.
  hardwareModule = null;
}
```

- [ ] **Step 4: Update `templates/default/flake.nix`**

Replace the whole `outputs` block with:

```nix
  outputs = { self, nixpkgs, emanix, disko, ... }:
    let
      system = "x86_64-linux";
      host = import ./host.nix;
    in
    {
      nixosConfigurations.${host.hostName} = emanix.lib.mkHost {
        inherit (host) hostName;
        role = "workstation";
        username = "youruser";
        hardware = ./hardware-configuration.nix;
        extraModules = [
          disko.nixosModules.disko
          (emanix.lib.mkDisk {
            inherit (host) device luks filesystem swapSize;
          })
          { emanix.hardware.gpu = host.gpu; }
          ./configuration.nix
          emanix.nixosModules.ewm
        ]
        # Optional per-model tuning, only when host.nix names a module. The
        # input comes from emanix so this file needs no input of its own.
        ++ nixpkgs.lib.optional (host.hardwareModule != null)
          emanix.inputs.nixos-hardware.nixosModules.${host.hardwareModule};
      };
    };
```

- [ ] **Step 5: Update `templates/default/README.md`**

Replace the paragraph beginning "The machine-specific parts of this repo" with:

```markdown
# An emanix host

The machine-specific parts of this repo are `host.nix` and the `username` set
in `flake.nix`. Everything else reads from those.

If `fresh-emanix-install` generated this repo for you, both are already set —
skip straight to the rebuild command below. If you started from
`nix flake init -t github:scott-whitson/emanix`, set `username` in
`flake.nix` yourself before rebuilding.

`host.nix` has two fields worth a second look:

- `gpu` — `"amd"`, `"intel"` or `null`. Forces the graphics driver to load in
  the initrd, so a compositor starting from tty1 does not come up before the
  GPU does. A graphical machine with this wrong boots to a black screen.
- `hardwareModule` — optional. The name of a
  [nixos-hardware](https://github.com/NixOS/nixos-hardware) module for your
  exact machine, such as `"lenovo-thinkpad-t14-amd-gen5"`. emanix does not
  guess this for you; leave it `null` if you do not know yours.

Before the first rebuild, generate a hardware module:

    sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix

Then rebuild:

    sudo nixos-rebuild switch --flake .#$(nix eval --raw -f host.nix hostName)

Documentation: https://emanix.net
```

- [ ] **Step 6: Verify**

```bash
git add -A templates/default checks/template-host.nix
nix flake check 2>&1 | tail -20
grep -rn 'templates/default/disko.nix' . --exclude-dir=.git || echo "no dangling references"
```
Expected: no errors, and no remaining reference to the deleted file. A hit in
`installer/fresh-emanix-install` would mean Task 5's work is a prerequisite —
check, and reorder if so.

- [ ] **Step 7: Commit**

```bash
git add -A templates/default checks/template-host.nix
git commit -m "refactor(template): consume lib.mkDisk, add gpu and hardwareModule

The disk layout moves to the distro (lib/disk.nix); the template keeps the
machine facts and now states two more of them. gpu is asked for by the
installer. hardwareModule is optional and hand-set: emanix does not guess a
nixos-hardware module name, because guessing wrong immediately before a disk
is wiped is worse than not guessing.

checks/template-host.nix follows the template rather than the deleted file."
```

---

### Task 5: The installer asks for graphics

**Repo:** `~/projects/emanix`

**Files:**
- Modify: `installer/fresh-emanix-install` — `interactive_prompts()` (ends at
  the swap-size loop) and `write_generated_flake()` (the `host.nix` heredoc)
- Modify: `tests/installer-modes.sh`

**Interfaces:**
- Consumes: the `host.nix` shape from Task 4.
- Produces: `GPU`, a shell variable holding `amd`, `intel` or `none`, written
  into `host.nix` as `"amd"` / `"intel"` / `null`.

- [ ] **Step 1: Write the failing test**

Append to `tests/installer-modes.sh`, before its final summary block:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/installer-modes.sh`
Expected: the three new assertions FAIL; the pre-existing ones still pass.

- [ ] **Step 3: Add the validator and the prompt**

In `installer/fresh-emanix-install`, beside `validate_swapsize`, add:

```bash
# Same reasoning as validate_swapsize: reject at the prompt rather than let a
# bad value reach the heredoc that writes host.nix.
validate_gpu() {
  printf '%s' "$1" | grep -qE '^(amd|intel|none)$'
}

# The PCI vendor ID, not the model name. 0x1002 is AMD, 0x8086 is Intel. This
# is a two-value lookup and it only picks the DEFAULT answer — the user is
# still asked. emanix does not auto-detect hardware; see the spec's "Why there
# is no hardware auto-detection".
detect_gpu_default() {
  local vga
  vga="$(lspci -nn 2>/dev/null | grep -iE 'vga|3d controller' || true)"
  case "$vga" in
    *1002:*) echo amd ;;
    *8086:*) echo intel ;;
    *) echo none ;;
  esac
}
```

At the end of `interactive_prompts()`, after the swap-size `while` loop:

```bash
  # Graphics. EWM launches from tty1 and loses the DRM-master race unless the
  # driver is forced into the initrd, so a wrong answer here is a black screen
  # on a machine whose owner has no other console. Asked, never assumed;
  # lspci only supplies the default.
  gpu_default="$(detect_gpu_default)"
  while :; do
    read -rp "Graphics [amd/intel/none] (${gpu_default}): " a
    GPU="${a:-$gpu_default}"
    validate_gpu "$GPU" && break
    warn "answer amd, intel, or none."
  done
```

- [ ] **Step 4: Write it into the generated `host.nix`**

In `write_generated_flake()`, beside the existing defensive `validate_swapsize`
call, add:

```bash
  validate_gpu "$GPU" ||
    die "internal error: graphics answer '$GPU' failed validation at generation time."
```

Then replace the `host.nix` heredoc with:

```bash
  # `none` becomes a bare `null`, not the string "null": emanix.hardware.gpu is
  # a nullOr enum, so a quoted "null" typechecks as a string and then fails the
  # enum at evaluation — long after the disk has been repartitioned.
  case "$GPU" in
    none) gpu_nix="null" ;;
    *) gpu_nix="\"${GPU}\"" ;;
  esac

  cat > "$dest/host.nix" <<EOF
# Generated by fresh-emanix-install on $(date -u +%Y-%m-%dT%H:%M:%SZ).
# The only file in this repo describing this machine.
{
  hostName = "${FLAKE_HOST}";
  device = "${DISK}";
  luks = ${LUKS};
  filesystem = "${FSTYPE}";
  swapSize = "${SWAPSIZE}";
  gpu = ${gpu_nix};

  # OPTIONAL. The name of a nixos-hardware module for this exact machine, e.g.
  # "lenovo-thinkpad-t14-amd-gen5". The installer does not guess it: see
  # https://github.com/NixOS/nixos-hardware for the list.
  hardwareModule = null;
}
EOF
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
./tests/installer-modes.sh
bash -n installer/fresh-emanix-install && echo "syntax ok"
nix run nixpkgs#shellcheck -- installer/fresh-emanix-install 2>&1 | tail -20
```
Expected: `PASS` from the test script, `syntax ok`, and no new shellcheck
findings beyond any the file already carried.

- [ ] **Step 6: Verify the generated file actually parses as Nix**

```bash
tmp=$(mktemp -d)
cat > "$tmp/host.nix" <<'EOF'
{ hostName = "x"; device = "/dev/vda"; luks = false; filesystem = "btrfs";
  swapSize = "0"; gpu = null; hardwareModule = null; }
EOF
nix eval --impure --json --expr "import $tmp/host.nix"
rm -rf "$tmp"
```
Expected: JSON with `"gpu": null` — a bare null, not `"null"`. This is the
failure the test in Step 1 guards against, confirmed end-to-end.

- [ ] **Step 7: Commit**

```bash
git add installer/fresh-emanix-install tests/installer-modes.sh
git commit -m "feat(installer): ask for the graphics driver

emanix.hardware.gpu cannot come from nixos-generate-config, which writes
availableKernelModules and never kernelModules, and the EWM tty1 race needs
the forced form. So the installer asks, defaulting from the lspci PCI vendor
ID -- a two-value lookup, not model-name archaeology. Asking is not guessing.

'none' emits a bare Nix null rather than the string \"null\", which would
typecheck as a string and only fail the nullOr enum at evaluation, long after
the disk has been repartitioned. Tested."
```

---

### Task 6: dotfiles adopts `mkDisk` for rafik — provably inert

**Repo:** `~/dotfiles`

**Files:**
- Delete: `ioshi/hi-hardware/disko/rafik.nix`
- Modify: `flake.nix` (rafik's `extraModules`, and the `diskoConfigurations`
  output which still names the deleted file)

**Interfaces:**
- Consumes: `emanix.lib.mkDisk` (Task 1).
- Produces: nothing new. This task's whole deliverable is that **nothing
  changes** — rafik's `toplevel.drvPath` must be byte-identical before and
  after.

**Why this is separate from Task 7:** rafik is a running machine. Swapping the
disko file for a `mkDisk` call is provably inert and can land today. Deleting
its hardware file is *not* inert and must wait for the reinstall, which is the
only moment a regenerated `hardware-configuration.nix` exists to replace it.

- [ ] **Step 1: Record the baseline drvPath**

```bash
cd ~/dotfiles
git status --porcelain   # must be clean; a dirty tree invalidates the comparison
nix eval --raw .#nixosConfigurations.rafik.config.system.build.toplevel.drvPath \
  > /tmp/rafik-before.drv
cat /tmp/rafik-before.drv; echo
```
Expected: a single `/nix/store/….drv` path. Save it — Step 4 compares against
this exact string.

- [ ] **Step 2: Point the emanix input at the new commit**

```bash
nix flake update emanix   # older nix: nix flake lock --update-input emanix
git add flake.lock
```
Note: this alone will change the drvPath, because emanix now imports
`hi-hardware/{gpu,firmware}.nix`. `firmware.nix` sets
`enableRedistributableFirmware` via `mkDefault`, which rafik's own hardware file
already sets to `true` at normal priority — so the merged value is unchanged,
but confirm rather than assume in Step 4.

- [ ] **Step 3: Replace the disko file with a `mkDisk` call**

```bash
git rm ioshi/hi-hardware/disko/rafik.nix
```

In `flake.nix`, in rafik's `extraModules`, replace:

```nix
            disko.nixosModules.disko
            ./ioshi/hi-hardware/disko/rafik.nix
```

with:

```nix
            disko.nixosModules.disko
            # The distro's layout, with this machine's facts. Proven identical
            # to the hand-written ioshi/hi-hardware/disko/rafik.nix it
            # replaces (2417 bytes of evaluated disko.devices — see emanix's
            # docs/superpowers/specs/2026-09-04-hardware-layer-design.md,
            # Gate 1).
            (emanix.lib.mkDisk {
              device = "/dev/nvme0n1";
              luks = true;
              filesystem = "btrfs";
              swapSize = "0";
            })
```

And in the `diskoConfigurations` output, replace:

```nix
        rafik = import ./ioshi/hi-hardware/disko/rafik.nix;
```

with:

```nix
        rafik = emanix.lib.mkDisk {
          device = "/dev/nvme0n1";
          luks = true;
          filesystem = "btrfs";
          swapSize = "0";
        };
```

- [ ] **Step 4: Prove it is inert**

```bash
cd ~/dotfiles
git add -A
nix eval --raw .#nixosConfigurations.rafik.config.system.build.toplevel.drvPath \
  > /tmp/rafik-after.drv
diff /tmp/rafik-before.drv /tmp/rafik-after.drv && echo "INERT — drvPath identical"

# And confirm the firmware option did not move.
nix eval .#nixosConfigurations.rafik.config.hardware.enableRedistributableFirmware
```
Expected: `INERT — drvPath identical`, and `true`.

**If the drvPath differs, stop.** Do not proceed and do not rebuild. Find the
cause first:

```bash
# Which module introduced the difference. Compare the EVALUATED disko layout
# first -- it is cheap and it is the thing this task changed:
nix eval --json .#nixosConfigurations.rafik.config.disko.devices \
  | python3 -m json.tool --sort-keys > /tmp/rafik-disko-after.json
git stash && nix eval --json .#nixosConfigurations.rafik.config.disko.devices \
  | python3 -m json.tool --sort-keys > /tmp/rafik-disko-before.json && git stash pop
diff -u /tmp/rafik-disko-before.json /tmp/rafik-disko-after.json
```
If the disko layout is identical but the drvPath still differs, the cause is
the emanix input bump in Step 2, not this task's edit — check
`hardware.enableRedistributableFirmware` and `boot.initrd.kernelModules` before
concluding anything. A difference in the *layout* means it is not what Gate 1
measured, which makes the reinstall unsafe.

- [ ] **Step 5: Verify the other two hosts did not move either**

```bash
for h in datacore whistle; do
  printf '%-10s ' "$h"
  nix eval --raw .#nixosConfigurations.$h.config.system.build.toplevel.drvPath
  echo
done
```
Compare against the same values from before Step 2 if you recorded them; if
not, at minimum confirm both still **evaluate**. datacore and whistle are out
of scope and must not have been touched.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(rafik): take the disk layout from emanix.lib.mkDisk

Replaces the hand-written ioshi/hi-hardware/disko/rafik.nix with a call to the
distro's parameterized layout. Provably inert: rafik's toplevel drvPath is
byte-identical before and after, and the layout was diffed against the deleted
file at 2417 bytes of evaluated disko.devices before any of this was written.

The hardware file is NOT touched here -- deleting it is not inert and waits
for the reinstall, which is the only moment a regenerated
hardware-configuration.nix exists to replace it."
```

---

### Task 7: rafik's reinstall — the acceptance test

**Repo:** `~/dotfiles`

**Run this on reinstall day, with the new 1 TB SSD installed. Not before.**

**Files:**
- Delete: `ioshi/hi-hardware/lenovo-t14-gen5-amd.nix`
- Create: `hosts/rafik/hardware-configuration.nix` (generated, then committed)
- Modify: `hosts/rafik/configuration.nix` (gains `powerManagement`,
  `power-profiles-daemon`, `emanix.hardware.gpu`)
- Modify: `flake.nix` (rafik's `hardware =` argument; drop the `nixos-hardware`
  input and its `follows`; source the module from emanix instead)

**Interfaces:**
- Consumes: everything from Tasks 1–6.
- Produces: a rafik whose only hardware inputs are a generated file plus the
  distro.

**This task is deliberately not inert.** Its drvPath will differ, in three
known ways: the hand-written `availableKernelModules`/`kernelParams` are
replaced by generate-config's, `amdgpu` now arrives via `emanix.hardware.gpu`,
and `nixos-hardware` resolves from emanix's lock rather than dotfiles'. Each is
intended. Verify them individually rather than accepting the diff wholesale.

- [ ] **Step 1: Before wiping — confirm the host key is staged**

```bash
ssh-keygen -lf ~/dotfiles/keys/rafik_host_ed25519
ssh-keygen -lf ~/dotfiles/keys/rafik_host_ed25519.pub
```
Expected: **identical fingerprints**, matching
`SHA256:iSfcodiwkeZlJIerPunJ1WmI+nRqlBQxYVy1Igc3UhM`. A mismatch is what the
installer's key preflight fails closed on, and the private half cannot be
recovered once the old drive is out. **Stop if these disagree.**

- [ ] **Step 2: Install**

Boot the emanix ISO and run the pre-staged path — rafik is a known host, so no
prompts:

```bash
sudo fresh-emanix-install rafik --check-only   # read the checklist first
sudo fresh-emanix-install rafik
```
Expected: the preflight reports repo, keys, UEFI, network and disk all present;
disko partitions; `nixos-install` completes. `mkDisk` and `gpu.nix` are what is
being exercised.

- [ ] **Step 3: Capture the generated hardware config**

On the freshly installed rafik:

```bash
sudo nixos-generate-config --show-hardware-config \
  > /tmp/rafik-hardware-configuration.nix
cat /tmp/rafik-hardware-configuration.nix
```
Read it. It should contain `fileSystems` entries, `boot.initrd.availableKernelModules`,
and `nixpkgs.hostPlatform`. Copy it to `~/dotfiles/hosts/rafik/hardware-configuration.nix`.

**Check for a `fileSystems` collision before committing it.** disko already
generates those entries, and this is exactly the latent hazard documented in
`hi-hardware/hp-15-ef2013dx.nix` — `options` is list-typed, so two definitions
concatenate rather than override. If the generated file declares `fileSystems`,
delete those stanzas from it and keep disko as the single source. Leave a
comment saying so.

- [ ] **Step 4: Move the choices into the host, delete the machine file**

In `hosts/rafik/configuration.nix`, add:

```nix
  # Moved out of the deleted ioshi/hi-hardware/lenovo-t14-gen5-amd.nix. These
  # are CHOICES, not machine facts: a host that wanted a performance governor
  # would legitimately set neither, which is why emanix does not.
  powerManagement.enable = true;
  services.power-profiles-daemon.enable = true;

  # Force amdgpu into the initrd — EWM launches from tty1 autologin and loses
  # the DRM-master race against late GPU bring-up otherwise. The reasoning now
  # lives once, in emanix's ioshi/hi-hardware/gpu.nix, instead of being copied
  # into every machine file.
  emanix.hardware.gpu = "amd";
```

Then:

```bash
cd ~/dotfiles
git rm ioshi/hi-hardware/lenovo-t14-gen5-amd.nix
```

- [ ] **Step 5: Rewire the flake**

In `flake.nix`, change rafik's hardware argument:

```nix
          hardware = ./hosts/rafik/hardware-configuration.nix;
```

Replace the nixos-hardware module line in rafik's `extraModules`:

```nix
            nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen5
```

with:

```nix
            # Via emanix, which carries the machine database now.
            emanix.inputs.nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen5
```

Delete the `nixos-hardware` input block and remove `nixos-hardware` from the
`outputs` argument list.

- [ ] **Step 6: Verify each intended change, individually**

```bash
cd ~/dotfiles
git add -A

# amdgpu still forced into the initrd — the black-screen guard.
nix eval .#nixosConfigurations.rafik.config.boot.initrd.kernelModules \
  | tr ' ' '\n' | grep -q amdgpu && echo "ok: amdgpu forced in initrd"

# Firmware still on.
nix eval .#nixosConfigurations.rafik.config.hardware.enableRedistributableFirmware

# No duplicate mount options — the hp-15 hazard, checked rather than assumed.
nix eval --json .#nixosConfigurations.rafik.config.fileSystems.\"/\".options \
  | python3 -c 'import json,sys; o=json.load(sys.stdin); print(o); assert len(o)==len(set(o)), "DUPLICATE mount options"'

# The other two hosts still evaluate.
for h in datacore whistle; do
  nix eval --raw .#nixosConfigurations.$h.config.system.build.toplevel.drvPath >/dev/null \
    && echo "ok: $h evaluates"
done
```
Expected: all four checks pass. The duplicate-options assertion is the one that
catches a generated `fileSystems` block colliding with disko's.

- [ ] **Step 7: Rebuild and reboot**

```bash
sudo nixos-rebuild switch --flake ~/dotfiles#rafik
sudo reboot
```
After the reboot, confirm the two things this whole design is for:

```bash
# amdgpu actually present in the running kernel's early boot, not merely
# configured: this is the difference the whole gpu.nix option exists to make.
lsinitrd "/boot/EFI/nixos/$(ls -1 /boot/EFI/nixos | grep initrd | head -1)" 2>/dev/null \
  | grep -c amdgpu \
  || echo "lsinitrd unavailable; fall back to the runtime check below"

# Runtime: the driver is bound and a DRM device exists.
lsmod | grep -q '^amdgpu' && echo "ok: amdgpu loaded"
ls /dev/dri/card* && echo "ok: DRM device present"

# The real test: a graphical EWM session on tty1.
systemctl --user status ewm 2>/dev/null | head -5
```
Expected: `amdgpu loaded`, a `/dev/dri/card0`, and a graphical session rather
than a black screen. That is Gate 3.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(rafik): hardware comes from emanix and generate-config

Reinstalled on the new 1TB SSD. The hand-written machine file is gone: its
amdgpu-in-initrd reasoning moved to emanix (ioshi/hi-hardware/gpu.nix), its
firmware line to emanix's default, its kernelParams and availableKernelModules
to a generated hardware-configuration.nix, and its power management to the
host config, where a choice belongs.

nixos-hardware now arrives via emanix rather than a dotfiles input.

Deliberately not inert -- verified per intended change rather than wholesale,
including an assertion that no fileSystems options duplicated, which is the
hazard hp-15-ef2013dx.nix still documents."
```

---

## Follow-ups, not in this plan

- **datacore's `fileSystems` block.** `hi-hardware/hp-15-ef2013dx.nix` hand-writes
  mount entries that disko also generates; `options` is list-typed so they
  concatenate rather than override. Currently inert, documented in the file as a
  live hazard. Gate 1 showed datacore's *disko* file is already expressible via
  `mkDisk` with `extraSubvolumes` (2522 bytes, identical) — so when datacore's
  turn comes, only the hardware half moves the closure.
- **whistle** needs nothing: WSL supplies its own mounts and has no GPU to force.
- **`intel` in `gpu.nix`** is reasoned, not verified. The first Intel machine to
  run emanix either confirms it or corrects it.
