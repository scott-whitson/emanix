# EWM Winit (Nested) Backend — Design

**Date:** 2026-07-23
**Status:** Approved design, awaiting plan
**Scope:** Contribute a third backend to upstream EWM (codeberg.org/ezemtsov/ewm)
that runs the compositor as a window inside another compositor; run it on
weasel (WSLg) from a fork via flake input override, ahead of upstream merge.

## Goal

`ewm-start` on weasel opens the EWM desktop as a single WSLg window: apps
launched inside become EWM buffers with the full eminix window-management
experience. Upstream gains a development backend (iterate on EWM without a
TTY or dedicated hardware) — that's the framing that makes this PR-shaped,
not fork-shaped.

## Why this route (alternatives rejected)

- **VNC/RDP into headless EWM**: EWM implements `wlr-screencopy` (output)
  but no virtual-keyboard/pointer protocols (input) → view-only. WSL also
  exposes only a render node (no KMS), so the DRM backend can't start and
  headless renders to nowhere useful. Strictly more work than the clean fix.
- **Hyper-V NixOS VM**: works today, costs 4–6 GB of 16 GB soldered RAM +
  admin + a fourth host. Fallback if this project stalls.
- **GlazeWM tiles + C-c o**: the shipped interim; Scott rejects it as a
  destination.

## Upstream architecture (verified against source, ewm @ 25a3113)

- Compositor core: Rust, **Smithay** (git head) + smithay-drm-extras, built
  as `ewm-core`; loaded into Emacs as a **dynamic module** (`module.rs`).
- `#[defun] start(cursor_theme, cursor_size)` spawns the compositor thread →
  `backend::drm::run_drm(cursor_config)` (drm.rs, 3533 lines: LibSeatSession,
  libinput, calloop loop, DRM/GBM rendering).
- `Backend` enum (`backend/mod.rs`, 548 lines): `Drm(DrmBackendState)` |
  `Headless(HeadlessBackend)`; surface = `output_infos()`, `render()`, plus
  per-variant specials. `HeadlessBackend` (198 lines) is the structural
  template for a simple backend: virtual outputs, no session.
- Emacs/elisp is **backend-agnostic**: outputs announce via
  `output_detected` events → elisp creates one frame per output
  (`ewm--create-frame-for-output`). A winit backend that emits one output
  reuses this flow unchanged.
- Tests: `testing/fixture.rs` drives `Backend::Headless` directly — the
  repo has a culture of backend abstraction + testability (good sign for
  PR reception).

## Design decisions

| Decision | Chosen | Rejected |
| --- | --- | --- |
| Windowing layer | `smithay::backend::winit` (window + EGL + input events pre-mapped to Smithay types; anvil's `winit.rs` is the reference) | Raw `wayland` backend (more code, no X11 fallback); custom EGL surface handling |
| Backend selection | New optional arg to the module `start()` defun + `EWM_BACKEND=winit` env var honored when arg absent (env-only = zero elisp change for experiments; arg = proper API). Auto-detect (`WAYLAND_DISPLAY` set ⇒ winit) proposed to upstream as default-question, not assumed | Replacing run_drm dispatch silently |
| Entry point | `run_winit(cursor_config)` in `backend/winit.rs`, structural sibling of `run_drm` — same thread-spawn call site in `module.rs` chooses by selection above | Threading a generic `run<B>` refactor through drm.rs (invasive first PR) |
| Outputs | ONE virtual output sized to the winit window; window resize ⇒ output mode change event (same event path headless uses for virtual output changes) | Multi-output nested (upstream can extend later) |
| Input | winit events from `WinitEventLoop` → Smithay `InputEvent<WinitInput>` → EWM's existing input dispatch. Device-config paths (libinput accel/click profiles) explicitly no-op for winit devices | Synthesizing libinput devices |
| Cursor | Parent compositor renders the hardware cursor where possible (winit backend default); EWM's software cursor as fallback | — |
| Screencast/screencopy | Compile out (`screencast` feature) for v1 winit; screencopy kept if it needs no DRM specifics (plan task verifies) | Blocking v1 on pipewire-under-WSL |
| Delivery | Fork on Scott's account + upstream issue FIRST (intent + design sketch, posted before code) + PR when working. weasel runs the fork via `inputs.ewm.url` override immediately | Waiting for upstream merge to use it |

## weasel integration (fork phase)

- Flake: `inputs.ewm.url` → Scott's fork branch. eminix ALSO builds from the
  fork then — the winit code path is inert on eminix (selection defaults to
  DRM), but eminix's next rebuild picks up the fork base; keep the fork
  branch rebased on the upstream rev eminix already runs (25a3113) so the
  DRM path is bit-for-bit familiar.
- weasel gets the EWM system module pieces it currently lacks, gated behind
  a new flag (e.g. `scott.ewm.nested`): the ewm elisp package into the
  emacs build + a `ewm-nested` launch script (sets `EWM_BACKEND=winit`,
  `WAYLAND_DISPLAY` from WSLg) — NOT the eminix tty1/getty/seat machinery
  (`ewm.nix` autologin/loginShellInit stays eminix-only).
- The weasel Emacs currently runs as a systemd user daemon (standalone.nix
  path). Nested EWM implies a SECOND emacs process (the compositor one) or
  the daemon itself starting the compositor — v1: the launch script starts a
  dedicated emacs process with `--init-directory` per eminix convention,
  leaving the daemon untouched. Consolidation is a later decision.
- GlazeWM: the EWM window title will contain "emacs" (frame-title pinned) →
  already ignored → floats; Scott fullscreens it (or a dedicated GlazeWM
  rule fullscreens it by title match). Revisit after feel-testing.

## Risks

| Risk | Mitigation |
| --- | --- |
| input.rs more libinput-coupled than the surface suggests | Plan Task 1 maps every `InputEvent` consumer before any code; if coupling is deep, the winit input shim grows but the approach stands |
| Upstream rejects or wants a different shape | Issue-first sequencing; fork serves weasel regardless; keep the patch small and rebase-friendly |
| WSLg's Weston lacks protocols smithay's winit needs | Spike task builds anvil (smithay's demo) under WSLg BEFORE writing EWM code — if anvil can't run nested there, stop and reassess (VM route) |
| Windows key contention (GlazeWM + Windows eat super-chords) | Known, accepted for v1: GlazeWM pause toggle (`lwin+shift+p`) when EWM focused, or alternate EWM modifier inside the nested session; fullscreen RDP capture is NOT available (WSLg windows aren't fullscreen-exclusive) |
| Emacs-module threading vs winit event loop assumptions | smithay's winit backend is calloop-driven like run_drm; anvil proves the pattern; verified no main-thread requirement on Linux |
| 16 GB RAM | Nested EWM adds one emacs + compositor thread — grams, not the VM's kilos |

## Success criteria

- `anvil --winit` (or equivalent smithay example) opens and accepts input
  under WSLg on weasel (feasibility gate, before EWM work).
- `ewm-nested` on weasel opens the EWM desktop as a WSLg window; `s-d`
  launcher (or C-c o) inside it opens ghostty AS AN EWM BUFFER; focus,
  moves, resizes behave; window resize resizes the EWM output.
- eminix rebuilt from the fork: DRM path byte-identical behavior (drvPath
  compare against pre-fork where the input rev is pinned equal).
- Upstream issue filed; PR opened once weasel validates the backend.

## Out of scope

Multi-output nested; screencast under winit; X11-host testing beyond
what winit gives for free; replacing weasel's daemon-emacs workflow;
upstream merge timeline; retiring GlazeWM (still manages non-EWM windows).
