# Zellaude — status bar plugin for Zellij

A fork of the [Zellaude](https://github.com/ishefi/zellaude) Zellij plugin, with
the left-slot branding dropped so the bar starts straight at the mode pill.

## What it does (vs upstream)

Upstream renders `" Zellaude (session-name) "` followed by an optional `MODE`
pill. This build renders the `MODE` pill alone, and the pill inherits the
branding's other job: it is the click target that opens zellaude's settings menu.

With `mode_indicator` switched off there would be nothing left to click, so the
prefix falls back to a single `●` (tinted when the settings menu is open).

An earlier version of this fork showed a 12-hour Eastern wall clock in that slot
instead. That was removed once the desktop bar started showing the time — with it
went the `chrono`/`chrono-tz` dependencies and the minute-rollover re-render gate.

## Source

The fork lives in `~/projects/zellaude` (`origin` = the consumer's own
remote; `upstream` = ishefi/zellaude). Only the compiled `.wasm` ships here,
because `~/.config/zellij` is an out-of-store symlink into
`ioshi/i-intelligence/zellij`,
so the plugin must be a real file in this directory rather than a store path.

## Rebuilding

    dot-zellaude-build

It builds in a `nix shell` with rustup's toolchain (nixpkgs' rustc has no
wasm32-wasip1 std) and copies the result over `zellaude.wasm` here — commit the
new binary afterwards. A new zellij tab or session loads it; existing tabs keep
the old code until they are recreated.

## Settings

`zellaude.json` holds the plugin's own settings (it writes this file itself, which
is why the config dir is a live symlink and not a store copy). Current values:
notifications Always, flash Off, elapsed_time false, mode_indicator true.
