# weasel — NixOS-WSL work distro

`weasel` is the third `nixosConfigurations` entry in this flake: a
NixOS-WSL distro that replaces the Debian WSL + `scott@work` standalone
Home-Manager pair on the work laptop. Unlike the standalone nodes, weasel
is a full NixOS host — agenix, declarative docker/oci-containers, and the
`ioshi` home layer arrive via the flake's `hmModule` (profile `wsl`, same
home as the retired `scott@work`). Design spec:
`docs/superpowers/specs/2026-07-21-weasel-nixos-wsl-design.md`; full
implementation plan (archived once this runbook is verified):
`docs/superpowers/plans/2026-07-21-weasel-nixos-wsl.md`.

This is the durable, standalone home for the import/bootstrap/cutover/
retirement procedure — it must work even after the plan doc is gone.

## Import & bootstrap

No repo changes. Highest-risk integration test happens here, before any
data moves.

1. Download the NixOS-WSL release (from Debian WSL):

```bash
cd /mnt/c/Users/swhitson.CENTRALDATA/Downloads
curl -LO https://github.com/nix-community/NixOS-WSL/releases/latest/download/nixos.wsl
```

2. Import (Scott, PowerShell or `!` prefix — does NOT disturb running distros):

```powershell
wsl --import weasel $env:LOCALAPPDATA\wsl\weasel $env:USERPROFILE\Downloads\nixos.wsl --version 2
```
If `--import` rejects the `.wsl` file (older WSL): `wsl --install --from-file $env:USERPROFILE\Downloads\nixos.wsl` and adjust the distro name below to what it registers (`wsl -l -v`).

3. Sparse vhdx from day one (weasel must be stopped; it is — never started):

```powershell
wsl --manage weasel --set-sparse true
```

4. First boot, seed SSH key, clone dotfiles (Scott: `wsl -d weasel`, default user `nixos`):

```bash
sudo -i
export NIX_CONFIG="experimental-features = nix-command flakes"   # in case the base image predates default-on flakes
/mnt/c/Windows/System32/wsl.exe -d Debian -u scott tar -C /home/scott -cf - .ssh | tar -xf - -C /root/
chmod 700 /root/.ssh && chmod 600 /root/.ssh/id_ed25519
GIT_SSH_COMMAND="ssh -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new" \
  nix run nixpkgs#git -- clone git@github.com:scott-whitson/dotfiles.git /tmp/dotfiles
```

5. First rebuild (creates user scott, applies everything):

```bash
nixos-rebuild switch --flake /tmp/dotfiles#weasel
```
Expected: builds the Emacs closure (long first build), switches, ends with activation output including home-manager. Exit weasel, `wsl --terminate weasel` (Scott), re-enter `wsl -d weasel` — now lands as user `scott` with zsh.

6. Move the clone home + hand over SSH:

```bash
# as scott on weasel
sudo mv /tmp/dotfiles /home/scott/dotfiles && sudo chown -R scott:users /home/scott/dotfiles
sudo cp -r /root/.ssh /home/scott/.ssh && sudo chown -R scott:users /home/scott/.ssh
chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_ed25519
git -C ~/dotfiles remote -v   # expect git@github.com:scott-whitson/dotfiles.git
sudo rm -rf /root/.ssh
```

7. SMOKE TEST (Scott): WSLg + pgtk Emacs

On weasel: `ec` → the Emacs GUI must open as a Wayland (WSLg) window with
correct fonts. In it: `C-h v window-system RET` shows `pgtk`. If this
fails, STOP the project here — Debian untouched, zero blast radius; debug
before any migration.

8. Verify the system services:

```bash
systemctl --user status emacs.service --no-pager | head -3    # active (running)
systemctl --user status syncthing.service --no-pager | head -3 # active (running)
systemctl status docker.service --no-pager | head -3           # active (running)
systemctl status tailscaled.service --no-pager | head -3       # active (auth pending — Task 6)
systemctl status docker-pearl-platform-db.service --no-pager | head -3 # failing is EXPECTED (env file arrives in Task 8)
docker info --format '{{json .DefaultRuntime}}' >/dev/null && echo docker-ok
```

## Rebuild

weasel rebuilds from its own local clone — it is the dotfiles writer once
the handoff below completes. No 3-hop (unlike datacore/eminix).

```bash
sudo nixos-rebuild switch --flake ~/dotfiles#weasel
```

## agenix recipient flow

Adds weasel as an agenix recipient. `secrets/secrets.nix` is edited on the
Debian WSL clone, which is still the writer until the write handoff.

1. Capture weasel's host key (net/ssh.nix enabled sshd → host keys exist):

```bash
# on weasel
sudo cat /etc/ssh/ssh_host_ed25519_key.pub
```

2. Add recipient + rekey (on Debian WSL, in `~/dotfiles`):

In `secrets/secrets.nix`, add above the `scott` line (key text from Step 1):

```nix
  weasel = "ssh-ed25519 AAAA<weasel-host-key> root@weasel";
```
and extend: `"openrouter-auth.age".publicKeys = [ eminix zordold weasel scott ];`

```bash
cd /home/scott/dotfiles/secrets
nix run github:ryantm/agenix -- --rekey -i /home/scott/.ssh/id_ed25519
cd /home/scott/dotfiles
git add secrets/secrets.nix secrets/openrouter-auth.age
git commit -m "secrets: add weasel as openrouter-auth recipient"
git push
```

3. Rebuild weasel and verify decryption:

```bash
# on weasel
git -C ~/dotfiles pull --ff-only
sudo nixos-rebuild switch --flake ~/dotfiles#weasel
sudo test -f /run/agenix/openrouter-auth && echo secret-ok
readlink ~/.pi/agent/auth.json    # expect /run/agenix/openrouter-auth
```
(Never cat the secret.)

## tailscale join ritual

1. Pre-auth key from datacore's headscale (from Debian WSL, existing ssh access):

```bash
ssh datacore "docker exec headscale headscale preauthkeys create --user 1 --expiration 1h"
```

2. Place the key on weasel and connect:

```bash
# on weasel — paste the key from Step 1
echo '<preauthkey>' | sudo tee /var/lib/tailscale-authkey >/dev/null
sudo systemctl restart tailscaled-autoconnect
sleep 5; tailscale status | head -5
```
Expected: weasel listed plus datacore/eminix peers. Then:

```bash
tailscale ping datacore   # expect pong, ideally direct
```

## syncthing join

weasel joins as a second, read-side spoke. Debian REMAINS the writer
throughout this step — weasel must not edit `~/projects` or
`~/docs/org/work` yet.

1. weasel's device ID:

```bash
# on weasel
syncthing --device-id
```

2. Register weasel on datacore + attach folders (from Debian WSL). Follow
   the Phase 3 REST recipe in `docs/ioshi/work-sync.md`: read the API key
   from datacore's `~/.local/state/syncthing/config.xml` into a shell
   variable (never print), then via `curl -sS` (never `-v`): add weasel as
   a device, and add weasel's device ID to the `devices` arrays of folders
   `work-projects` and `work-docs`. Use absolute paths for any `-d @file`
   payloads.

3. Wait for full sync, then verify:

```bash
# on weasel — completion via the local REST API, or simply:
watch -n 30 'df -h ~; find ~/projects -maxdepth 1 | wc -l'
```
Done when folder status in weasel's syncthing log shows both folders
idle/up-to-date. Verify:

```bash
# spot-check checksums Debian vs weasel on a couple of files
/mnt/c/Windows/System32/wsl.exe -d Debian -u scott sha256sum /home/scott/docs/org/work/*.org | sha256sum
sha256sum ~/docs/org/work/*.org | sha256sum
```
Expected: identical digest-of-digests.

## Cutover checklist

Write handoff + data migration (Scott's timing; this is the point of
commitment) and the Windows-side finish.

- [ ] Quiesce Debian (park other Claude sessions' edits first):
  `systemctl --user stop syncthing && systemctl --user disable syncthing`
  on Debian; verify on datacore both work folders are idle. From this
  moment weasel is the writer.
- [ ] DB password + env file placed on weasel (recovered from Debian's
  live container without ever printing it) at `/var/lib/pearl-db/env`.
- [ ] `pearl-platform-db` migrated: `pg_dump` on Debian AFTER the write
  quiesce, restore into weasel's declarative container; verify `\dt` and
  spot-check a row count.
- [ ] Worktree DBs migrated for each still-live worktree (`chat-interrupt`
  :5435, `kb-cores` :5444, `ap-automation-phase1`) — `docker compose up -d
  db` on weasel in each worktree, then dump/restore per DB. Skip and note
  any branch already merged/dead.
- [ ] Home state one-time copy done: `clients .claude .pi .gitconfig.local
  .zsh_history` (exhaustive list — nothing else copies), plus the md2org
  audit log only (`md2org-conversion-log-20260721.txt` — NOT the whole
  `~/.local/backups` dir; `cd-audit-premirror-20260720.git` holds dirty
  history and must not propagate).
- [ ] Dotfiles writer handoff confirmed: Debian's `~/dotfiles` clean, no
  unpushed commits. weasel's clone is now the working copy.
- [ ] `pi` and `claude` reinstalled on weasel (pi: npm package under
  `~/.local` prefix + launcher script copied from Debian; claude: native
  installer, runs via nix-ld). `pi --version && claude --version` both
  succeed; `pi` starts without demanding auth (auth.json is the agenix
  symlink from the agenix step above).
- [ ] Debian's syncthing device removed from datacore (`work-projects` /
  `work-docs` device arrays + device entry deleted). Debian fully out of
  the sync topology.
- [ ] Windows Terminal profile: weasel's generated profile's
  `startingDirectory` set to `//wsl$/weasel/home/scott`; picked as WT
  default if desired.
- [ ] Default distro set:

```powershell
wsl --set-default weasel
```
- [ ] GlazeWM: nothing to do — the `msrdc` ignore rule covers all WSLg
  windows.
- [ ] Begin the trust week: daily driving on weasel; Debian stays
  registered but dormant (syncthing disabled, DBs stopped — optional: `wsl
  -d Debian -u scott docker stop $(...)`). Log any friction in the
  quarterly tracker.

## Retirement

**Do not run any of this until the trust week has passed and Scott gives
the explicit go.**

1. (Scott) Unregister Debian — IRREVERSIBLE, destroys its vhdx (~65 GB reclaimed):

```powershell
wsl --unregister Debian
```

2. Flake cleanup (on weasel, now the dotfiles writer): remove
   `"scott@work" = mkHome "wsl";` from `flake.nix`
   `homeConfigurations` (datacore's entry stays). Update the `mkHome`
   comment ("Debian WSL" reference) and `docs/ioshi/standalone-hm.md`
   (`scott@work` retired → pointer to `docs/ioshi/weasel.md`).

```bash
cd ~/dotfiles
nix eval '.#homeConfigurations."scott@datacore".activationPackage.drvPath'   # still evaluates
nix eval '.#nixosConfigurations.weasel.config.system.build.toplevel.drvPath' # still evaluates
git add flake.nix docs/ioshi/standalone-hm.md
git commit -m "chore(weasel): retire the scott@work standalone config"
git push
```

3. Close the ledger: append completion to `.superpowers/sdd/progress.md`;
   update memory (`project_three_node_model.md` or a new weasel project
   memory).

## Gotchas

- **Port 5434 collision:** 5434 is owned by the declarative
  `pearl-platform-db` (oci-containers). Running `docker compose up db` in
  the pearl-platform main checkout now collides with it — use the
  declarative DB instead. Worktree DBs on their own ports (5435, 5444,
  ...) are unaffected.
- **`ec` / WSLg unchanged:** the Wayland-first `ec` launcher and the
  GlazeWM `msrdc` ignore rule both carry over as-is from the Debian setup
  (see `docs/ioshi/standalone-hm.md`) — no new gotchas introduced by the
  NixOS-WSL move.
- **`wsl --manage weasel --set-sparse true` requires the distro stopped.**
  weasel must never have been started before this runs (it isn't, at
  import time) — do this immediately after `wsl --import`, before first
  boot.
