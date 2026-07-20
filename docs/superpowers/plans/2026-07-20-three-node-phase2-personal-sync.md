# Three-Node Home Model — Phase 2 (Personal Sync) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `~/Downloads` syncs datacore↔eminix, and datacore keeps staggered version history for every personal share.

**Architecture:** eminix's syncthing folders are declarative (`ioshi/hi-hardware/net/syncthing.nix`, `overrideFolders = true`) — add the folder there and rebuild. datacore's syncthing is Debian-managed (user service, config at `~/.local/state/syncthing/config.xml`, REST API on `127.0.0.1:8384`) — add the folder by cloning the existing `docs` folder config via the REST API, which carries over the device set AND the staggered versioning in one move.

**Tech Stack:** NixOS module (eminix), syncthing v1.29.5 REST API + jq (datacore).

**Spec:** `docs/superpowers/specs/2026-07-19-three-node-home-model-design.md` (Sync topology section)

## Global Constraints

- **Never** `git add -A` or `git add .` — stage explicit paths only. **No** Co-Authored-By trailers.
- Propagation: commit+push on WSL → `ssh datacore "cd ~/projects/dotfiles && git pull --ff-only"` → `ssh eminix "cd ~/dotfiles && git fetch origin && git merge --ff-only origin/main"`. Never edit datacore's checkout directly.
- Downloads path is `~/Downloads` (capital D) on BOTH machines — verified 2026-07-20; XDG standard (`XDG_DOWNLOAD_DIR="$HOME/Downloads"`).
- Versioning to replicate (verbatim from datacore's existing `docs` share): type `staggered`, param `maxAge=2592000` (30 days), `cleanupIntervalS=3600`. Versions live ONLY on datacore (the hub); eminix folder entries get no versioning block.
- The datacore syncthing API key lives in `~/.local/state/syncthing/config.xml` (`<apikey>`). Read it into a shell variable on datacore; **never** print it into reports, commits, or files.
- Facts: datacore device ID `FXOPHIF-…-YHRNIAI`; eminix device ID `WIP5SWJ-…-URXLIQB`; both already paired; `docs` and `pi-agent` shares already exist WITH staggered versioning (only `downloads` is new). eminix has passwordless `nixos-rebuild` for scott.
- Out of scope: the stock `default` folder (`~/Sync`) on datacore; the work shares (Phase 3).

---

### Task 1: eminix — declare the `downloads` folder and rebuild

**Files:**
- Modify: `ioshi/hi-hardware/net/syncthing.nix`

**Interfaces:**
- Produces: folder id `downloads` (label `downloads`, path `/home/scott/Downloads`) offered from eminix to device `datacore`. Task 2 creates the matching side.

- [ ] **Step 1: Confirm the current state (the "failing test")**

```bash
ssh eminix "grep -c 'folders.downloads' ~/.local/state/syncthing/config.xml || echo ABSENT"
```

Expected: `0` or `ABSENT` — eminix's live syncthing config has no downloads folder yet.

- [ ] **Step 2: Add the folder to `ioshi/hi-hardware/net/syncthing.nix`**

After the existing `folders.docs` block, add:

```nix
      folders.downloads = {
        id = "downloads";
        label = "downloads";
        path = "/home/scott/Downloads";
        devices = [ "datacore" ];
      };
```

(Same shape as `folders.docs` above it. No versioning here — datacore keeps the versions.)

- [ ] **Step 3: Commit and propagate**

```bash
cd /home/scott/dotfiles
git add ioshi/hi-hardware/net/syncthing.nix
git commit -m "feat(sync): downloads share eminix-side (Phase 2)"
git push
ssh datacore "cd ~/projects/dotfiles && git pull --ff-only"
ssh eminix "cd ~/dotfiles && git fetch origin && git merge --ff-only origin/main"
```

- [ ] **Step 4: Rebuild eminix**

```bash
ssh eminix "sudo nixos-rebuild switch --flake ~/dotfiles#eminix" 2>&1 | tail -5
```

Expected: activation completes; syncthing unit restarts. (Timeout generously — 10+ min if the flake inputs moved.)

- [ ] **Step 5: Verify eminix offers the folder**

```bash
ssh eminix "grep -A2 'folder id=\"downloads\"' ~/.local/state/syncthing/config.xml | head -3; systemctl is-active syncthing"
```

Expected: a `<folder id="downloads" … path="/home/scott/Downloads"` line and `active`. (datacore's UI would now show "eminix wants to share downloads" — ignored; Task 2 configures it properly via API.)

---

### Task 2: datacore — accept the folder with versioning, verify end-to-end

**Files:** none in repo (remote ops via REST API; no commits).

**Interfaces:**
- Consumes: eminix offering folder id `downloads` (Task 1).
- Produces: bidirectional `~/Downloads` sync with staggered versioning on datacore — the spec's Phase 2 success criterion.

- [ ] **Step 1: Clone the `docs` folder config as the template**

```bash
ssh datacore 'APIKEY=$(grep -oP "(?<=<apikey>)[^<]+" ~/.local/state/syncthing/config.xml); \
  curl -s -H "X-API-Key: $APIKEY" 127.0.0.1:8384/rest/config/folders/docs \
  | jq ".id=\"downloads\" | .label=\"downloads\" | .path=\"/home/scott/Downloads\"" > ~/downloads-folder.json; \
  jq -r ".id, .path, .versioning.type, .versioning.params.maxAge" ~/downloads-folder.json'
```

Expected output (proves device set + versioning carried over):

```
downloads
/home/scott/Downloads
staggered
2592000
```

- [ ] **Step 2: PUT the new folder**

```bash
ssh datacore 'APIKEY=$(grep -oP "(?<=<apikey>)[^<]+" ~/.local/state/syncthing/config.xml); \
  curl -s -X PUT -H "X-API-Key: $APIKEY" -H "Content-Type: application/json" \
    -d @~/downloads-folder.json 127.0.0.1:8384/rest/config/folders/downloads && echo PUT-OK; \
  curl -s -H "X-API-Key: $APIKEY" 127.0.0.1:8384/rest/config/restart-required'
```

Expected: `PUT-OK` then `{"requiresRestart":false}` (config applies live). If `true`, restart: `systemctl --user restart syncthing` on datacore.

- [ ] **Step 3: Verify the folder is healthy on datacore**

```bash
ssh datacore 'APIKEY=$(grep -oP "(?<=<apikey>)[^<]+" ~/.local/state/syncthing/config.xml); \
  sleep 10; curl -s -H "X-API-Key: $APIKEY" "127.0.0.1:8384/rest/db/status?folder=downloads" | jq ".state, .errors"'
```

Expected: `"idle"` (or `"scanning"` briefly) and `0`.

- [ ] **Step 4: End-to-end sync test (eminix → datacore)**

```bash
ssh eminix "echo phase2-sync-test-$(date +%s) > ~/Downloads/phase2-sync-test.txt"
sleep 45
ssh datacore "cat ~/Downloads/phase2-sync-test.txt"
```

Expected: the same `phase2-sync-test-<epoch>` line appears on datacore.

- [ ] **Step 5: Versioning test (edit on eminix → old version archived on datacore)**

```bash
ssh eminix "echo REPLACED >> ~/Downloads/phase2-sync-test.txt"
sleep 45
ssh datacore "ls ~/Downloads/.stversions/ && grep -l phase2-sync-test ~/Downloads/.stversions/* | head -1"
```

Expected: `.stversions/` on datacore contains a dated copy of `phase2-sync-test.txt` (the pre-edit version). This proves the hub keeps history.

- [ ] **Step 6: Clean up test artifacts**

```bash
ssh eminix "rm ~/Downloads/phase2-sync-test.txt"
sleep 45
ssh datacore "ls ~/Downloads/phase2-sync-test.txt 2>&1; rm -rf ~/Downloads/.stversions/phase2-sync-test* ; rm ~/downloads-folder.json"
```

Expected: `No such file or directory` for the live file on datacore (deletion synced; the delete itself may add one more `.stversions` entry first — removing those is the cleanup).

- [ ] **Step 7: Confirm all three personal shares carry staggered versioning (spec criterion)**

```bash
ssh datacore 'APIKEY=$(grep -oP "(?<=<apikey>)[^<]+" ~/.local/state/syncthing/config.xml); \
  for f in docs pi-agent downloads; do \
    printf "%s: " $f; curl -s -H "X-API-Key: $APIKEY" 127.0.0.1:8384/rest/config/folders/$f | jq -r ".versioning.type"; \
  done'
```

Expected:

```
docs: staggered
pi-agent: staggered
downloads: staggered
```
