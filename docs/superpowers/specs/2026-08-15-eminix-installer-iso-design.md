# eminix installer ISO — design

> **Date:** 2026-08-15
> **Status:** Design — approved by Scott (full redesign chosen over "finish the
> stick flow" on 2026-08-15). Awaiting implementation plan (written alongside).
> **Scope:** The install experience of the eminix distribution. Produces a
> bootable installer ISO as a first-class flake output, hardens the installer
> script, and (phase B) adopts agenix-rekey so a fresh host no longer depends
> on hand-maintained recipient lists.
> **Prior art:** `docs/ioshi/eminix-install.md` (the runbook this supersedes),
> `docs/superpowers/specs/2026-08-05-datacore-nixos-design.md` (decision 8:
> the HP inherits the old box's host key), `docs/superpowers/plans/2026-08-08-datacore-cutover.md`
> (the cutover this will carry out), and the retired `ventoy/` bootstrap
> (mentioned in `docs/ioshi/history/deploy-checklist.md`).

## Problem

Installing eminix on bare metal is the weakest part of the distribution. The
2026-08-13/14 HP staging session surfaced every failure mode at once:

1. **Ventoy cannot be installed from NixOS.** Its tools (`mkexfatfs`, …) are
   glibc-dynamic binaries that NixOS refuses to exec. The workaround —
   wrapper scripts that fake `mkexfatfs -V`, rewrite `-s 256` to `-s 512`, and
   require `nix-shell -p nix-ld` — cost six rounds and only worked because
   exFAT tolerates a 512-byte sector size we forced onto a 256-sector device.
   Ventoy is the wrong tool for a workflow driven from a NixOS machine.
2. **The runbook's own path is wrong.** `eminix-install.md` and the cutover
   plan both tell you to run
   `sudo bash /run/media/*/Ventoy/dotfiles/installer/fresh-eminix-install`.
   The NixOS minimal ISO does **not** auto-mount USB under `/run/media` —
   there is no `/run/media` at all. The documented flow fails on first
   contact, and the `*` glob hides the failure.
3. **Staging is manual and fragile.** The private repo cannot be fetched on a
   fresh machine (no GitHub auth on a live ISO), so the flake must be carried
   physically. The mount→copy→unmount dance failed in four distinct ways in
   one session: copies landing in an unmounted directory, exFAT root-owned
   mounts blocking plain `cp`, a wrong filename (`ssh_host_ed25519` vs the
   real Debian `ssh_host_ed25519_key`), and the `datacore-keys/` directory
   silently missing from the stick.
4. **Guesswork.** Device names, mount points, partition labels, and the target
   disk are all resolved by hand, by a user who is also operating the target
   machine.
5. **Physical secrets.** The host private key rides on a FAT/exFAT stick — no
   Unix permissions, `chmod 600` is a no-op, and it stays there after the
   install unless someone remembers to delete it.

The session ended with the decision that this is not the experience the
distribution should have, and that the fix is the thing Scott originally asked
for: **make eminix produce its own installer ISO.**

## Goal

One command produces the distribution artifact; one command runs the install:

```bash
# on rafik (the trusted builder)
bin/eminix-iso /dev/sdX

# on the target machine, booted from the USB
fresh-eminix-install datacore
```

No Ventoy. No staging. No GitHub auth. No globs. No manual device discovery.
`dd` is the only flashing tool, and it is everywhere.

## Decisions

| Question | Decision |
| --- | --- |
| What is the artifact? | A bootable NixOS **installer ISO**, built from the flake via `nixosConfigurations.installer.config.system.build.isoImage`, written with `dd`. Ventoy is retired from the eminix flow (it can still serve other ISOs if Scott wants). |
| How is it built? | Native ISO builder (`installation-cd-minimal.nix` + `isoImage`), **not** nixos-generators. The flake already composes `nixosSystem`s; adding a flake input to wrap one format buys nothing. (`nixos-rebuild build-image --image-variant iso` exists but the explicit output is clearer in a flake.) |
| Is the installer an eminix host? | **No.** It is a tool, not a host: a separate `nixosConfigurations.installer` that imports `installation-cd-minimal.nix` + `installer/iso.nix`. It does **not** go through `mkHost` and imports no role profile — the installer must not become a workstation or a server. |
| Where does the flake live on the ISO? | At **`/etc/eminix/dotfiles`**, staged by a copy derivation (excludes `result` and VCS metadata). `/etc` is on the live overlay, so it survives the disko step — unlike a stick mounted under `/mnt`, which disko hides when it mounts the target root (the trap from 2026-08-14). Encrypted `.age` files ride along in the repo; they are already host-encrypted and are no secret change from today. |
| Where do host keys come from? | A **`keys/` directory** in the repo — the public halves (`<host>_host_ed25519.pub`) are committed (they are already recipient strings in `secrets.nix` today); the private halves are gitignored and staged by `bin/eminix-iso` from `/etc/ssh` or copied off the source box. Whatever is present is baked into the ISO at build time. An ISO built without private keys still builds — it just lacks baked identity, and `fresh-eminix-install` falls back to today's staged-dir behavior. |
| Is baking private keys into the ISO acceptable? | Yes, with the tradeoff recorded: **the ISO is your identity.** It already holds the encrypted secrets; adding the keys makes it sufficient on its own. Mitigations: built only on the trusted machine, `keys/` is gitignored (committing is refused), the ISO is read-only (no FAT permission lies), and the key never lingers on a stick after install. For identity-inheriting installs (datacore, spec decision 8) the private key **must** ride the artifact — decryption at first boot needs it. Phase B removes the need only for fresh-identity hosts. |
| How does the installer find things? | **No globs, no guessing.** Repo: `$EMINIX_REPO` → `realpath $0` → `/etc/eminix/dotfiles` → a bounded search of known mounts. Disk: auto-detect the largest non-removable, read-only-excluded block device, confirm interactively, `--disk` override. A printed preflight checklist lists repo/keys/UEFI/network/disk/Secure-Boot status before anything destructive happens. |
| What does the ISO provide beyond the repo? | Both installer scripts on PATH, `git`, `disko` (from the flake input, not a `nix run` fetch), `iwd` + NetworkManager (WiFi), `exfatprogs`/`dosfstools`, an ephemeral `sshd` for driving the target from rafik, a boot banner (`/etc/issue`) with the three commands, and volume label `eminix`. |
| How do secrets evolve (phase B)? | Adopt **agenix-rekey** (oddlama). Master identity = scott's `~/.ssh/id_ed25519` (age); `storageMode = "local"` with a **gitignored** `secrets/rekeyed/<host>/`; `secrets.nix` is deleted; `hostPubkey` per host (from `/etc/ssh/...` for existing hosts, the inherited key file for datacore). New hosts bootstrap via rekey's **dummy-pubkey** path: install with a dummy recipient → first boot generates the real key → `agenix rekey` on the builder → reboot. |
| Does phase B remove the physical secret? | Only for fresh-identity hosts. Datacore keeps inheriting the old box's key (decision 8), so its private key still rides the ISO at install time — that is identity preservation, not a rekey problem. Phase B's win is deleting `secrets.nix` and the hand-maintained recipient list, plus a clean story for every *future* host. |
| What happens to the old flow? | Retired. `eminix-install.md` is rewritten around the ISO; the cutover plan's staging tasks are superseded (deltas listed in the plan). The `datacore-keys/`-beside-the-repo convention dies with Ventoy. |

## Target architecture

```
keys/                          # gitignored; per-host keypairs the ISO bakes in
  <host>_host_ed25519.pub      # committed (public — already in secrets.nix today)
  <host>_host_ed25519         # gitignored private half; staged at ISO build time

installer/
  iso.nix                      # NEW: the installer module (see below)
  fresh-eminix-install         # v2: repo auto-location, disk auto-detect, checklist
  eminix-firstboot             # unchanged (still packaged by os-system/firstboot.nix)

bin/
  eminix-iso                   # NEW: validate keys/ -> nix build isoImage -> dd -> sync

flake.nix                      # + nixosConfigurations.installer (NOT via mkHost)
secrets/rekeyed/<host>/        # phase B: gitignored agenix-rekey output
```

### `installer/iso.nix` (shape)

```nix
{ pkgs, lib, inputs, ... }:
{
  imports = [ "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix" ];

  isoImage.volumeID = "eminix";   # boot menu shows eminix, not nixos-26.11…

  # The flake at a fixed, /mnt-safe path (staged by a copy derivation that
  # drops `result` and VCS metadata).
  environment.etc."eminix/dotfiles".source = <staged repo>;

  environment.systemPackages = with pkgs; [
    git                              # minimal ISO lacks it; firstboot clones with it
    exfatprogs dosfstools            # mounting arbitrary USB sticks
    (pkgs.writeShellApplication { name = "fresh-eminix-install"; text = builtins.readFile ./fresh-eminix-install; })
    (pkgs.writeShellApplication { name = "eminix-firstboot";    text = builtins.readFile ./eminix-firstboot; })
  ] ++ lib.optional (keys staged) (import <bake-keys-derivation>);

  networking.wireless.iwd.enable = true;   # WiFi on the HP etc.
  services.openssh.enable = true;          # ephemeral host key; drive from rafik
  systemd.services.eminix-motd = { ... };  # print the three commands at boot

  # disko baked from the flake input so the installer does not `nix run` it.
}
```

Baking decisions (key presence, disko availability) are evaluated with
`builtins.pathExists` against the *working tree* of the build, so an ISO built
from a fresh clone without `keys/` degrades gracefully.

### `fresh-eminix-install` v2 (behavior)

1. **Resolve repo** — `$EMINIX_REPO`, then `realpath $0`, then `/etc/eminix/dotfiles`, then a bounded scan of mounted volumes for `dotfiles/flake.nix`. Dies with the candidates it tried.
2. **Resolve keys** — baked `/etc/eminix/keys/<host>/` if present; else `../<host>-keys/` beside the repo (today's convention); else a prompt for a directory. Fingerprint check against the agenix recipient stays.
3. **Resolve disk** — `lsblk -dno NAME,SIZE,TRAN,RO` → filter out `usb`/removable and read-only → pick the largest → confirm; `--disk` overrides. The disko layout's declared device is cross-checked and a mismatch warns loudly (datacore's layout names `/dev/nvme0n1` with a "verify" comment; the HP may present it differently).
4. **Preflight checklist** — a printed table: repo ✓, keys ✓, UEFI ✓, network ✓, disk ✓, Secure-Boot ⚠ (warn, never block silently). Nothing destructive before the checklist passes or Scott overrides.
5. Then exactly the current body: disko → inject key → `nixos-install --flake "$REPO#<host>"` → password → reboot.

### Phase B (agenix-rekey) shape

- `age.rekey.masterIdentities = [ "/home/scott/.ssh/id_ed25519" ]` (scott's identity; the current secrets were already encrypted to scott's pubkey as a recipient, so the plaintexts are recoverable with it).
- `age.rekey.hostPubkey = "/etc/ssh/ssh_host_ed25519_key.pub"` per host; datacore's is the inherited-key file under `keys/`.
- Secrets move from `file =` to `rekeyFile =`; `secrets.nix` is deleted; `agenix rekey -a` produces `secrets/rekeyed/<host>/*.age` in **local storage mode**, and those files are **committed**, not gitignored. Rationale: whistle builds its own system and would have no rekeyed files to activate from if they lived only on rafik; the repo is private; and the exposure (a compromised host key decrypts committed secrets) is identical to today, where the multi-recipient `.age` files are already committed. `keys/` (private host keys) remains gitignored — that is a different class.
- New-host bootstrap (documented in the runbook): build/install with the dummy pubkey (rekey is one `agenix rekey` away once the real key exists) → first boot generates the key → `agenix rekey` + `nixos-rebuild switch` → secrets decrypt. `eminix-firstboot` gains a step that prints exactly this when the agenix sanity check fails.

## Phases

**Phase 1 — Installer ISO (repo work, no live host touched).**
`keys/` scaffolding + gitignore; `installer/iso.nix`; the `installer` flake
output; `bin/eminix-iso`; `fresh-eminix-install` v2; motd; build + QEMU boot
test; docs (`eminix-install.md` rewrite).

**Phase 2 — agenix-rekey migration (repo work, secrets-touching).**
Input wiring; secrets converted to `rekeyFile` + master identity; `secrets.nix`
deleted; rekey (committed, local mode); `firstboot` bootstrap step; VM
fresh-install test proves secrets decrypt with a generated key. Reversible:
revert + re-encrypt to the old multi-recipient format.

**Phase 3 — Real artifact + datacore cutover (Scott-operational).**
Stage `keys/` (rafik's key from `/etc/ssh`, datacore's from the old box via the
`ssh -t` flow already documented in the cutover plan); `bin/eminix-iso`; boot
the ISO on the HP; execute the cutover per
`2026-08-08-datacore-cutover.md` with the deltas: no stick staging, keys baked,
`fresh-eminix-install datacore` is the whole install step.

## Verification

- `nix flake check` and `nix build .#nixosConfigurations.installer.config.system.build.isoImage` build clean on rafik.
- QEMU boot of the ISO (`qemu-system-x86_64 -cdrom result/iso/*.iso -m 2G`) reaches a login, shows the motd, and the preflight checklist prints all-found with `EMINIX_REPO=/etc/eminix/dotfiles`.
- **Fresh-disk VM test** (mirrors the rafik precedent in `eminix-install.md`): a virtual disk install via `fresh-eminix-install` reaches multi-user with the agentic secrets decrypted — with a baked key in phase 1, with a generated key through the rekey path in phase 2.
- After phase 3: cutover plan's Task 6 verification ring (host-key no-warning SSH, syncthing reconnects, Immich, backrest→B2).
- `keys/` never appears in `git status` output during any phase.

## Rollout / risk

- **Phase 1** is inert: builds an artifact, touches no live host. Can land anytime.
- **Phase 2** touches rafik's secret activation (the daily driver). Mitigation: single commit, `secrets.nix` only deleted after the rekeyed tree is verified in a VM; rollback is `git revert` + re-encrypting to the old recipient set with scott's key (which never leaves the machine).
- **Phase 3** inherits the cutover plan's rollback structure (parallel build, one identity flip, headscale moves last). The ISO changes *how* the HP is installed, not *what* is installed.

## Out of scope

- A GUI installer, multi-arch builds, or `nixos-anywhere` support.
- Making the ISO a public "distribution" artifact (branding, CI builds, download page) — this spec is its prerequisite; that is its own follow-up.
- Converting datacore's compose stacks to native services (decision 10 of the datacore spec governs).
- Impermanence (rafik v2 item).
- Retiring `zordold` from any recipient list — that happens at datacore cutover (cutover plan Task 8 step 4), and phase 2 makes the question moot by deleting the list.

## As-built corrections

None yet — this spec is new. The plan records deviations as they land.
