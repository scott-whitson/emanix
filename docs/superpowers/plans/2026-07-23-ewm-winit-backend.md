# EWM Winit (Nested) Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `Backend::Winit` in EWM so the compositor runs as a window inside another compositor; weasel runs the real EWM desktop as a WSLg window from Scott's fork.

**Architecture:** New `compositor/src/backend/winit.rs` (`run_winit`, structural sibling of `run_drm`) on `smithay::backend::winit`; one virtual output sized to the window; selection via optional `start()` arg + `EWM_BACKEND` env; weasel consumes the fork via `inputs.ewm.url`.

**Tech Stack:** Rust (Smithay git head, calloop), Emacs dynamic module (emacs crate), Nix flakes, WSLg as target environment.

**Spec:** `docs/superpowers/specs/2026-07-23-ewm-winit-backend-design.md`
**Upstream ref:** anvil's winit backend — `https://github.com/Smithay/smithay/blob/master/anvil/src/winit.rs` (the canonical template; fetch and read it in Task 3).

## Global Constraints

- Work happens in `~/projects/ewm` (fresh clone of `https://codeberg.org/ezemtsov/ewm`), branch `winit-backend`, based on rev `25a3113` (the rev the dotfiles flake pins — keeps eminix's DRM path bit-familiar). The dotfiles repo is touched ONLY in Task 9.
- Upstream hygiene: this code is a future PR. Match upstream style (rustfmt via their toolchain, follow existing module doc-comment conventions, no `unwrap()` where surrounding code uses error handling). Commits small and message-styled like `git log --oneline -20` shows. NO Co-Authored-By trailers.
- NEVER `git add -A` / `git add .` — explicit paths.
- Every code task ends with `cargo build` clean AND the existing test suite green (`cargo test`) inside `nix develop` — the DRM/headless paths must never regress.
- The winit path must be PURELY ADDITIVE outside `backend/winit.rs`: touching `backend/mod.rs` (enum + dispatch arms), `module.rs` (selection), `Cargo.toml` (winit feature deps if needed) is expected; any edit beyond those files needs justification in the task report.
- Visual gates (window appears, input works) need Scott at the machine — batch them at natural checkpoints; everything else is assertable from the terminal.
- `nix` commands via login shell (`bash -lc`) when PATH lacks them.

---

### Task 1: Feasibility gate — a nested Smithay compositor under WSLg

**Files:** none (throwaway processes only)

**Interfaces:**
- Produces: GO / NO-GO for the entire project. If NO-GO → stop, reassess (Hyper-V VM route per spec).

- [ ] **Step 1: Launch niri (Smithay-based, packaged) nested under WSLg**

```bash
bash -lc 'timeout 120 nix run nixpkgs#niri 2>&1 | tee /tmp/niri-spike.log' &
sleep 30 && grep -iE 'winit|backend|output|error|failed' /tmp/niri-spike.log | head -20
```
Expected: log lines indicating the winit backend initialized and an output/window was created; a niri window visible on the Windows desktop (Scott confirms).

- [ ] **Step 2: Input check (Scott, at the machine)**

In the niri window: keyboard input reaches niri (its default binds — e.g. `Super+Shift+E` exits; typing into a spawned terminal if trivially available). Confirm: keyboard YES/NO, mouse YES/NO.

- [ ] **Step 3: Record verdict**

Append GO/NO-GO + any protocol errors from the log to the progress ledger. NO-GO = stop the plan here.

---

### Task 2: Fork workspace + baseline build

**Files:**
- Create: `~/projects/ewm` (clone), branch `winit-backend`

**Interfaces:**
- Produces: a building, test-green baseline at `25a3113` for all later tasks.

- [ ] **Step 1: Clone and branch**

```bash
git clone https://codeberg.org/ezemtsov/ewm.git /home/scott/projects/ewm
cd /home/scott/projects/ewm
git checkout 25a3113af0c675a15e61bdfe29dd5f6e5be6984b -b winit-backend
```

- [ ] **Step 2: Baseline build + tests inside the repo's dev environment**

```bash
cd /home/scott/projects/ewm
bash -lc 'nix develop --command bash -c "cd compositor && cargo build 2>&1 | tail -3 && cargo test 2>&1 | tail -5"'
```
Expected: build succeeds; test summary all green. Record counts (N passed) in the report — later tasks must match or exceed.
If `nix develop` fails on the flake, fall back to `nix-shell` (repo ships `shell.nix`).

- [ ] **Step 3: Commit nothing** — this task produces workspace state only; note the baseline test count in the ledger.

---

### Task 3: Seam map — input, launch flow, and the anvil reference (READ-ONLY)

**Files:**
- Create: `/home/scott/projects/ewm/.winit-notes.md` (git-ignored scratch — add to `.git/info/exclude`, NOT committed)

**Interfaces:**
- Produces: the written map every later task consumes. Must answer, with file:line citations:
  1. How `run_drm` constructs the calloop loop, session, and input pipeline; which pieces are session/DRM-bound vs generic.
  2. Every consumer of Smithay `InputEvent` — what dispatch function the winit event stream must feed (and how device-config, `AccelProfile` etc., paths should no-op).
  3. How outputs announce (`output_detected` event emission path) and what `HeadlessBackend::add_output` does that a winit output must mirror.
  4. How `render()` is driven (frame clock, `redraw_queued_outputs`) and what a winit `render()` arm needs (anvil's `WinitGraphicsBackend::bind()/submit()` pattern).
  5. How emacs-the-client connects (`EWM_WAYLAND_DISPLAY`, module.rs:889 area; `ewm-launch` script anatomy from `nix/service.nix`) — what a nested launch script must replicate.
  6. The `start()` defun signature change needed for backend selection (and the no-arg env-var path).
  7. From anvil's `winit.rs` (fetch: `curl -sL https://raw.githubusercontent.com/Smithay/smithay/master/anvil/src/winit.rs`): the init/event-loop/damage-tracker pattern to transplant, adjusted to EWM's `Backend` enum shape.

- [ ] **Step 1: Produce the map** (analysis only; cite file:line for every claim)
- [ ] **Step 2: Flag blockers** — anything contradicting the spec's design decisions (e.g. input dispatch NOT generic over backend) goes to the controller before Task 4 is dispatched.

---

### Task 4: Backend selection plumbing (`EWM_BACKEND` + `start()` arg)

**Files:**
- Modify: `compositor/src/module.rs` (start defun), `compositor/src/backend/mod.rs` (if a selection enum belongs there)

**Interfaces:**
- Consumes: Task 3 map item 6.
- Produces: `start(cursor_theme, cursor_size, backend?)` — `backend` optional string (`"drm"`/`"winit"`); absent → `EWM_BACKEND` env; absent → `"drm"`. Dispatches to `run_drm` or `run_winit` (stub: logs "winit backend selected" and returns an explanatory error — real entry lands in Task 5).

- [ ] **Step 1: Write the failing check** — a unit test (or `cargo test`-visible assertion) that backend selection resolves: arg beats env beats default; unknown value errors cleanly.
- [ ] **Step 2: Implement selection + stub `run_winit`** in a new minimal `backend/winit.rs` (returns `Err("winit backend not yet implemented")`).
- [ ] **Step 3: `cargo build && cargo test`** — green, baseline count + new tests.
- [ ] **Step 4: Commit** — `git add compositor/src/module.rs compositor/src/backend/mod.rs compositor/src/backend/winit.rs` + message in upstream style, e.g. `backend: select drm/winit via start() arg or EWM_BACKEND`.

---

### Task 5: Winit window + one output + rendered scene

**Files:**
- Modify: `compositor/src/backend/winit.rs` (the real `run_winit`), `compositor/src/backend/mod.rs` (`Backend::Winit` variant + `output_infos`/`render` arms), `compositor/Cargo.toml` (enable smithay `backend_winit` feature)

**Interfaces:**
- Consumes: Task 3 map items 1, 3, 4, 7.
- Produces: `run_winit(cursor_config)` — winit window opens; ONE output (`WINIT-1`, window size, 60 Hz nominal) announced through the same path headless uses → `output_detected` reaches Emacs; scene renders via the shared render path; frame callbacks fire. No input yet.

- [ ] **Step 1: Implement** per the anvil pattern (init `WinitGraphicsBackend` + `WinitEventLoop`, damage-tracked render on `WinitEvent::Redraw`, output mode from window size).
- [ ] **Step 2: Build + tests green.**
- [ ] **Step 3: Terminal-assertable check** — `EWM_BACKEND=winit` + a headless-style smoke run under WSLg logging `output added` and at least one successful `submit()`; capture the log.
- [ ] **Step 4: CHECKPOINT (Scott):** launch under WSLg — an EWM window appears showing the Emacs frame (module started from a test emacs: `EWM_BACKEND=winit emacs --init-directory ...` per Task 3 item 5's launch anatomy). Window content correct even though input is dead.
- [ ] **Step 5: Commit** (`backend/winit.rs`, `backend/mod.rs`, `Cargo.toml`).

---

### Task 6: Input

**Files:**
- Modify: `compositor/src/backend/winit.rs` (event pump → dispatch), possibly `compositor/src/input.rs` ONLY if the map (Task 3 item 2) proved a shim is unavoidable

**Interfaces:**
- Consumes: Task 3 map item 2.
- Produces: keyboard + pointer (motion, buttons, scroll) from winit events flowing through EWM's existing input dispatch; libinput-only config paths no-op cleanly for winit devices.

- [ ] **Step 1: Implement the event translation** (smithay's winit input events are already `InputEvent<WinitInput>` — wire them into the dispatch the map identified).
- [ ] **Step 2: Build + tests green.**
- [ ] **Step 3: CHECKPOINT (Scott):** type in the EWM window — Emacs responds; `C-c o` ghostty inside → ghostty opens AS AN EWM BUFFER; meow chords work. Note Windows-key behavior for the record (expected: eaten by GlazeWM/Windows).

---

### Task 7: Resize + lifecycle polish

**Files:**
- Modify: `compositor/src/backend/winit.rs`

**Interfaces:**
- Produces: window resize → output mode change (Emacs frame follows); clean shutdown on window close (compositor thread exits, no Emacs crash — the `catch_unwind` in module.rs must never trip); cursor rendered (software cursor acceptable v1).

- [ ] **Step 1: Implement resize→mode-change + close→clean-stop.**
- [ ] **Step 2: Build + tests green; add a winit-scoped unit test if the seam allows (resize math, mode struct).**
- [ ] **Step 3: CHECKPOINT (Scott):** resize the window (GlazeWM float-drag) — EWM output follows; close the window — emacs survives, `ewm-start`-again works.

---

### Task 8: Upstream-readiness pass

**Files:**
- Modify: `compositor/src/backend/winit.rs` + touched files (docs/comments); `compositor/src/backend/mod.rs` (module doc listing the third backend)

- [ ] **Step 1: rustfmt + clippy clean** (`cargo fmt --check`, `cargo clippy` — match whatever CI the repo runs, see `.woodpecker/` or CI config if present).
- [ ] **Step 2: Doc comments** in the style of drm.rs/headless.rs headers; update `backend/mod.rs` module docs (currently documents exactly two backends).
- [ ] **Step 3: Feature gating** — `screencast` feature compiles out under winit per spec; verify both feature combinations build.
- [ ] **Step 4: Rebase/squash review** — reorder into a reviewable commit series; final `cargo test` green.
- [ ] **Step 5: Push the branch to Scott's fork** (Scott creates the Codeberg fork — or a GitHub mirror if Codeberg friction — and provides the remote URL; push is his call/credentials).

---

### Task 9: weasel integration (dotfiles repo)

**Files:**
- Modify: `flake.nix` (inputs.ewm → fork URL/branch — NOTE: this changes eminix's input too; see Task 10 gate)
- Create: `ioshi/i-intelligence/ewm-nested.nix` (flag `scott.ewm.nested`: ewm elisp into the weasel emacs build + `ewm-nested` launch script wrapping the Task 3 item-5 anatomy: `EWM_BACKEND=winit`, WSLg `WAYLAND_DISPLAY`, dedicated emacs process with `--init-directory /home/scott/.config/emacs`)
- Modify: flake weasel HM block (`scott.ewm.nested = true`)

**Interfaces:**
- Consumes: working fork branch (Task 8), launch anatomy (Task 3 item 5).
- Produces: `ewm-nested` on weasel's PATH; the EWM desktop one command away.

- [ ] **Step 1: Write ewm-nested.nix** (module body designed at implementation time from the launch anatomy — the emacs build gains `config.programs.ewm.ewmPackage`-equivalent elisp WITHOUT the eminix tty/getty/seat machinery).
- [ ] **Step 2: Flake input swap + `nix flake lock --update-input ewm`.**
- [ ] **Step 3: Eval gates:** weasel toplevel evaluates; `scott@work`/`scott@datacore` activationPackages UNCHANGED (they don't consume the ewm input — verify by drv compare); eminix toplevel EVALUATES (drv necessarily changes with the input; Task 10 audits).
- [ ] **Step 4: Build + activate weasel; `ewm-nested` opens the desktop (Scott).**
- [ ] **Step 5: Commit dotfiles** (explicit paths; push).

---

### Task 10: eminix safety audit (before eminix ever rebuilds from the fork)

- [ ] **Step 1: Diff audit** — `git diff 25a3113..winit-backend --stat` in the ewm repo: outside `backend/winit.rs`, changes limited to the declared files; DRM path changes are dispatch-arms only. Any surprise → resolve before eminix rebuilds.
- [ ] **Step 2: Build eminix toplevel from the swapped flake** (`nix build .#nixosConfigurations.eminix...toplevel --dry-run` then real build if cheap) — proves eminix CAN rebuild when Scott next pulls on it.
- [ ] **Step 3: Ledger note**: eminix runs the fork's DRM path after its next rebuild; revert path = flip `inputs.ewm.url` back.

---

### Task 11: Upstream PR

- [ ] **Step 1: Sync with the issue thread** — if ezemtsov replied with direction changes, reconcile (controller + Scott decide).
- [ ] **Step 2: PR text** — summary, design notes (selection mechanism, single-output v1), test evidence (WSLg screenshots/logs, DRM regression statement), known limitations (multi-output, screencast) — drafted for Scott's review; he submits.
- [ ] **Step 3: Track review; fork remains weasel's source until merge.**

---

## Success criteria (from the spec)

- Task 1 GO recorded; baseline tests stay green through every task.
- `ewm-nested` on weasel: EWM desktop as a WSLg window; ghostty via the in-EWM launcher opens as a buffer; resize follows; close/restart clean.
- Fork diff purely additive outside declared files; eminix builds from the fork.
- Upstream issue live before code review starts; PR opened when weasel validates.
