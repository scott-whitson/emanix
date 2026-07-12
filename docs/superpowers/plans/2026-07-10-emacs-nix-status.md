# Emacs-on-Nix Status

> **Date:** 2026-07-10
> **Scope:** Current state of the Emacs / Org-roam / Pi migration on zord

## What is done

- Nix is installed on zord and flakes are enabled.
- Home Manager is working on zord.
- Emacs runs as a Home Manager-managed daemon.
- Emacs config is linked from the dotfiles repo into `~/.config/emacs`.
- The legacy `~/.emacs.d` compatibility links are in place.
- Emacs package loading order issues were fixed with explicit `require` calls.
- Org-roam is the canonical note system for this machine.
- The old quarter-tracker shell workflow was moved into Emacs as `C-c q`.
- `C-c q` opens the current quarter note in a new frame and resolves the note by quarter.
- A dedicated Org-roam `Emacs Shortcuts` note exists and now documents:
  - buffer / window / frame navigation
  - the quarter-tracker shortcut
  - Pi workflow keys
- The Pi-in-Emacs experiment was removed after the vterm path proved too brittle.
- The old Pi shortcuts are no longer active.
- Pi will need a different launcher/workflow if it returns.
- The Hyprland launcher behavior for Emacs was corrected so it no longer hits the unsupported GTK/X11 path.

## Current state

Emacs is now a legitimate daily-driver workspace on zord:

- notes live in Org-roam under `~/docs/org`
- navigation is documented in Emacs itself
- the quarter tracker is date-driven and no longer hard-coded to one file

## Remaining work

### High priority

- Keep pruning any old shortcuts or launcher paths that still imply the old terminal-centric workflow.

### Medium priority

- Consider whether a new Pi launcher should be terminal-first, separate-app, or something else.
- Consider a Pi handoff note or capture template if you want repeatable session summaries.

### Later

- Resume the broader stow → Home Manager migration after the Emacs pilot settles.
- Continue the NixOS cutover plan when Debian phase 1 is stable.
- Eventually convert the note vault from markdown to Org if that migration remains desired.

## Suggested next checkpoint

1. Pick a replacement Pi workflow.
2. Decide whether it should live in Emacs, the terminal, or as a separate launcher.
3. Reintroduce it only after we have a simpler failure mode than vterm.

If that’s settled, the cleanup is complete and we can rebuild on a cleaner foundation.
