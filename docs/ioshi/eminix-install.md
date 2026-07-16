# eminix — install runbook (ThinkPad T14 Gen 5 AMD)

The reproducible from-bare-metal install for **eminix**, the ioshi daily driver:
disko (LUKS + btrfs) + `nixos-install --flake .#eminix`, on-device from a Ventoy
NixOS ISO. Supersedes `docs/manual/10-nixos-install.md` (manual `parted`, pre-disko)
and the pre-ioshi `docs/new-host-checklist.md`.

Verified buildable on zord-old (2026-07-16):
`.#nixosConfigurations.eminix.config.system.build.{diskoScript,toplevel}` both build.

---

## 0. Before you touch the T14 (on your workstation)

1. **Insert the real OpenRouter keys** (agenix), if not already done:
   ```bash
   cd ~/dotfiles
   nix run github:ryantm/agenix -- -e secrets/openrouter-auth.age -i ~/.ssh/id_ed25519
   # replace the REPLACE-ME values, save
   git add secrets/openrouter-auth.age && git commit -m "secret: real openrouter keys" && git push
   ```
2. **Stage a checkout + the host key on the Ventoy USB** (private repo — the installer
   has no GitHub creds, so carry it):
   ```bash
   git clone ~/dotfiles /run/media/$USER/Ventoy/dotfiles         # or clone from GitHub
   mkdir -p /run/media/$USER/Ventoy/eminix-keys
   cp ~/.ssh/eminix_host_ed25519 ~/.ssh/eminix_host_ed25519.pub \
      /run/media/$USER/Ventoy/eminix-keys/
   ```
   The private `eminix_host_ed25519` is what lets agenix decrypt on first boot — it
   MUST become `/etc/ssh/ssh_host_ed25519_key` on the installed system (step 4).
3. **Mint a Tailscale preauthkey** (short-lived; used once at first boot):
   ```bash
   # on datacore:
   docker exec headscale headscale preauthkeys create --user 1 --expiration 1h
   ```
   Keep it handy for step 6.

## 1. Boot the installer

1. Plug in the Ventoy USB, reboot, open the boot menu (**F12** / Enter on ThinkPad).
2. Ventoy → `nixos-*-minimal-x86_64.iso`.
3. Network: ethernet is automatic. Wi-Fi: `iwctl` → `station wlan0 connect <ssid>`.
4. Confirm: `ping -c1 nixos.org`.

## 2. Get the flake onto the installer

```bash
sudo -i
mkdir -p /mnt-usb && mount /dev/disk/by-label/Ventoy /mnt-usb    # label may differ; lsblk
cp -r /mnt-usb/dotfiles /tmp/dotfiles
```

## 3. Partition + format + mount (disko)

```bash
lsblk   # CONFIRM the internal drive is /dev/nvme0n1 — disko WIPES it
nix --experimental-features "nix-command flakes" run github:nix-community/disko/latest -- \
  --mode destroy,format,mount \
  --flake /tmp/dotfiles#eminix
```
disko prompts for the **LUKS passphrase** — set the disk-encryption passphrase here.
When it finishes, the layout is mounted under `/mnt` (`/`, `/boot`, `/nix`, `/home`
as btrfs subvolumes `@`/`@nix`/`@home`, zstd).

## 4. Inject the pre-generated host key (BEFORE install)

Critical for agenix — the recipient pubkey in `secrets/secrets.nix` is this exact key.
If NixOS generates a fresh host key instead, agenix decryption fails on first boot.
```bash
mkdir -p /mnt/etc/ssh
cp /mnt-usb/eminix-keys/eminix_host_ed25519     /mnt/etc/ssh/ssh_host_ed25519_key
cp /mnt-usb/eminix-keys/eminix_host_ed25519.pub /mnt/etc/ssh/ssh_host_ed25519_key.pub
chmod 600 /mnt/etc/ssh/ssh_host_ed25519_key
```

## 5. Install

```bash
nixos-install --flake /tmp/dotfiles#eminix --no-root-password
# set scott's password when prompted, or:
nixos-enter --root /mnt -c 'passwd scott'
```
This builds the system closure and activates it into `/mnt`. Then `reboot` (remove USB).

## 6. First boot

1. LUKS passphrase → console autologin as `scott` → EWM launches from tty1
   (`ioshi/i-intelligence/ewm.nix`). If EWM flaps, see the flap note in that module.
2. **Verify agenix worked** (proves the host-key injection):
   ```bash
   cat ~/.pi/agent/auth.json     # should show your REAL openrouter keys, not REPLACE-ME
   ```
3. **Join the tailnet** (the login-server URL is baked into the flake):
   ```bash
   echo '<preauthkey from step 0.3>' | sudo tee /var/lib/tailscale-authkey
   sudo systemctl restart tailscaled-autoconnect
   tailscale status && ping -c1 datacore
   sudo rm /var/lib/tailscale-authkey        # tailscale state holds the identity now
   ```
4. **Pair Syncthing** — on datacore (`:8384` or REST), add eminix's device ID and share
   the `pi-agent` + `docs` folders (pairing is two-sided; the flake declares the datacore
   side). Device ID: `syncthing --device-id` on eminix.
5. **Clone the repo to its live-edit home** (liveElisp symlinks
   `~/.config/emacs` → `~/dotfiles/ioshi/i-intelligence/emacs`, and
   `scott.dotfiles.path` defaults to `~/dotfiles`):
   ```bash
   git clone git@github.com:scott-whitson/dotfiles ~/dotfiles
   ```

## 7. Ongoing

```bash
cd ~/dotfiles && sudo nixos-rebuild switch --flake .#eminix
```

## Notes / gotchas

- **No swap** in eminix's disko layout (unlike zord-old). Add a btrfs swapfile later if
  you want hibernation.
- **nixos-hardware** supplies AMD pstate + the s2idle `acpi.ec_no_wakeup` fix; firmware
  is set by `ioshi/hi-hardware/lenovo-t14-gen5-amd.nix` (nixos-hardware does NOT set it).
- **agenix identity** = `/etc/ssh/ssh_host_ed25519_key` (default). Losing the pre-generated
  key means re-keying the secret (`agenix -r`) with eminix's new host key.
