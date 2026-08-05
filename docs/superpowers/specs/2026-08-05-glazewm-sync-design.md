# GlazeWM config sync — design

**Date:** 2026-08-05
**Status:** approved (in-session)

## Problem

The working GlazeWM arrangement on the work laptop spans three files in
`C:\Users\swhitson.CENTRALDATA\.glzr\glazewm\` — `config.yaml` (Emacs
ignore rule + hjkl-only move bindings), `focus-emacs.vbs`, and
`focus-emacs.ps1` — none of them tracked anywhere. A GlazeWM update or
reinstall can trample all of it silently. The arrangement took a full day
of debugging to land (see `docs/ioshi/standalone-hm.md` and the
2026-08-05 session); losing it should cost one `dot-sync`, not another
day.

## Decision: repo is authoritative

Scott edits `tools/glazewm/` in the repo; the sync step pushes repo →
Windows. A trample is auto-healed on the next sync, with the discarded
Windows-side diff printed so it is visible, never silent. Hand-edits on
the Windows side are explicitly unsupported (they get reverted, loudly).

Rejected alternatives: Windows-authoritative (a trample would get
committed as if legit) and drift-detection-only (a trample sits unnoticed
until something breaks).

## Layout

- `tools/glazewm/config.yaml`, `tools/glazewm/focus-emacs.vbs`,
  `tools/glazewm/focus-emacs.ps1` — tracked copies, seeded byte-exact
  from the current (working) Windows files.
- `bin/dot-glazewm-push` — standalone script owning all logic; `dot-sync`
  calls it after restow in both normal and pull-only modes.

## Behavior of `dot-glazewm-push`

1. **Guard:** locate the target via glob
   `/mnt/c/Users/*/.glzr/glazewm/` — exits 0 silently on every machine
   without one (non-WSL hosts, no GlazeWM). No hardcoded Windows
   username.
2. **Per file:** byte-compare (`cmp -s`) repo copy vs Windows copy.
   Identical → quiet. Different → print a short unified diff of what the
   Windows side will lose, then copy repo → Windows.
3. **If `config.yaml` changed:** best-effort `wm-reload-config` via the
   GlazeWM CLI (skipped with a note if GlazeWM isn't running), plus a
   printed reminder that window-rule changes need a full GlazeWM restart
   (reload never re-evaluates already-seen windows).
4. **Never fails the sync:** same best-effort contract as the restow
   step — any failure warns and exits 0.

## Testing

Manual verification (no test framework exists for `bin/`):
identical files → no-op; mutated Windows copy → diff shown, overwritten,
reload attempted; missing `.glzr` dir → silent skip. Verified in-session
before commit.

## Docs

`docs/ioshi/standalone-hm.md` GlazeWM section rewritten: the 2026-08-05
three-part arrangement (ignore rule, hjkl-only moves, dormant focus
scripts), the tracked location, and the real cause of the old "window
won't move to external monitors" limitation (WSLg monitor wedge — see
memory `reference_wslg_monitor_wedge`), which was never GlazeWM's fault.
