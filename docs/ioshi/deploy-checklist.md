# eminix v1 — deploy checklist (Scott's action items)

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

## 3. Install eminix on the physical T14
- [ ] Follow `docs/ioshi/eminix-install.md` end to end. Key don't-forget:
      - Stage a repo checkout AND `~/.ssh/eminix_host_ed25519{,.pub}` on the Ventoy USB.
      - Inject the pre-gen host key to `/mnt/etc/ssh/ssh_host_ed25519_key` BEFORE
        `nixos-install`, or agenix can't decrypt on first boot.
- [ ] First boot: tailscale preauthkey join, pair Syncthing on datacore
      (add eminix's device id + share pi-agent/docs), verify `~/.pi/agent/auth.json`.
- [ ] Clone repo to `~/dotfiles` (liveElisp home).

## 4. Housekeeping
- [ ] Once eminix + zord-old are confirmed good, delete the zord-old safety backups:
      `~/zord-old-backup-*.bundle`, `~/zord-old-worktree-*.tar.gz` (on zord-old).
- [ ] The pre-generated `~/.ssh/eminix_host_ed25519` — keep it backed up somewhere
      safe (password manager / offline) in case you ever re-key agenix.

## Deferred to eminix v2
Impermanence (ephemeral root); repo-wide `nixpkgs-fmt`; Home-Manager deprecation
cleanups; retiring the Debian-era `install/*.sh` + `ventoy/` bootstrap.
