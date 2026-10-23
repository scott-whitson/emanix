# The GPU Emacs: EWM's pwayl/Skia 31.1 fork, built through emacs-overlay

**Decided** 2026-10-23. **Applies to** `emacs/pwayl.nix`, which
`modules/ewm.nix` imports as the EWM hosts' Emacs base.

## Decision

EWM hosts run an Emacs built from EWM's own fork — upstream
`codeberg.org/ezemtsov/emacs`, branch `wayland-31`, reached through the `ewm`
flake input and built by its `nix/emacs.nix` — whose recipe, flags and
dependencies come from **emacs-overlay's `emacs-unstable` (31.1)**, not from the
channel. `emacs/pwayl.nix` is the only place that expression exists, so the
NixOS tier (the compositor) and the Home Manager tier (the package set) build
the same derivation. It lives in `emacs/pwayl.nix` rather than inside a host's
config for exactly that reason: a second copy anywhere else would quietly give
the fleet two Emacsen that differ by more than their backend.

## Why `emacs-unstable` and not `emacs31`

nixpkgs 26.05 ships Emacs 30.2 and has no `emacs31` attribute at all: `emacs30`
and `emacs30.2` are the newest. EWM's `nix/emacs.nix` is a `callPackage` that
takes an `emacs31` argument, so one has to come from somewhere.
emacs-overlay's `emacs-unstable` is 31.1 built from the same release branch,
and that is close enough because **the fork replaces `src` anyway**: emacs31
only ever contributes the build recipe, the configure flags and the dependency
set, and none of the upstream Emacs source survives.

Verified on this pin: `pkgs.emacs31.name` errors, `pkgs.emacs-unstable.version`
is `"31.1"`, and `pkgs.emacs.version` is `"30.2"`.

## The passthru reconnect is load-bearing

emacs-overlay's `mkGitEmacs` reconnects each build's `passthru.pkgs` to that
build, and EWM's `nix/emacs.nix` calls `.override` on the base — which re-runs
the base recipe. The reconnected `passthru.pkgs` therefore still points at the
base before the fork's `src` override, i.e. an X11 Emacs.

That is not cosmetic. `emacs/packages.nix` builds the distro's Emacs through
`emacsPackagesFor base`, and EWM's own `nix/default.nix` byte-compiles `ewm.el`
with `emacsPackage.pkgs.trivialBuild`. Left un-reconnected, `ewm.el` is compiled
by the other Emacs and a **second full Emacs build** lands in every host's
closure. `emacs/pwayl.nix` restates the reconnect (`pkgs = pkgs.emacsPackagesFor
pwayl`, self-referential by design) so that the package set and the binary are
the same derivation. Verified: the fixed `passthru.pkgs.emacs.drvPath` becomes
the fork, and the resulting closure references only the pwayl output.

## Upstream's `programs.ewm.withSkia` is deliberately not used

The option looks like the intended path and is not. It defaults `emacsPackage`
to `emacs31-pwayl.pkgs.withPackages`, and the `emacs` attribute of that package
set is the base the fork was derived from — so it would install an **X11**
Emacs 31.1, not a pwayl one. That is the same un-reconnected base as above.

On this pin it does not get even that far: `nix/service.nix` builds
`emacs31-pwayl` with `pkgs.callPackage ./emacs.nix { }`, and `pkgs.emacs31` does
not exist in 26.05 (see the `emacs31` note above), so `withSkia = true` fails
to evaluate rather than installing anything. The outcome is worse, not better —
but it also means the drvPath evidence below was obtained by supplying
`emacs31` explicitly, the way `emacs/pwayl.nix` does, not by setting the option.

Evidence, recorded this session on nixpkgs rev `7c8764b` plus emacs-overlay:
`pwayl.pkgs.emacs` was drv `6s8gpgb7` (`pname emacs`, `--with-x`, no Skia)
while the fork itself was `9zmy1zgn` (`--with-pwayl --with-skia`).

`modules/ewm.nix` therefore passes the fork explicitly as `emacsPackage` and
never sets `withSkia`.

## `emanix.emacs.base`: the variant stays the distribution's choice

`emacs/packages.nix`'s `mkEmacs` takes a required `base` and defines no default,
because the base is the host's: the EWM tier runs the pwayl build, the rest of
the fleet a pgtk one. A consumer that has to build something from the package
set itself — dotfiles' `ement`, `mu4e` and `kkp` land in the profile — cannot
name a variant without freezing that choice in the wrong place, so
`home/emacs.nix` declares `emanix.emacs.base`, set by `modules/ewm.nix`
(`pwaylEmacs`) on EWM hosts and by `home/emacs-daemon.nix`
(`pkgs.emacs-unstable-pgtk`, behind `!emanix.ewm.enable`) everywhere else. A
host that sets neither fails to evaluate rather than quietly building the wrong
Emacs.

## Trial evidence

Observed 2026-10-21 through 2026-10-23:

- EWM's fork built clean.
- emanix's full package list built against 31.1 with zero errors, ghostel's Zig
  module, org-roam and the treesit grammars included.
- `tests/init-guard.sh` passes.
- A daemon running the real config reports `emanix/init-error` nil with
  catppuccin applied.
- An EWM compositor launched on the pwayl build mapped per-output frames with
  `window-system` `pwayl`, took keyboard input, and composited Firefox. The
  user's verdict was that it feels fast.

## Exit conditions

- **nixpkgs ships `emacs31`.** The `emacs-unstable` vehicle exists only to
  supply the recipe; a channel `emacs31` replaces it with no other change.
- **Upstream reconnects `passthru.pkgs` itself.** `emacs/pwayl.nix`'s reconnect
  is a workaround for `.override` re-running the recipe; when EWM's base carries
  the fork's package set on its own, the override-and-restate goes.
- **Upstream fixes `withSkia`.** When that option's default `emacsPackage`
  resolves to the pwayl build rather than its un-patched base, the option
  becomes usable and the explicit `emacsPackage` argument can retire.

## A development snapshot after the 2026-10-23 bump

After the 2026-10-23 `ewm` input bump the fork reports `31.1.50` — a
development snapshot on the way to 31.1, not the 31.1 release. That is the
fork's own version string, not the overlay's, and it is why the trial evidence
above is dated rather than current.
