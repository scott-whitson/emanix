# eminix — install runbook

Fresh bare-metal install of an eminix host (rafik, datacore, …) from the
**eminix installer ISO**. The ISO carries the flake at `/etc/eminix/dotfiles`
and the host keys at `/etc/eminix/keys`, so the whole install is: build ISO →
boot → one command. Supersedes the Ventoy + staged-repo flow.

> **Design:** `docs/superpowers/specs/2026-08-15-eminix-installer-iso-design.md`.
> **Why not Ventoy anymore:** its installer tools are glibc-dynamic binaries
> that NixOS cannot run, and the minimal ISO does not auto-mount USB under
> `/run/media` — the old `/run/media/*/Ventoy/...` path failed on first
> contact (2026-08-13). The ISO removes staging, globs, and guesswork.

**Verified (2026-08-15):** ISO builds (`nix flake check` + isoImage);
installer v2 `--check-only` passes on rafik. QEMU boot test and the HP
cutover are the remaining validation (plan tasks 6 and 13–15).

---

## 1. Build the ISO (on rafik, before you go)

One command produces the artifact (fails closed if a host pubkey has no
staged private half):

```bash
cd ~/dotfiles
bin/eminix-iso                 # build only — prints the ISO path
sudo bin/eminix-iso /dev/sdX   # build and flash (ERASES /dev/sdX)
```

> **⚠ The ISO is your identity.** With keys baked in, whoever holds the ISO
> holds every host key. Build it on rafik, keep the `.iso` file and the stick
> like a host key, and re-flash rather than leaving sticks around.

### Staging the private halves (once)

`keys/<host>_host_ed25519.pub` are committed; the private halves are
gitignored and must be staged before a keys-carrying build:

```bash
cd ~/dotfiles
sudo cp /etc/ssh/ssh_host_ed25519_key keys/rafik_host_ed25519
# a host inheriting its key from another box (datacore inherits the OLD
# Debian box's key — cutover plan decision 8):
ssh -t datacore 'sudo cat /etc/ssh/ssh_host_ed25519_key'     > keys/datacore_host_ed25519
ssh -t datacore 'sudo cat /etc/ssh/ssh_host_ed25519_key.pub' > /tmp/datacore.pub
chmod 600 keys/*_host_ed25519
ssh-keygen -lf keys/datacore_host_ed25519.pub   # fingerprints must match
ssh-keygen -lf /tmp/datacore.pub
```

`bin/eminix-iso --no-keys` builds a debug/rescue ISO with no identity — the
installer then falls back to a staged `<host>-keys/` dir beside the repo or a
prompt.

## 2. Boot the target

1. **Disable Secure Boot** in the firmware and confirm **UEFI** mode.
   systemd-boot is unsigned — with Secure Boot on, the system installs fine
   but won't boot. The installer *warns* if it detects Secure Boot on, but it
   cannot change firmware for you.
2. Boot the stick (UEFI entry). The boot banner prints the three commands.
3. Network: ethernet is automatic; else `iwctl` (or `nmtui`) to join WiFi.
4. Optional remote driving: boot with `live.nixos.passwd=<pw>` on the kernel
   cmdline, then `ssh nixos@<ip>` from rafik (sshd runs with an ephemeral
   host key generated each boot).

## 3. Install

```bash
sudo fresh-eminix-install datacore          # or rafik, whistle, …
```

The installer prints a preflight checklist (repo, keys, UEFI, network, disk,
Secure Boot), auto-detects the target disk (largest non-removable device with
no mounted partitions — override with `--disk /dev/X`), then automates:
preflight → disko → inject host key → `nixos-install` → set scott's password
→ reboot. Remove the USB on reboot.

Dry-run the whole preflight without touching anything:

```bash
sudo fresh-eminix-install datacore --check-only
```

## 4. First boot (on the new host)

1. LUKS passphrase (where the layout uses one) → autologin → EWM (workstation
   role) or tty (server role).
2. Run the one-time setup:

```bash
eminix-firstboot
```

It joins the tailnet (prompts for a datacore preauthkey — mint with
`docker exec headscale headscale preauthkeys create --user 1 --expiration 1h`),
prints the Syncthing device id to pair on datacore (`:8384`, share
`pi-agent` + `docs`), clones the repo to `~/dotfiles`, and confirms
`~/.pi/agent/auth.json` decrypted.

## 5. Add a new host

1. Declare it in `flake.nix` via `mkHost` (role + hardware + disko layout +
   `hosts/<name>/configuration.nix`).
2. Commit its pubkey: `cp <host>:/etc/ssh/ssh_host_ed25519_key.pub keys/<host>_host_ed25519.pub`
   (or use a boot-generated key per the agenix-rekey bootstrap note in
   `eminix-firstboot`).
3. Stage the private half (section 1), rebuild the ISO, install.

## 6. Ongoing

```bash
cd ~/dotfiles && sudo nixos-rebuild switch --flake .#<host>
```

---

## What the installer does (and manual fallback)

`installer/fresh-eminix-install` automates, in order — run these by hand if the
script fails partway (needs `EMINIX_REPO` pointing at a checkout and the host
key staged beside it):

```bash
# (repo at $REPO; DISK=/dev/nvme0n1; KEY_DIR=…/<host>-keys)
nix run github:nix-community/disko/latest -- --mode destroy,format,mount --flake "$REPO#<host>"
install -d -m 755 /mnt/etc/ssh
install -m 600 "$KEY_DIR/<host>_host_ed25519"     /mnt/etc/ssh/ssh_host_ed25519_key
install -m 644 "$KEY_DIR/<host>_host_ed25519.pub" /mnt/etc/ssh/ssh_host_ed25519_key.pub
nixos-install --flake "$REPO#<host>" --no-root-password
nixos-enter --root /mnt -c 'passwd scott'
reboot
```

## Notes / gotchas

- **Host key = agenix identity.** The installer verifies the staged key's
  fingerprint against the recipient in `secrets/secrets.nix` (or, after the
  agenix-rekey migration, against the keypair's own `.pub`) before wiping
  anything. Losing the key means re-keying secrets.
- **agenix ↔ Home Manager.** The openrouter secret decrypts to
  `/run/agenix/openrouter-auth` (NOT into `~/.pi/agent`, which HM owns);
  `pi.nix` symlinks `~/.pi/agent/auth.json` to it. Don't set the agenix `path`
  back into `~/.pi/agent` — that recreates a root/scott ownership collision
  that breaks HM activation (caught in a VM boot test).
- **Secure Boot must stay off** — systemd-boot is unsigned; a firmware update
  re-enabling it stops the machine booting until you disable it again.
- **No swap** in datacore's disko layout. Add a btrfs swapfile later if you
  want hibernation. (rafik's layout has 16G swap; datacore's is
  swap-partition-free by decision — B2/restic is the encrypted copy.)
- **nixos-hardware** supplies per-CPU tuning (AMD pstate / s2idle fix on rafik
  via `lenovo-t14-gen5-amd.nix`); redistributable firmware is set per machine
  under `ioshi/hi-hardware/`.
