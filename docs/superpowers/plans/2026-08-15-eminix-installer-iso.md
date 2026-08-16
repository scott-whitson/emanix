# eminix installer ISO + agenix-rekey — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Part I (Tasks 1–7) and Part II (Tasks 8–12) are repo work an agent can
> execute, with verification per task.** Task 6, 12 and everything in Part III
> (Tasks 13–15) are operational and must be run by Scott at the machines —
> they involve `sudo` on live hosts, physical media, QEMU, and firmware. An
> agent's job on those is to prepare commands, verify output that is pasted
> back, and stop.

**Goal:** Replace the Ventoy + manual-staging install flow with a bootable
eminix installer ISO produced by the flake (`bin/eminix-iso /dev/sdX` → boot →
`fresh-eminix-install datacore`), then migrate secrets to agenix-rekey so the
hand-maintained recipient list in `secrets/secrets.nix` dies.

**Architecture:** The ISO is a minimal NixOS live system (not an eminix host)
that carries the flake at `/etc/eminix/dotfiles` and the host keys at
`/etc/eminix/keys`, with both installer scripts on PATH. The installer script
v2 auto-locates repo/keys/disk, prints a preflight checklist, and only then
does what it does today (disko → host-key inject → nixos-install → reboot).
Phase B adopts agenix-rekey: secrets become master-key-encrypted `rekeyFile`s,
rekeyed per host into `secrets/rekeyed/<host>/` (committed — whistle builds its
own system; see self-review note 1).

**Tech Stack:** NixOS ISO builder (`installation-cd-minimal` + `isoImage`),
`dd`, disko, agenix → agenix-rekey (oddlama), shellcheck, QEMU.

**Spec:** `docs/superpowers/specs/2026-08-15-eminix-installer-iso-design.md`.
Read its Decisions before starting. The datacore cutover itself remains
governed by `docs/superpowers/plans/2026-08-08-datacore-cutover.md`; Part III
lists only the deltas this redesign forces.

## Global Constraints

- **Never commit private host keys.** `keys/<host>_host_ed25519` (private) is
  gitignored; `keys/<host>_host_ed25519.pub` (public) is committed — the pubkeys
  are already public today via `secrets/secrets.nix`.
- **Never print secret plaintext.** Verify by byte counts (`wc -c`), never by
  cat.
- **Never add `Co-Authored-By` or tool-attribution trailers to commits.**
- All `.nix` files pass `nixpkgs-fmt --check`; both installer scripts pass
  `shellcheck` before commit.
- Build check (used throughout):
  `nix build --no-link --print-out-paths .#nixosConfigurations.<host>.config.system.build.toplevel`
- ISO build check:
  `nix build --no-link --print-out-paths .#nixosConfigurations.installer.config.system.build.isoImage`
- **Part III is destructive to the HP only.** Nothing else is wiped without
  Scott's explicit confirmation.
- An ISO built with baked keys **is identity** — treat the artifact and the
  `.iso` file like a host key after Task 13.

## File Structure

| File | Responsibility |
| --- | --- |
| `installer/iso.nix` | **New.** Installer module: minimal profile + repo staging + keys baking + packages + motd + sshd |
| `installer/fresh-eminix-install` | **Modify.** v2: repo/keys/disk resolution, `--check-only`, preflight checklist |
| `bin/eminix-iso` | **New.** Validate keys/ → build isoImage → locate ISO → dd → sync |
| `keys/<host>_host_ed25519.pub` | **New, committed.** Public host keys (already public via secrets.nix) |
| `keys/<host>_host_ed25519` | **New, gitignored.** Private host keys; staged by Scott in Task 13 |
| `.gitignore` | **Modify.** Ignore `keys/*_host_ed25519` (private halves only) |
| `flake.nix` | **Modify.** `nixosConfigurations.installer`; Part II: agenix-rekey input + `configure` block |
| `lib/mkHost.nix` | **Modify (Part II).** agenix-rekey module + shared `age.rekey` settings |
| `ioshi/i-intelligence/secrets.nix` | **Modify (Part II).** `file` → `rekeyFile` |
| `secrets/secrets.nix` | **Delete (Part II).** superseded by rekey |
| `secrets/rekeyed/<host>/*.age` | **New (Part II), committed.** agenix-rekey per-host output |
| `installer/eminix-firstboot` | **Modify (Part II).** bootstrap instructions when the sanity check fails |
| `docs/ioshi/eminix-install.md` | **Rewrite.** the ISO flow |

---

# Part I — Installer ISO

## Task 1: `keys/` scaffolding + gitignore

**Agent-executable.**

**Files:**

- New: `keys/rafik_host_ed25519.pub`, `keys/datacore_host_ed25519.pub`, `keys/whistle_host_ed25519.pub`
- Modify: `.gitignore`

**Why this task exists:** Part II's `age.rekey.hostPubkey` must reference
per-host pubkeys that exist at eval time on *any* builder (see self-review
note 2) — so the pubkeys become committed files. The values are public
(they are already the recipient strings in `secrets/secrets.nix`).

- [ ] **Step 1: Add the gitignore rule for private halves**

In `.gitignore`, append:

```
# Private host keys — never committed (public .pub halves ARE committed)
keys/*_host_ed25519
```

- [ ] **Step 2: Create the public key files** from the recipient strings in
`secrets/secrets.nix` (take the string after `=`, verbatim — including the
stale `root@eminix` / `root@weasel` comments):

```bash
mkdir -p keys
printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHiZAqCjE7nX2iXAlZDdZIzURl/X55ljlbpVHNlN9Za8 root@eminix'    > keys/rafik_host_ed25519.pub
printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHn7dUeQQeGMDAuQ8YJRxV2Nlo31biEtxpcHxawrBZ1J root@datacore' > keys/datacore_host_ed25519.pub
printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINp8VpIPlKLxcfPh1jvPc+LnFOnyQhTyxMulwQbTg2xA root@weasel'   > keys/whistle_host_ed25519.pub
```

- [ ] **Step 3: Verify the ignore rules**

```bash
git check-ignore -q keys/rafik_host_ed25519 && echo "private: ignored ✓"   # exit 0
git check-ignore keys/rafik_host_ed25519.pub; test $? -ne 0 && echo "pub: tracked ✓"
git status --porcelain
```

Expected: the three `.pub` files listed as untracked; no `keys/*_host_ed25519`
(no private files exist yet). `git add keys/` then `git status --porcelain`
must show exactly the three `.pub` files — run it and if anything else appears,
stop.

- [ ] **Step 4: Commit**

```bash
nixpkgs-fmt --check flake.nix   # untouched, sanity
git add keys/ .gitignore
git commit -m "feat(installer): commit per-host public keys under keys/

The pubkeys are already public recipient strings in secrets/secrets.nix; they
move to files so agenix-rekey's hostPubkey can reference them at eval time on
any builder, and so the installer ISO can fingerprint-bake them. The private
halves stay gitignored and are staged only at ISO build time."
git push origin main
```

---

## Task 2: `installer/iso.nix`

**Agent-executable.**

**Files:**

- New: `installer/iso.nix`

**Interfaces:** Produces the installer module. Task 3 wires it into the flake;
Task 6 boots it in QEMU.

- [ ] **Step 1: Write the module**

```nix
# installer/iso.nix — the eminix installer ISO.
# A minimal NixOS live system (NOT an eminix host — never through mkHost) that
# carries the flake + host keys so a bare-metal install is: boot -> one command.
# Spec: docs/superpowers/specs/2026-08-15-eminix-installer-iso-design.md
{ pkgs, lib, nixpkgs, disko, ... }:

let
  # The repo, staged without history/symlink/keys so /etc/eminix/dotfiles is a
  # clean, buildable flake tree. builtins.path (not cleanSource) so the filter
  # is explicit. secrets/rekeyed/ is intentionally INCLUDED once Part II lands:
  # nixos-install builds from this tree, and agenix activates from it.
  stagedRepo = builtins.path {
    name = "eminix-dotfiles";
    path = ../.;
    filter = p: t:
      let b = builtins.baseNameOf p;
      in b != ".git" && b != "result" && b != "keys" && b != ".superpowers";
  };

  # Present only when the builder staged keys/ (gitignored privates + committed pubs).
  hasKeys = builtins.pathExists ../keys;
in
{
  imports = [ "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix" ];

  isoImage.volumeID = "eminix";   # boot menu + mount label

  environment.etc."eminix/dotfiles".source = stagedRepo;

  environment.systemPackages = with pkgs; [
    git                      # minimal ISO lacks it; eminix-firstboot clones with it
    exfatprogs               # mounting arbitrary USB sticks
    dosfstools
    disko.packages.${pkgs.system}.default
    (pkgs.writeShellScriptBin "fresh-eminix-install" (builtins.readFile ./fresh-eminix-install))
    (pkgs.writeShellScriptBin "eminix-firstboot" (builtins.readFile ./eminix-firstboot))
  ]
  # Keys baked at build time. Without them the ISO still builds; the installer
  # falls back to its staged-dir prompt. This block makes the ISO identity.
  ++ lib.optional hasKeys {
    environment.etc."eminix/keys".source = ../keys;
  };

  # WiFi (HP has no ethernet guarantee) + sshd for driving the target from rafik.
  networking.wireless.iwd.enable = true;
  services.openssh.enable = true;   # ephemeral host key generated at boot

  # The three commands, printed on every console login.
  environment.etc."issue".text = ''
    ══ eminix installer ════════════════════════════════════════════
      repo : /etc/eminix/dotfiles
      keys : /etc/eminix/keys
      install a host:  sudo fresh-eminix-install <host> [--disk /dev/X]
      check only:      sudo fresh-eminix-install <host> --check-only
    ═════════════════════════════════════════════════════════════════
  '';
}
```

Notes for implementation: `disko.packages.${pkgs.system}.default` — if that
attr does not exist at eval (disko exposes `packages.<system>.default` in
recent releases; verify), fall back to `nix run github:nix-community/disko/latest`
in the script (already the current behavior) and drop the package line. If
`iwd` conflicts with the minimal profile's `wpa_supplicant`, drop the
wpa_supplicant side — verify at eval (Task 3).

- [ ] **Step 2: Format-check**

```bash
nixpkgs-fmt --check installer/iso.nix
```

---

## Task 3: flake wiring — `nixosConfigurations.installer`

**Agent-executable.**

**Files:**

- Modify: `flake.nix`

**Interfaces:** Produces `. #nixosConfigurations.installer.config.system.build.isoImage`.

- [ ] **Step 1: Add the installer configuration**

In `flake.nix`'s `outputs`, inside `nixosConfigurations` (after `datacore`):

```nix
        # The installer ISO — a minimal live system carrying the flake + keys.
        # Deliberately NOT via mkHost: this is a tool, not an eminix host.
        installer = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit nixpkgs disko; };
          modules = [ ./installer/iso.nix ];
        };
```

- [ ] **Step 2: Eval + build**

```bash
nixpkgs-fmt flake.nix
nix flake check
nix build --no-link --print-out-paths .#nixosConfigurations.installer.config.system.build.isoImage
```

Expected: flake check passes (installer config evaluates; watch for the iwd /
wpa_supplicant conflict and the disko package attr, resolve per Task 2 notes);
the ISO build succeeds — first build may take a while, most paths are cached.

- [ ] **Step 3: Commit**

```bash
git add flake.nix installer/iso.nix
git commit -m "feat(installer): add the eminix installer ISO configuration

A minimal live system (installation-cd-minimal) that stages the flake at
/etc/eminix/dotfiles, bakes keys/ when present, and puts both installer
scripts on PATH. Boot -> sudo fresh-eminix-install <host> is now the whole
install flow; no Ventoy, no /run/media globs."
git push origin main
```

---

## Task 4: `bin/eminix-iso` — build-and-flash wrapper

**Agent-executable.**

**Files:**

- New: `bin/eminix-iso` (executable)

**Interfaces:** Produces the one-command artifact flow from the spec's Goal.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# eminix-iso — build the eminix installer ISO and optionally flash it.
# Usage:
#   bin/eminix-iso                 # build only; prints the ISO path
#   bin/eminix-iso --no-keys       # build without baked keys (debug/rescue ISO)
#   bin/eminix-iso /dev/sdX        # build and dd to the device (destructive!)
set -euo pipefail

die() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
say() { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

BUILD_KEYS=1
DEV=""
for a in "$@"; do
  case "$a" in
    --no-keys) BUILD_KEYS=0 ;;
    *) DEV="$a" ;;
  esac
done

if [ "$BUILD_KEYS" -eq 1 ]; then
  # Every committed .pub must have a staged private half, else the ISO would
  # bake a keypair missing its private part and fail at install.
  missing=""
  for pub in keys/*_host_ed25519.pub; do
    priv="${pub%.pub}"
    [ -f "$priv" ] || missing="$missing $(basename "$priv")"
  done
  [ -z "$missing" ] || die "no private key staged for:$missing
  rafik:   sudo cp /etc/ssh/ssh_host_ed25519_key keys/rafik_host_ed25519
  others:  ssh -t <host> 'sudo cat /etc/ssh/ssh_host_ed25519_key' > keys/<host>_host_ed25519
  (or pass --no-keys for a debug ISO that carries no identity)"
  # Belt-and-braces: private halves must never be tracked.
  [ -z "$(git ls-files keys/ | grep -v '\.pub$' || true)" ] \
    || die "a private key is tracked in git — fix before building."
fi

say "Building installer ISO"
nix build --no-link --print-out-paths \
  .#nixosConfigurations.installer.config.system.build.isoImage \
  --print-out-paths >/dev/null
ISO="$(ls result/iso/*.iso 2>/dev/null | head -1 || true)"
[ -n "$ISO" ] || die "no ISO produced under result/iso/"
say "Built: $ISO ($(du -h "$ISO" | cut -f1))"

if [ -z "$DEV" ]; then
  echo "Flash it:  sudo bin/eminix-iso /dev/sdX"
  exit 0
fi

[ -b "$DEV" ] || die "$DEV is not a block device."
echo
echo "This ERASES $DEV entirely."
read -rp "Type the device path to confirm ($DEV): " c
[ "$c" = "$DEV" ] || die "aborted."

say "Flashing $ISO to $DEV"
sudo dd if="$ISO" of="$DEV" bs=4M status=progress conv=fsync
sync
say "Done. Remove the stick and boot the target from it."
```

- [ ] **Step 2: Verify**

```bash
chmod +x bin/eminix-iso
shellcheck bin/eminix-iso
bin/eminix-iso --no-keys    # expects: builds, prints path, exits 0
```

Expected: shellcheck clean; with no keys staged, `--no-keys` builds the ISO
and prints the flash hint; without `--no-keys` it dies with the staging
instructions (keys not staged yet — that is the intended behavior until Task 13).

---

## Task 5: `fresh-eminix-install` v2 — no globs, no guessing

**Agent-executable.**

**Files:**

- Modify: `installer/fresh-eminix-install`

**Interfaces:** Produces the auto-locating installer used by the ISO and the
fallback (`--check-only`) used by every verification step in this plan.

- [ ] **Step 1: Add repo/keys/disk resolution**

Replace the fixed `REPO`/`KEY_DIR` block with:

```bash
FLAKE_HOST="${1:-rafik}"
DISK=""
for a in "${@:2}"; do
  case "$a" in
    --disk) shift; DISK="${1:-}"; shift ;;
    --disk=*) DISK="${a#--disk=}" ;;
    --check-only) CHECK_ONLY=1 ;;
    *) DISK="${DISK:-$a}" ;;   # positional disk (back-compat: fresh-eminix-install <host> <disk>)
  esac
done
```

Then a `resolve_repo` function, in order: `$EMINIX_REPO` → `realpath $0`'s
grandparent (working-tree execution) → `/etc/eminix/dotfiles` (ISO) → bounded
scan of `/mnt/*`, `/run/media/*/*`, `/media/*` for a directory containing
`dotfiles/flake.nix`. Die listing every candidate tried.

Then `resolve_keys`: baked `/etc/eminix/keys` (ISO) → `$(dirname "$REPO")/<host>-keys`
(today's convention) → interactive prompt for a directory. Keep the existing
fingerprint check against `secrets/secrets.nix` (note: after Part II there is
no `secrets.nix` — see Step 3).

Then `resolve_disk`: `lsblk -dno NAME,SIZE,TRAN,RO` → exclude `usb`/removable
and RO=1 → pick the largest → confirm interactively (`--disk` bypasses).
Cross-check against the disko layout's declared device (grep the layout file
for `device =`) and warn loudly on mismatch.

- [ ] **Step 2: Print the preflight checklist**

After the existing UEFI/Secure-Boot/network checks, print a table:

```
eminix installer preflight — datacore
  repo        ✓ /etc/eminix/dotfiles
  keys        ✓ /etc/eminix/keys/datacore_host_ed25519 (fp match)
  UEFI        ✓
  network     ✓
  disk        ✓ /dev/nvme0n1 (1.0T, non-removable)
  Secure Boot ⚠ DISABLED
```

With `--check-only`, print the table and `exit 0` (or 1 with the missing list)
without touching anything.

- [ ] **Step 3: Disko invocation**

Prefer a baked `disko` binary on PATH; fall back to
`nix run github:nix-community/disko/latest -- ...` (current behavior). After
Part II, the fingerprint check's `secrets/secrets.nix` grep must tolerate a
missing file: if `secrets.nix` is gone, validate the staged key against
`keys/<host>_host_ed25519.pub` instead (same fingerprint, same source of truth).

- [ ] **Step 4: Verify**

```bash
shellcheck installer/fresh-eminix-install
EMINIX_REPO="$PWD" bash installer/fresh-eminix-install --check-only datacore
```

Expected: shellcheck clean; `--check-only` prints the checklist — repo ✓,
keys ✗ (not staged until Task 13), UEFI ✓ (running on rafik), network ✓,
disk ✓ (the NVMe) — and exits non-zero listing the key gap. That non-zero
exit on a missing key is the designed fail-closed behavior.

- [ ] **Step 5: Commit**

```bash
git add installer/fresh-eminix-install bin/eminix-iso
git commit -m "feat(installer): v2 auto-locates repo/keys/disk; add --check-only

The v1 script assumed a Ventoy-staged checkout under /run/media/* and a
hardcoded nvme0n1. v2 resolves the repo (env -> script path -> /etc/eminix ->
mounted volumes), the keys (baked -> staged dir -> prompt), and the disk
(largest non-removable) with interactive confirmation, prints a preflight
checklist, and supports --check-only for deterministic verification."
git push origin main
```

---

## Task 6: QEMU boot verification

**Scott-operational (interactive).** Agent prepares, Scott runs, agent verifies pasted output.

- [ ] **Step 1: Boot the ISO in QEMU**

```bash
cd ~/dotfiles
ISO="$(ls result/iso/*.iso | head -1)"
nix shell nixpkgs#qemu --command \
  qemu-system-x86_64 -m 2048 -cdrom "$ISO" -boot d \
  -netdev user,id=n0 -device e1000,netdev=n0
```

- [ ] **Step 2: From the live shell, verify**

```bash
ls /etc/eminix/dotfiles/flake.nix                       # repo staged
which fresh-eminix-install eminix-firstboot             # scripts on PATH
ls /etc/eminix/keys/                                    # keys baked
sudo bash /etc/eminix/dotfiles/installer/fresh-eminix-install --check-only datacore
cd /etc/eminix/dotfiles && nix build .#nixosConfigurations.datacore.config.system.build.toplevel
```

Expected: flake.nix present; both scripts resolve; keys/ listed; `--check-only`
prints a full-green checklist (repo ✓ keys ✓ UEFI ✓ network ✓ disk = the QEMU
vd*-style disk ✓ — expect the disko cross-check warning about datacore's
declared `/dev/nvme0n1`, which is correct here since the layout was written for
the HP); the datacore toplevel builds from the staged tree (proves the ISO's
repo copy is complete). Paste the output; stop there.

---

## Task 7: Docs — rewrite `eminix-install.md`

**Agent-executable.**

**Files:**

- Rewrite: `docs/ioshi/eminix-install.md`
- Modify: `README.md` ("Fresh install" line)

**Content:** The runbook becomes:

1. **Build the ISO (on rafik):** `bin/eminix-iso` (+ the key-staging
   instructions it prints, incl. the `ssh -t datacore 'sudo cat …'` flow for
   the inherited key).
2. **Flash:** `bin/eminix-iso /dev/sdX` (confirmation prompt) — or dd by hand.
3. **Boot the target:** disable Secure Boot first (systemd-boot unsigned —
   keep the existing firmware warning verbatim).
4. **Install:** `sudo fresh-eminix-install <host>` — preflight checklist, then
   disko → key inject → nixos-install → password → reboot.
5. **First boot:** unchanged (`eminix-firstboot`).
6. **Add a new host:** mkHost entry → commit pubkey to `keys/` → stage private
   half → build ISO.
7. **Manual fallback:** the existing "what the installer does" section, kept —
   the script is runnable from a plain NixOS ISO with `EMINIX_REPO` set and
   keys staged beside it.

Supersede banner at the top pointing at the spec; delete all
`/run/media/*/Ventoy` references. Update README's "Fresh install (bare metal)"
line to the ISO flow.

- [ ] **Verify + commit**

```bash
grep -rn 'run/media' docs README.md || echo "no /run/media references remain"
git add -A
git commit -m "docs(installer): rewrite eminix-install.md around the ISO flow"
git push origin main
```

---

# Part II — agenix-rekey

## Task 8: input + configure + module wiring

**Agent-executable.** (Does not touch secrets yet.)

**Files:**

- Modify: `flake.nix`
- Modify: `lib/mkHost.nix`

**Interfaces:** Produces `agenix rekey` availability and the per-host rekey
options. Task 9/10 consume them.

- [ ] **Step 1: Add the input** (nixpkgs.follows is mandatory — rekeyed
derivations must come from the same nixpkgs):

```nix
    agenix-rekey = {
      url = "github:oddlama/agenix-rekey";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

Add `agenix-rekey` to the outputs destructure.

- [ ] **Step 2: Configure the output**

```nix
    # Lets `nix run github:oddlama/agenix-rekey -- rekey` see every host.
    agenix-rekey = agenix-rekey.configure {
      userFlake = self;
      nixosConfigurations = self.nixosConfigurations;
    };
```

- [ ] **Step 3: Wire mkHost**

In `lib/mkHost.nix`, alongside `agenix.nixosModules.default` and
`home-manager.nixosModules.home-manager`, add
`agenix-rekey.nixosModules.default`, plus a shared module:

```nix
    # agenix-rekey: secrets live master-key-encrypted in the repo; every host
    # gets them re-encrypted to its own key under secrets/rekeyed/<host>/.
    # hostPubkey MUST be the committed keys/<host>_host_ed25519.pub path, not
    # /etc/ssh/... — all hosts evaluate on the builder, where /etc/ssh is the
    # builder's own key (self-review note 2).
    {
      age.rekey = {
        masterIdentities = [ "/home/scott/.ssh/id_ed25519" ];
        storageMode = "local";
        localStorageDir = ../. + "/secrets/rekeyed/${hostName}";
        hostPubkey = ../keys/${hostName}_host_ed25519.pub;
      };
    }
```

(`../.` — mkHost.nix lives in `lib/`, so the repo root is one level up.)

- [ ] **Step 4: Verify**

```bash
nixpkgs-fmt flake.nix lib/mkHost.nix
nix flake check
nix eval .#nixosConfigurations.rafik.config.age.rekey.masterIdentities
```

Expected: flake check green; eval prints `[ "/home/scott/.ssh/id_ed25519" ]`.
Watch that the `zordold` recipient is still referenced by the existing
`file =` secrets (Task 9 removes it — that is intended; nothing breaks in eval
because rekey is not yet active).

---

## Task 9: Convert the two secrets to `rekeyFile` + master encryption

**Agent-executable. Secrets-touching — backup first, byte-count checks only.**

**Files:**

- Modify: `ioshi/i-intelligence/secrets.nix` (`file` → `rekeyFile`)
- Rewritten: `secrets/openrouter-auth.age`, `secrets/ibkr-creds.age`

**Why:** agenix-rekey requires `rekeyFile` files encrypted to the *master*
identity only (scott's key). Today they are encrypted to all five recipients.
Conversion = decrypt with scott's key (a current recipient) and re-encrypt to
scott's ssh recipient alone.

- [ ] **Step 1: Back up**

```bash
cd ~/dotfiles
mkdir -p /tmp/agenix-backup
cp secrets/openrouter-auth.age secrets/ibkr-creds.age /tmp/agenix-backup/
wc -c /tmp/agenix-backup/*
```

- [ ] **Step 2: Re-encrypt each secret to the master identity**

```bash
SCOTT_RECIPIENT='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINW1gKUfmcHDWf02SHUpZuIZEqq7qk4IJfmd8hlLAUQi swhitson-11l'
for s in openrouter-auth ibkr-creds; do
  nix run github:ryantm/agenix -- -d secrets/$s.age -i ~/.ssh/id_ed25519 > /tmp/$s.plain
  nix shell nixpkgs#age --command age -e -r "$SCOTT_RECIPIENT" -o secrets/$s.age /tmp/$s.plain
  rm -f /tmp/$s.plain
done
```

Never print the plaintext; only counts.

- [ ] **Step 3: Switch the module to `rekeyFile`**

In `ioshi/i-intelligence/secrets.nix`:

```nix
  age.secrets.openrouter-auth = {
    rekeyFile = ../../secrets/openrouter-auth.age;
    owner = "scott";
    group = "users";
    mode = "0400";
  };
```

(Do not touch the `path =` comment — the pi.nix symlink contract is unchanged.)

- [ ] **Step 4: Verify**

```bash
grep -ac 'ssh-ed25519' secrets/openrouter-auth.age   # expect 1 (was 5)
grep -ac 'ssh-ed25519' secrets/ibkr-creds.age        # expect 1 (was 2)
nix shell nixpkgs#age --command age -d -i ~/.ssh/id_ed25519 secrets/openrouter-auth.age | wc -c   # non-trivial
```

Expected: single-recipient files; master decryption works (byte counts equal
the backup's plaintext sizes — compare against the backup via the same
decrypt+wc, not by printing).

---

## Task 10: Rekey, delete `secrets.nix`, commit

**Agent-executable.**

**Files:**

- New: `secrets/rekeyed/<host>/*.age`
- Delete: `secrets/secrets.nix`
- Modify: `.gitignore` (ensure rekeyed is NOT ignored)

- [ ] **Step 1: Rekey**

```bash
cd ~/dotfiles
nix run github:oddlama/agenix-rekey -- rekey -a
```

Expected: creates `secrets/rekeyed/rafik/openrouter-auth.age`,
`secrets/rekeyed/datacore/openrouter-auth.age`,
`secrets/rekeyed/whistle/openrouter-auth.age`, and
`secrets/rekeyed/rafik/ibkr-creds.age`. The `zordold` recipient dies with
`secrets.nix` — the HP's zord-old era key no longer decrypts anything, which is
the correct end state (that machine is datacore now).

- [ ] **Step 2: Verify each rekeyed file is host-key-only**

```bash
# rafik's rekeyed secret decrypts ONLY with rafik's key:
nix shell nixpkgs#age --command age -d -i /etc/ssh/ssh_host_ed25519_key secrets/rekeyed/rafik/openrouter-auth.age | wc -c
# and NOT with scott's:
nix shell nixpkgs#age --command age -d -i ~/.ssh/id_ed25519 secrets/rekeyed/rafik/openrouter-auth.age 2>&1 | head -1
```

Expected: rafik key → non-trivial count; scott's key → an error line. Then
delete `secrets/secrets.nix`.

- [ ] **Step 3: Idempotency + build + commit**

```bash
nix run github:oddlama/agenix-rekey -- rekey -a   # no changes, exit 0
rm secrets/secrets.nix
for h in rafik whistle datacore; do nix build --no-link --print-out-paths .#nixosConfigurations.$h.config.system.build.toplevel; done
git add -A
git status --porcelain   # review: rekeyed/*.age added; NO keys/*_host_ed25519 privates
git commit -m "feat(secrets): migrate to agenix-rekey; drop secrets.nix

Secrets are now master-key-encrypted (scott) in the repo and rekeyed per host
into secrets/rekeyed/<host>/ at build time. The recipient list is inferred
from each host's committed keys/<host>_host_ed25519.pub; no hand-maintained
secrets.nix. zordold's recipient disappears with it — that machine is datacore
now. Adding a new host is: commit its pubkey, agenix rekey, rebuild."
git push origin main
```

---

## Task 11: first-boot bootstrap for fresh-identity hosts

**Agent-executable.**

**Files:**

- Modify: `installer/eminix-firstboot`

**Interfaces:** Documents + automates the "unknown host" path the spec's phase B
describes (hosts WITHOUT an inherited key, e.g. a future laptop).

- [ ] **Step 1: Extend the sanity-check section**

In `eminix-firstboot`, when the auth.json check fails, print instead of the
generic warning:

```
  auth.json: not decrypted — this is normal for a brand-new host.
  On the BUILDER (rafik):  cd ~/dotfiles
      cp <this host's> /etc/ssh/ssh_host_ed25519_key.pub keys/<host>_host_ed25519.pub
      nix run github:oddlama/agenix-rekey -- rekey -a
      git add keys/ secrets/rekeyed/ && git commit -m "secrets: add <host>" && git push
  Then here:  sudo nixos-rebuild switch --flake github:scott-whitson/dotfiles#<host>
  The agenix unit will now find the rekeyed secret and auth.json will appear.
```

- [ ] **Step 2: Verify + commit**

```bash
shellcheck installer/eminix-firstboot
git add installer/eminix-firstboot
git commit -m "feat(firstboot): print the rekey bootstrap for fresh-identity hosts"
git push origin main
```

---

## Task 12: Fleet verification + rafik switch

**Agent prepares commands; Scott executes the switch on rafik (daily driver).**

- [ ] **Step 1: Agent — build everything**

```bash
for h in rafik whistle datacore; do
  nix build --no-link --print-out-paths .#nixosConfigurations.$h.config.system.build.toplevel
done
nix build --no-link --print-out-paths .#nixosConfigurations.installer.config.system.build.isoImage
nix flake check
```

- [ ] **Step 2: Scott — switch rafik** (rollback = select the previous boot
generation; the old `file =` secrets still exist in git history if a revert is
needed)

```bash
cd ~/dotfiles && sudo nixos-rebuild switch --flake .#rafik
ls -l /run/agenix/openrouter-auth     # must exist and be scott-owned
```

- [ ] **Step 3: Scott — switch whistle** (from whistle, after `git pull`)

```bash
cd ~/dotfiles && git pull && sudo nixos-rebuild switch --flake .#whistle
```

Expected: both switches activate with the rekeyed secrets (whistle's rekeyed
files are in the repo it just pulled — the reason they are committed, self-review note 1).

---

# Part III — Real ISO + datacore cutover

**Scott-operational. Everything here is at the machines.**

## Task 13: Stage keys, build the real ISO, flash

- [ ] **Step 1: Stage the private halves** (the ISO-baking step `bin/eminix-iso`
   requires):

```bash
cd ~/dotfiles
sudo cp /etc/ssh/ssh_host_ed25519_key keys/rafik_host_ed25519
# datacore inherits the OLD Debian box's key (cutover plan Task 4 step 1 flow):
ssh -t datacore 'sudo cat /etc/ssh/ssh_host_ed25519_key'     > keys/datacore_host_ed25519
ssh -t datacore 'sudo cat /etc/ssh/ssh_host_ed25519_key.pub' > /tmp/datacore.pub
chmod 600 keys/*_host_ed25519
# fingerprint sanity vs the committed .pub:
ssh-keygen -lf keys/datacore_host_ed25519.pub
ssh-keygen -lf /tmp/datacore.pub    # must match
```

- [ ] **Step 2: Build + flash**

```bash
bin/eminix-iso /dev/sdX   # confirm the device; this is your identity now
```

Keep the resulting `result/iso/*.iso` on rafik (copy to a safe place, e.g.
`~/eminix-installer.iso`) and the stick somewhere sane — both are host-key
equivalents.

- [ ] **Step 3: Verify the ISO contents** (loop-mount, read-only):

```bash
mkdir -p /tmp/iso1 /tmp/iso2
sudo mount -o loop result/iso/*.iso /tmp/iso1
sudo mount -o loop /tmp/iso1/nixos.squashfs /tmp/iso2
ls /tmp/iso2/etc/eminix/keys/ /tmp/iso2/etc/eminix/dotfiles/flake.nix
sudo umount /tmp/iso2 /tmp/iso1
```

Expected: keys/ lists rafik + datacore pairs; flake.nix present.

## Task 14: Boot-test on the HP

- [ ] **Step 1: Firmware** — disable Secure Boot, confirm UEFI (unchanged from
the cutover plan Task 4 step 2).
- [ ] **Step 2: Boot the stick, run the check**

```bash
sudo fresh-eminix-install --check-only datacore
lsblk -f
```

Expected: full-green checklist (keys baked ✓); the disk shown matches
datacore's declared `/dev/nvme0n1` — if not, install with
`fresh-eminix-install datacore --disk /dev/actual`.

## Task 15: Datacore cutover — deltas to `2026-08-08-datacore-cutover.md`

Everything in that plan still applies (parallel build, warm rsync, one identity
flip, headscale handover, soak, retirement) **except**:

| Cutover plan item | Delta |
| --- | --- |
| Task 1 (re-point agenix recipient) | **N/A.** `secrets.nix` is deleted (Task 10); datacore's rekeyed files are already encrypted to the inherited key |
| Task 4 step 1 (stage the Ventoy USB) | **N/A.** Replaced by Task 13 (keys baked into the ISO) |
| Task 4 step 3 (install command) | `sudo fresh-eminix-install datacore` (on PATH; no `/run/media` path) |
| Task 4 step 8 (wipe staged key off USB) | **N/A.** Nothing staged; keep the ISO as the artifact |
| Task 8 step 4 (drop `zordold` recipient) | **N/A.** Gone with `secrets.nix` (Task 10) |

The install step is now: boot → `fresh-eminix-install datacore` → first boot
→ `eminix-firstboot` → data sync per cutover plan Task 5 onward.

---

## Self-Review Notes

**Spec coverage.** D1 (artifact = ISO) → Tasks 1–6. D2 (not via mkHost) → Task 3.
D3 (repo at /etc/eminix/dotfiles) → Tasks 2, 6. D4 (keys baked, gitignored) →
Tasks 1, 2, 4, 13. D5 (no globs, checklist) → Task 5. D6 (ISO contents) →
Task 2. D7 (agenix-rekey) → Tasks 8–11. D8 (docs) → Task 7. D9 (verification) →
Tasks 6, 12.

**Corrections found while planning (spec amended where it said otherwise):**

1. **Rekeyed secrets are COMMITTED, not gitignored.** Whistle builds its own
   system from git; with a gitignored `secrets/rekeyed/`, whistle would have no
   rekeyed files to activate from. The repo is private and the exposure (host
   key decrypts committed secrets) equals today's committed multi-recipient
   `.age` files. Only `keys/*_host_ed25519` (private halves) are gitignored.
2. **`hostPubkey` must be committed `keys/<host>_host_ed25519.pub` paths, not
   `/etc/ssh/…`.** Every host evaluates on the builder (rafik), where
   `/etc/ssh/ssh_host_ed25519_key.pub` is rafik's own key — whistle would have
   been rekeyed for rafik. The committed pubs make eval location-independent.
   This is why Task 1 creates the `.pub` files before Part II.
3. **`keys/*.pub` are committed.** They are public data (recipient strings in
   the committed `secrets.nix` today). The spec's "gitignored `keys/`" language
   now means *private halves only*.
4. **`--check-only` flag** added in Task 5 — every non-destructive verification
   step in this plan depends on it.
5. **`builtins.path` with an explicit filter** (not `lib.cleanSource`) stages the
   repo — keeps `secrets/rekeyed/` in (nixos-install builds from the staged
   tree and agenix activates from it) while dropping `.git`, `result`, `keys`,
   `.superpowers`.
6. **`zordold` disappears with `secrets.nix`** — the cutover plan's Task 8
   step 4 cleanup becomes moot; noted in Task 15.

**Risks.** (a) The ISO is identity — mitigated by Task 13's handling and the
build-time-only baking. (b) Part II touches rafik's secret activation — rollback
is the previous boot generation plus a git revert (the old multi-recipient
files survive in history). (c) First ISO build downloads a large closure — plan
for it. (d) The disko cross-check warning on the HP (Task 14) — expected if the
HP presents its NVMe differently; the `--disk` override is the escape hatch.

**As-built corrections (Tasks 1–7 landed 2026-08-15, commits cef1de9, f220547,
03be7c7, c9eb164, 6503b68):**

1. **Keys baking is one `environment.etc` merge**, not `lib.optional` inside
   `environment.systemPackages` — the plan's sketch was structurally wrong
   (a module attrset cannot be an element of a package list). Implemented as
   `{ "eminix/dotfiles"... } // lib.optionalAttrs hasKeys { "eminix/keys"... } // { "issue"... }`.
2. **NetworkManager, not bare iwd.** The installer profile (`installation-device.nix`)
   already enables NetworkManager, whose wpa_supplicant backend sets
   `networking.wireless.enable = true` — which iwd asserts against. Resolved
   with `networking.networkmanager.wifi.backend = "iwd"` (nixpkgs enables iwd
   automatically), so both `nmcli`/`nmtui` and `iwctl` work.
3. **`--check-only` must not require root** — the uid check moved below the
   check-only branch, so the verification path runs as any user on any
   machine (the plan's Task 5 step 4 runs it as scott).
4. **Disk auto-detect excludes mounted disks.** On rafik the checklist reports
   `disk ✗ none detected` — correct fail-closed behavior (rafik's NVMe is
   live); detection matters on the ISO/QEMU where the target disk is
   unmounted. The plan's "disk ✓ (the NVMe)" expectation was written for a
   different context.
5. **`git` dropped from systemPackages** — `installation-cd-base` already sets
   `programs.git.enable`; the plan's line was redundant.
6. **`resolve_disk` returns 0 when no disk is found** — the sketch's
   `[ -n "$best" ] || return` returned 1 under `set -e` and killed the script
   before the checklist could report the gap.
7. **Runbook rewrite also carries the host-key-inheritance staging commands**
   (the `ssh -t` flow) and the `live.nixos.passwd=` sshd note — both were
   implied by the plan, made explicit in the doc.
8. **QEMU validation (Task 6, 2026-08-16):** the full staged-repo
   `nix build` is infeasible in a 2GB QEMU VM — the live ISO's `/nix` is
   memory-backed tmpfs, so a multi-GB closure thrashes/ENOSPC. Replaced the
   VM build check with `nix flake check` (eval-completeness is what a missing
   staged file would break); the real multi-GB build is validated by the HP
   install (Task 14). Also: QEMU without OVMF boots legacy BIOS, so the
   checklist's UEFI reads ✗ in the VM and ✓ on real UEFI hardware; pass
   `-drive if=pflash,format=raw,readonly=on,file=<OVMF>/OVMF_CODE.fd` for a
   UEFI-capable VM. The `diskoConfigurations` warning from `nix flake check`
   is pre-existing and cosmetic (a custom flake output the checker doesn't
   recognize).

**As-built corrections (Tasks 8–11 landed 2026-08-16, commits 1f63da9, 7b034ba,
4c49348):**

1. **The plan's master-key assumption was wrong — the local `~/.ssh/id_ed25519`
   was NOT a recipient of the old secrets.** The `scott` recipient in
   `secrets.nix` (`swhitson-11l`) had a different private key, which no longer
   exists on rafik. The conversion decrypted with **rafik's host key**
   (`/etc/ssh/ssh_host_ed25519_key` — a recipient of both secrets) and
   re-encrypted to scott's current key. Consequence: the old multi-recipient
   files in git history can no longer be decrypted (the `swhitson-11l` key is
   gone); `/tmp/agenix-backup/` on rafik is the only copy decryptable by a
   key that still exists. If recovery ever matters, back that directory up
   somewhere durable. This is why Task 9 was paused for Scott's explicit go.
2. **The `installer` nixosConfiguration must be excluded from the rekey
    scope** (`builtins.removeAttrs self.nixosConfigurations [ "installer" ]`)
    — it has no agenix module, and agenix-rekey refuses to continue while any
    configured node lacks it.
3. **`localStorageDir` must derive from `self.outPath`** (passed in as
    `dotfilesRoot`), not a relative path from `lib/`. A relative path
    evaluates to a *different store copy* of the flake than the one
    agenix-rekey resolves as its root, failing the origin check with
    "doesn't seem to be a direct subpath of the flake directory".
4. **`ibkr-creds` lives in `ioshi/i-intelligence/ibgateway.nix`**, not the
    secrets module — its `file =` had to become `rekeyFile =` there too, or
    rafik's activation (ibgateway is enabled) would have hit the
    master-encrypted file and failed to decrypt.
