# rafik v1 — deploy checklist (Scott's action items)

Everything Claude verified in-repo but deliberately did NOT do (real secrets,
physical install, sudo on live hosts). Order matters.

## 1. Secrets — insert the real OpenRouter keys
- [ ] From the WSL box (your key edits the secret):
      ```
      cd ~/dotfiles
      nix run github:ryantm/agenix -- -e secrets/openrouter-auth.age -i ~/.ssh/id_ed25519
      ```
      Replace both `REPLACE-ME` values with the real management + regular keys.
- [ ] `git add secrets/openrouter-auth.age && git commit -m "secret: real openrouter keys" && git push`

## 2. Deploy to zord-old (the live NixOS box)
- [ ] Fix the root-owned repo + sync to canonical line (needs your sudo):
      ```
      sudo chown -R scott:users /etc/dotfiles/.git
      cd /etc/dotfiles && git fetch origin && git reset --hard origin/main
      sudo nixos-rebuild switch --flake .#zord-old
      ```
- [ ] Post-switch verification:
      - `cat ~/.pi/agent/auth.json` → real openrouter keys (proves agenix + host key)
      - `nix-store -qR /run/current-system | grep -c emacs.*-with-packages` → 1
      - `tailscale status`, `systemctl status syncthing`

## 3. Install rafik on the physical T14 (now scripted)
- [ ] Firmware: **disable Secure Boot**, confirm UEFI (the one thing the script can't do).
- [ ] Stage on Ventoy: `git clone ~/dotfiles <V>/dotfiles` and
      `cp ~/.ssh/rafik_host_ed25519{,.pub} <V>/rafik-keys/` (key beside the repo).
- [ ] Boot the NixOS ISO, then one command:
      `sudo bash /run/media/*/Ventoy/dotfiles/installer/fresh-eminix-install`
      (handles disko + host-key inject + fingerprint check + nixos-install + reboot).
- [ ] First boot: `eminix-firstboot` (tailnet join, Syncthing pairing id, repo clone,
      auth.json check). Then pair the device id on datacore (`:8384`).
- [ ] Full detail / manual fallback: `docs/ioshi/eminix-install.md`.

## 4. Housekeeping
- [ ] Once rafik + zord-old are confirmed good, delete the zord-old safety backups:
      `~/zord-old-backup-*.bundle`, `~/zord-old-worktree-*.tar.gz` (on zord-old).
- [ ] The pre-generated `~/.ssh/rafik_host_ed25519` — keep it backed up somewhere
      safe (password manager / offline) in case you ever re-key agenix.

## Deferred to rafik v2
Impermanence (ephemeral root); repo-wide `nixpkgs-fmt`; Home-Manager deprecation
cleanups; retiring the Debian-era `install/*.sh` + `ventoy/` bootstrap.
