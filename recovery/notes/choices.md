# Architecture choices — rationale

One-liner summary of decisions made in the 2026-04-18 DR design.
Full reasoning now lives in vault: `~/docs/vault/Whitsgrove/Debian Recovery - Minimum Viable System.md` and `~/docs/vault/Whitsgrove/Debian Migration Plan.md`.

## Filesystem: Btrfs with subvolumes (`@`, `@home`, `@var_log`, `@pkg`, `@snapshots`)
Subvolumes give the "wipe root without touching home" property of separate partitions,
plus shared free space and coherent system snapshots. `@home`/`@var_log`/`@pkg` are
deliberately **not** snapshotted — snapshots protect rollback of `/`, user data is
protected by backups.

## Encryption: LUKS2 with argon2id KDF
Laptop leaves the house → at-rest encryption required. `/boot` stays unencrypted on the
EFI partition; encrypting it is possible but adds complexity without meaningful gain
for the laptop threat model.

## Bootloader: GRUB (with `GRUB_ENABLE_CRYPTODISK=y`)
Enables `grub-btrfs` which auto-generates boot entries for snapshots. That's the whole
reason snapshots are useful — booting into an old snapshot when `/` is broken.
systemd-boot is simpler but has no equivalent snapshot-boot UX. Limine (Omarchy) is
nice but has a smaller community for learners looking up errors.

## Swap: zram only, no swap partition
30 GiB RAM + zram makes disk swap unnecessary. No hibernate support by design —
add a swapfile later if needed.

## Snapshot stack: snapper + snap-pac + grub-btrfs
Standard Arch stack. `snap-pac` auto-snapshots before/after every `pacman` operation —
the main value prop ("a bad update borked my system → boot the pre-update snapshot").

## `/home` as subvolume, not separate partition
The current layout has `/home` on its own partition (`nvme0n1p3`). Reinstall folds it
into the main Btrfs pool. Shared free space wins; the "separate partition" reinstall-
isolation property is already covered by subvolumes.

## `p8` (gdrive partition) preserved across reinstalls
`nvme0n1p8` holds 157 GiB of locally-cached Google Drive data. Re-syncing it from the
cloud takes hours. `partition.sh` is designed to verify and preserve it.
