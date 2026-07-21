# weasel — NixOS-WSL Work Distro Design

**Date:** 2026-07-21
**Status:** Approved design, awaiting plan
**Scope:** Replace the Debian 13 work-WSL distro with a NixOS-WSL distro named
**weasel**, built side-by-side from the dotfiles flake, cut over deliberately,
Debian retired afterward.

## Goal

weasel is a third full `nixosConfiguration` in the dotfiles flake — the same
declarative quality as eminix, on the work laptop. One
`nixos-rebuild switch --flake ~/dotfiles#weasel` updates kernel-to-keybindings
atomically with rollback generations. The Debian+standalone-HM hybrid (foreign
OS underneath, hand-managed docker/syncthing/tailscale) retires.

## Decisions

| Decision | Chosen | Rejected |
| --- | --- | --- |
| Migration | Side-by-side distros, deliberate cutover, Debian kept as fallback until trusted, then unregistered | Clean break (no fallback); keeping Debian forever |
| Dev databases | Declarative `virtualisation.oci-containers` for the four pgvector DBs; one-time `pg_dump`/restore | Plain compose as today; fresh empty DBs |
| Home layer | home-manager as NixOS module (eminix's shape); standalone `scott@work` HM config retires at cutover | Standalone HM on top of NixOS |
| Name | `weasel` (pronunciation of WSL) | — |

## Architecture

### Flake shape

- New input: `nixos-wsl` (github:nix-community/NixOS-WSL), following the
  flake's nixpkgs.
- `nixosConfigurations.weasel` = nixos-wsl module + `hosts/weasel/` +
  home-manager NixOS module importing the existing `ioshi` home layer with
  `scott.dotfiles.profile = "wsl"`, `scott.gui = false` — matching today's
  working `scott@work` exactly (the `gui` flag gates cursor theme, swaylock,
  ghostty, and GUI apps; the pgtk Emacs GUI is installed by the non-EWM
  emacs module regardless and runs under WSLg as it does today).
- weasel is the dotfiles **writer** (as the Debian WSL is today): it edits
  `~/dotfiles` and rebuilds directly from the local clone. No 3-hop
  propagation for its own rebuilds; pushes to GitHub feed datacore/eminix as
  usual.

### Flag refactor (prerequisite)

`scott.standalone` today conflates two meanings: "foreign OS under HM" and
"Emacs without EWM." weasel is NixOS (not standalone) but has no EWM. Split:

- `scott.ewm.enable` (default false): gates EWM — the exwm-style modules,
  launch hooks, and EWM-only keybindings. eminix sets it true.
- `scott.standalone` keeps only the foreign-OS meaning (datacore, and the
  Debian WSL until cutover): HM-owned emacs daemon service, no agenix, etc.
- The emacs-minus-EWM build currently defined in `standalone.nix` becomes the
  non-EWM default so weasel and the standalone hosts share it; eminix's EWM
  emacs remains gated behind `scott.ewm.enable`.

**Gate:** eminix's `system.build.toplevel.drvPath` must be byte-identical
before/after the refactor (known technique from Phase 1; list order in
`home.packages` is load-bearing — gate with in-place `lib.optional` splices,
never reorder).

### System layer (`hosts/weasel/`)

- **nixos-wsl:** systemd enabled; `wsl.wslConf` carries the current
  hand-tuned `/etc/wsl.conf` settings declaratively —
  `appendWindowsPath = false` and the plan9 `metadata` mount options
  (2026-05-13 tuning) — plus hostname `weasel`. Default user `scott`.
- **Docker:** `virtualisation.docker.enable = true` with
  `daemonSettings.builder.gc = { enabled = true; defaultKeepStorage = "25GB"; }`
  (the cap installed by hand on Debian 2026-07-21, now declarative).
- **Dev databases:** `virtualisation.oci-containers.backend = "docker"`;
  ONE declarative container — `pearl-platform-db` (image
  `pgvector/pgvector:pg16`, host port 5434, the project's long-lived DB),
  volume as a plain bind mount under `/var/lib/pearl-db` (no named-volume
  opacity). The other three current DBs (`chat-interrupt-db` :5435,
  `kb-cores-db` :5444, `ap-automation-phase1-db`) are **branch-scoped
  worktree DBs** — they stay compose-managed, recreated on demand per
  worktree, their data migrated at cutover only if the branch is still
  alive. (Decision revised 2026-07-21 during planning, with approval: the
  original "all four declarative" assumed four independent projects; three
  turned out to be worktrees of pearl-platform, and baking branch-scoped
  DBs into the flake would mean a flake edit per feature branch.)
- **Tailscale:** `services.tailscale.enable = true` — real tailscaled
  (kernel tun works in WSL2), replacing the userspace daemon. One-time
  `tailscale up` auth on weasel (new node).
- **Syncthing:** stays HM-level (`ioshi/i-intelligence/syncthing.nix`, already
  gated on the `wsl` profile) — weasel inherits it unchanged. weasel is a
  **new syncthing device** (new ID); see cutover.
- **nix-ld:** `programs.nix-ld.enable = true` — vendor binaries (npm native
  modules, downloaded tools) run without FHS patching. Pre-empts the classic
  first-week NixOS papercut.
- **agenix:** module wired in; no secrets migrate at cutover (the WSL
  standalone config carries none today). The machinery existing means future
  secrets (e.g. pi auth) go encrypted-in-repo instead of hand-placed.

### Home layer

Unchanged by design: the `ioshi` modules with profile `wsl` produce the same
emacs daemon (pgtk, minus EWM), zsh (`ec`/`et` Wayland-first functions),
git, zellij, claude, pi, and syncthing config as today. The only home-layer
change is mechanical: delivered via the HM NixOS module instead of
`home-manager switch`.

## Cutover choreography

Ordered; single-writer discipline is the invariant.

1. **Build:** import the NixOS-WSL tarball as distro `weasel` (vhdx sparse
   from day one: `wsl --manage weasel --set-sparse true`), clone dotfiles
   from GitHub, first `nixos-rebuild switch --flake .#weasel`.
2. **Smoke test first, before any data moves:** WSLg + pgtk emacs (`ec`) —
   this is the highest-risk integration (GPU/GL plumbing via `/usr/lib/wsl`).
   If it fails, weasel development pauses with zero blast radius.
3. **Syncthing join:** add weasel's device ID to datacore's `work-projects`
   and `work-docs` folders (REST API recipe from Phase 3), let it sync to
   completion. Debian remains the writer throughout.
4. **Write handoff (one moment):** stop editing on Debian; verify syncthing
   idle on both; from then on weasel is the writer of `~/projects` and
   `~/docs/org/work`. Debian's syncthing is stopped and its device removed
   from datacore's folders.
5. **Databases:** after the last Debian write, `pg_dump` each of the four
   DBs on Debian, restore into weasel's declarative containers, re-run each
   project's checks against them.
6. **`~/clients` and unsynced home state:** one-time local copy Debian →
   weasel (tar stream between distros or via a Windows temp path, then
   delete the temp) of an explicit list: `~/clients`, `~/.ssh` (weasel
   reuses the existing key — it must authenticate to GitHub before it can
   even clone dotfiles, so this lands early, with step 1), `~/.claude`
   (sessions + memory), `~/.pi`, `~/.gitconfig.local`, zsh history. The
   list is enumerated in the plan; nothing else copies — everything other
   home content arrives via syncthing or the flake. `~/clients` still
   never syncs, never leaves the laptop.
7. **Odds and ends:** `~/dotfiles` fresh clone (verify no unpushed work on
   Debian first); Windows Terminal profile for weasel + default distro
   switch; `wsl --shutdown` choreography coordinated around live Claude
   sessions as usual. GlazeWM needs nothing (the msrdc rule covers all WSLg
   windows).
8. **Trust period:** Debian sits dormant (not deleted) while weasel proves
   out — target one work week of daily use.
9. **Retire:** `wsl --unregister Debian` reclaims its ~65 GB vhdx. The
   `scott@work` standalone HM config and any Debian-only conditionals are
   removed from the flake in a cleanup commit.

## Risks

| Risk | Mitigation |
| --- | --- |
| WSLg + pgtk emacs breaks on NixOS | Smoke-tested at step 2, before any migration; Debian untouched |
| SentinelOne EDR reacts to a new distro / heavy Nix builds | Known failure modes documented (wslservice spin, relay spin); same workarounds apply; nothing about weasel increases exposure |
| Sync split-brain during side-by-side | Single-writer invariant + explicit write-handoff step; datacore versioning (30d) as the net |
| DB drift between dump and cutover | Dump happens *after* the write handoff, when nothing writes to Debian |
| Flag refactor perturbs eminix | drvPath identity gate, proven technique |
| Corporate-managed Windows blocks distro import | Import is per-user (no admin); the existing Debian distro was imported the same way |

## Success criteria

- `nixos-rebuild switch --flake ~/dotfiles#weasel` builds and switches
  cleanly on the work laptop; eminix drvPath unchanged by the flag refactor.
- `ec` opens the pgtk emacs GUI under WSLg; org-roam finds the work vault;
  magit, zellij, claude, pi all function as on Debian.
- All four DBs answer on their compose-era ports with migrated data;
  `docker system df` build cache stays under the 25 GB cap.
- `~/projects` and `~/docs/org/work` identical on weasel/datacore/eminix;
  weasel is the sole writer; Debian's device removed from datacore.
- tailscaled (non-userspace) connects; WSL↔datacore direct connection
  (QUIC or better) confirmed.
- After retirement: Debian unregistered, its vhdx gone, `scott@work`
  standalone config removed, and the flake still evaluates cleanly with
  weasel alongside all existing hosts and datacore's standalone config.

## Out of scope

Datacore's NixOS conversion (separate parked project); EWM under WSLg;
changes to the sync topology; Windows-side automation beyond the Terminal
profile.
