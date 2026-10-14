# Contributing to emanix

emanix is a NixOS distribution where Emacs is the desktop. It is small on
purpose and its rules are load-bearing, most of them negative. This file exists
because those rules were previously discoverable only by reading the comment in
whichever file last depended on them.

Read [`WALKTHROUGH.md`](WALKTHROUGH.md) once first — it explains the two tiers,
`mkHost`, the theme system, the installer and the checks in plain language.
[`README.md`](README.md) is the reference. Neither is required before your first
patch, but one of them will answer the question that brought you here.

## Requirements

- `nix` with flakes and `nix-command` enabled.
- Nothing else. The dev shell carries the linters:

```bash
nix develop                  # nixd, nixpkgs-fmt, deadnix, statix
nix flake check              # compose a throwaway host per role label; run every check
nix flake check --no-build   # the same evaluation, building nothing
nix fmt                      # formatter.${system} == nixpkgs-fmt
```

You do not need to be running emanix, or NixOS, to work on it: no check ever
builds a host closure.

## Where a file goes

**The module system decides.** That is the whole rule.

| Directory | Tier | Example |
| --- | --- | --- |
| `home/` | Home Manager modules | `home/zsh.nix`, `home/emacs.nix` |
| `modules/` | NixOS modules | `modules/base.nix`, `modules/ewm.nix` |
| `emacs/` | The Emacs config and the single build site | `emacs/config.el`, `emacs/packages.nix` |
| `lib/` | Plain-value library and the host composer | `lib/mkHost.nix`, `lib/themes.nix` |
| `checks/` | Derivations `nix flake check` runs | `checks/disk-layout.nix` |
| `tests/` | Shell and Python tests the checks call, or that need a live filesystem | `tests/init-guard.sh` |

A Home Manager module goes in the `imports` list of `home/default.nix`. A NixOS
module is either imported by `emanix.nix` (if every emanix box needs it) or
exported as a flake output (`nixosModules.ewm`) and imported by the consumer.

An option belongs in the file whose concern it is, on the tier whose module
system it belongs to: `emanix.hardware.gpu` is a NixOS option and lives in
`modules/gpu.nix`; `emanix.theme` is a Home Manager option and lives in
`home/theme.nix`. Cross-tier reads are done by reaching through
`config.home-manager.users.${config.emanix.username}` — see the `hmCfg` note in
`modules/ewm.nix` — never by declaring the option twice.

## The rules that are not obvious

These are the ones a reasonable patch can violate and still evaluate.

### 1. emanix is ONE shape

The distribution ships a base system, Emacs, EWM, a shell, a terminal, a theme
system, and the first-boot convention. It does **not** ship a host shape.

That means no role profiles, no hostnames, no usernames (there is deliberately no
default — `emanix.username` fails loudly rather than creating an account), no SSH
keys, no secrets, no disk layouts, no hardware selections, no fleet management.
`profiles/roles/` was deleted on 2026-08-30 for exactly this reason, and the
README's "There are no roles" section is the argument. Do not reintroduce it in
a new spelling.

A fact about a machine — or about a person — belongs in the consuming flake.
A general capability belongs here. Emanix is never a hostname.

The one deliberate exception is named in the README so it does not read as a
leak: `arc` is pinned to `scott-whitson/arc`, a public repository belonging to
the same author.

### 2. `mkHost`'s arguments are invariants; `emanix.role` is an opinion

A value the distribution sets as `mkDefault` is an opinion, and a consumer
outranks it. A value `mkHost` sets from its own arguments is an invariant, and
`mkForce`-style overriding produces an incoherent host. `lib/mkHost.nix`'s
header states which is which; do not move one across the line without saying so.

When you need to beat a `mkDefault` somewhere else in nixpkgs, the house pattern
is `lib.mkOverride 500`: it outranks an upstream `mkDefault true` (1000) and
still loses to a plain definition in a consumer's config. `services.speechd` in
`emanix.nix` is the worked example, including the measurement that justified it.

### 3. Checks are EVALUATED, never built

`role-workstation`, `role-server` and `role-wsl` each compose a throwaway host
through the real `mkHost` and take its `toplevel.drvPath` under
`builtins.unsafeDiscardStringContext`. The derivation is computed; the closure is
never realized. This is deliberate — a workstation closure source-compiles EWM,
and a check that cannot be run safely on the machine you are using is not a
check. Do not "fix" it into a build so it can test more.

### 4. Every check must be capable of failing

A check that passes for every input proves nothing, and this repository has
already shipped one guard that was passing on a mistranscribed layout
(`tests/disk-layout.sh`'s byte counts were a four-digit checksum over
length-preserving edits). If you add a check, add its negative control, or say
in the header why one is impossible.

### 5. A comment states the decision; the working-out lives in `docs/decisions/`

A comment that restates the code is noise. A comment that records *why this
value* is the most valuable thing in the file — but past a few lines it stops
being a comment and starts being an essay, and the essay belongs in a record.

The budgets ([`docs/decisions/README.md`](docs/decisions/README.md)):

| Where | Budget |
| --- | --- |
| File header comment | 12 lines |
| Comment on one binding or attribute | 6 lines |
| Link from code to a record | 2 lines |

Over budget means relocate, never delete. A measurement, a rejected alternative
or a verified claim moves to `docs/decisions/<slug>.md`, and the comment keeps
the decision plus one link. `emanix.nix` (645 MiB of voice data, now
`decisions/speechd.md`) and `modules/ewm.nix` (the two EWM patches, now
`decisions/ewm-patches.md`) are the worked examples.

What stays inline, and why: `emacs/packages.nix` (an ELPA pin that became the
outage) and `tests/init-guard.sh` (two real faults on 2026-08-10) are short
enough to read where they sit.

The consuming repository makes the other choice, deliberately. dotfiles keeps the
measurement and the rejected alternative inline, because it deleted its own
`docs/` archive on 2026-09-20 and committed to reasoning living next to the code
it applies to. A rule that differs between the two repositories is fine; one that
differs silently is not.

### 6. Naming is enforced, not remembered

`i-intelligence/`, `os-system/` and `hi-hardware/` were renamed on 2026-08-30.
`checks/retired-names.nix` fails the build if a live `.nix` file names one as if
it were a current path. `README.md` is the one place that spells the old names,
because it is the one place that explains why they are gone; other files point at
it rather than restating it.

If you rename something, add its old name to that check's `retired` list and
update the README — in the same commit.

## Adding a module

1. Put the file in the tier its module system dictates (see the table above).
2. Wire it: `home/default.nix`'s `imports`, `emanix.nix`'s `imports`, or a
   `nixosModules` output.
3. Declare any option it introduces, with a `description` that says what the
   consumer is choosing.
4. Set config values with the right strength — see rule 2.
5. `nix flake check`. If nothing in the check set evaluates your module, add a
   check that does, or say in the header why it cannot be evaluated.
6. `nix develop -c nixpkgs-fmt --check .`, `deadnix .`, `statix check .`.

## Adding a consumer seam

A seam is an `emanix.*` option a consuming flake is expected to set. The current
set is the table in the README's "The consumer seams". A seam is justified when a
consumer legitimately needs to differ; it is not justified as a convenience for
one consumer's one host. Prefer a value the consumer passes to `mkHost` or a
module the consumer puts in `extraModules` — that is what those are for.

## Naming

- Files: `kebab-case.nix`, descriptive of what the file configures.
- Nix attributes: `camelCase` (`stateVersion`, `homeModules`).
- Options: lower-case, namespaced under `emanix.` or the tier's own root.
- NixOS-level settings keep nixpkgs' spelling exactly (`hardware.enableRedistributableFirmware`).

## Commits

Imperative subject, one concern per commit, and a body that says *why*. This
repository's history is the design record; a commit that only says what changed
throws that away. Reference the file or check that holds the invariant you are
protecting.

## Pull requests

Before opening one:

```bash
nix flake check
nix develop -c nixpkgs-fmt --check .
nix develop -c deadnix .
nix develop -c statix check .
./tests/disk-layout.sh
./tests/installer-modes.sh
EMACS=$(nix build --no-link --print-out-paths .#emacs)/bin/emacs \
  ./tests/init-guard.sh
```

`.github/workflows/ci.yml` runs these, split into a cheap job that runs on every
pull request (which adds a build-free `nix flake check --no-build`) and an
Emacs-building job that runs on `main`. If you change what CI runs, change this
list too.

State in the PR what you measured, and what you rejected. "It works" is not a
description; a `nix store diff-closures` line is.

## Documentation

- `README.md` — the reference contract. It states what the distribution refuses
  to do, which is the most useful part for a stranger.
- `WALKTHROUGH.md` — one read, Simplified Technical English.
- `docs/decisions/` — **maintained.** One record per decision that needs more
  room than a comment can carry: measurements, rejected alternatives, exit
  conditions. If a decision changes, its record changes with it.
- `docs/superpowers/` — **frozen.** History, not instructions. Do not edit these
  to match the present; that destroys the record of what was decided and why.
  `checks/retired-names.nix` exempts them for that reason.
