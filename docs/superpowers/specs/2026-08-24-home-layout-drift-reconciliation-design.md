# Home-layout drift reconciliation across rafik, datacore and whistle

Date: 2026-08-24
Status: approved design, not yet executed

## Problem

Three invariants of the three-node home model have drifted:

1. **Home top level.** Every host's `$HOME` should contain exactly `docs`,
   `dotfiles`, `downloads`, `projects`. rafik has three extra entries plus a
   1.4G ISO; Debian datacore has eleven; whistle has `clients` and a stray
   tarball.
2. **Personal projects.** rafik and datacore should hold the same set of
   personal projects under `~/projects`. Only three of eighteen overlap, and
   two of those three disagree.
3. **No duplicate namespaces.** `archive`, `org` and `work` each exist in two
   places at once on some host.

The shared layer is *not* drifted. `~/docs` is identical across rafik and
datacore (Syncthing `docs`), and `~/projects/work` is identical across all
three hosts (whistle's `~/projects` is the same folder). This design does not
touch either.

## Root causes

- **Debian datacore never received `ioshi/i-intelligence/xdg.nix`.** That
  module already encodes the four-directory rule and already documents the
  capital-P `~/Projects` trap. datacore runs home-manager from an older
  configuration without it, so home-manager minted `Projects`, `Music`,
  `Pictures` and `Videos` there. The rule needs no new mechanism — it needs
  applying. The NixOS datacore inherits it by construction.
- **Retired mechanisms were never removed.** `datacore-config/scripts/work_sync.sh`
  is a one-way rsync mirror of whistle's `~/projects` into `~/work`,
  superseded by the Syncthing `work-projects` folder. The script still ships,
  so `~/work` (847M, a strict subset of `~/projects/work`) would regenerate on
  any run. Syncthing's `default` -> `~/Sync` folder is likewise vestigial — an
  empty stock "Default Folder" shared with nobody.
- **Personal projects have no transport.** The model says personal projects are
  git-transported rather than synced, but five of them have no remote to
  transport over, and three have no git history at all. (A sixth,
  `websites.git`, also has no remote — correctly, because it *is* one.)

## Decisions

| # | Decision |
|---|---|
| D1 | Personal projects mirror rafik <-> datacore by **git transport only**. Every one becomes a real repo with a GitHub remote and is cloned on both hosts. `websites.git` is exempt — see below. |
| D2 | Archives do **not** mirror. `~/projects/_archive` (6.5G) and `~/projects/archive/waybar` move to `/srv/data/_archive/projects/`, out of `$HOME` entirely. |
| D3 | `chstr`, `swc` and `typ` are treated as working-tree-is-truth: `.gitignore`, `git init`, one initial commit, push, clone to both hosts. Their history is unrecoverable and is not mourned. |
| D4 | whistle's `~/clients` moves to `~/projects/clients` and is **excluded from Syncthing**, keeping the four-directory rule without replicating 4.4G of client data to personal machines. |
| D6 | **Datacore's backups are repaired first, as a hard gate.** No phase that moves or deletes data runs until a verified snapshot exists. Discovered mid-planning; approved 2026-08-24. |
| D5 | Debian datacore gets **cutover prep only** — repo repair, remotes, pushes, archive relocation. Cosmetic home tidying is skipped there because the box is being replaced; the NixOS host gets a clean home from `xdg.nix`. |

Both hosts authenticate to GitHub as `scott-whitson`, verified. No relay
through datacore is needed; an earlier note claiming rafik lacks a GitHub key
is stale.

## Target state

### Home top level, all hosts

Exactly `docs`, `dotfiles`, `downloads`, `projects`. Enforced declaratively by
`ioshi/i-intelligence/xdg.nix`.

### Personal-project roster (10, identical on rafik and datacore)

| Project | Current state | Action |
|---|---|---|
| `eminix` | rafik only, GitHub remote | clone to datacore |
| `scottwhitson.com` | rafik only, GitHub remote | clone to datacore |
| `datacore-config` | real repo on datacore; on rafik a bare `bootstrap/` dir, not a repo | delete rafik's, clone the real one |
| `elisa` | both, GitHub remote, clean | none. `main` vs `sqlite-vec` is a checkout choice, not drift |
| `minne` | both, GitHub remote, 5 unpushed each, 20 dirty files on rafik | reconcile, push, align |
| `fragpaper` | datacore, 38 commits on `main`, HEAD on an empty `master`, no remote | fix HEAD, create repo, push, clone both |
| `mardy` | datacore, 9 commits on `master`, no remote | create repo, push, clone both |
| `chstr` | datacore, `.git` empty, 75M tree | per D3 |
| `swc` | datacore, `.git` has no objects or refs, 117M tree | per D3 |
| `typ` | datacore, `.git` has no objects or refs, 51M tree | per D3 |

`ni-tests` (rafik, 12K, three loose elisa test files, not a repo) folds into
`elisa` or is deleted. It does not join the roster.

**`websites.git` is exempt from D1 and stays datacore-only.** It is the
deliberate **bare** remote for the `~/docs/org/websites` tree, which Syncthing
replicates; git supplies history there, not replication. `~/projects/websites`
was intentionally eliminated in the 2026-08-14 merge and must not be
recreated, and the repo must not be given a GitHub origin — it *is* the origin.
Its `main` branch reading as "13 unpushed" was a misreading: a bare origin has
no upstream to be ahead of. rafik remains the sole commit host. It is
nevertheless a single copy of that history on a box about to be replaced, so
**migrating `websites.git` belongs in the cutover checklist**, not in this
plan.

### Sizes after `.gitignore`

Each of `chstr`, `swc` and `typ` carries a 51M `.claude/mind.mv2` — 153M of the
243M is agent database, not source. Ignoring `/.claude/` leaves `typ` ~200K,
`chstr` ~24M (including a vendored 21M `stockfish_13_x64_mac`) and `swc` ~67M
(34M `static/images`, 33M `manim`). The stockfish binary and the manim/static
assets need an explicit keep-or-ignore call before the first commit.

**`swc` is live production**, not dead code: it is the FastAPI + Jinja2 +
Tailwind app serving `scottwhitson.com` out of `/srv/swc`. Its 34M
`static/images` is very likely served content and should be kept, not ignored.
Treat its first commit with production care, and note that rafik's separate
`scottwhitson.com` repo is the *weblorg* site of the same name, whose deploy is
currently commented out — two different things sharing a domain name.

### Syncthing

Unchanged: `docs`, `downloads` (rafik <-> datacore), `pi-agent`,
`work-projects`, **`websites` and `work-docs`**. Removed from datacore:
`default` -> `~/Sync` only. Added to whistle's `projects/.stignore`:
`/clients`.

**`websites` and `work-docs` must NOT be removed from datacore.** They look
redundant because their paths sit inside `~/docs`, which rafik syncs whole —
but they are whistle's *peer pairs*, not duplicates. Verified from whistle's
own config: `websites` (`~/docs/org/websites`) and `work-docs`
(`~/docs/org/work`) are each shared `whistle <-> datacore`, and whistle does
**not** sync `~/docs` as a whole. Deleting them on datacore would sever
whistle's only route to the work vault and the websites tree. This asymmetry —
rafik gets the content through its nested whole-`docs` folder, whistle gets it
through two narrow folders — is the three-node model working as designed.

## Execution

The spine: **nothing is deleted until everything is on GitHub and verified.**

### Phase 0A — Repair datacore's backups (HARD GATE)

**Found 2026-08-24 while planning: datacore has had no backup since
2026-08-02** — 22 days, 370G of payload including 129G of family photos, days
before its hardware is replaced. This plan's spine is "nothing is destroyed
until it is safe elsewhere", which is currently false on datacore. Nothing in
Phases 1-7 that moves or deletes data may run until this gate passes.

Four independent defects, all verified:

1. **Backrest has no backup plan.** `~/.config/backrest/config.json` (live —
   `backrest.service` runs as `User=scott`) defines the B2 repo and a retention
   policy but has **no `plans` key at all**. The daemon is up with nothing
   scheduled. 19 snapshots exist, newest `2026-08-02 01:00:09`.
2. **Comsat alerts on heartbeat freshness only.** Its documented conditions are
   heartbeat older than 26h, or missing. A *fresh* heartbeat whose payload says
   `FAIL:snapshot:527h` therefore reads as `ok` indefinitely. Verified:
   `/var/lib/comsat/datacore.backup-status` says `ok` with an 11h-old
   heartbeat. The monitor watches its own liveness, not the thing it monitors.
   **This is why the outage was invisible for 22 days.**
3. **The heartbeat JSON is malformed.** `restic-health-check.sh` writes the
   status file with `>` then `>>`, producing two lines, which
   `restic-heartbeat.sh` interpolates raw into a JSON string value — yielding a
   literal newline inside `"status"`. Any downstream parser chokes, so even a
   status-aware Comsat check could not read it as written.
4. **The documented scope step does not exist.** `05-restic-b2.sh` was reduced
   on 2026-08-18 to installing restic and rclone, delegating backups to
   Backrest, and `20-home-backup-scope.sh` — which `RECOVERY.md` lists as the
   step widening scope to `~/projects`, `~/docs` and `/srv/data` — appears in no
   commit on any branch.

**Intended selection**, from `~/docs/org/Datacore Backups.org`: paths
`/home/scott/` and `/srv/data/`; excludes from `~/.config/restic/excludes.txt`
(present, 29 lines); snapshot daily ~01:00 EDT; prune and check monthly on the
1st; retention hourly 24, daily 30, monthly 12 (already in `config.json`, but
its `forgetPolicy` schedule is `disabled: true`).

**`_archive` is not excluded**, so D2's destination
`/srv/data/_archive/projects/` lands inside the selection once backups run —
which is what makes D2 safe rather than merely tidy.

Gate: a snapshot newer than the gate's start exists in B2, `restic-status`
reports OK, and defect 2 is fixed so the next silent failure is not silent.

### Phase 0 — Preflight, no changes

- **Blocking, requires Scott:** create five empty **private** repos —
  `fragpaper`, `mardy`, `chstr`, `swc`, `typ`. `gh` is authed on no host
  (absent on datacore, not logged in on whistle), so this is web UI or a
  token.
- **Urgent, requires Scott, runs in parallel:** resolve whistle's stranded
  `eminix` commits (see Risks R1). No other phase depends on it, so it does
  not gate this plan — but the imminent datacore install does, which is why it
  belongs in preflight rather than at the end.
- Secret-scan `chstr`, `swc`, `typ`. A filename sweep found no `.env`, key,
  pem or credential files, but these are first-ever pushes of trees that have
  never been under version control; a content scan is required, not optional.
- Write the three `.gitignore` files. Report the stockfish and manim/static
  question to Scott.
- Inspect minne's 20 dirty files on rafik and report. Do not discard.

### Phase 1 — Make everything durable, additive only

1. `minne`: resolve the dirty tree, confirm both hosts' 5 unpushed commits are
   the same commits, push.
2. `fragpaper`: repoint HEAD off the empty `master` onto `main`, add remote, push.
3. `mardy`: add remote, push `master`.
4. `chstr`, `swc`, `typ`: `.gitignore`, `git init`, initial commit, push.

**Gate:** a script walks both hosts and asserts every personal project has a
remote and zero unpushed commits. No later phase runs until it passes.

### Phase 2 — Mirror the roster

- rafik: remove the non-repo `datacore-config`, clone the real one, plus
  `fragpaper`, `mardy`, `chstr`, `swc`, `typ` (~100M post-ignore).
- datacore: clone `eminix`, `scottwhitson.com`.
- Resolve `ni-tests`.

**Gate:** `ls ~/projects` minus `work` is identical on both hosts.

### Phase 3 — Archive off home, datacore

`~/projects/_archive` -> `/srv/data/_archive/projects/`, and `archive/waybar`
with it. `/srv/data` is a symlink to `/home/srv-data`, so source and
destination share the `/home` filesystem and this is an atomic rename — no
6.5G copy, no half-moved window.

Then confirm `/srv/data/_archive/projects/` is actually captured — not merely
"inside the selection" as this spec originally assumed, since Phase 0A found
there was no selection at all. Verify by listing the path inside a real
post-repair snapshot (`restic ls latest`), not by reading config.

### Phase 4 — Retire dead mechanisms, datacore

- Delete `scripts/work_sync.sh` from `datacore-config`; commit and push.
  Without this, `~/work` regenerates.
- Remove **only** the `default` -> `~/Sync` Syncthing folder. Leave `websites`
  and `work-docs` alone — see the Syncthing section; removing them breaks
  whistle.
- Per D5, leave `~/work`, `~/dotfiles-usb-snapshot`, the XDG cruft, the
  pre-home-manager dotfiles and the loose logs and tarballs in place. They are
  simply not migrated at cutover.

### Phase 5 — whistle

Order is load-bearing:

1. Add `/clients` to `projects/.stignore` **in the eminix repo**.
2. Push, rebuild whistle, verify the store symlink updated and Syncthing
   reloaded the ignore pattern.
3. Only then `mv ~/clients ~/projects/clients`.
4. Verify no `clients` directory appears on rafik or datacore.
5. Clear `~/quarterly-snapshot-2026-08-13.tar.gz`.

Reversed, Syncthing begins replicating 4.4G of client data to both personal
machines the moment the directory lands under the share root.

### Phase 6 — rafik tidy

- `~/org/gdocs/Whitsgrove-Shared-Living-Document.org` -> `~/docs/org/`, then
  `rmdir ~/org`. It is an org file; the synced org tree is where it belongs.
- Delete `~/tmp` and `~/ventoy-setup` (24M, refetchable).
- **Keep `eminix-installer.iso` until after datacore install day.** It is
  flake-rebuildable and deleting it before the cutover it exists to serve
  would be self-defeating. Delete it after.

### Phase 7 — Verify and codify

- A drift-check script comparing both hosts' `~/projects` rosters and home top
  levels, suitable for periodic use.
- Confirm the NixOS datacore configuration imports
  `ioshi/i-intelligence/xdg.nix`.

## Risks

**R1 — CONFIRMED: the only installer ISO in the fleet is the pre-fix,
pubs-only build, and it will fail at the HP's console.** Verified 2026-08-24 by
extracting `nix-store.squashfs` from `rafik:~/eminix-installer.iso` and listing
it: the staged eminix flake's `keys/` directory contains **only**
`datacore_host_ed25519.pub`, `rafik_host_ed25519.pub` and
`whistle_host_ed25519.pub`. No private halves. That is precisely the failure
`4e1197d` exists to prevent — `fresh-eminix-install datacore` dies at
`preflight failed: keys`.

Supporting facts, all verified:

- `4e1197d` **is** on `origin/main`. An earlier reading of it as stranded on
  whistle was a stale remote-tracking ref, now corrected.
- rafik's `~/projects/eminix` is at `a71050e` and does **not** contain
  `4e1197d`. It needs a pull.
- Exactly one eminix ISO exists anywhere on rafik, whistle or datacore:
  `rafik:~/eminix-installer.iso`, 1438613504 bytes. Its `/nix/store`
  counterpart is the same size and same single build; there is no second,
  keys-carrying store path. The Aug-16 mtime is when `cp` ran, not proof of
  build date — but the squashfs contents settle it regardless.
- The project record's "built and verified 2026-08-21, private halves
  physically inside the image" does not correspond to any surviving artifact.
  A keys build requires `--impure` with `EMINIX_ISO_KEYS`; either it was never
  retained or it was garbage-collected.

**Required before install day, in order:** pull rafik's eminix to pick up
`4e1197d`; rebuild the ISO with `--impure` and `EMINIX_ISO_KEYS` set; re-verify
by listing the squashfs and confirming private halves are present, **not** by
running `--check-only` on the build host (that check passes spuriously because
`resolve_repo` finds the live checkout, which is what produced the false
Aug-16 verification in the first place); then reflash the stick.

**Consequence for this plan:** Phase 6 must not delete
`eminix-installer.iso` — and now has a stronger reason than caution. It is a
known-bad image whose only remaining value is as a comparison baseline for the
rebuild. Delete it once a verified replacement exists.

**R2 — Secrets in first-ever pushes.** `chstr`, `swc` and `typ` have never
been version-controlled. Precedent: the ionapi leak required a full history
rewrite across every ref. If a content scan finds anything, treat it as
rotate-the-credential, not scrub-and-move-on.

**R3 — `.stignore` ordering in Phase 5.** Covered above; called out separately
because getting it backwards is silent and immediate.

**R4 — minne divergence.** 1.1G, 5 unpushed commits on both hosts and 20 dirty
files on rafik. The one place in this plan needing Scott's judgment rather
than a default.

**R5 — New repos must be private.** All five.

**R6 — Plaintext credentials in the backup stack.** `~/.config/backrest/config.json`
stores the B2 account key and the restic repo password in plaintext, and
`/usr/local/bin/restic-health-check.sh` hardcodes the same B2 credentials in
three separate command invocations. File modes are sane (`0600` scott, and
root-owned respectively) so this is not a live exposure, but the values are
readable by anything running as those users and were exposed to an assistant
context during this investigation. Treat as rotate-worthy on Scott's timeline,
and prefer agenix for both when datacore becomes a NixOS host — see
`reference_agenix_secret_editing`. Not a blocker for Phase 0A.

## Out of scope

- The `~/docs` and `~/projects/work` Syncthing trees, which are not drifted.
- The `~/docs/org/websites` tree and its bare `websites.git` remote, whose
  layout is a settled decision. Only its cutover migration is flagged above.
- The eminix bundled-installer project.
- Rotating the ConnectWise keys scrubbed from ecomms history.
