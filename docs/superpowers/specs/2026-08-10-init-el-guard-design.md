# Guarding init.el so one bad form cannot take the desktop down

**Date:** 2026-08-10
**Status:** approved (design), not yet implemented
**Prior art:** `docs/manual/06-architecture.md` (liveElisp), `2026-08-09-theming-high-contrast-design.md`

## Goal

Make a failure anywhere in Scott's Emacs configuration cost the failing feature
and nothing else. On `rafik`, Emacs is the Wayland compositor — an unhandled
error in `init.el` is not a config inconvenience, it is losing the desktop.

## Why this exists

On 2026-08-10 the same visible symptom — no top bar, `s-d` dead, no window
navigation — was produced twice by two unrelated faults:

1. **A read-time failure.** An unbalanced paren in an edit to the `gdocs` block
   left `(use-package gdocs` unclosed. Emacs read to EOF and aborted the whole
   file: `End of file during parsing`.
2. **A load-time failure.** A bare `(require 'gdocs)` signalled, because
   `~/.config/emacs/elpa` is not on `load-path` — this Emacs takes its packages
   from Nix, so `package-activate-all` never runs and package-vc's download is
   invisible to `require`.

Both aborted `init.el` partway. Both times the visible symptom pointed somewhere
other than the fault: the first presented as "the theme system is broken", the
second as "things like `s-d` aren't working". Neither was.

The structural cause is that everything is one file with no boundary. 8
`scott/ewm-*` window-management commands and the modeline activation sit at
lines 498–605, **below all 14 bare `require` calls** (vertico, orderless,
marginalia, consult, corfu, avy, meow, dirvish, magit, treesit, apheleia, org,
org-id, disp-table). Any one of those failing takes the desktop with it.

## Facts that shape the design

Established by inspection 2026-08-10, not assumed:

- **`liveElisp` means edits are live.** `xdg.configFile."emacs/init.el"` is an
  out-of-store symlink into the checkout (`emacs.nix`), so editing the repo file
  changes the running config with no rebuild. **Both incidents were uncommitted
  live edits.** A build-time or pre-commit check would have caught neither.
  Runtime resilience is the only protection that matches the workflow.
- **Read-time failures cannot be caught from inside the file.** No
  `condition-case` in `init.el` can guard a paren error in `init.el`, because
  nothing in it runs. The guard must live in a *different* file.
- **The compositor is already resilient.** Emacs is launched
  `--fg-daemon --eval (require 'ewm) --eval (ewm-start-module)`, and Emacs
  processes `--eval` arguments *after* loading init. EWM therefore starts even
  when init fails — which is why a screen survived both incidents. What dies is
  Scott's own layer: modeline, launcher, slot commands, theme.
- **`lisp/` modules already survive independently** — 8 files, each `require`d
  separately. `scott-modeline.el` (12 defuns), `scott-launcher.el`,
  `scott-theme.el` and `scott-ewm.el` are all intact even when init.el aborts;
  they simply never get required.
- **Only 4 of 18 `require` calls are guarded** (`org-roam`, `scott-elisa`,
  `scott-ewm`, and `gdocs` as of tonight's fix). The other 14 are bare. Counted
  2026-08-10; two further `require` mentions are inside comments.

## Decisions (with rationale)

1. **A loader outside the file that can break.** `init.el` becomes a small
   loader that `load`s `config.el` inside a `condition-case`. A signal raised
   *inside* a loaded file propagates to the caller, so this catches read-time
   and load-time failures alike — the only structure that covers both.

   Rejected: guarding the 14 bare requires in place (contains load failures
   only, does nothing for a paren error — which was the worse of the two
   incidents). Rejected: reordering so desktop-critical forms come first (zero
   machinery, but it is only a convention; the next form added at the top
   silently reintroduces the risk, and it still leaves parse errors fatal).

2. **Extract the window-management commands into `lisp/` first.** The 8
   `scott/ewm-*` functions move to `lisp/scott-ewm-slots.el`. They are
   self-contained and belong beside `scott-ewm.el`; more importantly it means
   the fallback *requires* them rather than duplicating them. A fallback that
   is a second copy of the config is a fallback that rots.

3. **The fallback contains nothing that can fail.** `fallback.el` requires
   `lisp/` modules and binds keys. No package requires, no `:vc`, no network,
   no file parsing beyond what `scott-theme.el` already does defensively. Every
   form individually guarded, so a failure inside the fallback still leaves the
   rest of the fallback applied.

4. **Falling back must be visible.** A silent degraded mode is worse than a
   hard failure: Scott ran the broken config across a reboot without knowing
   why. The fallback sets a marker that shows in the modeline and is queryable
   over ssh, and the caught error is preserved for inspection rather than
   discarded.

5. **Both incidents get a regression test.** Verification deliberately corrupts
   a *copy* of `config.el` — once with an unbalanced paren, once with a
   signalling `require` — and asserts the desktop-critical surface survives.
   This is the actual deliverable; the restructuring is only the means.

6. **Build-time validation is out of scope, deliberately.** A flake check that
   batch-loads `config.el` is cheap and worth having later as insurance for the
   *committed* path, so a broken config cannot propagate to another host. It is
   not part of this work because it would not have caught either incident.

## Architecture

```
early-init.el          unchanged
init.el                LOADER (~20 lines). condition-case around config.el;
                       on error records the error and loads fallback.el
config.el              today's init.el, minus the extracted commands
fallback.el            requires lisp/ modules, binds desktop keys, loads a
                       theme. Nothing that can fail.
lisp/scott-ewm-slots.el  NEW - the 8 scott/ewm-* commands, extracted
lisp/*.el              unchanged
```

Normal boot: `init.el` → `config.el` → everything, exactly as today.
Broken `config.el`: `init.el` catches → `fallback.el` → modeline, launcher,
slot commands, theme, and a visible marker. EWM starts from the command line
either way.

## Components

| File | Responsibility |
|---|---|
| `init.el` | **Rewrite.** Loader only. The one file that must never break, and therefore the one that stops changing. |
| `config.el` | **Create** (from init.el). All current configuration. Free to be edited and to break. |
| `fallback.el` | **Create.** Minimum viable desktop. No package requires. |
| `lisp/scott-ewm-slots.el` | **Create** (extracted from init.el:505–605). The 8 `scott/ewm-*` commands, `provide`d so both paths can require it. |
| `ioshi/i-intelligence/emacs.nix` | **Modify.** Deploy `config.el` and `fallback.el` beside `init.el`, honouring `liveElisp` identically. |
| `docs/manual/` | **Modify.** Document the loader, the fallback, and how to tell you are in it. |

## What the fallback must provide

Derived from what was actually lost in both incidents, not from a guess:

- `scott/modeline-mode` — the top bar
- the launcher binding (`C-c o` → `scott/launch-app`) and `s-d`
- the `scott/ewm-*` slot commands — navigation, close, select, rename
- a theme, via `scott/theme-init` (already defensive: it falls back rather than
  signalling, and reads its data from `themes/<name>/`)
- the fallback marker

Not in the fallback: completion (vertico/corfu/consult), meow, magit, dirvish,
org, apheleia, treesit, pi, weather, openrouter, gdocs. All are recoverable by
fixing `config.el`; none are the desktop.

## Verification

The tests are the point. Each runs `emacs --batch` against a temp directory so
nothing touches the live config.

1. **Normal path unchanged.** Load the real `init.el` and assert the same
   surface a healthy boot has today: `scott/modeline-mode`, `scott/launch-app`,
   `scott/ewm--goto`, all six `scott-*` features, `custom-enabled-themes`
   non-nil, and the fallback marker **not** set.
2. **Read-time regression** (this morning's bug). Copy `config.el`, delete a
   closing paren, and assert: the fallback marker is set, the recorded error
   mentions end-of-file, and `scott/modeline-mode`, `scott/launch-app` and
   `scott/ewm--goto` are all still defined.
3. **Load-time regression** (tonight's bug). Copy `config.el`, insert
   `(require 'a-package-that-does-not-exist)` near the top, and assert the same
   three survive plus the marker.
4. **The fallback is itself resilient.** Break one form inside `fallback.el` and
   confirm the remaining forms still apply — the fallback must degrade, not
   collapse.
5. **Live check on rafik.** After deploying, query over ssh that the marker is
   unset and the surface matches test 1, then confirm the visible desktop.

Test 1 matters as much as the failure tests: the most likely way this project
does harm is by changing behaviour on the healthy path.

## Risks

- **The extraction touches working window-management code.** `scott/ewm--goto`,
  `--slot-frame` and `--slot-label` are used by the tab-bar content function, so
  the extraction must keep them together and `provide` correctly. This is the
  part that wants review rather than a quick edit.
- **Two more files under `liveElisp`.** Each is another out-of-store symlink;
  if `emacs.nix` deploys `config.el` but not `fallback.el`, the fallback path is
  silently unavailable and the guard looks fine until it is needed. Verification
  test 2 catches that, which is why it asserts on a real deployed layout.
- **`init.el` becoming the file nobody tests.** It is small and stops changing,
  which is the point, but a mistake in it is unguarded by construction. Keeping
  it under 25 lines and covered by test 1 is the mitigation.

## Out of scope

- The flake check described in decision 6.
- Guarding the 14 bare requires individually. Once `config.el` sits behind the
  loader, a failed require costs the packages below it and not the desktop,
  which is the goal. Tightening them further is a separate, optional cleanup.
- Packaging `gdocs` in Nix so it stops depending on `~/.config/emacs/elpa`
  being on `load-path`. Worth doing, unrelated to the guard.
