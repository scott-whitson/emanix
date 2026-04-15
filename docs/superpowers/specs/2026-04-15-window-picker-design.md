# Window picker (custom Rust overlay) — design

**Date:** 2026-04-15
**Status:** Approved design, ready for implementation plan.
**Supersedes:** `2026-04-15-hyprswitch-window-picker-design.md` (abandoned after live test revealed hyprswitch is a modal picker, not the per-window ace-jump overlay actually wanted).

## Goal

A keyboard-driven per-window ace-jump tool for Hyprland. Press `Super+Tab`; a digit appears centered on each visible window; press the digit to focus that window. The user never looks away from the window they want — the digit is right there on it.

## User flow

1. User presses `Super+Tab`.
2. A transparent dimmed overlay appears on each monitor within ~60–80ms.
3. Each visible window on each monitor has a single large digit (`1`–`9`) centered on it.
4. User presses the digit on the window they're already looking at → that window is focused, overlay closes.
5. `Esc` or any non-digit closes the overlay without changing focus.
6. Edge cases:
   - Exactly one visible window → tool exits immediately (already focused).
   - More than nine visible windows → only the first nine (spatial order) get digits. The rest are reachable via `Super+hjkl` as before.

## Why Rust, not Python

Python + PyGObject cold-starts GTK4 in 200–300ms. That breaks the "instantaneous" feel the user explicitly requires: the hand and eye have already committed, the tool must not make them wait. A compiled Rust binary using `gtk4-rs` + `gtk4-layer-shell` cold-starts in 60–80ms — low enough to feel immediate. This matches the existing fragpaper precedent (Rust + wgpu for the wallpaper renderer).

## Architecture

**One-shot binary, no daemon.**

Flow each time the binary runs:

1. Exec `hyprctl -j monitors` and `hyprctl -j clients`.
2. Parse both JSON blobs with serde.
3. For each monitor, take its `activeWorkspace.id`. A client is "visible" iff its `workspace.id` matches the active workspace of its monitor.
4. Sort visible clients spatially: within each monitor, top-to-bottom rows (by y), then left-to-right within each row (by x). Flatten: monitor A's windows first, then monitor B's, etc. — monitors ordered by their x offset.
5. Assign digits `1`–`9` in that flattened order. Excess windows get no digit.
6. For each monitor that contains ≥1 visible window, create a fullscreen `gtk4-layer-shell` surface:
   - `layer = Overlay` (above all normal windows)
   - `keyboard-interactivity = Exclusive` (this surface grabs all keyboard input)
   - Anchored to all four edges of the monitor.
   - Transparent background; a single full-surface `DrawingArea` where we paint via cairo.
7. Draw per-surface:
   - Dimmed backdrop: `rgba(0,0,0,0.45)` covering the whole monitor.
   - For each window on this monitor: a large digit (~96px bold) centered on the window's rect (converted to monitor-local coordinates). Digit rendered in a filled colored pill for contrast.
8. GTK main loop runs until a keypress:
   - `Key_1`..`Key_9` → if that digit maps to a window, exec `hyprctl dispatch focuswindow address:0x...`; quit either way.
   - `Escape` or any other key → quit.
9. Exit. The GTK loop tears everything down; no state persists.

## Components

The code is small enough (~300 lines) to live in a single `main.rs`, but it must be structured by responsibility so each section can be understood independently. Three logical units:

1. **Hyprctl layer** — `query_monitors()`, `query_clients()`, `dispatch_focus(address)`. Shell out, parse, return typed structs. Self-contained, testable against fixture JSON.
2. **Layout layer** — `visible_windows(monitors, clients) -> Vec<LabeledWindow>`. Pure function over the types from layer 1. Deterministic: same inputs → same digit assignment. Testable without GTK.
3. **Overlay layer** — creates per-monitor surfaces, paints, handles keys, triggers dispatch. Uses layers 1 and 2. This is the GTK-bound code; not unit-testable without a display.

A `LabeledWindow` type ties them together:

```rust
struct LabeledWindow {
    digit: char,             // '1'..'9'
    address: String,         // "0x..." for hyprctl dispatch focuswindow
    monitor_name: String,    // which monitor to draw on
    rect_local: Rect,        // x,y,w,h in MONITOR-local coordinates
}
```

Layer 3 never parses hyprctl output; layer 1 never knows about GTK; layer 2 never does IO. Boundaries are clean.

## Theming

Read `~/.local/state/theme-current` (managed by `theme-switch`) once at startup. Two hardcoded palettes:

- **Dark** (default if state file missing): backdrop `rgba(0,0,0,0.45)`, digit text `#1a1b26`, digit pill `#7aa2f7`, pill border none.
- **Light**: backdrop `rgba(0,0,0,0.30)` (slightly lighter dim to match light-theme feel), digit text `#e1e2e7`, digit pill `#2e7de9`.

Palette is a simple `struct` selected at startup. No CSS file, no hot-reload, no theme-switch integration needed — the binary re-reads the state file every time it runs, which is every key press.

## Repository layout

**New code (source):**

```
tools/window-picker/
├── Cargo.toml         # crate name: window-picker, edition 2021
├── .gitignore         # target/
└── src/
    └── main.rs        # single file with the three logical layers clearly sectioned
```

**Dependencies (Cargo.toml):**

- `gtk4 = "0.9"` (track current stable gtk4-rs release at implementation time)
- `gtk4-layer-shell = "0.4"` (ditto)
- `serde = { version = "1", features = ["derive"] }`
- `serde_json = "1"`
- `anyhow = "1"`

**New shell wrapper:**

`base/bin/.local/bin/window-picker` — a minimal shell script that execs the built binary:

```sh
#!/usr/bin/env bash
exec "$HOME/dotfiles/tools/window-picker/target/release/window-picker" "$@"
```

This matches the existing `yt_transcript` / `web_extract` / `news` wrapper pattern (wrappers in `base/bin/.local/bin/`, real code in `~/dotfiles/tools/`).

**install.sh addition:**

For the arch desktop profile, after the existing package installs, add a build step:

```sh
if [[ "$IS_DESKTOP" == "true" && "$DISTRO" == "arch" ]]; then
    if [[ ! -x "$DOTFILES_DIR/tools/window-picker/target/release/window-picker" ]]; then
        echo "Building window-picker..."
        (cd "$DOTFILES_DIR/tools/window-picker" && cargo build --release)
    fi
fi
```

Idempotent: rebuilds only if the binary is missing. Users who want to rebuild after code changes run `cargo build --release` manually (or delete the binary).

**hyprland.conf addition:**

One line in `base/hypr/.config/hypr/hyprland.conf`:

```
bind = $mod, Tab, exec, window-picker
```

No `exec-once`, no daemon.

**theme-switch:** no changes. The binary re-reads the state file every invocation; restart-on-theme-swap is not a concept.

## Testing

**Unit-testable (layer 1 and 2):**

- Fixture-based: a `tests/` directory with real `hyprctl -j` output captured from a live session, loaded via `include_str!`. Test that `visible_windows` filters correctly, assigns digits in spatial order, and handles 0/1/many monitors.
- Edge cases: 0 visible windows (monitors vec empty for display); 1 visible window (empty labels returned because caller treats this as "skip overlay"); >9 visible windows (only first 9 get digits); windows on inactive workspaces are excluded; special workspaces (`special:scratch`) excluded unless visible.

**Not unit-testable (layer 3):**

- Overlay rendering, key handling, layer-shell behavior — these require a live compositor. Manual interactive testing only, documented in the plan's verification steps.

## Error handling

- `hyprctl` missing or failing → print error to stderr, exit 1. No retry.
- JSON parse failure → print parse error with context, exit 1.
- No visible windows across all monitors → silent exit 0 (nothing to pick).
- Exactly 1 visible window → silent exit 0 (already focused).
- gtk4-layer-shell not supported by the compositor → GTK will panic or error during init; let that surface as a normal crash rather than pre-checking.
- `hyprctl dispatch focuswindow` fails (window closed between query and keypress) → log to stderr, exit 1. Rare race; no retry.

Keep it ruthless: no retry loops, no fallback paths. If something's wrong, the user presses `Super+Tab` again.

## Performance budget

- Cold binary launch to first overlay visible: **< 100ms** target, < 80ms expected.
- `hyprctl` query: ~5ms total for both calls.
- GTK4 init + layer-shell surface creation: ~40–60ms.
- Cairo paint: <5ms for realistic window counts.
- Keypress to focus dispatch: <20ms (local exec of hyprctl).

Total perceived latency: press `Super+Tab` → overlay visible ~70ms → press digit → focused window ~90ms. Well within "feels instant."

## Out of scope

- Mouse interaction with the overlay (click to focus). Keyboard only.
- Mnemonic labels (asdfjkl;) — digits only, per the Q2 decision in the hyprswitch brainstorm that still holds.
- Cycling through windows (Alt-Tab-style). This is ace-jump, one press to focus.
- Workspace switching via the picker. Picker only acts on already-visible windows.
- Special workspaces (`special:*`) — excluded. If the user has a scratchpad visible, it gets a digit; otherwise it doesn't.
- Settings/config file for the binary. Zero config; palette is hardcoded; reads only `theme-current`.
- Icon/thumbnail rendering. Just digits on a dim backdrop.
- Animation (fade in/out). Instant on, instant off.
- Per-binary logging — anyhow error messages to stderr are sufficient.

## Open implementation details

Marked so the implementer knows these are decided during the work, not before:

- Exact digit font and weight: pick a bundled GTK default that renders boldly at 96px. Adjust during manual verification if the digit looks weak.
- Exact pill dimensions and radius: start with `padding = 16px`, `border-radius = 12px`, tune visually.
- Whether the pill also carries the window title in small text underneath. Default: no. Revisit only if the unlabeled pill feels confusing during testing.
- Fallback digit size on very small windows (e.g., a 200x100 px floating window): scale digit down if window rect is smaller than ~150×80 px.
