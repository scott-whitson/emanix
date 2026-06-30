# Zellaude — status bar plugin for Zellij

A fork of the [Zellaude](https://github.com/imsnif/zellaude) Zellij plugin,
modified to show a 12-hour Eastern wall clock in place of the default branding.

## What it does

Replaces the left-slot branding text (`"Zellaude (session-name) MODE"`) with
`"4:56 PM MODE"` — a `current_clock()` function using `chrono-tz`
(America/New_York) renders the time, pinned to Eastern regardless of host TZ,
with DST handled by the bundled timezone database.

The clock region remains clickable (opens settings), and the minute-rollover
triggers a re-render so the display stays accurate without wasteful frames.

## Source

The compiled `.wasm` ships here pre-built. The source history (bare repo) lives
at `~/projects/_archive/2026/zellaude.git` if you ever need to rebuild.

## Rebuilding

If you lose the archive, the mod is ~15 lines across 3 files:

- **`src/state.rs`** — add `current_clock()` function + `last_minute: u64` field
- **`src/render.rs`** — replace branding text with clock
- **`src/main.rs`** — add minute-rollover re-render trigger

Upstream: <https://github.com/imsnif/zellaude>

Changes from upstream:

- Removed session-name display in prefix
- Replaced brand text with `current_clock()` (chrono-tz Eastern time)
- Added `last_minute` re-render gate so the timer only redraws on rollover
