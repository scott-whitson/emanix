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
  any run. Syncthing's `default` -> `~/Sync` folder is likewise vestigial, and
  the `websites` and `work-docs` folders are nested inside the already-synced
  `docs` tree.
- **Personal projects have no transport.** The model says personal projects are
  git-transported rather than synced, but six of them have no remote to
  transport over, and three have no git history at all.

## Decisions

| # | Decision |
|---|---|
| D1 | Personal projects mirror rafik <-> datacore by **git transport only**. Every one becomes a real repo with a GitHub remote and is cloned on both hosts. `websites.git` is exempt — see below. |
| D2 | Archives do **not** mirror. `~/projects/_archive` (6.5G) and `~/projects/archive/waybar` move to `/srv/data/_archive/projects/`, out of `$HOME` entirely. |
| D3 | `chstr`, `swc` and `typ` are treated as working-tree-is-truth: `.gitignore`, `git init`, one initial commit, push, clone to both hosts. Their history is unrecoverable and is not mourned. |
| D4 | whistle's `~/clients` moves to `~/projects/clients` and is **excluded from Syncthing**, keeping the four-directory rule without replicating 4.4G of client data to personal machines. |
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
`work-projects`. Removed from datacore: `default` -> `~/Sync`, `websites`,
`work-docs`. Added to whistle's `projects/.stignore`: `/clients`.

## Execution

The spine: **nothing is deleted until everything is on GitHub and verified.**

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

Then confirm `/srv/data/_archive/projects/` falls inside the Backrest/restic
backup selection. A moved 6.5G that lands outside the backup policy is worse
off than where it started.

### Phase 4 — Retire dead mechanisms, datacore

- Delete `scripts/work_sync.sh` from `datacore-config`; commit and push.
  Without this, `~/work` regenerates.
- Remove the `default`, `websites` and `work-docs` Syncthing folders.
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

**R1 — rafik is behind origin, and the staged installer ISO predates the keys
fix.** Corrected after fetching: the 2026-08-21 keys-baking fix `4e1197d` **is**
on `origin/main`. An earlier reading of this as fifteen stranded commits on
whistle was an artefact of a stale remote-tracking ref. whistle's only unpushed
commits are the two that carry this spec, and the verified
bare-relay-through-datacore recipe covers them.

What does remain: rafik's `~/projects/eminix` last committed 2026-08-19 with
zero unpushed, so it predates `4e1197d` and **needs a pull**. And
`rafik:~/eminix-installer.iso` is dated 2026-08-16, which predates the keys fix
outright, while the project record says an ISO was built and verified with the
private halves physically inside the image on 2026-08-21. Those two facts
cannot both describe the same file, so either the verified ISO lives at another
path or that file is not the one staged for install day. rafik went unreachable
mid-investigation, so this is unresolved.

**Consequences for this plan:** pull rafik's eminix before Phase 2 compares
rosters, and **do not delete `eminix-installer.iso` in Phase 6 until the
install-day ISO is positively identified** — Phase 6 already defers it past
cutover, which is the safe ordering regardless.

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

## Out of scope

- The `~/docs` and `~/projects/work` Syncthing trees, which are not drifted.
- The `~/docs/org/websites` tree and its bare `websites.git` remote, whose
  layout is a settled decision. Only its cutover migration is flagged above.
- The eminix bundled-installer project.
- Rotating the ConnectWise keys scrubbed from ecomms history.
