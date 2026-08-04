# weasel → whistle Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the NixOS-WSL work host from `weasel` to `whistle` across every layer — dotfiles repo, live Linux identity, tailnet, syncthing labels, peer configs, and the WSL distro registration on Windows — with no functional change anywhere.

**Architecture:** Four layers renamed in dependency order. The repo change lands and is pushed first (fully reversible, nothing disrupted). Then the new system closure is activated on this box, which stages `/etc/wsl.conf` without changing the live hostname. Then the network identities (tailnet, syncthing) and the one peer that resolves this host by name (eminix's ssh config). Finally the Windows registry edit, which requires `wsl --shutdown` and therefore **ends the session that is executing this plan** — so it is last, manual, and everything before it must be pushed.

**Tech Stack:** Nix flakes (NixOS-WSL), agenix, Tailscale, Syncthing REST API, PowerShell/Windows registry, Windows Terminal, GlazeWM.

**Spec:** `docs/superpowers/specs/2026-08-04-whistle-rename-design.md`

## Execution status (2026-08-04)

- **Tasks 1–5: COMPLETE.** Repo renamed and pushed (`f047955`, `0e0a564`);
  closure `nixos-system-whistle` activated (agenix decrypted clean, zero
  failed units, both DB containers untouched); tailnet node renamed
  (`whistle` @ 100.64.0.10); both syncthing labels renamed, datacore still
  connected; eminix `~/.ssh/config` now `Host whistle` (backup left at
  `~/.ssh/config.bak-prewhistle`), verified connecting on 2222.
- **Task 2 Step 10: DEFERRED** — datacore's clone diverged, see the note there.
- **Task 6: PENDING, manual.** Scott runs the PowerShell block; it ends the
  session that was executing this plan. `/etc/wsl.conf` is already staged with
  `hostname=whistle`, so the live hostname flips on that restart.
- **Task 7: PENDING** — run after the restart, in a fresh session.

## Global Constraints

- The new name is exactly `whistle`, lowercase, everywhere. Prose capitalization (`Whistle` at sentence start) is fine; identifiers and hostnames are lowercase.
- **Never regenerate the SSH host key.** The pubkey strings in `secrets/secrets.nix` — including the literal `root@weasel` comment inside `whistle`'s key — stay byte-identical. No agenix rekey is performed. If any `.age` file stops decrypting, stop and roll back.
- Ports do not change: sshd `2222`, syncthing GUI `8385`, syncthing sync `22001`.
- Tailnet IP stays `100.64.0.10`. All syncthing device IDs stay unchanged (this host is `BWI6SYR-ASNGFB4-AM7XL7S-MHOJ2PW-LD6ADBF-FK5H6AU-KIQ5QMJ-DPBHXQN`).
- Dated docs under `docs/superpowers/` keep their filenames **and prose**. Only the 4 weasel-titled ones get a one-line header note. Do not blanket-sed that directory.
- Build as `scott`, activate as `root` (`sudo nixos-rebuild` fails on libgit2 repo ownership). Never `nix build` another host's toplevel on this box — eminix's closure source-compiles and hard-crashes WSL.
- **No `Co-Authored-By` trailers in commits.** Standing rule.
- Tasks 1–5 must be committed and pushed before Task 6 runs.
- This plan's "tests" are verification commands with exact expected output. There is no unit-test suite here; a step is done when its command prints what the plan says it will.

Set this once per shell for the out-link steps:

```bash
SCRATCH=/tmp/claude-1000/-home-scott/d6ad2e25-a06d-433d-87b5-92b94133cac3/scratchpad
```

---

### Task 1: Rename the Nix layer

**Files:**
- Move: `hosts/weasel/` → `hosts/whistle/`
- Modify: `flake.nix` (lines ~71, ~131, ~136, ~169)
- Modify: `hosts/whistle/configuration.nix` (lines 4, 19–31, 40–45)
- Modify: `secrets/secrets.nix` (lines 7, 11)
- Modify: `ioshi/i-intelligence/zsh.nix:76`, `ioshi/i-intelligence/emacs/lisp/scott-launcher.el:3`, `ioshi/i-intelligence/ghostty.nix:14`, `ioshi/i-intelligence/standalone.nix:5`, `ioshi/i-intelligence/packages.nix:67`

**Interfaces:**
- Consumes: nothing.
- Produces: the flake attribute `nixosConfigurations.whistle` (used by Task 3's build), and `config.system.name = "whistle"` (checked by Task 3's generation-label verification).

- [ ] **Step 1: Capture the pre-state baseline**

```bash
cd ~/dotfiles
git status --porcelain
nix eval .#nixosConfigurations.weasel.config.system.build.toplevel.drvPath --raw; echo
```

Expected: a `/nix/store/*.drv` path prints. `git status` may show unrelated modified files (e.g. `base/claude/.claude/settings.json`) — leave them alone and never `git add -A` in this plan.

- [ ] **Step 2: Move the host directory**

```bash
cd ~/dotfiles && git mv hosts/weasel hosts/whistle
```

- [ ] **Step 3: Edit `flake.nix`**

Line ~71, inside `hmModule`:

```nix
            # eminix instances run the system-owned EWM Emacs. mkDefault so a
            # non-EWM NixOS host (whistle) can opt out while reusing hmModule.
```

Lines ~128–136, the host block header and attribute:

```nix
        # NixOS-WSL on the work laptop — replaces the Debian WSL + scott@work
        # standalone HM pair at cutover (spec 2026-07-21; the host was named
        # weasel until 2026-08-04). Not an eminix instance (no EWM/hardware
        # layer), so composed here, not via mkHost.
        whistle = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = sharedSpecialArgs;
          modules = [
            nixos-wsl.nixosModules.default
            ./hosts/whistle/configuration.nix
```

Line ~169, in `homeConfigurations`:

```nix
        # datacore is the last standalone-HM node (Debian). The work-WSL's
        # scott@work retired 2026-08-04 with the Debian distro — whistle
        # (nixosConfigurations) replaced the pair.
```

- [ ] **Step 4: Edit `hosts/whistle/configuration.nix`**

Line 4:

```nix
  # whistle — NixOS-WSL work distro (design spec 2026-07-21, named weasel
  # until the 2026-08-04 rename).
```

Lines 19–31 — keep `networking.hostName = ""` and its comment exactly as they are, change only the `wslConf` hostname, and add `system.name` immediately after:

```nix
  networking.hostName = "";

  # networking.hostName must stay empty (above), which leaves the generation
  # label reading "unnamed" — system.name restores a real label without
  # touching the hostname WSL bootstraps against.
  system.name = "whistle";

  wsl = {
    enable = true;
    defaultUser = "scott";
    wslConf = {
      # Carried over from the hand-tuned Debian /etc/wsl.conf (2026-05-13
      # plan9 tuning): metadata mounts + no Windows PATH pollution.
      automount.options = "metadata,uid=1000,gid=1000,umask=022,fmask=11,case=off,msize=262144";
      interop.appendWindowsPath = false;
      network.hostname = "whistle";
    };
  };
```

Lines ~40–45:

```nix
  # Debian retired 2026-08-04 — whistle is the only distro, so kernel-mode
  # WireGuard is safe again (during coexistence, two kernel tailscaleds
  # fought over routing table 52 and blackholed Debian's DNS; see
  # docs/ioshi/whistle.md gotchas for the history). sshd stays on 2222 and
  # syncthing on 8385/22001 — nothing depends on the old numbers and the
  # muscle memory/config (eminix ssh config, datacore) already points here.
```

- [ ] **Step 5: Edit `secrets/secrets.nix`**

Rename the binding and its use. **The quoted key string does not change** — `root@weasel` is the real comment on the still-current host key:

```nix
  whistle = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINp8VpIPlKLxcfPh1jvPc+LnFOnyQhTyxMulwQbTg2xA root@weasel";
```

```nix
  "openrouter-auth.age".publicKeys = [ eminix zordold whistle scott ];
```

- [ ] **Step 6: Edit the 5 incidental `ioshi/` strings**

`ioshi/i-intelligence/zsh.nix:76` — user-facing, must be correct:

```nix
            echo "    wsl --terminate whistle   (from PowerShell, then reopen)" >&2
```

`ioshi/i-intelligence/emacs/lisp/scott-launcher.el:3`:

```elisp
;; The launcher half of EWM's s-d, portable to non-EWM machines (whistle).
```

`ioshi/i-intelligence/ghostty.nix:14`:

```nix
    description = "Install ghostty + its managed config. Defaults to the gui flag; whistle (gui=false) sets it true — WSLg renders it like any Wayland app.";
```

`ioshi/i-intelligence/standalone.nix:5`:

```nix
  # package — non-EWM machines (foreign-distro nodes AND whistle/NixOS-WSL)
```

`ioshi/i-intelligence/packages.nix:67`:

```nix
  # ghostty for non-gui hosts that opt in (whistle/WSLg). gui hosts already
```

- [ ] **Step 7: Verify no stale refs remain in the Nix layer**

```bash
cd ~/dotfiles && grep -rn -i weasel flake.nix hosts/ secrets/ ioshi/
```

Expected: **exactly two lines** — the `root@weasel` key string in `secrets/secrets.nix:7` and the "named weasel until 2026-08-04" history comments. Anything else is a miss; fix it before continuing.

- [ ] **Step 8: Verify the old flake attribute is gone**

```bash
cd ~/dotfiles && nix eval .#nixosConfigurations.weasel.config.system.name --raw
```

Expected: FAIL — `error: attribute 'weasel' missing`.

- [ ] **Step 9: Verify the new attribute evaluates**

```bash
cd ~/dotfiles && nix eval .#nixosConfigurations.whistle.config.system.name --raw; echo
```

Expected: `whistle`

- [ ] **Step 10: Build the new toplevel**

```bash
cd ~/dotfiles && nix build .#nixosConfigurations.whistle.config.system.build.toplevel --out-link "$SCRATCH/whistle-toplevel"
```

Expected: succeeds, no source compiles of note. If it starts building `bitwarden-desktop` or `ewm-core`, **abort immediately** (`Ctrl-C`) — that means an eminix path leaked into this host and it will OOM the VM.

- [ ] **Step 11: Prove the diff is only the intended one**

```bash
grep hostname "$SCRATCH/whistle-toplevel/etc/wsl.conf"
nix store diff-closures /run/current-system "$SCRATCH/whistle-toplevel"
```

Expected: `hostname=whistle`, and `diff-closures` reports **no package version changes** (empty output, or only the `etc-wsl.conf` / system-path store paths differing). Any package version bump means something other than the rename changed — investigate before activating.

- [ ] **Step 12: Commit**

```bash
cd ~/dotfiles && git add flake.nix hosts/ secrets/secrets.nix ioshi/ && git commit -m 'refactor(host): rename weasel → whistle (nix layer)

Also sets system.name so the generation label stops reading "unnamed".
Host SSH key is unchanged, so secrets/secrets.nix keeps the literal
root@weasel key comment and no agenix rekey is needed.'
```

---

### Task 2: Rename the docs layer, push, and sync datacore's clone

**Files:**
- Move: `docs/ioshi/weasel.md` → `docs/ioshi/whistle.md` (rewrite all 59 refs)
- Modify: `docs/ioshi/standalone-hm.md:10`
- Modify (header note only): `docs/superpowers/specs/2026-07-21-weasel-nixos-wsl-design.md`, `docs/superpowers/plans/2026-07-21-weasel-nixos-wsl.md`, `docs/superpowers/specs/2026-07-23-weasel-zellij-zellaude-design.md`, `docs/superpowers/plans/2026-07-23-weasel-zellij-zellaude.md`

**Interfaces:**
- Consumes: Task 1's commit (the runbook describes the renamed flake attribute and `hosts/whistle/`).
- Produces: `docs/ioshi/whistle.md` as the operational runbook path, referenced by `hosts/whistle/configuration.nix:43` (already updated in Task 1 Step 4).

- [ ] **Step 1: Move the runbook**

```bash
cd ~/dotfiles && git mv docs/ioshi/weasel.md docs/ioshi/whistle.md
```

- [ ] **Step 2: Rewrite its references, then restore the historical filenames**

The blanket sed would also rewrite the three historical doc paths the runbook cites, which must keep their real names. Run both commands:

```bash
cd ~/dotfiles
sed -i 's/weasel/whistle/g; s/Weasel/Whistle/g' docs/ioshi/whistle.md
sed -i 's|2026-07-21-whistle-nixos-wsl|2026-07-21-weasel-nixos-wsl|g; s|2026-07-23-whistle-zellij-zellaude|2026-07-23-weasel-zellij-zellaude|g' docs/ioshi/whistle.md
```

- [ ] **Step 3: Verify the historical paths survived and still exist on disk**

```bash
cd ~/dotfiles
grep -n '2026-07-2' docs/ioshi/whistle.md
for f in $(grep -oh 'docs/superpowers/[a-z]*/[0-9-]*[a-z-]*\.md' docs/ioshi/whistle.md | sort -u); do test -f "$f" && echo "OK $f" || echo "BROKEN $f"; done
```

Expected: every cited path prints `OK`. A `BROKEN` line means the sed mangled a filename.

- [ ] **Step 4: Read the runbook and add a name-history line**

Read `docs/ioshi/whistle.md` top to bottom. The sed makes every sentence read as though the host was always `whistle`, which is right for a runbook — but add this immediately after the opening paragraph so the old name is still findable:

```markdown
**Name history:** this host was called `weasel` from its 2026-07-22 cutover
until 2026-08-04, when it was renamed `whistle`
(`docs/superpowers/specs/2026-08-04-whistle-rename-design.md`). Dated specs
and plans still say weasel deliberately.
```

Also fix any sentence the sed made wrong rather than merely renamed — in particular check the `wsl --terminate` / `wsl -d` examples and any prose that quotes a *Windows-side* name, since that name only changes in Task 6.

- [ ] **Step 5: Update `docs/ioshi/standalone-hm.md:10`**

Keep it truthful about the retirement it records:

```markdown
| ~~work-WSL~~ | ~~`scott@work`~~ | wsl | RETIRED 2026-08-04 with the Debian distro — replaced by the `whistle` nixosConfiguration, named `weasel` at the time (see `docs/ioshi/whistle.md`) |
```

- [ ] **Step 6: Add the header note to the 4 weasel-titled historical docs**

For each of the four files, insert this line as its own paragraph directly after the header block (after the `**Goal:**` / `**Scope:**` / `**Context:**` lines, before the first `##` section). Do not touch anything else in these files:

```markdown
> **Renamed:** this host was renamed `weasel` → `whistle` on 2026-08-04
> (`docs/superpowers/specs/2026-08-04-whistle-rename-design.md`). The name
> `weasel` below is preserved as the historical record.
```

Files:
- `docs/superpowers/specs/2026-07-21-weasel-nixos-wsl-design.md`
- `docs/superpowers/plans/2026-07-21-weasel-nixos-wsl.md`
- `docs/superpowers/specs/2026-07-23-weasel-zellij-zellaude-design.md`
- `docs/superpowers/plans/2026-07-23-weasel-zellij-zellaude.md`

The two `ewm-winit-backend` docs mention weasel only in passing and get **no** note.

- [ ] **Step 7: Verify the docs layer**

```bash
cd ~/dotfiles && grep -rln -i weasel docs/
```

Expected: exactly these 10 files, every hit deliberate —

- the 6 dated `docs/superpowers/` specs+plans (historical record, 4 of them now carrying the rename note)
- `docs/superpowers/specs/2026-08-04-whistle-rename-design.md` and `docs/superpowers/plans/2026-08-04-whistle-rename.md` (the spec and this plan, which are *about* the old name)
- `docs/ioshi/whistle.md` (the name-history line from Step 4)
- `docs/ioshi/standalone-hm.md` (the "named `weasel` at the time" parenthetical from Step 5)

Any 11th file is a miss. Read each hit to confirm it is one of the above rather than a leftover.

- [ ] **Step 8: Commit**

```bash
cd ~/dotfiles && git add docs/ && git commit -m 'docs: rename weasel runbook to whistle, note the rename in dated docs

Runbook renamed and rewritten (operational truth). Dated specs/plans keep
their filenames and prose as historical record, with a one-line rename note.'
```

- [ ] **Step 9: Push**

```bash
cd ~/dotfiles && git push origin main && git log --oneline -3
```

Expected: push succeeds; the three commits are the spec, the nix rename, and the docs rename.

- [ ] **Step 10: Update datacore's clone**

```bash
ssh datacore 'cd ~/projects/dotfiles && git pull --ff-only && git log --oneline -3'
```

Expected: fast-forward succeeds. datacore's clone is several commits behind, so **unrelated commits will come along** — that is normal, not a problem. datacore's `homeConfigurations."scott@datacore"` is untouched by this rename, so no rebuild there is required.

> **DEFERRED 2026-08-04.** The fast-forward failed: datacore's clone has
> **diverged**, carrying 3 unpushed local commits (`b919ea0` IB Gateway /
> Steam XWayland, `4e99c0d` pi declarative install, `beeab2f` Emacs bindings)
> while missing 9 from `origin/main`. Those commits exist nowhere else — a
> force-push to `main` would destroy them, and the pi/Emacs subject overlap
> with later commits makes a rebase conflict-prone. Scott's call was to skip
> this step and give datacore its own session. **The rename is unaffected:**
> the repo change is pushed, and `homeConfigurations."scott@datacore"` does
> not reference the renamed host.

---

### Task 3: Activate the new closure on this host

**Files:** none (system activation only, no repo change).

**Interfaces:**
- Consumes: `nixosConfigurations.whistle` from Task 1.
- Produces: `/etc/wsl.conf` containing `hostname=whistle`, staged for Task 6's restart.

- [ ] **Step 1: Build as scott**

```bash
cd ~/dotfiles && nix build .#nixosConfigurations.whistle.config.system.build.toplevel --out-link "$SCRATCH/whistle-toplevel" && readlink -f "$SCRATCH/whistle-toplevel"
```

Expected: a `/nix/store/...-nixos-system-whistle-*` path. Note that the store path now carries the new name — first visible proof `system.name` took.

- [ ] **Step 2: Activate as root**

Root cannot read scott's repo (libgit2 ownership), so activation is two explicit commands against the built path:

```bash
TOP=$(readlink -f "$SCRATCH/whistle-toplevel")
sudo nix-env -p /nix/var/nix/profiles/system --set "$TOP"
sudo "$TOP/bin/switch-to-configuration" switch
```

Expected: `switch-to-configuration` reports restarted/reloaded units and exits 0. Warnings about units it declines to restart are normal.

- [ ] **Step 3: Verify `/etc/wsl.conf` is staged**

```bash
grep hostname /etc/wsl.conf
hostname
```

Expected: `hostname=whistle` from the first command, and **`weasel` from the second**. This is correct and expected — `wsl.conf` is only read when the distro starts, so the live hostname does not change until Task 6's restart. Do not try to "fix" it with `hostnamectl`; that is the exact change `networking.hostName = ""` exists to avoid.

- [ ] **Step 4: Verify the generation label**

```bash
readlink -f /run/current-system
sudo nix-env -p /nix/var/nix/profiles/system --list-generations | tail -3
```

Expected: the store path reads `nixos-system-whistle-<version>` — it was
`nixos-system-unnamed-<version>` before `system.name` was set. Note that
`--list-generations` prints no name column, so it confirms only that the new
generation is `(current)`; the store path is where the name is visible.

- [ ] **Step 5: Verify nothing else broke**

```bash
systemctl is-active sshd tailscaled
systemctl --user is-active syncthing
systemctl is-system-running
docker ps --format '{{.Names}}\t{{.Status}}'
sudo -n true && echo "passwordless sudo OK"
/mnt/c/Windows/System32/cmd.exe /c echo interop-ok
```

Expected: `active` for sshd/tailscaled/syncthing; `running` or `degraded` (check `systemctl --failed` if degraded, and confirm any failures predate this task); the pearl-platform-db and chat-interrupt containers `Up`; passwordless sudo OK; `interop-ok` printed.

---

### Task 4: Rename the tailnet node and both syncthing labels

**Files:** none in the repo. Live state on this host and on datacore.

**Interfaces:**
- Consumes: Task 3's activation (not strictly required, but keeps the identity flip in one sitting).
- Produces: MagicDNS name `whistle` — which Task 5 depends on, and which **breaks the name `weasel` immediately**.

- [ ] **Step 1: Rename the tailnet node**

```bash
sudo tailscale set --hostname=whistle
```

This renames the existing node — same node key, same IP — rather than creating a second record, and the preference persists in `/var/lib/tailscale` across restarts.

- [ ] **Step 2: Verify the tailnet identity**

```bash
tailscale status --self --peers=false
```

Expected: `100.64.0.10   whistle   ...`. The IP must be unchanged. From this moment `weasel` no longer resolves over MagicDNS — Task 5 is now time-sensitive.

- [ ] **Step 3: Rename this host's syncthing self-label**

```bash
K=$(grep -oP '(?<=<apikey>)[^<]+' ~/.local/state/syncthing/config.xml)
ID=BWI6SYR-ASNGFB4-AM7XL7S-MHOJ2PW-LD6ADBF-FK5H6AU-KIQ5QMJ-DPBHXQN
curl -sf -X PATCH -H "X-API-Key: $K" -H 'Content-Type: application/json' \
  -d '{"name":"whistle"}' "http://127.0.0.1:8385/rest/config/devices/$ID"
```

Expected: exits 0 (empty body is fine). The device ID is untouched, so no re-pairing happens.

- [ ] **Step 4: Verify this host's label**

```bash
curl -sf -H "X-API-Key: $K" "http://127.0.0.1:8385/rest/config/devices/$ID" | grep '"name"'
```

Expected: `"name": "whistle",`

- [ ] **Step 5: Rename the peer label on datacore**

datacore runs syncthing v1.29.5 with its GUI on `127.0.0.1:8384`, and its device list is imperative (not in the flake):

```bash
ssh datacore 'K=$(grep -oP "(?<=<apikey>)[^<]+" ~/.local/state/syncthing/config.xml); \
  ID=BWI6SYR-ASNGFB4-AM7XL7S-MHOJ2PW-LD6ADBF-FK5H6AU-KIQ5QMJ-DPBHXQN; \
  curl -sf -X PATCH -H "X-API-Key: $K" -H "Content-Type: application/json" \
    -d "{\"name\":\"whistle\"}" "http://127.0.0.1:8384/rest/config/devices/$ID" \
  && curl -sf -H "X-API-Key: $K" "http://127.0.0.1:8384/rest/config/devices/$ID" | grep "\"name\""'
```

Expected: `"name": "whistle",`

- [ ] **Step 6: Verify the two nodes are still connected**

```bash
curl -sf -H "X-API-Key: $K" "http://127.0.0.1:8385/rest/system/connections" | grep -A2 FXOPHIF | grep connected
```

Expected: `"connected": true` for datacore (`FXOPHIF-…`). Folder sync is label-independent, but this confirms the PATCH did not disturb the connection.

---

### Task 5: Update eminix's ssh config

**Files:**
- Modify (on eminix, not in this repo): `~/.ssh/config` lines 1–2

**Interfaces:**
- Consumes: Task 4's MagicDNS rename (which is what breaks the current entry).
- Produces: a working `ssh whistle` from eminix.

- [ ] **Step 1: Reach eminix by IP**

The MagicDNS name `eminix` currently points at a stale offline node record (there are two: `eminix` offline, `eminix-mzbvi6by` online), so use the IP:

```bash
ssh 100.64.0.11 'hostname && head -4 ~/.ssh/config'
```

Expected: `eminix`, then the `Host weasel` block with `Port 2222`.

- [ ] **Step 2: Rewrite the Host block**

This file is hand-written on eminix and not nix-managed — the same imperative edit the runbook warns about:

```bash
ssh 100.64.0.11 "sed -i '1,4{s/^Host weasel$/Host whistle/; s/# weasel sshd listens on 2222/# whistle sshd listens on 2222/}' ~/.ssh/config && head -4 ~/.ssh/config"
```

Expected output:

```
Host whistle
    # whistle sshd listens on 2222 (NixOS-WSL, mirrored networking)
    Port 2222
    StrictHostKeyChecking accept-new
```

- [ ] **Step 3: Verify the connection works under the new name**

```bash
ssh 100.64.0.11 'ssh -o ConnectTimeout=8 whistle hostname'
```

Expected: **`weasel`** — the ssh *name* resolves and connects (which is what this task proves), but the remote host's live hostname does not become `whistle` until Task 6's restart. Re-run this in Task 7 and expect `whistle`.

The stale `weasel` entry in eminix's `known_hosts` is harmless: the host key is unchanged and `StrictHostKeyChecking accept-new` re-learns it under the new name.

---

### Task 6: Rename the WSL distro on Windows (manual — ends this session)

**Files:**
- Modify: registry `HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss\{ef72914c-2122-46d0-9b1f-800c91cf0d9f}` values `DistributionName`, `BasePath`
- Move: `%LOCALAPPDATA%\wsl\weasel` → `%LOCALAPPDATA%\wsl\whistle`
- Modify: Windows Terminal `settings.json` (`defaultProfile`, `profiles.list`)
- Modify: `%USERPROFILE%\.glzr\glazewm\config.yaml` lines 270, 280

**Interfaces:**
- Consumes: everything above, committed and pushed.
- Produces: the live hostname `whistle` and `wsl -d whistle`.

- [ ] **Step 1: Pre-flight — nothing may be left unpushed**

```bash
cd ~/dotfiles && git status --porcelain && git log --oneline origin/main..HEAD
```

Expected: no output from the second command (nothing unpushed). Unrelated modified files in `git status` are fine as long as they are files you intend to keep working on — they survive the restart untouched; only the running session dies.

- [ ] **Step 2: Run the rename from PowerShell**

`wsl --shutdown` terminates the distro this session runs in, so **this is the last step Claude can be part of.** Scott runs this in a PowerShell window:

```powershell
wsl --shutdown
$k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\{ef72914c-2122-46d0-9b1f-800c91cf0d9f}'
Rename-Item "$env:LOCALAPPDATA\wsl\weasel" whistle
Set-ItemProperty $k DistributionName whistle
Set-ItemProperty $k BasePath "$env:LOCALAPPDATA\wsl\whistle"
wsl -l -v
```

Expected from `wsl -l -v`: one distro, `whistle`, `Stopped`, version 2.

Both registry values must change together — a `BasePath` still pointing at `...\wsl\weasel` after the folder move is the one way to make the distro unstartable. The folder move is a same-volume rename: instant, no data copied, and it carries the `ext4.vhdx`.

**Rollback:** the same three edits in reverse, while shut down:

```powershell
wsl --shutdown
$k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\{ef72914c-2122-46d0-9b1f-800c91cf0d9f}'
Rename-Item "$env:LOCALAPPDATA\wsl\whistle" weasel
Set-ItemProperty $k DistributionName weasel
Set-ItemProperty $k BasePath "$env:LOCALAPPDATA\wsl\weasel"
```

- [ ] **Step 3: Start the distro and confirm the hostname landed**

```powershell
wsl -d whistle -- hostname
```

Expected: `whistle`

- [ ] **Step 4: Fix Windows Terminal's default profile**

WT derives WSL dynamic-profile GUIDs from the distro *name*, so the rename orphans the old profile and `defaultProfile` — currently `{9615d19c-43da-5f57-b75a-7d1a947760f9}`, the weasel-derived GUID — points at a profile that no longer exists. In order:

1. Launch Windows Terminal once so it generates the new `whistle` profile.
2. Open Settings → JSON file. In `profiles.list`, find the new entry with `"name": "whistle"` and `"source": "Microsoft.WSL"`; copy its `guid`.
3. Set the top-level `"defaultProfile"` to that GUID.
4. Delete the orphaned `{"name": "weasel", "source": "Microsoft.WSL"}` entry, and the equally stale `{"name": "Debian", "source": "Microsoft.WSL"}` entry left from the unregistered distro.
5. Save, open a new tab.

Expected: a new tab opens `whistle` by default, and the dropdown lists no `weasel` or `Debian`.

- [ ] **Step 5: Update the GlazeWM comments**

In `%USERPROFILE%\.glzr\glazewm\config.yaml`, lines 270 and 280 describe the keybinds as targeting "Windows Terminal on its default profile (weasel)" and "Windows Terminal (weasel)". Change both to `whistle`. Comments only — no keybind behavior changes, since the binds target WT's default profile, which Step 4 just repointed.

---

### Task 7: Post-restart verification sweep and memory update

**Files:**
- Modify: `/home/scott/.claude/projects/-home-scott/memory/project_weasel.md` → `project_whistle.md`
- Modify: `/home/scott/.claude/projects/-home-scott/memory/project_three_node_model.md`, `reference_wsl_vhdx_bloat.md`, `MEMORY.md`

**Interfaces:**
- Consumes: the completed rename.
- Produces: nothing further depends on this.

- [ ] **Step 1: Run the full verification table**

```bash
hostname; cat /etc/hostname
grep hostname /etc/wsl.conf
tailscale status --self --peers=false
systemctl is-active sshd tailscaled; systemctl --user is-active syncthing
systemctl is-system-running; sudo -n true && echo "sudo OK"
docker ps --format '{{.Names}}\t{{.Status}}'
/mnt/c/Windows/System32/cmd.exe /c echo interop-ok
readlink -f /run/current-system
```

Expected: `whistle` (twice), `hostname=whistle`, tailnet `whistle` at `100.64.0.10`, all units active, system running, sudo OK, both DB containers `Up`, `interop-ok`, and a current-system path reading `nixos-system-whistle-<version>`.

- [ ] **Step 2: Verify the agenix secret still decrypts**

The host key was never regenerated, so this must pass without a rekey:

```bash
sudo test -r /run/agenix/openrouter-auth && echo "agenix OK"
head -c 40 ~/.pi/auth.json 2>/dev/null; echo
```

Expected: `agenix OK`. If it fails, the host key changed — stop and investigate before touching secrets.

- [ ] **Step 3: Verify eminix→whistle ssh end to end**

```bash
ssh 100.64.0.11 'ssh -o ConnectTimeout=8 whistle hostname'
```

Expected: `whistle` — now that the restart has landed, this is the value Task 5 Step 3 could not yet produce.

- [ ] **Step 4: Verify syncthing reconnected under the new labels**

```bash
K=$(grep -oP '(?<=<apikey>)[^<]+' ~/.local/state/syncthing/config.xml)
curl -sf -H "X-API-Key: $K" http://127.0.0.1:8385/rest/config/devices | grep '"name"'
curl -sf -H "X-API-Key: $K" http://127.0.0.1:8385/rest/system/connections | grep -A2 FXOPHIF | grep connected
```

Expected: names `whistle` and `datacore`; datacore `"connected": true`.

- [ ] **Step 5: Confirm no stale name survives anywhere reachable**

```bash
cd ~/dotfiles && grep -rln -i weasel . --exclude-dir=.git | sort
grep -rn -i weasel ~/.ssh/config /etc/wsl.conf 2>/dev/null
```

Expected: the same 10 files enumerated in Task 2 Step 7, and nothing else. No hits in `~/.ssh/config` or `/etc/wsl.conf`. (`~/.zcompdump-weasel-5.9.1` regenerates itself under the new name; delete the stale one if it bothers you.)

- [ ] **Step 6: Update the Claude memory files**

- Write `project_whistle.md` carrying `project_weasel.md`'s content with the name updated, plus a "renamed from weasel 2026-08-04" line, and delete `project_weasel.md`.
- Update the weasel references in `project_three_node_model.md` and `reference_wsl_vhdx_bloat.md`.
- Update both pointer lines in `MEMORY.md`.

- [ ] **Step 7: Final commit if the sweep changed anything in the repo**

```bash
cd ~/dotfiles && git status --porcelain
```

If Steps 1–5 surfaced a missed reference, fix it and commit **the specific files you touched** — never `git add -A` or `git add -u`, which would sweep in the unrelated working changes noted in Task 1 Step 1:

```bash
cd ~/dotfiles && git add <the files you fixed> && git commit -m 'fix: catch stale weasel references missed in the rename' && git push origin main
```

Otherwise nothing to do — the rename is complete.
