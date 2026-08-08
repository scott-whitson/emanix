# eminix Convergence — Design

> **Status:** Design approved 2026-08-07. Awaiting implementation plan.
> **Goal:** `eminix` becomes purely the name of the distribution. Every machine
> is an eminix instance composed through one code path, and stow is retired.

## Problem

The repo is mid-migration and it shows in three ways.

**`eminix` names two different things.** It is both the distribution (`profiles/eminix.nix`,
"compose an eminix nixosSystem" in `lib/mkHost.nix`) and the hostname of the T14
daily driver. Every sentence about the project has to disambiguate.

**Only half the hosts go through `mkHost`.** `zord-old` and `eminix` do; `whistle`
and `datacore` are hand-composed inline in `flake.nix`, carrying ~90 lines of
module lists that duplicate what `mkHost` exists to provide. They were excluded
because `profiles/eminix.nix` is not actually a distro definition — it is a
*workstation* definition (it imports `desktop.nix`, `ewm.nix` and `ollama.nix`),
so a headless server or a WSL instance cannot use it.

**Two config systems own the home directory.** Home Manager manages most things,
but GNU stow still deploys `base/`'s twelve packages via `dot-restow`. Five of
those packages (`btop`, `lf`, `mpv`, `yt-dlp`, `claude`) have Home Manager
modules that exist but sit commented out of `ioshi/i-intelligence/default.nix` —
so the module and the stow copy are maintained in parallel and only one wins.

## Decisions

| Question | Decision |
|---|---|
| What is `eminix`? | The distribution only. Never a hostname. |
| T14 hostname | `rafik` — Arabic *rafīq*, the companion on a journey; the root Swahili `rafiki` comes from |
| `zord-old` | **Deleted.** Superseded by `datacore` on the same physical HP |
| Role modelling | Explicit role profiles, not option flags or capability booleans |
| Stow | Full retirement. `base/`, `dot-restow` and `dot-sync` all removed |
| Rollout order | `datacore` → `whistle` → `rafik` |

### Why role profiles over the alternatives

Two other shapes were considered. A single profile with a `scott.role` enum and
`mkIf` throughout scatters conditionals across every module — the exact pressure
that produced the existing `desktop.nix`/`server.nix` split, so adopting it would
undo a decision the repo already got right. Capability booleans on `mkHost`
(`{ desktop = true; ewm = false; }`) allow states that mean nothing (EWM without
a desktop) and push "what is a workstation" back out to every call site, which is
what this work is trying to centralise. There are four machines in three
well-understood shapes, not an open-ended matrix; naming the shapes is cheaper
than parameterising them.

## Target architecture

```
profiles/
  eminix.nix              common core: os base + net + secrets + nix settings
  roles/
    workstation.nix       desktop.nix + ewm.nix + ollama.nix + firstboot.nix
    server.nix            os-system/server.nix, headless
    wsl.nix               nixos-wsl module, no hardware layer

lib/mkHost.nix            { hostName, role, hardware ? null, extraModules ? [] }

hosts/
  rafik/                  role = workstation   (T14 daily driver)
  datacore/               role = server        (HP home server)
  whistle/                role = wsl           (work laptop)
```

`profiles/eminix.nix` shrinks to what is true of *every* eminix box. Roles supply
what is true of a *kind* of box. `mkHost` gains `role` and makes `hardware`
optional so `whistle` — which has no hardware layer — can stop being a special
case in `flake.nix`.

### Role as the single source of truth

`scott.gui`, `scott.ewm.enable` and `scott.dotfiles.profile` currently encode the
same fact three times, set by hand per host, with nothing preventing contradiction
(`gui = true; ewm.enable = false;` is expressible and meaningless). The role
profile sets all three. Hosts may still override surgically where they genuinely
differ — `whistle`'s `ghostty.enable = true` despite `gui = false` is a real
exception and is preserved deliberately.

### What stays per-host

`system.stateVersion` (records the release a machine was first installed under;
must never be shared or bumped), disko layout, the hardware module, and genuine
one-offs.

## Phases

Each phase builds all hosts, lands independently, and is verified before the next
begins.

### Phase A — rename `eminix` → `rafik`

In-repo this is mechanical: the `nixosConfigurations` key, `hosts/eminix/` →
`hosts/rafik/`, and `ioshi/hi-hardware/disko/eminix.nix` → `disko/rafik.nix`. The
hostname itself already flows from `mkHost`'s `hostName` argument, so no module
hardcodes it.

The off-repo surface is the risk, and is why this phase runs first — while the
rest of the config is still in its known-good shape:

- Tailscale node name and its MagicDNS entry
- `ssh_config` aliases on the other machines
- `known_hosts` entries
- Syncthing device label (cosmetic — Syncthing identifies devices by key, not name)

**Read before touching:** `secrets/secrets.nix`. If agenix keys secrets by
hostname rather than by host public key, a rename can lock the machine out of its
own secrets. This must be confirmed, not assumed.

### Phase B — role profiles

Restructure per the target architecture above, and fold `whistle` and `datacore`
into `mkHost`. This is a **pure refactor**: no host changes behaviour.

`zord-old` is deleted in this phase. That unblocks a cleanup it was holding
hostage: `ioshi/hi-hardware/hp-15-ef2013dx.nix` is currently pinned byte-identical
so `zord-old`'s derivation path does not move, which forced `datacore` to
`mkForce` its own `fileSystems`, `swapDevices` and `luks.devices` in `flake.nix`
rather than the hardware file simply being correct. With `zord-old` gone those
overrides fold into the hardware module and stop being workarounds.

**Verify:** `whistle`'s Syncthing port overrides (GUI 8385, listen 22001) exist
because it shared a network namespace with the Debian WSL distro. That distro is
retired. Determine whether these are now vestigial rather than carrying them
forward by default.

### Phase C — stow retirement

`base/`'s twelve packages resolve three ways:

| Package | Disposition |
|---|---|
| `bin` (16 scripts), `pi` (20 files) | Home Manager `mkOutOfStoreSymlink` — stays live-editable without a rebuild |
| `btop`, `lf`, `mpv`, `yt-dlp`, `claude` | Activate the dormant modules already in `ioshi/i-intelligence/` |
| `nvim`, `hypr` | Deleted — Emacs is the sole editor, EWM replaced Hyprland |
| `zellij`, `systemd` | **Reconcile, do not port.** Their modules are already active *and* the `base/` copies also deploy. Determine which currently wins before touching either |
| `wireplumber` | Port to a small Home Manager module |

Then `bin/dot-restow`, `bin/dot-sync` and the `stow` package are removed.

`mkOutOfStoreSymlink` is the reason full retirement is safe: it already provides
live-editability without a rebuild (it is how `init.el` works today), so "I need
stow to edit scripts without rebuilding" is not a real constraint.

### Phase D — legacy prune and docs

- Delete `hyprland.nix`, `mako.nix`, `fuzzel.nix` — superseded by EWM
- Verify `scott.standalone` is dead now that the last Debian node is gone; remove if so **(the premise is false — see the as-built correction at the end of this document)**
- `ioshi/i-intelligence/standalone.nix` **stays** — `whistle` depends on it — but its
  name now misleads. It means "non-EWM Emacs", not "foreign distro". Rename accordingly
- `docs/manual/07-nix-roadmap.md` describes the completed Debian→NixOS migration; rewrite or retire
- `home/scott/default.nix` header still says "used by both zord-old (HP) and zord (T14)"
- `README.md` and `docs/manual/01-install.md` reference the retired Debian bootstrap

## Verification

Closure comparison, per phase, for every host:

```
nix build .#nixosConfigurations.<host>.config.system.build.toplevel
```

**Phase B must produce a byte-identical closure path for `rafik`.** If the store
path moves, the pure-refactor claim is false and behaviour changed by accident.
`datacore` and `whistle` legitimately change — they gain the common core — so
those are diffed and reviewed rather than matched.

Phases A, C and D change Home Manager content by design, so their closures move.
For those, verification is behavioural: the relevant service starts, the config
file lands at the expected path with the expected content, and the deleted thing
is genuinely absent.

## Rollout

`datacore` → `whistle` → `rafik`, for phases B, C and D.

`datacore` is the canary: headless, nothing interactive depends on it, physically
accessible if SSH dies, and NixOS generations make rollback a boot-menu choice.
`whistle` is second — WSL rolls back with `nixos-rebuild --rollback` from any
shell with no bootloader involved. `rafik` is last because it is the daily driver.

**Phase A is the exception and runs `rafik` first**, because `rafik` is the machine
being renamed — there is no way to canary a rename on a host that is not changing
identity. The other two hosts follow only to pick up `ssh_config` and `known_hosts`
updates, which are recoverable by editing a text file.

This ordering is a change forced by deleting `zord-old`, which was previously the
cheap thing to break. No disposable host remains, so the order is chosen by
recovery cost instead.

## Out of scope

- Renaming `whistle` or `datacore`. Their names are fine and the churn buys nothing
- Any change to EWM itself (`~/projects/ewm`)
- The `tools/` directory
- `docs/superpowers/specs/` and `plans/` — dated decision records, corrected only where they describe the present rather than the past

## As-built correction (Task 4, 2026-08-07)

The target architecture's `roles/server.nix` (and the plan's Task 3 code for
it) included `ioshi/hi-hardware/net/syncthing.nix`. That module is the
workstation-side syncthing *peer* config — it declares `datacore` as a
remote device with `overrideDevices = true` / `overrideFolders = true` and
folders pointing at device `"datacore"`. `datacore` is the fleet's syncthing
*hub*, not a peer of itself, so importing that module into the server role
made the hub declare itself its own peer and would force its real runtime
`config.xml` to that bogus self-referential set on activation the moment
`settings.devices`/`settings.folders` stopped being empty.

Fixed by removing the import from `roles/server.nix` entirely (a server
gets no syncthing peer config by default) and having `datacore` assert its
own policy explicitly in its own `services.syncthing` block:
`overrideDevices = false; overrideFolders = false;`, with a comment
recording why plain assignments (not `mkForce`) are correct there now that
nothing else sets those options. No other server-role host exists yet, so
this was caught before it could bite one.

## As-built correction (rollout, 2026-08-08)

**This spec's central factual premise about `datacore` was wrong, and it caused
a real defect. Read this before planning the datacore cutover.**

Phase D says "Verify `scott.standalone` is dead now that the last Debian node is
gone", and the Decisions table treats `datacore` as a NixOS host to be rolled
out. Neither is true. At rollout time `datacore` was — and still is — **Debian 13
(trixie)**: no `/etc/NIXOS`, no `nixos-rebuild`, no `/run/agenix`. Its
`nixosConfigurations.datacore` entry is the *target* for a cutover that has not
happened (see `2026-08-05-datacore-nixos-design.md`), and the plan is to build it
on the HP that `zord-old` used to run. The flake has no `homeConfigurations`
output, so its standalone Home Manager profile — last activated 2026-07-20 —
cannot be rebuilt from this repo at all.

The consequence: Task 13 deleted `scott.standalone` reasoning that "every eminix
instance is a NixOS node with agenix". Being a NixOS host with agenix is not the
same as being a *recipient* of a given secret, and `datacore` is neither. `pi.nix`
was left symlinking `~/.pi/agent/auth.json` at `/run/agenix/openrouter-auth` on a
host that can decrypt nothing, which would have replaced a real working file with
a dangling link. Repaired by gating that symlink on a new `scott.pi.enable`
(false in `roles/server.nix`); it failed safe in the meantime, because Home
Manager aborts rather than clobber a file it does not own.

Rollout as actually performed: `rafik` and `whistle` switched; `datacore`
untouched. Rollout order was therefore *not* `datacore → whistle → rafik`.

One further correction, to the verification method this spec leans on: a
byte-identical closure proves nothing changed, but a **changed** closure does not
prove something did. Relocating a module import reorders the buildEnv input list
and moves the derivation hash while package set and file tree stay identical
(measured: 1805 paths either side, clean `find` diff).
