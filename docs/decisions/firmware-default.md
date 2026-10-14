# Redistributable firmware is on for every host

**Applies to** `emanix.nix`'s import of `modules/firmware.nix`;
`hardware.enableRedistributableFirmware = lib.mkDefault true`.

## Decision

Imported unconditionally — every host, graphical or not.

## What that costs

The default contributes unconditionally and pulls `linux-firmware`, **roughly
791 MiB of closure**, onto the headless server that has no wifi to bring up and
the WSL guest that has no hardware at all, as much as onto the laptop the
default exists for.

## Why it is still right

A distribution whose installer completes onto a laptop that then cannot see its
wifi has not installed anything, and the operator has no network with which to
fix it. The cost of being wrong is asymmetric, and it is asymmetric in the
direction of shipping the firmware. Debian reached the same conclusion for the
same reason.

## Rejected: gate the import on "is this a WSL or headless host"

That puts a host SHAPE into the distribution, which is precisely what this
design does not do. emanix is ONE shape.

## Why mkDefault

It is one line to decline: a host writes
`hardware.enableRedistributableFirmware = false;` and wins with no `mkForce`.

## Assertion: do not decline it on a graphical host

Declining the firmware while `emanix.hardware.gpu` is set is the black-screen
combination. The assertion in `modules/gpu.nix` is what stops it building.

## Why `gpu.nix` is imported even though it is inert until set

It declares an option defaulting to `null`, and its config block is behind
`mkIf`, so a host carries the declaration and none of the effect. Gating that
import would mean `emanix.hardware.gpu` did not exist on hosts that have merely
not set it — a worse error message than a no-op.
