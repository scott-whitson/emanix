# Three-Node Home Model — Phase 3 (Work Content) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Work docs and projects sync from the work-WSL to datacore (versioned) and eminix; the OneDrive vault folds into the org docs and OneDrive is retired for it; `~/clients` never syncs.

**Architecture:** Hub-and-spoke syncthing — WSL and eminix each pair only with datacore. Two new shares: `work-docs` (`~/docs/org/work` on every node; nested inside datacore's existing `docs` share, so eminix receives it through `docs` automatically — only WSL needs the dedicated share) and `work-projects`. **Deliberate per-device path asymmetry (user decision 2026-07-20):** `work-projects` is ALL of `~/projects` on the WSL, landing at `~/projects/work` on datacore and eminix. WSL syncthing is Home-Manager-native (`services.syncthing`), declarative, gated to the `wsl` profile; datacore stays Debian-managed (REST API config); eminix stays NixOS-declarative.

**Tech Stack:** HM `services.syncthing` (WSL), syncthing REST API + jq (datacore), NixOS module (eminix), rsync (vault migration).

**Spec:** `docs/superpowers/specs/2026-07-19-three-node-home-model-design.md` (work-content + sync topology sections; the ionapi prerequisite completed 2026-07-20).

## Global Constraints

- **Never** `git add -A`/`git add .`; stage explicit paths. **No** Co-Authored-By trailers.
- Propagation: push on WSL → `ssh datacore "cd ~/projects/dotfiles && git pull --ff-only"` → `ssh eminix "cd ~/dotfiles && git fetch origin && git merge --ff-only origin/main"`. Never edit datacore's checkout.
- `~/clients` (WSL) is NEVER part of any share, ignore file, or task — it must be untouched and unsynced at the end.
- datacore is the hub: its `~/projects` contains the git hub and personal repos — only `~/projects/work` is ever shared. The datacore API key is read into a shell var per task; never printed/echoed/persisted (and never use `curl -v` with it).
- Versioning on both new datacore folders: `staggered`, `maxAge=2592000`, `cleanupIntervalS=3600` (clone the `docs` folder config via REST to inherit it).
- Device IDs: datacore `FXOPHIF-EMJAP6C-CLI6PB4-HCLUDMK-RJ3PXLE-GIV4IJ7-3NMTE35-YHRNIAI`, eminix `WIP5SWJ-R3HTLW5-MJAO4SX-QCVLR3X-DFEUG43-MSMTDEN-XQMRQ5Z-URXLIQB`, WSL = generated in Task 1.
- `.stignore` patterns use NO trailing slashes (syncthing ignores are not gitignore — trailing-slash patterns match nothing; learned 2026-07-13). `.git` is deliberately NOT ignored (spec: repos sync whole; single-writer discipline, WSL is the writer).
- Connectivity: WSL reaches datacore via syncthing global discovery + public relays (userspace tailscale can't route the tailnet) — no network changes; expect relay latency (30s–3min for small changes; be patient in verification, retry before judging).
- OneDrive vault source: `/mnt/c/Users/swhitson.CENTRALDATA/OneDrive - Central Data Systems, Inc/docs` — 110 `.md` files, 5.1M (verified 2026-07-20). Retirement = RENAME to `docs-retired-20260720` (reversible), never delete.
- eminix rebuild in Task 3 also picks up two pending HM-layer changes (ec/et aliases from c82cada and this plan's systemd.nix unit removal) — expected, not a regression.

**Shared `.stignore` content** (referenced by Tasks 1–3 as THE STIGNORE BLOCK):

```
// Build/venv/cache junk — arch- and machine-specific, never sync
node_modules
.venv
venv
__pycache__
.direnv
.pytest_cache
.mypy_cache
.ruff_cache
target
dist
build
*.pyc
```

---

### Task 1: WSL — declarative syncthing (repo) + first start

**Files:**
- Create: `ioshi/i-intelligence/syncthing.nix`
- Modify: `ioshi/i-intelligence/systemd.nix` (remove the hand-rolled syncthing unit)
- Modify: `ioshi/i-intelligence/default.nix` (import syncthing.nix)

**Interfaces:**
- Produces: running WSL syncthing with datacore paired and folders `work-docs` (`/home/scott/docs/org/work`) + `work-projects` (`/home/scott/projects`) declared; the WSL DEVICE ID (printed in Step 5) — Task 2 needs it verbatim.

- [ ] **Step 1: Confirm no syncthing runs on the WSL yet**

Run: `systemctl --user status syncthing --no-pager 2>&1 | head -2`
Expected: `Unit syncthing.service could not be found.` (or inactive).

- [ ] **Step 2: Create `ioshi/i-intelligence/syncthing.nix`**

```nix
{ config, lib, pkgs, ... }:

{
  # Work-WSL syncthing (Phase 3): hub-and-spoke with datacore only.
  # eminix's syncthing is the NixOS module (ioshi/hi-hardware/net/syncthing.nix);
  # datacore's is Debian-managed (the hub, configured via REST). This HM-native
  # config exists only for the wsl profile.
  config = lib.mkIf (config.scott.dotfiles.profile == "wsl") {
    services.syncthing = {
      enable = true;
      overrideDevices = true;
      overrideFolders = true;
      settings = {
        devices.datacore.id =
          "FXOPHIF-EMJAP6C-CLI6PB4-HCLUDMK-RJ3PXLE-GIV4IJ7-3NMTE35-YHRNIAI";
        # Per-device path asymmetry (user decision): ALL of ~/projects here,
        # lands at ~/projects/work on datacore/eminix. ~/clients lives OUTSIDE
        # ~/projects and is never shared.
        folders.work-projects = {
          id = "work-projects";
          label = "work-projects";
          path = "/home/scott/projects";
          devices = [ "datacore" ];
        };
        folders.work-docs = {
          id = "work-docs";
          label = "work-docs";
          path = "/home/scott/docs/org/work";
          devices = [ "datacore" ];
        };
      };
    };

    # Ignore build junk at the source. NB: no trailing slashes — syncthing
    # ignores are not gitignore. .git is intentionally synced (spec).
    home.file."projects/.stignore" = {
      force = true;
      text = ''
        // Build/venv/cache junk — arch- and machine-specific, never sync
        node_modules
        .venv
        venv
        __pycache__
        .direnv
        .pytest_cache
        .mypy_cache
        .ruff_cache
        target
        dist
        build
        *.pyc
      '';
    };
  };
}
```

- [ ] **Step 3: Remove the hand-rolled syncthing unit from `ioshi/i-intelligence/systemd.nix`**

Delete the whole `syncthing = lib.mkIf (!config.scott.standalone) { ... };` block from `systemd.user.services` (it duplicated eminix's system-level syncthing and served no node). Keep the `dot-sync` timer and everything else. If `systemd.user.services` becomes empty, leave it as `systemd.user.services = { };` with the existing migration comment.

- [ ] **Step 4: Import it and commit**

In `ioshi/i-intelligence/default.nix`, after `./standalone.nix`, add `./syncthing.nix`. Then:

```bash
cd /home/scott/dotfiles
git add ioshi/i-intelligence/syncthing.nix ioshi/i-intelligence/systemd.nix ioshi/i-intelligence/default.nix
git commit -m "feat(sync): WSL work-content syncthing, HM-native (Phase 3)"
git push
ssh datacore "cd ~/projects/dotfiles && git pull --ff-only"
```

- [ ] **Step 5: Switch, create the docs dir, capture the device ID**

```bash
mkdir -p ~/docs/org/work
bash -lc 'home-manager switch --flake ~/dotfiles#scott@work' 2>&1 | tail -2
sleep 5; systemctl --user is-active syncthing
bash -lc 'syncthing cli show system 2>/dev/null | jq -r .myID || grep -oP "(?<=<device id=\")[A-Z0-9-]{63}" ~/.local/state/syncthing/config.xml | head -1'
```

Expected: `active`, then a 63-char device ID (7 dash-separated groups). **Record it in your report — Task 2 needs it.** Also verify the ignore file: `head -3 ~/projects/.stignore` shows the junk comment.

---

### Task 2: datacore — accept WSL device + both folders (ops, no commits)

**Files:** none in repo.

**Interfaces:**
- Consumes: WSL DEVICE ID from Task 1's report (`.superpowers/sdd/task-1-report.md`).
- Produces: datacore shares `work-docs` (to WSL) and `work-projects` (to WSL + eminix), both staggered-versioned; dirs + .stignore in place.

- [ ] **Step 1: Create dirs and .stignore on datacore**

```bash
ssh datacore 'mkdir -p ~/projects/work ~/docs/org/work && cat > ~/projects/work/.stignore <<"EOF"
// Build/venv/cache junk — arch- and machine-specific, never sync
node_modules
.venv
venv
__pycache__
.direnv
.pytest_cache
.mypy_cache
.ruff_cache
target
dist
build
*.pyc
EOF
echo dirs-ok'
```

- [ ] **Step 2: Add the WSL device (REST)**

Replace `WSL_DEVICE_ID` with the ID from Task 1's report:

```bash
ssh datacore 'APIKEY=$(grep -oP "(?<=<apikey>)[^<]+" ~/.local/state/syncthing/config.xml); \
  curl -s -X PUT -H "X-API-Key: $APIKEY" -H "Content-Type: application/json" \
    -d "{\"deviceID\":\"WSL_DEVICE_ID\",\"name\":\"work-wsl\"}" \
    127.0.0.1:8384/rest/config/devices/WSL_DEVICE_ID && echo DEVICE-OK'
```

- [ ] **Step 3: Create both folders by cloning the `docs` template (inherits staggered versioning)**

```bash
ssh datacore 'APIKEY=$(grep -oP "(?<=<apikey>)[^<]+" ~/.local/state/syncthing/config.xml); \
  curl -s -H "X-API-Key: $APIKEY" 127.0.0.1:8384/rest/config/folders/docs \
    | jq ".id=\"work-projects\" | .label=\"work-projects\" | .path=\"/home/scott/projects/work\" | .devices=[{\"deviceID\":\"FXOPHIF-EMJAP6C-CLI6PB4-HCLUDMK-RJ3PXLE-GIV4IJ7-3NMTE35-YHRNIAI\"},{\"deviceID\":\"WIP5SWJ-R3HTLW5-MJAO4SX-QCVLR3X-DFEUG43-MSMTDEN-XQMRQ5Z-URXLIQB\"},{\"deviceID\":\"WSL_DEVICE_ID\"}]" \
    > /home/scott/wp.json; \
  curl -s -X PUT -H "X-API-Key: $APIKEY" -H "Content-Type: application/json" -d @/home/scott/wp.json 127.0.0.1:8384/rest/config/folders/work-projects && echo WP-OK; \
  curl -s -H "X-API-Key: $APIKEY" 127.0.0.1:8384/rest/config/folders/docs \
    | jq ".id=\"work-docs\" | .label=\"work-docs\" | .path=\"/home/scott/docs/org/work\" | .devices=[{\"deviceID\":\"FXOPHIF-EMJAP6C-CLI6PB4-HCLUDMK-RJ3PXLE-GIV4IJ7-3NMTE35-YHRNIAI\"},{\"deviceID\":\"WSL_DEVICE_ID\"}]" \
    > /home/scott/wd.json; \
  curl -s -X PUT -H "X-API-Key: $APIKEY" -H "Content-Type: application/json" -d @/home/scott/wd.json 127.0.0.1:8384/rest/config/folders/work-docs && echo WD-OK; \
  rm /home/scott/wp.json /home/scott/wd.json'
```

(Absolute paths for `-d @` — `~` inside this quoting context broke curl in Phase 2.)
Expected: `WP-OK` and `WD-OK`.

- [ ] **Step 4: Verify folders + versioning + device**

```bash
ssh datacore 'APIKEY=$(grep -oP "(?<=<apikey>)[^<]+" ~/.local/state/syncthing/config.xml); \
  for f in work-projects work-docs; do printf "%s: " $f; \
    curl -s -H "X-API-Key: $APIKEY" 127.0.0.1:8384/rest/config/folders/$f | jq -r "[.path, .versioning.type, (.devices|length)] | @tsv"; done; \
  sleep 10; curl -s -H "X-API-Key: $APIKEY" "127.0.0.1:8384/rest/db/status?folder=work-projects" | jq -r .state'
```

Expected: `work-projects: /home/scott/projects/work  staggered  3`, `work-docs: /home/scott/docs/org/work  staggered  2`, then `idle`/`scanning`.

- [ ] **Step 5: Confirm the WSL connects (relay)**

```bash
ssh datacore 'APIKEY=$(grep -oP "(?<=<apikey>)[^<]+" ~/.local/state/syncthing/config.xml); \
  sleep 30; curl -s -H "X-API-Key: $APIKEY" 127.0.0.1:8384/rest/system/connections | jq -r ".connections | to_entries[] | select(.value.connected) | [.key[0:7], .value.type] | @tsv"'
```

Expected: three connected rows — eminix (likely `tcp-*`) and the WSL device (likely `relay-*`). If the WSL row is missing, retry after 60s (relay discovery can be slow); if still absent, check `systemctl --user status syncthing` on the WSL and report.

---

### Task 3: eminix — receive work-projects (repo + rebuild)

**Files:**
- Modify: `ioshi/hi-hardware/net/syncthing.nix`

**Interfaces:**
- Consumes: datacore sharing `work-projects` to eminix (Task 2).
- Produces: eminix receives `~/projects/work`; also activates the pending HM-layer changes (ec/et aliases, syncthing-unit removal) via the rebuild.

- [ ] **Step 1: Add the folder to `ioshi/hi-hardware/net/syncthing.nix`**

After the `folders.downloads` block, add:

```nix
      folders.work-projects = {
        id = "work-projects";
        label = "work-projects";
        path = "/home/scott/projects/work";
        devices = [ "datacore" ];
      };
```

- [ ] **Step 2: Commit, propagate, prepare the dir + .stignore on eminix**

```bash
cd /home/scott/dotfiles
git add ioshi/hi-hardware/net/syncthing.nix
git commit -m "feat(sync): work-projects share eminix-side (Phase 3)"
git push
ssh datacore "cd ~/projects/dotfiles && git pull --ff-only"
ssh eminix 'cd ~/dotfiles && git fetch origin && git merge --ff-only origin/main && mkdir -p ~/projects/work && cat > ~/projects/work/.stignore <<"EOF"
// Build/venv/cache junk — arch- and machine-specific, never sync
node_modules
.venv
venv
__pycache__
.direnv
.pytest_cache
.mypy_cache
.ruff_cache
target
dist
build
*.pyc
EOF
echo eminix-prep-ok'
```

- [ ] **Step 3: Rebuild eminix**

```bash
ssh eminix "sudo nixos-rebuild switch --flake ~/dotfiles#eminix" 2>&1 | tail -4
```

Expected: activation completes (syncthing restarts; ec/et aliases and the HM syncthing-unit removal land too — expected side effects, not regressions).

- [ ] **Step 4: Verify**

```bash
ssh eminix "grep -c 'folder id=\"work-projects\"' ~/.local/state/syncthing/config.xml; systemctl is-active syncthing; zsh -lic 'type ec' | head -1"
```

Expected: `1`, `active`, and `ec is a shell function…` (proves the rebuild carried the pending zsh change).

---

### Task 4: Vault migration — OneDrive → `~/docs/org/work` (ops, WSL; no commits)

**Files:** none in repo.

**Interfaces:**
- Consumes: `work-docs` share live (Tasks 1–2).
- Produces: vault content in `~/docs/org/work` on WSL + datacore (+ eminix via the `docs` share); OneDrive folder renamed `docs-retired-20260720`.

- [ ] **Step 1: Record the source inventory**

```bash
SRC="/mnt/c/Users/swhitson.CENTRALDATA/OneDrive - Central Data Systems, Inc/docs"
find "$SRC" -type f | wc -l; du -sh "$SRC"
```

Expected: ~110+ files (110 are `.md`; extras like `.obsidian` config are fine), ~5.1M. Record exact numbers.

- [ ] **Step 2: Copy with WSL-friendly permissions**

```bash
SRC="/mnt/c/Users/swhitson.CENTRALDATA/OneDrive - Central Data Systems, Inc/docs"
[ -d "$SRC" ] || { echo "SRC MISSING — STOP"; exit 1; }
rsync -rt --no-perms --no-owner --no-group --exclude='.obsidian' "$SRC"/ ~/docs/org/work/ && echo COPY-DONE
find ~/docs/org/work -type f | wc -l
```

(Re-declare `SRC` in every step — shell state does not persist between command invocations, and an unset `SRC` here would misfire.)

Expected: `COPY-DONE`; file count = Step 1's count minus `.obsidian` contents. (`.obsidian` is Obsidian per-app state — Emacs takes over, so it stays behind with the retired copy.)

- [ ] **Step 3: Verify the copy content-wise (not just counts)**

```bash
SRC="/mnt/c/Users/swhitson.CENTRALDATA/OneDrive - Central Data Systems, Inc/docs"
(cd ~/docs/org/work && md5sum *.md | md5sum); (cd "$SRC" && md5sum *.md | md5sum)
```

Expected: the two aggregate hashes are IDENTICAL. (Top-level `.md` files; if the vault has subdirs, extend with `find … -name '*.md' -exec md5sum {} +` sorted — state what you ran.)

- [ ] **Step 4: Watch it arrive on datacore (and eminix)**

```bash
sleep 90; ssh datacore 'find ~/docs/org/work -name "*.md" | wc -l'
ssh eminix 'find ~/docs/org/work -name "*.md" | wc -l' 2>/dev/null || echo "eminix asleep — verify later, docs share carries it"
```

Expected: datacore count matches Step 2 (relay latency: retry once after another 90s before judging). eminix may lag or be asleep — non-blocking.

- [ ] **Step 5: Retire the OneDrive copy (rename, never delete)**

```bash
SRC="/mnt/c/Users/swhitson.CENTRALDATA/OneDrive - Central Data Systems, Inc/docs"
[ -d "$SRC" ] || { echo "SRC MISSING — STOP"; exit 1; }
mv "$SRC" "/mnt/c/Users/swhitson.CENTRALDATA/OneDrive - Central Data Systems, Inc/docs-retired-20260720" && echo RETIRED
```

Expected: `RETIRED`. OneDrive will sync the rename; Obsidian loses its vault path by design (user-approved — Emacs/org takes over).

---

### Task 5: End-to-end verification + docs

**Files:**
- Create: `docs/ioshi/work-sync.md`

**Interfaces:**
- Consumes: everything above.
- Produces: proven round-trips, junk-exclusion proof, `~/clients` untouched proof, reference doc on all nodes.

- [ ] **Step 1: Projects round-trip WSL → datacore → eminix**

```bash
echo "phase3-test-$(date +%s)" > ~/projects/reports/phase3-sync-test.txt
sleep 90; ssh datacore "cat ~/projects/work/reports/phase3-sync-test.txt"
ssh eminix "cat ~/projects/work/reports/phase3-sync-test.txt" 2>/dev/null || echo eminix-later
```

Expected: same content on datacore (note the path asymmetry working: `~/projects/reports/...` → `~/projects/work/reports/...`); eminix if awake. Retry once on relay lag.

- [ ] **Step 2: Junk exclusion + clients isolation proof**

```bash
ssh datacore 'find ~/projects/work -maxdepth 3 -type d \( -name node_modules -o -name .venv \) | wc -l; ls ~/projects/work | head -12'
ls -ld ~/clients; ssh datacore 'ls ~/clients 2>&1 | head -1'
```

Expected: `0` junk dirs on datacore; the work repo list (cd-audit, pearl-platform, …); `~/clients` present locally and ABSENT on datacore (`No such file or directory`).

- [ ] **Step 3: Versioning spot-check on a work share**

```bash
echo change >> ~/projects/reports/phase3-sync-test.txt; sleep 90
ssh datacore 'ls ~/projects/work/.stversions/reports/ 2>/dev/null | head -2'
rm ~/projects/reports/phase3-sync-test.txt; sleep 60; ssh datacore 'rm -rf ~/projects/work/.stversions/reports 2>/dev/null; ls ~/projects/work/reports/phase3-sync-test.txt 2>&1'
```

Expected: a dated archived copy appears in `.stversions`, and after cleanup the live file is gone on datacore.

- [ ] **Step 4: Write `docs/ioshi/work-sync.md`**

```markdown
# Work-content sync (Phase 3)

Work docs and projects replicate from the work-WSL through datacore (the
versioned hub) to eminix. Spec:
`docs/superpowers/specs/2026-07-19-three-node-home-model-design.md`.

| Share | WSL path | datacore/eminix path | Devices |
| --- | --- | --- | --- |
| `work-projects` | `~/projects` (all of it) | `~/projects/work` | WSL ↔ datacore ↔ eminix |
| `work-docs` | `~/docs/org/work` | `~/docs/org/work` | WSL ↔ datacore (eminix gets it via `docs`) |

- **Path asymmetry is deliberate:** the WSL's whole `~/projects` IS work;
  personal nodes keep it namespaced under `work/`.
- **`~/clients` never syncs** — it lives outside `~/projects` on the WSL.
- Single-writer discipline: the WSL is the writing machine for work repos;
  treat datacore/eminix copies as read-mostly. Recovery = datacore's
  `.stversions` (staggered, 30 days).
- Build junk (`node_modules`, `.venv`, …) is `.stignore`d on every node —
  no trailing slashes in those patterns, and `.git` is NOT ignored.
- The WSL connects via syncthing relays (userspace tailscale can't route
  the tailnet); small-change latency of 30s–3min is normal.
- The old Obsidian vault was folded into `~/docs/org/work` and the OneDrive
  copy renamed `docs-retired-20260720` (2026-07-20); Emacs/org owns work
  notes now (files stay `.md` until a conversion project).
- WSL syncthing is HM-managed (`ioshi/i-intelligence/syncthing.nix`);
  datacore is Debian-managed (REST); eminix is the NixOS module.
```

- [ ] **Step 5: Commit and propagate everywhere**

```bash
cd /home/scott/dotfiles
git add docs/ioshi/work-sync.md
git commit -m "docs: work-content sync reference (Phase 3)"
git push
ssh datacore "cd ~/projects/dotfiles && git pull --ff-only"
ssh eminix "cd ~/dotfiles && git fetch origin && git merge --ff-only origin/main" 2>&1 | tail -1
```

Expected: all nodes at the same commit (eminix may be asleep — report if unreachable).
