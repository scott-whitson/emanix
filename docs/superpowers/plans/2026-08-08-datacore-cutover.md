# Datacore Debian → NixOS Cutover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Tasks 1–2 are repo work an agent can execute. Tasks 3–8 are operational and
> must be run by Scott at the machines** — they involve physical media, firmware,
> a router change, and `sudo` on live hosts. An agent's job on those is to
> prepare commands, verify output that is pasted back, and stop.

**Goal:** Move datacore off Debian 13 onto NixOS on the HP, preserving its identity so no other machine is reconfigured.

**Architecture:** Parallel build — the HP is installed and validated while the old box keeps serving. One identity flip (hostname + SSH host keys + Syncthing device ID), then headscale hands over separately. NixOS owns the substrate only; the 22 containers run unchanged as compose stacks from `~/projects/datacore-config`.

**Tech Stack:** NixOS 26.11, disko, agenix, Docker + compose stacks, Syncthing, backrest→restic→B2, headscale.

**Spec:** `docs/superpowers/specs/2026-08-05-datacore-nixos-design.md` (revised 2026-08-08). Read its Decisions section before starting — decisions 8 and 9 shape this plan, and decision 10 records why the compose stacks are NOT converted to native NixOS services here.

## Global Constraints

- **The old box is never modified destructively.** Data is copied, never moved. It stays powered-off-but-intact 2–4 weeks after cutover. Its disk is the last pre-migration copy — wipe only after the soak passes.
- **`/home/srv-data` is preserved verbatim** on the new box. Zero compose-file edits.
- **The HP inherits the OLD box's SSH host key** (`/etc/ssh/ssh_host_*`), and that same key must be datacore's agenix recipient. These cannot drift — see spec decision 8.
- **headscale stays on the old box through the main flip** and moves alone in Phase 2b — see spec decision 9.
- **Never add `Co-Authored-By` or tool-attribution trailers to commits.**
- All `.nix` files must pass `nixpkgs-fmt --check` before commit.
- Build check (used throughout): `nix build --no-link --print-out-paths .#nixosConfigurations.datacore.config.system.build.toplevel`

## File Structure

| File | Responsibility |
|---|---|
| `secrets/secrets.nix` | **Modify.** `datacore` recipient becomes the OLD box's host key |
| `secrets/openrouter-auth.age`, `secrets/ibkr-creds.age` | **Rekeyed** by agenix; not hand-edited |
| `hosts/datacore/configuration.nix` | **Modify.** Add `docker-compose` and `restic` — both already resolve via the docker/backrest wrappers, but kept on PATH for interactive use (the Task 8 restore test) at zero closure cost |
| `~/.ssh/datacore_host_ed25519{,.pub}` | **Delete.** The generated key from 2026-08-08; superseded by decision 8 |

---

## Task 1: Re-point the agenix recipient at the old box's host key

**Agent-executable.**

**Files:**
- Modify: `secrets/secrets.nix`
- Rekeyed: `secrets/openrouter-auth.age`, `secrets/ibkr-creds.age`
- Delete: `~/.ssh/datacore_host_ed25519`, `~/.ssh/datacore_host_ed25519.pub`

**Interfaces:**
- Produces: a `datacore` recipient in `secrets/secrets.nix` whose value equals the old box's `/etc/ssh/ssh_host_ed25519_key.pub`. Task 4 stages that same key on the USB, and the installer greps this file for it.

- [ ] **Step 1: Capture the old box's actual host key**

```bash
ssh datacore 'cat /etc/ssh/ssh_host_ed25519_key.pub'
```

Expected (verified 2026-08-08 — confirm it still matches before using it):

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHn7dUeQQeGMDAuQ8YJRxV2Nlo31biEtxpcHxawrBZ1J root@datacore
```

**If it differs, use what the command returns, not what is written here.** A host key can change if the machine was reinstalled.

- [ ] **Step 2: Back up the encrypted secrets before touching them**

```bash
cd ~/dotfiles
mkdir -p /tmp/agenix-backup
cp secrets/openrouter-auth.age secrets/ibkr-creds.age /tmp/agenix-backup/
ls -l /tmp/agenix-backup/
```

Rekeying rewrites these in place. If it goes wrong, restore from here.

- [ ] **Step 3: Replace the datacore recipient**

In `secrets/secrets.nix`, replace the whole `datacore = "...";` line and its comment block with:

```nix
  # datacore inherits the OLD Debian box's SSH host key at cutover (spec
  # decision 8): /etc/ssh/ssh_host_* are copied so peers never re-pin. The
  # agenix recipient must therefore BE that key — a host cannot inherit one
  # key and decrypt with another. A freshly generated key was briefly used
  # here on 2026-08-08 and was wrong for exactly that reason.
  datacore = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHn7dUeQQeGMDAuQ8YJRxV2Nlo31biEtxpcHxawrBZ1J root@datacore";
```

Leave every other recipient byte-identical, including rafik's stale `root@eminix` comment and whistle's `root@weasel`.

- [ ] **Step 4: Rekey**

`agenix` reads `secrets.nix` from the working directory, so this must run from `secrets/`:

```bash
cd ~/dotfiles/secrets
nix run github:ryantm/agenix -- -r -i ~/.ssh/id_ed25519
```

Expected: `rekeying ibkr-creds.age...` and `rekeying openrouter-auth.age...`

- [ ] **Step 5: Verify the rekey did what it should**

```bash
cd ~/dotfiles/secrets
grep -ac 'ssh-ed25519' openrouter-auth.age   # expect 5
grep -ac 'ssh-ed25519' ibkr-creds.age        # expect 2
nix run github:ryantm/agenix -- -d openrouter-auth.age -i ~/.ssh/id_ed25519 | wc -c
nix run github:ryantm/agenix -- -d ibkr-creds.age -i ~/.ssh/id_ed25519 | wc -c
```

Expected: 5 and 2 stanzas; both decrypt to non-trivial byte counts (242 and 49 as of 2026-08-08). **Do not print the plaintext.**

Then confirm no other key string changed:

```bash
cd ~/dotfiles
diff <(git show HEAD:secrets/secrets.nix | grep -oE '"ssh-ed25519 [^"]+"' | sort) \
     <(grep -oE '"ssh-ed25519 [^"]+"' secrets/secrets.nix | sort)
```

Expected: exactly one `<` line (the generated key leaving) and one `>` line (the old box's key arriving). Any other difference means a recipient was disturbed.

- [ ] **Step 6: Delete the superseded generated key**

```bash
rm -f ~/.ssh/datacore_host_ed25519 ~/.ssh/datacore_host_ed25519.pub
ls ~/.ssh/datacore_host_ed25519* 2>&1
```

Expected: "No such file or directory". Leaving it invites someone staging the wrong key on the USB later.

- [ ] **Step 7: Build and commit**

```bash
cd ~/dotfiles
nixpkgs-fmt secrets/secrets.nix
for h in rafik whistle datacore; do
  nix build --no-link --print-out-paths .#nixosConfigurations.$h.config.system.build.toplevel
done
git add -A
git commit -m "fix(secrets): datacore's agenix recipient is the OLD box's host key

Spec decision 8. The migration copies /etc/ssh/ssh_host_* from the Debian box
so no peer re-pins anything, which means the agenix recipient must be that same
key. A freshly generated key was used here on 2026-08-08 and would have failed
to decrypt on first boot, since the installer overwrites the host key with the
inherited one. The generated pair is deleted so it cannot be staged by mistake."
git push origin main
```

---

## Task 2: Give datacore docker compose and restic

**Agent-executable.**

**Files:**
- Modify: `hosts/datacore/configuration.nix`

**Interfaces:**
- Produces: `docker compose` and `restic` on datacore's PATH. Task 5 brings up stacks with `docker compose up -d`; backrest shells out to `restic`.

**Why this task exists:** `~/projects/datacore-config` invokes `docker compose` at 16 call sites, and backrest shells out to restic. Both already resolve without this task — `virtualisation.docker.package`'s wrapper sets `DOCKER_CLI_PLUGIN_DIRS` so `docker compose` is already on the plugin path, and `pkgs.backrest`'s wrapper sets `BACKREST_RESTIC_COMMAND` to a store restic path. This task exists so `docker-compose` and `restic` are also reachable as **plain interactive commands** on datacore's PATH — needed for the Task 8 restore test — at zero closure cost, since both store paths are already pulled in by the mechanisms above.

- [ ] **Step 1: Confirm the gap is real before fixing it**

```bash
cd ~/dotfiles
nix eval .#nixosConfigurations.datacore.config.environment.systemPackages \
  --apply 'ps: map (p: p.name or "?") (builtins.filter (p: builtins.match ".*(compose|restic).*" (p.name or "") != null) ps)'
```

Expected: `[ ]` — neither present.

- [ ] **Step 2: Add both packages**

In `hosts/datacore/configuration.nix`, insert before the `system.stateVersion` line:

```nix
  # `docker compose` and `restic` already work WITHOUT these packages:
  # - virtualisation.docker.package's wrapper sets DOCKER_CLI_PLUGIN_DIRS, so
  #   `docker compose` already resolves.
  # - pkgs.backrest's wrapper sets BACKREST_RESTIC_COMMAND to a store restic
  #   path, so backrest already finds restic on its own.
  # Kept anyway: zero closure growth (both paths are already pulled in above),
  # and an interactive `restic` on PATH is needed for the Task 8 restore test.
  # Caveat: this list does NOT reach backrest.service — its unit PATH is only
  # coreutils/findutils/gnugrep/gnused/systemd, not /run/current-system/sw/bin
  # — so a command hook needs systemd.services.backrest.path, not this.
  environment.systemPackages = with pkgs; [
    docker-compose
    restic
  ];
```

- [ ] **Step 3: Verify both land**

```bash
nixpkgs-fmt hosts/datacore/configuration.nix
nix eval .#nixosConfigurations.datacore.config.environment.systemPackages \
  --apply 'ps: map (p: p.name or "?") (builtins.filter (p: builtins.match ".*(compose|restic).*" (p.name or "") != null) ps)'
```

Expected: a list containing a `docker-compose-*` and a `restic-*` entry.

- [ ] **Step 4: Build and commit**

```bash
nix build --no-link --print-out-paths .#nixosConfigurations.datacore.config.system.build.toplevel
git add -A
git commit -m "feat(datacore): add docker compose and restic

The 22 workloads are compose stacks invoked with \`docker compose\` (16 call
sites in datacore-config), and backrest shells out to restic — the Debian box
has it at /usr/bin/restic. virtualisation.docker from the server role supplies
neither, so a fresh install would have come up with no way to start a single
stack or run a single backup."
git push origin main
```

This task actually landed as commit `80ddd1d`, carrying the commit message
above verbatim. A later review (finding 1) established that message's "supplies
neither... no way to start" framing is wrong — `docker compose` and `restic`
both already resolved via wrapper mechanisms before this task, and what it
really achieved was putting both on PATH as plain interactive commands, at
zero closure cost, for the Task 8 restore test. That correction is not
retroactively rewritten into the shipped git history; it lives here and in the
comment `hosts/datacore/configuration.nix` now carries.

- [ ] **Step 5: Note why `docker compose` was never actually at risk**

`docker compose` resolves without `environment.systemPackages` at all:
`virtualisation.docker.package` is a wrapper that sets `DOCKER_CLI_PLUGIN_DIRS`
to a `docker-compose-*/libexec/docker/cli-plugins` path, so the subcommand is
already on the plugin path before this task's packages are even considered.
**Task 4 step 7's `docker compose version` check is still worth running** as a
live confirmation on the real machine — it just isn't guarding against a real
gap, and there is no hyphenated `docker-compose` fallback to reach for if it
somehow fails.

---

## Task 3: Pre-flight — Scott only

**Operational. Nothing here is destructive; all of it is measurement and one commit.**

- [ ] **Step 1: Commit the datacore-config working tree**

```bash
ssh datacore 'cd ~/projects/datacore-config && git status --short'
```

It had **12 uncommitted files** on 2026-08-08. This migration treats that repo
as the source of truth for every stack — anything uncommitted is silently left
behind. Review, commit and push before continuing.

- [ ] **Step 2: Confirm the HP boots and has the disk**

Power on the HP. From a live USB or its existing install:

```bash
lsblk -dno NAME,SIZE
df -h
```

Expected: a ~1 TB device. **Required: ≥ 400 GB usable.** Its state has not been
verified since 2026-07-16.

- [ ] **Step 3: Re-measure the payload**

```bash
ssh datacore 'sudo du -sh /home/srv-data /var/lib/docker; du -sh ~scott'
```

It was 326 G + 13 G + ~16 G on 2026-08-08 and grows ~9 G/day. Recompute the
total and confirm it still fits with headroom.

- [ ] **Step 4: Record the identity you are about to preserve**

```bash
ssh datacore 'cat /etc/ssh/ssh_host_ed25519_key.pub; \
  sudo sha256sum /home/scott/.local/state/syncthing/cert.pem /home/scott/.local/state/syncthing/key.pem'
```

Keep this output. Task 6 copies these files; these checksums prove the copy
landed intact.

---

## Task 4: Phase 1 — install NixOS on the HP

**Operational. Destructive to the HP only.**

- [ ] **Step 1: Stage the Ventoy USB**

`sudo cat` over a plain `ssh` has no tty for sudo to prompt on. If this account
is not NOPASSWD, the command can still exit and leave the redirected file
**empty** — a failure that only surfaces much later, at the installer's
fingerprint preflight, after the ISO is already booted. Check first:

```bash
ssh datacore 'sudo -n true' && echo "NOPASSWD confirmed" || echo "needs a tty — use ssh -t below"
```

If it needs a tty, use `ssh -t` so sudo can prompt — note `-t` merges the
remote pty's stdout/stderr onto one stream, so a password prompt can land
inside the redirected file too, which is why the size check below is not
optional:

```bash
V=/run/media/$USER/Ventoy            # adjust to your mount
git clone ~/dotfiles "$V/dotfiles"
mkdir -p "$V/datacore-keys"
ssh -t datacore 'sudo cat /etc/ssh/ssh_host_ed25519_key'     > "$V/datacore-keys/datacore_host_ed25519"
ssh -t datacore 'sudo cat /etc/ssh/ssh_host_ed25519_key.pub' > "$V/datacore-keys/datacore_host_ed25519.pub"
chmod 600 "$V/datacore-keys/datacore_host_ed25519"
wc -c "$V/datacore-keys/datacore_host_ed25519" "$V/datacore-keys/datacore_host_ed25519.pub"
```

Expected: both files non-trivial (an ed25519 private key is a few hundred
bytes). Near-zero means the sudo prompt was not answered cleanly — do not
proceed with an empty or contaminated key staged.

This is the **old box's** key — spec decision 8. The installer looks for
`../datacore-keys/` beside the repo and matches its fingerprint against the
`datacore` recipient in `secrets/secrets.nix`, so a mismatch fails loudly.

- [ ] **Step 2: Firmware**

Disable Secure Boot and confirm UEFI. systemd-boot is unsigned — with Secure
Boot on, the install succeeds and the machine will not boot. The installer warns
but cannot change firmware.

- [ ] **Step 3: Install**

Boot the NixOS minimal ISO from Ventoy, get networking, then:

```bash
sudo bash /run/media/*/Ventoy/dotfiles/installer/fresh-eminix-install datacore
```

The `datacore` argument is why Task 2 of the convergence parameterized this
script. Confirm the disk it names is the HP's, not something else.

- [ ] **Step 4: First boot, join the tailnet under a temporary name**

The old box still owns `datacore`, and its headscale is still serving:

```bash
sudo tailscale up --login-server https://headscale.stonewallmapletree.com --hostname datacore-new
tailscale status | head -3
```

- [ ] **Step 5: Verify agenix decrypted**

```bash
ls -l /run/agenix/openrouter-auth
systemctl status agenix --no-pager | head -5
```

Expected: the secret exists, owned by `scott`. **If it failed, stop** — it means
the inherited host key and the recipient in `secrets.nix` disagree, which is
exactly what Task 1 exists to prevent. Do not proceed to data sync.

- [ ] **Step 6: Run first-boot setup, then clone the two remaining repos**

```bash
eminix-firstboot
```

It joins the tailnet (prompts for a preauthkey — generate one on the OLD box
with `docker exec headscale headscale preauthkeys create --user scott
--expiration 1h`), prints the Syncthing device ID, and clones the flake to
**`~/dotfiles`**. Safe to re-run.

The old box carries **three** repos, and firstboot only creates the first:

| Path | Purpose |
|---|---|
| `~/dotfiles` | The flake checkout. `scott.dotfiles.path` points here, and `liveElisp` symlinks `~/.config/emacs` into it — if it is missing, Emacs' config is a dangling link |
| `~/projects/dotfiles` | **The git mirror.** rafik's `origin` is literally `scott@datacore:~/projects/dotfiles`. Without this, rafik cannot pull at all |
| `~/projects/datacore-config` | The compose stacks |

So clone the other two:

```bash
git clone git@github.com:scott-whitson/dotfiles.git ~/projects/dotfiles
git clone git@github.com:scott-whitson/datacore-config.git ~/projects/datacore-config
```

Both repos are private, so this needs an SSH key with GitHub access.
`~/.ssh` is deliberately excluded from the Task 5 rsync, so it is **not** there
yet — restore `~/.ssh/id_ed25519` from the old box first, or add a deploy key.
`eminix-firstboot` already prints a fallback message if its own clone fails for
this reason.

- [ ] **Step 7: Verify docker and compose actually work**

```bash
docker run --rm hello-world
docker compose version
restic version
```

All three must succeed. `docker compose version` resolves via the docker
wrapper's plugin dir (see Task 2 step 5) — this is a live confirmation, not a
gap-check; it should not fail.

- [ ] **Step 8: Wipe the staged host key off the USB**

`datacore-keys/datacore_host_ed25519` is the old box's **private** host key,
staged in clear on a FAT filesystem — the `chmod 600` in step 1 is a no-op
there, FAT has no Unix permission bits — and that key is now an agenix
recipient's private key. Remove it as soon as the install no longer needs it:

```bash
rm -rf "$V/datacore-keys"
ls "$V" 2>&1
```

---

## Task 5: Phase 1 — warm data sync and stack validation

**Operational. Read-only against the old box.**

- [ ] **Step 1: Warm rsync the data**

Runs over the tailnet — the two boxes connect directly, so this is LAN speed.

**Every rsync below needs `--numeric-ids`.** Without it, rsync maps ownership
by *name*, and Debian and NixOS disagree on system UIDs — container-internal
UIDs under `/var/lib/docker` (Immich's postgres data included) and under
`/home/srv-data` would land owned by the wrong user on the HP.

**Every rsync pulling a root-owned path also needs `--rsync-path="sudo rsync"`.**
`sudo` on the local side elevates only the *writing* half; the reading half runs
on the old box as `scott`, who cannot read what it is being asked to send.
Verified on the live box 2026-08-08:

- `/var/lib/docker` is `drwx--x---  root root` — scott cannot even traverse it.
- `/home/srv-data` is scott-owned at the top, but **17 paths beneath it are
  unreadable as scott**, `/home/srv-data/stacks-state/immich/postgres` among
  them. That is Immich's entire database. Without the flag rsync copies the
  tree, reports those as errors amid thousands of lines of progress output,
  and exits non-zero — leaving a migration that looks done and has no Immich DB.
- `/etc/ssh/ssh_host_ed25519_key` (Task 6 step 3) is `0600 root root`.

`sudo -n true` succeeds over ssh on the old box, so `--rsync-path="sudo rsync"`
needs no tty. **Check the exit status of each rsync** — a non-zero exit here
means files were skipped, not that a cosmetic warning was printed.

**Order matters here — compare first, stop second, in exactly this order.**
First, while both daemons are still up, compare storage drivers on both
boxes — the HP's root is btrfs, and a storage-driver mismatch orphans every
layer you are about to copy:

```bash
ssh datacore 'sudo docker info | grep "Storage Driver"'
sudo docker info | grep "Storage Driver"
```

**Then stop docker on the HP before the `/var/lib/docker` line** — that path
is a live daemon's state directory on this machine once anything has touched
it, and rsyncing into a running daemon's state risks a corrupt copy. Stop
**both** the socket and the service, and in that order: `docker.service`
`Requires=docker.socket` but not the reverse, and `docker.socket` is
`wantedBy=sockets.target` independently of the service, so stopping the
service alone leaves the socket listening — and the next `docker` command
anyone runs (including a re-run of the storage-driver check above) would
socket-activate the daemon right back up before the rsync ever starts:

```bash
sudo systemctl stop docker.socket docker.service
```

Do not run any further `docker ...` command on the HP until after the rsync
below completes — each one would revive the daemon via socket activation.
Then sync:

```bash
sudo rsync -aHAX --numeric-ids --rsync-path="sudo rsync" --info=progress2 \
  scott@datacore:/home/srv-data/ /home/srv-data/
echo "srv-data rsync exit: $?"
sudo rsync -aHAX --numeric-ids --rsync-path="sudo rsync" --info=progress2 \
  scott@datacore:/var/lib/docker/ /var/lib/docker/
echo "docker rsync exit: $?"
# This one needs no elevation on either side: scott's home, read and written
# as scott. Adding sudo here would land the files owned by root.
rsync -aHAX --numeric-ids --info=progress2 scott@datacore:/home/scott/ /home/scott/ \
  --exclude '.ssh/' --exclude '.local/state/syncthing/'
```

`~/.ssh` and the syncthing state are excluded deliberately: identity files are
copied at the flip (Task 6), not now, so the two boxes never both hold a live
device identity.

- [ ] **Step 2: Bring up every stack EXCEPT headscale**

```bash
cd ~/projects/datacore-config
for s in immich media hindsight control-center bootstrap-portal; do
  (cd stacks/$s && docker compose up -d)
done
docker ps --format '{{.Names}}\t{{.Status}}'
```

**Do not start the headscale stack.** A second control plane running against
copied state would fight the live one. It moves in Phase 2b.

- [ ] **Step 3: Validate against the copied data**

- Immich: web UI loads and the library shows photos
- Jellyfin: a title plays end to end **using hardware transcoding, not just
  direct play**. The old box is an Intel i5-8250U (QSV); the HP is a Ryzen
  (amdgpu), and datacore's NixOS config evaluates `hardware.graphics.enable =
  false`. Confirm `/dev/dri/renderD128` exists (`ls /dev/dri/`) and that
  Jellyfin's transcoding setting is not still pointed at QSV (Dashboard →
  Playback in the admin UI) before trusting a transcoded play — "stacks run
  unchanged" does not survive a CPU-vendor change
- hindsight: app reaches its database
- Uptime-Kuma / Beszel: monitors load their history

Iterate here over as many evenings as needed — nobody depends on this box yet,
and this is the only phase where mistakes are free.

- [ ] **Step 4: Re-run the warm sync before the flip day**

Repeat step 1. Each pass shortens the Phase 2 delta window.

---

## Task 6: Phase 2 — the identity flip

**Operational. Target < 1 hour. This is the window where datacore is down.**

- [ ] **Step 1: Quiesce both boxes, but leave headscale running on the old box**

```bash
# on the OLD box
cd ~/projects/datacore-config
for s in immich media hindsight control-center bootstrap-portal; do
  (cd stacks/$s && docker compose down)
done
sudo systemctl stop syncthing backrest
docker ps --format '{{.Names}}'
```

Expected remaining: only the headscale stack's containers. sshd stays up.
**headscale must keep running** — step 5 needs a control plane.

```bash
# on the HP — Task 5 step 2 already brought these stacks up against warm
# data; stop them and the docker daemon (socket AND service, in that order —
# see Task 5 step 1) so step 2's delta rsync into /var/lib/docker isn't
# writing under a live daemon. Run no `docker ...` command after this until
# the rsync below completes — it would socket-activate the daemon back up.
cd ~/projects/datacore-config
for s in immich media hindsight control-center bootstrap-portal; do
  (cd stacks/$s && docker compose down)
done
sudo systemctl stop docker.socket docker.service
```

- [ ] **Step 2: Delta rsync**

Same commands as Task 5 step 1 — **including `--numeric-ids` and
`--rsync-path="sudo rsync"`**, and the same exit-status check. Only that day's
changes move; minutes, not hours.

- [ ] **Step 3: Copy the identity files**

```bash
# SSH host keys — makes peers' known_hosts and the git mirror hop keep working.
# --rsync-path="sudo rsync": the private keys are 0600 root:root on the old box,
# so the sending side must be root too (see Task 5 step 1).
sudo rsync -a --rsync-path="sudo rsync" scott@datacore:/etc/ssh/ssh_host_* /etc/ssh/
sudo systemctl restart sshd

# Syncthing device identity — same device ID, so peers reconnect with no re-pairing
sudo rsync -a scott@datacore:/home/scott/.local/state/syncthing/ \
  /home/scott/.local/state/syncthing/
sudo chown -R scott:users /home/scott/.local/state/syncthing
```

Verify against the checksums recorded in Task 3 step 4:

```bash
sha256sum /home/scott/.local/state/syncthing/cert.pem /home/scott/.local/state/syncthing/key.pem
```

- [ ] **Step 4: Check backrest's config.json for command hooks**

`config.json` arrived with the rest of `/home/scott` in the rsyncs above. Any
command hooks in it run inside `backrest.service`, whose generated unit PATH
is only coreutils/findutils/gnugrep/gnused/systemd — `/run/current-system/sw/bin`
is not in it (see the comment above `environment.systemPackages` in
`hosts/datacore/configuration.nix`). A bare `docker` or `restic` in a hook
will not resolve there even though it works fine at an interactive shell.

```bash
grep -B1 -A2 -i '"command"' /home/scott/.config/backrest/config.json
```

If any hooks exist, add to `hosts/datacore/configuration.nix`:

```nix
systemd.services.backrest.path = with pkgs; [ docker restic ];  # match what the hook actually calls
```

then `nixpkgs-fmt`, build, commit, and `sudo nixos-rebuild switch --flake .#datacore`
before step 6 starts backrest — otherwise the hook silently fails the first
time it fires.

- [ ] **Step 5: Flip the identity — while the old headscale still serves**

```bash
# OLD box: stand down. Bootable, but no longer claiming the name.
sudo tailscale logout
sudo hostnamectl set-hostname datacore-old

# HP: take the name
sudo hostnamectl set-hostname datacore
sudo tailscale up --login-server https://headscale.stonewallmapletree.com --hostname datacore
```

Then rename the node in headscale so MagicDNS follows — it is still running on
the old box, so this works:

```bash
# on the OLD box, where headscale still runs
docker exec headscale headscale nodes list
docker exec headscale headscale nodes rename -i <id-of-datacore-new> datacore --force
```

- [ ] **Step 6: Start services on the HP**

```bash
sudo systemctl start docker syncthing backrest
cd ~/projects/datacore-config
for s in immich media hindsight control-center bootstrap-portal; do
  (cd stacks/$s && docker compose up -d)
done
```

- [ ] **Step 7: Verify the ring**

- Phone syncs a new photo to Immich
- `ssh datacore hostname` from rafik returns `datacore` **with no host-key warning** — this is the proof that decision 8 worked
- Syncthing peers reconnect on their own (same device ID); check rafik and whistle
- `cd ~/dotfiles && git fetch origin` on rafik succeeds via the mirror hop
- A manual backrest run to B2 completes

**If the SSH check warns about a changed host key, stop and investigate** — it
means the inherited keys did not land, and every peer will need re-pinning.

---

## Task 7: Phase 2b — hand over headscale

**Operational. Its own window, only after Task 6 has verified.**

- [ ] **Step 1: Stop headscale on the old box**

```bash
# on the OLD box
cd ~/projects/datacore-config/stacks/headscale && docker compose down
```

The tailnet now has no control plane. Existing nodes ride cached peer state —
connectivity continues; new registrations and renames do not.

- [ ] **Step 2: Sync headscale's state**

```bash
# --rsync-path/--numeric-ids for the same reasons as Task 5 step 1: 7 paths
# under stacks-state/headscale are unreadable as scott (verified 2026-08-08),
# and headscale's sqlite DB is the whole point of this step.
sudo rsync -aHAX --numeric-ids --rsync-path="sudo rsync" \
  scott@datacore-old:/home/srv-data/stacks-state/headscale/ \
  /home/srv-data/stacks-state/headscale/
echo "headscale state rsync exit: $?"
# scott's own repo checkout — no elevation on either side.
rsync -aHAX scott@datacore-old:~/projects/datacore-config/stacks/headscale/config/ \
  ~/projects/datacore-config/stacks/headscale/config/
```

Small — seconds. Reach the old box by its new name `datacore-old`, or by its
tailnet IP if DNS is unhappy with the control plane down.

- [ ] **Step 3: Start headscale on the HP and wait for it to actually serve**

```bash
cd ~/projects/datacore-config/stacks/headscale && docker compose up -d
docker compose logs -f headscale     # watch until it reports listening
docker exec headscale headscale nodes list
```

Do not touch anything else until `nodes list` returns the fleet.

- [ ] **Step 4: Re-point the router's port forward**

In the router admin UI, change the 80/443 forward from the old box's LAN IP to
the HP's. **This is manual and nothing in either repo can do it.** Find the HP's
LAN IP with `ip -4 addr show | grep 192.168`.

- [ ] **Step 5: Verify from a third machine**

From rafik or whistle — not from datacore itself:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://headscale.stonewallmapletree.com
tailscale status
```

Expected: an HTTP response, and a sane peer list. Then prove the thing the old
control plane could no longer do — register something new:

```bash
docker exec headscale headscale preauthkeys create --user scott --expiration 1h
```

---

## Task 8: Phase 3 — soak, then retire

**Operational. Spread over a week.**

- [ ] **Step 1: Define done**

All of these, sustained for a week:

- 22 containers healthy
- Syncthing in sync fleet-wide (rafik, whistle, datacore agree)
- One full backrest → B2 cycle **plus a spot restore test** — a backup you have
  not restored from is a hypothesis
- Mirror hop proven: rafik pulls via `scott@datacore:~/projects/dotfiles`
- whistle → datacore over ssh and tailscale
- headscale has served at least one new registration

- [ ] **Step 2: Update the docs to match reality**

```bash
cd ~/dotfiles
```

- `docs/manual/06-architecture.md` — remove datacore's "not yet cut over"
  Status row and the paragraph explaining it; restore the plain "every host is
  NixOS" claim, which becomes true at this point
- `docs/ioshi/README.md` — the "Not yet written" section names this cutover;
  replace it with a link to the runbook
- `docs/ioshi/standalone-hm.md` — its banner says datacore is "still the last
  standalone-HM node"; that ends here. Move it to `docs/ioshi/history/`
- `docs/superpowers/specs/2026-08-05-datacore-nixos-design.md` — append an
  as-built correction if anything diverged, rather than editing the body

Commit and push.

- [ ] **Step 3: Retire the old laptop**

Only after step 1 passes. Its disk holds the last pre-migration copy, so this is
the true point of no return:

```bash
# from a live USB on the old laptop
sudo wipefs -a /dev/nvme0n1
```

- [ ] **Step 4: Clean up the tailnet and secrets**

```bash
# remove the stood-down node
docker exec headscale headscale nodes list
docker exec headscale headscale nodes delete -i <id-of-datacore-old> --force
```

Then consider dropping the now-meaningless `zordold` recipient from
`secrets/secrets.nix` and rekeying — that machine is the HP, and it is datacore
now. Rekeying needs a current recipient's private key (`~/.ssh/id_ed25519`).

---

## Self-Review Notes

**Spec coverage.** Decision 8 → Task 1 and Task 4 step 1. Decision 9 → Task 7.
Pre-flight section → Task 3. Phase 1 → Tasks 4–5. Phase 2 → Task 6. Phase 2b →
Task 7. Phase 3 → Task 8. Rollback is not a task because it is a *reaction*; the
spec's Rollback section governs, and each operational task names the point past
which its rollback changes.

**One gap the spec did not list**, found while writing this plan and added as
Task 2: datacore's NixOS config had neither `docker-compose` nor `restic` as
plain interactive commands. **Correction from final review:** this was never a
"nothing starts" gap — `docker compose` and `restic` both already resolve
without those packages, via the docker wrapper's plugin-dir mechanism and
backrest's wrapper respectively (see the comment in
`hosts/datacore/configuration.nix`). Task 2's real value is putting both on
PATH for interactive use — needed for the Task 8 restore test — at zero
closure cost.

**Correction from final review.** `docker compose version` was never actually
at risk: the docker wrapper's `DOCKER_CLI_PLUGIN_DIRS` resolves it without
`environment.systemPackages`. Task 4 step 7 still runs the check on the real
machine as confirmation; there is no fallback needed, and none exists.
