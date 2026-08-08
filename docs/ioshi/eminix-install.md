# rafik — install runbook (ThinkPad T14 Gen 5 AMD)

Fresh bare-metal install of **rafik**, the ioshi daily driver. Two scripts do the
work; you type one command each (plus passphrases). Supersedes the manual
`docs/manual/10-nixos-install.md` and `docs/new-host-checklist.md`.

Verified (2026-07-16): `.#rafik` diskoScript + toplevel build; a fresh-disk VM boot
reaches multi-user with Home Manager clean; both scripts pass shellcheck.

**Name history:** this host was called `eminix` until it was renamed `rafik`
on 2026-08-07, so that `eminix` names only the NixOS distribution (see
`profiles/eminix.nix`) and not any one machine. The installer scripts keep
their `eminix` filenames (`fresh-eminix-install`, `eminix-firstboot`) — they
install and configure the *eminix distribution*, now onto the host `rafik`.

> ### ⚠ The one thing a script can't do: firmware
> **Disable Secure Boot** in the T14 firmware (F1 at the ThinkPad logo → Security →
> Secure Boot → Disabled) and confirm **UEFI** mode. systemd-boot is unsigned — with
> Secure Boot on, the system installs fine but won't boot. The installer *warns* if it
> detects Secure Boot on, but it cannot change firmware for you.

---

## 1. On your workstation (once, before you go)

1. **Insert the real OpenRouter keys** (skip if done):
   ```bash
   cd ~/dotfiles
   nix run github:ryantm/agenix -- -e secrets/openrouter-auth.age -i ~/.ssh/id_ed25519
   git add secrets/openrouter-auth.age && git commit -m "secret: real openrouter keys" && git push
   ```
2. **Stage the repo + host key on the Ventoy USB** (private repo → the installer carries it;
   the key must sit *beside* the repo — the installer looks for `../rafik-keys`):
   ```bash
   V=/run/media/$USER/Ventoy            # adjust to your mount
   git clone ~/dotfiles "$V/dotfiles"
   mkdir -p "$V/rafik-keys"
   cp ~/.ssh/rafik_host_ed25519{,.pub} "$V/rafik-keys/"
   ```

## 2. Install (in the NixOS live ISO)

1. Boot Ventoy → `nixos-*-minimal-x86_64.iso`.
2. Network: ethernet is automatic; else `iwctl` → `station wlan0 connect <ssid>`.
3. Run the installer:
   ```bash
   sudo bash /run/media/*/Ventoy/dotfiles/installer/fresh-eminix-install
   ```
   It preflights (UEFI, network, Secure-Boot warning, **host-key fingerprint match**),
   asks you to type `yes` to wipe `/dev/nvme0n1`, prompts the **LUKS passphrase**
   (disko), injects the host key, runs `nixos-install`, prompts a **password for scott**,
   and offers to reboot. Remove the USB on reboot.

## 3. First boot (on rafik)

1. LUKS passphrase → autologin → EWM. (If EWM can't bring up the GPU, you land on a tty —
   recoverable; investigate `journalctl`/the flap note in `ewm.nix`.)
2. Run the one-time setup:
   ```bash
   eminix-firstboot
   ```
   It joins the tailnet (prompts for a datacore preauthkey — mint with
   `docker exec headscale headscale preauthkeys create --user 1 --expiration 1h`), prints
   the Syncthing device id to pair on datacore (`:8384`, share `pi-agent` + `docs`), clones
   the repo to `~/dotfiles`, and confirms `~/.pi/agent/auth.json` decrypted.

## 4. Ongoing

```bash
cd ~/dotfiles && sudo nixos-rebuild switch --flake .#rafik
```

---

## What the installer does (and manual fallback)

`installer/fresh-eminix-install` automates, in order — run these by hand if the script
fails partway:

```bash
# (repo staged at $REPO on the USB; DISK=/dev/nvme0n1)
nix run github:nix-community/disko/latest -- --mode destroy,format,mount --flake "$REPO#rafik"
install -d -m 755 /mnt/etc/ssh
install -m 600 <usb>/rafik-keys/rafik_host_ed25519     /mnt/etc/ssh/ssh_host_ed25519_key
install -m 644 <usb>/rafik-keys/rafik_host_ed25519.pub /mnt/etc/ssh/ssh_host_ed25519_key.pub
nixos-install --flake "$REPO#rafik" --no-root-password
nixos-enter --root /mnt -c 'passwd scott'
reboot
```

## Notes / gotchas

- **Host key = agenix identity.** The installer verifies the staged `rafik_host_ed25519`
  fingerprint matches the recipient in `secrets/secrets.nix` before wiping anything. Losing
  the key means re-keying the secret (`agenix -r`) with rafik's new host key.
- **agenix ↔ Home Manager.** The openrouter secret decrypts to `/run/agenix/openrouter-auth`
  (NOT into `~/.pi/agent`, which HM owns); `pi.nix` symlinks `~/.pi/agent/auth.json` to it.
  Don't set the agenix `path` back into `~/.pi/agent` — that recreates a root/scott
  ownership collision that breaks HM activation (caught in a VM boot test).
- **Secure Boot must stay off** — systemd-boot is unsigned; a firmware update re-enabling it
  stops the machine booting until you disable it again.
- **No swap** in rafik's disko layout. Add a btrfs swapfile later if you want hibernation.
- **nixos-hardware** supplies AMD pstate + the s2idle `acpi.ec_no_wakeup` fix; redistributable
  firmware is set in `ioshi/hi-hardware/lenovo-t14-gen5-amd.nix`.
