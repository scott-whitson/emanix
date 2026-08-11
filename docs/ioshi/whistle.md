# whistle — NixOS-WSL work distro

`whistle` is the third `nixosConfigurations` entry in this flake: a
NixOS-WSL distro that replaces the Debian WSL + `scott@work` standalone
Home-Manager pair on the work laptop. Unlike the standalone nodes, whistle
is a full NixOS host — agenix, declarative docker/oci-containers, and the
`ioshi` home layer arrive via the flake's `hmModule` (role `wsl`, same
home as the retired `scott@work`). Design spec:
`docs/superpowers/specs/2026-07-21-weasel-nixos-wsl-design.md`; full
implementation plan (archived once this runbook is verified):
`docs/superpowers/plans/archive/2026-07-21-weasel-nixos-wsl.md`.

**Name history:** this host was called `weasel` from its 2026-07-22 cutover
until 2026-08-04, when it was renamed `whistle`
(`docs/superpowers/specs/2026-08-04-whistle-rename-design.md`). Dated specs
and plans still say weasel deliberately. Commands below use the current name;
anything older than 2026-08-04 in your shell history or the tailnet admin log
will say weasel.

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
wsl --import whistle $env:LOCALAPPDATA\wsl\whistle $env:USERPROFILE\Downloads\nixos.wsl --version 2
```
If `--import` rejects the `.wsl` file (older WSL): `wsl --install --from-file $env:USERPROFILE\Downloads\nixos.wsl` and adjust the distro name below to what it registers (`wsl -l -v`).

3. Sparse vhdx: **skipped** (2026-07-22). Current WSL gates sparse VHDs
   behind `--allow-unsafe` over data-corruption reports — see Gotchas.
   Compact manually when the vhdx ever bloats.

4. First boot, seed SSH key, clone dotfiles (Scott: `wsl -d whistle`, default user `nixos`):

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
nixos-rebuild switch --flake /tmp/dotfiles#whistle
```
Expected: builds the Emacs closure (long first build), switches, ends with activation output including home-manager. The switch exits NONZERO with three EXPECTED failures that self-heal later: the agenix activation snippet (no host key + not yet a recipient — Task 5), docker-pearl-platform-db.service (env file — Task 8), and tailscaled-autoconnect.service (authkey — Task 6). These are not stop conditions; only the Emacs/WSLg smoke test (Step 7) is. Exit whistle, `wsl --terminate whistle` (Scott), re-enter `wsl -d whistle` — now lands as user `scott` with zsh.

6. Move the clone home + hand over SSH:

```bash
# as scott on whistle
sudo mv /tmp/dotfiles /home/scott/dotfiles && sudo chown -R scott:users /home/scott/dotfiles
sudo cp -r /root/.ssh /home/scott/.ssh && sudo chown -R scott:users /home/scott/.ssh
chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_ed25519
git -C ~/dotfiles remote -v   # expect git@github.com:scott-whitson/dotfiles.git
sudo rm -rf /root/.ssh
```

7. SMOKE TEST (Scott): WSLg + pgtk Emacs

On whistle: `ec` → the Emacs GUI must open as a Wayland (WSLg) window with
correct fonts. In it: `C-h v window-system RET` shows `pgtk`. If this
fails, STOP the project here — Debian untouched, zero blast radius; debug
before any migration.

8. Verify the system services:

```bash
systemctl --user status emacs.service --no-pager | head -3    # active (running)
systemctl --user status syncthing.service --no-pager | head -3 # active (running)
systemctl status docker.service --no-pager | head -3           # active (running)
systemctl status tailscaled.service --no-pager | head -3       # active (auth pending — Task 6; tailscaled-autoconnect.service failed is expected until then)
systemctl status docker-pearl-platform-db.service --no-pager | head -3 # failing is EXPECTED (env file arrives in Task 8)
test -f /run/agenix/openrouter-auth || echo "agenix activation snippet failure is EXPECTED until Task 5 (/run/agenix empty, ~/.pi/agent/auth.json a dangling symlink until then)"
docker info --format '{{json .DefaultRuntime}}' >/dev/null && echo docker-ok
```

## Rebuild

whistle rebuilds from its own local clone — it is the dotfiles writer once
the handoff below completes. No 3-hop (unlike datacore/rafik).

```bash
sudo nixos-rebuild switch --flake ~/dotfiles#whistle
```

## agenix recipient flow

Adds whistle as an agenix recipient. `secrets/secrets.nix` is edited on the
Debian WSL clone, which is still the writer until the write handoff.

1. Capture whistle's host key (net/ssh.nix enabled sshd → host keys exist):

```bash
# on whistle
sudo cat /etc/ssh/ssh_host_ed25519_key.pub
```

2. Add recipient + rekey (on Debian WSL, in `~/dotfiles`):

In `secrets/secrets.nix`, add above the `scott` line (key text from Step 1):

```nix
  whistle = "ssh-ed25519 AAAA<whistle-host-key> root@<hostname-at-keygen>";
```

The live entry's comment reads `root@weasel` — the key was generated before
the 2026-08-04 rename and was deliberately **not** regenerated, so the stale
comment is correct and must not be "fixed".
and extend: `"openrouter-auth.age".publicKeys = [ rafik zordold whistle scott ];`

```bash
cd /home/scott/dotfiles/secrets
nix run github:ryantm/agenix -- --rekey -i /home/scott/.ssh/id_ed25519
cd /home/scott/dotfiles
git add secrets/secrets.nix secrets/openrouter-auth.age
git commit -m "secrets: add whistle as openrouter-auth recipient"
git push
```

3. Rebuild whistle and verify decryption:

```bash
# on whistle
git -C ~/dotfiles pull --ff-only
sudo nixos-rebuild switch --flake ~/dotfiles#whistle
sudo test -f /run/agenix/openrouter-auth && echo secret-ok
readlink ~/.pi/agent/auth.json    # expect /run/agenix/openrouter-auth
```
(Never cat the secret.)

## tailscale join ritual

1. Pre-auth key from datacore's headscale (from Debian WSL, existing ssh access):

```bash
ssh datacore "docker exec headscale headscale preauthkeys create --user 1 --expiration 1h"
```

2. Place the key on whistle and connect:

```bash
# on whistle — paste the key from Step 1
echo '<preauthkey>' | sudo tee /var/lib/tailscale-authkey >/dev/null
sudo systemctl restart tailscaled-autoconnect
sleep 5; tailscale status | head -5
```
Expected: whistle listed plus datacore/rafik peers. Then:

```bash
tailscale ping datacore   # expect pong, ideally direct
```

## syncthing join

whistle joins as a second, read-side spoke. Debian REMAINS the writer
throughout this step — whistle must not edit `~/projects` or
`~/docs/org/work` yet.

1. whistle's device ID:

```bash
# on whistle
syncthing --device-id
```

2. Register whistle on datacore + attach folders (from Debian WSL). Follow
   the Phase 3 REST recipe in `docs/ioshi/work-sync.md`: read the API key
   from datacore's `~/.local/state/syncthing/config.xml` into a shell
   variable (never print), then via `curl -sS` (never `-v`): add whistle as
   a device, and add whistle's device ID to the `devices` arrays of folders
   `work-projects` and `work-docs`. Use absolute paths for any `-d @file`
   payloads.

3. Wait for full sync, then verify:

```bash
# on whistle — completion via the local REST API, or simply:
watch -n 30 'df -h ~; find ~/projects -maxdepth 1 | wc -l'
```
Done when folder status in whistle's syncthing log shows both folders
idle/up-to-date. Verify:

```bash
# spot-check checksums Debian vs whistle on a couple of files
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
  moment whistle is the writer.
- [ ] DB password + env file placed on whistle (recovered from Debian's
  live container without ever printing it) at `/var/lib/pearl-db/env`.
- [ ] `pearl-platform-db` migrated: `pg_dump` on Debian AFTER the write
  quiesce, restore into whistle's declarative container; verify `\dt` and
  spot-check a row count.
- [ ] Worktree DBs migrated for each still-live worktree (`chat-interrupt`
  :5435, `kb-cores` :5444, `ap-automation-phase1`) — `docker compose up -d
  db` on whistle in each worktree, then dump/restore per DB. Skip and note
  any branch already merged/dead.
- [ ] Home state one-time copy done: `clients .claude .pi .gitconfig.local
  .zsh_history` (exhaustive list — nothing else copies; the tar excludes
  `.pi/agent/auth.json` because on whistle it's an HM-managed symlink to
  `/run/agenix/openrouter-auth` — copying Debian's plain file would replace
  the symlink, breaking the next home-manager activation with an "existing
  file in the way" conflict and re-introducing a plaintext key on disk),
  plus the md2org audit log only (`md2org-conversion-log-20260721.txt` —
  NOT the whole `~/.local/backups` dir; `cd-audit-premirror-20260720.git`
  holds dirty history and must not propagate).
- [ ] Dotfiles writer handoff confirmed: Debian's `~/dotfiles` clean, no
  unpushed commits. whistle's clone is now the working copy.
- [ ] `pi` and `claude` reinstalled on whistle (pi: npm package under
  `~/.local` prefix + launcher script copied from Debian; claude: native
  installer, runs via nix-ld). `pi --version && claude --version` both
  succeed; `pi` starts without demanding auth (auth.json is the agenix
  symlink from the agenix step above).
- [ ] Debian's syncthing device removed from datacore (`work-projects` /
  `work-docs` device arrays + device entry deleted). Debian fully out of
  the sync topology.
- [ ] Windows Terminal profile: whistle's generated profile's
  `startingDirectory` set to `//wsl$/whistle/home/scott`; picked as WT
  default if desired.
- [ ] Default distro set:

```powershell
wsl --set-default whistle
```
- [ ] GlazeWM: nothing to do — the `msrdc` ignore rule covers all WSLg
  windows.
- [ ] Begin the trust week: daily driving on whistle; Debian stays
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

2. Flake cleanup (on whistle, now the dotfiles writer): remove
   `"scott@work" = mkHome "wsl";` from `flake.nix`
   `homeConfigurations` (datacore's entry stays). Update the `mkHome`
   comment ("Debian WSL" reference) and `docs/ioshi/standalone-hm.md`
   (`scott@work` retired → pointer to `docs/ioshi/whistle.md`).

```bash
cd ~/dotfiles
nix eval '.#homeConfigurations."scott@datacore".activationPackage.drvPath'   # still evaluates
nix eval '.#nixosConfigurations.whistle.config.system.build.toplevel.drvPath' # still evaluates
git add flake.nix docs/ioshi/standalone-hm.md
git commit -m "chore(whistle): retire the scott@work standalone config"
git push
```

3. Close the ledger: append completion to `.superpowers/sdd/progress.md`;
   update memory (`project_three_node_model.md` or a new whistle project
   memory).

## Gotchas

- **Port 5434 collision:** 5434 is owned by the declarative
  `pearl-platform-db` (oci-containers). Running `docker compose up db` in
  the pearl-platform main checkout now collides with it — use the
  declarative DB instead. Worktree DBs on their own ports (5435, 5444,
  ...) are unaffected.
- **`ec` / WSLg:** the Wayland-first `ec` launcher carries over as-is. The
  GlazeWM ignore rule narrowed 2026-07-23: only the Emacs WSLg window is
  ignored (matched by `msrdc` process + `(?i)emacs` title, backed by a
  pinned `frame-title-format`); other WSLg windows (ghostty via `C-c o`)
  are tiled by GlazeWM — details in `docs/ioshi/standalone-hm.md`.
- **Sparse vhdx SKIPPED (2026-07-22 decision).** Current WSL disables
  sparse VHDs over data-corruption reports; forcing needs
  `--set-sparse true --allow-unsafe`. Not worth the risk on the primary
  work distro — compact manually when needed (fstrim inside, then the
  usual vhdx compaction, see `docs`/memory for the Debian recipe).
- **WSLg's compositor can die under a still-running distro** (seen
  2026-07-26 after ~3 days uptime spanning a VM crash): the wayland-0/X0
  socket FILES survive but nothing listens — every GUI app fails, and pgtk
  emacs KILLS ITS OWN DAEMON when frame creation can't open the display
  (`cannot open display: wayland-0`, then systemd restart-loops it).
  Liveness tell: `/tmp/.X11-unix/X0` vanishes when WSLg is dead. Only fix:
  `wsl --terminate whistle` + reopen. The `ec` function guards on the X0
  probe and prints this instead of assassinating the daemon.
- **WSLg windows that open but never paint** (2026-08-10, quieter sibling of
  the compositor death above — cost most of a morning). weston hit an I/O
  error mapping `/mnt/shared_memory` at session start and therefore set
  `use_gfxredir = 0`, killing the channel that carries window pixels to
  Windows. Everything else looks healthy and points you at the wrong layer:
  the emacs daemon responds, `make-frame-on-display` succeeds, the frame is
  a real `pgtk` frame with `frame-visible-p` = `t`, Windows reports the
  `RAIL_WINDOW` visible and focusable with a taskbar button — and not one
  pixel is drawn on any monitor. The only tell is a `[WARN:COPY MODE]`
  prefix on the window title. Diagnose in one line:
  `grep 'shared_memory\|use_gfxredir' /mnt/wslg/weston.log` — read
  `use_gfxredir` ONLY (`0` broken, `1` fine); `enable_copy_warning_title = 1`
  is 1 in healthy sessions too and is NOT a fault signal.
  **Only fix: `wsl --shutdown`.** weston reads shared memory once at startup,
  `/mnt/shared_memory` lives in WSLg's *system* distro (invisible from here),
  and `wsl --terminate whistle` is NOT enough — nor is killing `msrdc.exe`,
  which renegotiates straight back into copy mode (both tried). Confirmed
  fixed 2026-08-11: clean boot came up `use_gfxredir = 1`, so the EIO was a
  one-off host-side race, not an EDR block. `ec` now guards on this too, and
  `et` (terminal frame) is unaffected throughout — reach for it immediately
  rather than debugging the GUI under pressure. Innocent bystanders that
  wasted time here: the GlazeWM ignore rule (verify via its unelevated IPC,
  `ws://127.0.0.1:6123` + `query windows`; `localhost` resolves to `::1` and
  fails, and the CLI needs elevation), the laptop panel being Windows'
  primary display, and `PrintWindow` returning solid black — which is normal
  for GPU-composited WSLg surfaces and proves nothing.
- **Stock-image boots wipe `WSLInterop` for EVERY distro.** binfmt_misc is
  global across WSL2 distros; the unconfigured NixOS-WSL image's boot can
  drop the entry, which breaks running `*.exe` from Debian too
  (`exec format error`). Restore from any affected distro with:
  `sudo sh -c "echo ':WSLInterop:M::MZ::/init:PF' > /proc/sys/fs/binfmt_misc/register"`.
  Keeping whistle running (instead of letting it idle-stop and re-boot)
  avoids repeats during bootstrap.
  **Only true since 2026-08-10** that "post-rebuild whistle registers interop
  properly": it never did. WSL's systemd generator writes drop-ins for
  `systemd-binfmt.service` / `binfmt-support.service` that re-register the
  handler, and NixOS generates NEITHER unit unless `boot.binfmt` has
  registrations — so both sat inert and `/proc/sys/fs/binfmt_misc` had no
  `WSLInterop` at all, while `wsl.conf`'s `interop.enabled=true` implied
  otherwise. Every `.exe` call died with "cannot execute binary file". Fixed
  by `wsl.interop.register = true` (upstream defaults it off, assuming an
  existing registration — only valid on non-NixOS distros). Verified
  registering at boot 2026-08-11.
- **Shared network namespace with Debian (until retirement):** sshd
  listens on **2222** (Debian holds 22); syncthing runs on **GUI 8385 /
  sync 22001** (Debian owns 8384/22000 — two instances crash-collide
  otherwise); tailscale runs **userspace-networking** — two kernel-mode
  tailscaleds fight over routing table 52 and the 100.100.100.100
  MagicDNS route, and whistle's daemon winning BLACKHOLED Debian's DNS
  (repaired with `sudo systemctl restart tailscaled` on Debian).
  Configured in `hosts/whistle/configuration.nix` + the flake's whistle HM
  block. AFTER RETIREMENT: flip tailscale to kernel mode (real interface
  name); ports can stay.
- **whistle session activity tramples Debian's user@1000** (WSL#10205
  class): Debian's emacs/syncthing user services die whenever whistle
  boots/logs in. Self-serve heal on Debian:
  `sudo /usr/local/sbin/fix-user-session` (NOPASSWD, installed
  2026-07-22, like fix-wslinterop). Dies with Debian's retirement.
- **Seeded `~root/.ssh` needs `chown -R root:root`** after the tar copy —
  tar preserves scott's uid and ssh refuses a config file it doesn't own
  ("Bad owner or permissions").
- **User services need lingering.** WSL's session bootstrap doesn't
  reliably create logind sessions ("Failed to start the systemd user
  session"), so emacs/syncthing user units never start.
  `users.users.scott.linger = true` (in the whistle host config) boots the
  user manager unconditionally. A stale pre-rebuild `user@1000` from the
  image's `nixos` user can sit in `failed (Result: resources)` — cleared
  by the first `wsl --terminate whistle` + restart after the rebuild.
