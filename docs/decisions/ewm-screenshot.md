# PrintScreen: capture a region, then save it or copy it

**Applies to** `emacs/lisp/emanix-ewm-screenshot.el`. **Decided** 2026-11-08.

## Decision

The distribution binds EWM's `<Print>` to `emanix/ewm-screenshot`: slurp draws a
region, grim writes the pixels to a temp PNG, and a minibuffer prompt offers
**Save**, **Copy**, **Both** or **Cancel**. `S-<Print>` is the whole output
instead of a region. Both bindings carry `:fullscreen`.

## Why the key was free

Upstream's `ewm-mode-map` already contains `"<Print>" (ewm-key :intercept
:fullscreen)` — the compositor hands PrintScreen to Emacs and Emacs has nothing
bound, so the key is reserved and does nothing. The keysym resolves: EWM's
`resolve_keysym_from_name` looks names up case-insensitively, so Emacs's
`<print>` reaches `XK_Print` with no compositor patch.

## Why a prompt and not a menu or a tool

- **No menu program is installed.** `wofi`, `bemenu` and `rofi` are all absent,
  and adding one to ask a three-item question buys a process, a theme and a
  focus transition.
- **`satty` would match Greenshot more closely** — region select, annotate, then
  save or copy — but it is a new GUI dependency and an annotator, and the want
  here is only the save-or-copy choice. Revisit if annotation is wanted.
- **Modifier-only bindings were rejected.** PrintScreen-to-copy and
  `S-<Print>`-to-save with no prompt is faster and never steals focus, but the
  request is Greenshot's *choose after selecting*, and one prompt keeps one key
  for the common case.

## Why it is the distribution's, not the consumer's

`grim`, `slurp` and `wl-clipboard` are already emanix packages
(`home/packages.nix`), and EWM already binds the media and hardware keys in that
same keymap. A compositor that reserves PrintScreen for Emacs and ships no
command for it leaves a gap in the distribution rather than a personal
preference. The personal parts stay in the consumer: the save directory is
`emanix/screenshot-directory`, overridden from `personal.el`, and the org-link
capture remains the consumer's own `C-c S`.

## One link not exercised here

The prompt reads a key immediately after PrintScreen was itself intercepted.
EWM claims it enables keyboard capture when a command enters a
minibuffer/transient/read-key state, but that has not been pressed for real in
this build. It is falsified in one keystroke: if the prompt swallows input,
switch `emanix/ewm--choose-action` from `read-multiple-choice` to
`completing-read`, which is unambiguously a minibuffer.

## Exit condition

Upstream EWM binds a command to `<Print>` or ships its own screenshot. This
override then duplicates it and should be dropped.
