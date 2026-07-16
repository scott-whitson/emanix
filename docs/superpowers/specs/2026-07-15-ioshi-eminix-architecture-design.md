# ioshi / eminix — Ecosystem Architecture Design

**Date:** 2026-07-15
**Status:** Design — awaiting review
**Scope:** North-star architecture for the whole modernization. Individual
phases (A–E) each get their own spec + implementation plan; this document is
the map they hang on.

## Concept

- **ioshi** — the *stack*: a reusable 3-concern model for the machine.
  - **i — intelligence interface:** Emacs + the pi agent (the human/AI workspace).
  - **os — operating system:** NixOS (the reproducible system layer).
  - **hi — hardware / internet:** the physical machine + connectivity substrate.
- **eminix** — the concrete *platform* both machines run: **em**acs + l**in**ux +
  n**ix**OS (with EWM), a portmanteau nodding to minix. `ioshi` is the pattern;
  `eminix` is this instance of it — the daily driver.

The repo currently splits modules by *technology* (`modules/nixos/` vs
`modules/home-manager/`). This design re-splits them by *concern* (i/os/hi),
which is how the machine is actually reasoned about, and gives the remaining
modernization work a spine: each piece becomes "build out a layer," not a
bolt-on.

## Decisions (locked during brainstorming)

- ioshi is the **literal architecture**, not just naming. `eminix` is composed
  from the layers.
- **Host naming:** T14 host renamed `zord` → `eminix` (free — not yet
  installed). `zord-old` keeps its name (live tailnet node; renaming disrupts
  MagicDNS/keys). Both instantiate the eminix platform.
- **eminix v1 scope:** i/os/hi rearchitecture + concept docs + **reproducible
  install runbook** + **one-Emacs unification** + **secrets management**.
  Impermanence is **deferred to v2**.
- **Secrets:** **agenix** (age-based, one file per secret, minimal deps).
- **One-Emacs placement:** **system-owned** — the EWM system module builds the
  single Emacs binary at `/run/current-system`; Home Manager contributes only
  the elisp config + package list.

## Target repository structure

```
ioshi/
  i-intelligence/
    emacs/            # ONE unified emacs: package set + elisp config
    ewm.nix           # EWM system integration (tty1 launch, seat, PAM)
    pi.nix            # pi agent
    theme/            # theming; the dotfilesLib.theme lib gets a real home here
    workspace/        # zsh, ghostty, helix, lf, mpv, … (user tools)
  os-system/
    base.nix          # nix settings, gc, locale, users, zsh-at-system
    desktop.nix       # docker, steam, printing, audio, bluetooth, libinput, networkmanager
  hi-hardware/
    lenovo-t14-gen5-amd.nix   # via nixos-hardware
    hp-15-ef2013dx.nix
    disko/            # per-machine disk layouts
    net/              # tailscale, headscale join, syncthing, resolved
profiles/
  eminix.nix          # the platform = i + os composed (host supplies its hi)
hosts/
  eminix/             # T14 = eminix profile + hi/lenovo-t14 + disko/eminix
  zord-old/           # HP  = eminix profile + hi/hp-15 + its luks layout
secrets/              # agenix-encrypted (tailscale authkey, …) + secrets.nix
lib/                  # mkHost helper + theme lib
docs/ioshi/           # concept doc + eminix install runbook
flake.nix
```

### HM vs NixOS within concerns

Concerns cross the Home-Manager/NixOS boundary (the "i" layer has both the EWM
system launch hook / PAM / `hardware.graphics` *and* the user's Emacs config +
zsh). Each concern module that needs both exposes a **`system`** module and a
**`home`** module. `lib/mkHost` wires the `system` set into `nixpkgs.lib.nixosSystem`
and the `home` set into `home-manager.users.scott`. Net effect: "everything
about Emacs" lives in `ioshi/i-intelligence/`, without fighting either module
system.

### `lib/mkHost`

A helper that takes a host's `{ hostName, hardware, disko, extraModules ? [] }`
and returns a `nixosSystem`, composing: the eminix profile (i + os `system`
modules), the chosen `hi` hardware + disko + net modules, the shared
`nixpkgsModule` (from Phase 0), disko/home-manager/agenix modules, and the HM
`home` module set. Hosts become a few lines of declaration.

## Phase sequence

**Phase 0 — Foundation & correctness. ✅ DONE + BUILT** (separate spec/plan).
Overlay reaches NixOS, one HM wiring, one nixpkgs, deduped cross-cutting config,
disko single-source install fix. Both systems build clean on real Nix.

**Phase A — ioshi rearchitecture.**
Carve `modules/*` into `ioshi/{i,os,hi}/`; introduce `profiles/eminix.nix` and
`lib/mkHost`; rename `zord` → `eminix`. Behavior-neutral where possible — the
drv for each host should stay invariant across pure moves (guarded the same way
Phase 0 was). The rename is the one intentional change. Structure lands first,
before any new behavior.

**Phase B — one-Emacs.**
Collapse the two Emacs builds (system `ewm.nix` + HM `emacs.nix`) into a single
system-owned package set in `ioshi/i-intelligence/emacs/`; HM supplies only the
elisp config directory + package list. Remove the hand-mirrored org ELPA pin.

**Phase C — hi hardening.**
Add `nixos-hardware` input; use the Lenovo T14 AMD module for `eminix`, dropping
hand-rolled bits it tunes. Consolidate `net/` (tailscale/headscale-join/
syncthing/resolved) into the `hi` layer.

**Phase D — secrets (agenix).**
Add agenix; move the Tailscale authkey (currently plaintext to
`/var/lib/tailscale-authkey`) and any other sensitive values into
`secrets/*.age`, decrypted at activation. Establish the recipient keys (host +
scott).

**Phase E — reproducible install runbook.**
Document + dry-run-test a single command path to reprovision the T14 from bare
metal: boot installer → `disko` partition → `nixos-anywhere`/`nixos-install
--flake .#eminix` → first boot into eminix. Lives in `docs/ioshi/`.

## Definition of done (eminix v1)

- The T14 can be installed from scratch via the runbook into a booting eminix
  daily driver.
- Repo is organized as ioshi (i/os/hi + profiles + mkHost).
- Emacs is a single build.
- No plaintext secrets in the repo.
- Both `eminix` and `zord-old` `nix build` clean on real Nix.
- Impermanence is **not** in v1 (v2 candidate).

## Constraints / operating reality

- **No Nix on the WSL authoring box.** All eval/build verification runs on
  zord-old (the only Nix host; datacore is not NixOS). Sync path: edit here →
  `git bundle` → scp → `~/dotfiles-build` clone on zord-old → `nix eval/build`.
  zord-old can't reach the private GitHub repo non-interactively; the bundle is
  the conduit.
- **Deploy needs sudo on zord-old** (its `/etc/dotfiles` `.git` is root-owned;
  `sudo -n` is off). Resetting `/etc/dotfiles` to the canonical line and
  `nixos-rebuild switch` is a manual step Scott runs.
- **Canonical line = GitHub `main`.** The old divergent zord-old working tree is
  backed up on zord-old (bundle + tar) and superseded.

## Per-phase flow

Each phase A–E: brainstorm (if needed) → spec → implementation plan → execute
on zord-old with per-task eval/build verification → commit + push. Phase A is
next.
