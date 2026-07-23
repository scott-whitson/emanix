# weasel zellij + zellaude — design

**Date:** 2026-07-23
**Status:** approved (design), pending implementation
**Context:** eminix→weasel ssh now works (port 2222 + key, fixed 2026-07-23). Weasel
needs the Debian WSL zellij experience for ssh sessions: persistent sessions that
survive disconnects, zellaude tab bar with Claude activity, zellij-forgot cheatsheet.

## Problem

- weasel has no zellij installed and no `~/.config/zellij`.
- `~/.claude/settings.json` on weasel (copied at cutover) points ten hooks at
  `~/.config/zellij/plugins/zellaude-hook.sh`, which does not exist → silent no-ops.
- The HM module `ioshi/i-intelligence/zellij.nix` is commented out and **stale**: it
  carries old HM-generated keybinds that do not match the real config. The real,
  battle-tested config lives in `base/zellij/.config/zellij/` (config.kdl, zellaude
  layout, zellaude.wasm + zellij_forgot.wasm, zellaude-hook.sh, zellaude.json).
- Emacs alternatives (TRAMP, vterm, detached.el) were considered and rejected as the
  persistence layer: nothing Emacs-side keeps a TUI process alive on weasel across
  disconnects. TRAMP remains complementary (remote file editing from eminix).

## Design

### 1. Module shape

Rewrite `ioshi/i-intelligence/zellij.nix` as an opt-in module (ghostty pattern):

- `options.scott.zellij.enable = lib.mkEnableOption ...`, body under `lib.mkIf`.
- Uncomment `./zellij.nix` in `ioshi/i-intelligence/default.nix` (defaults off, safe
  for all machines).
- Only weasel sets `scott.zellij.enable = true` in its host config.
- `programs.zellij.enable = true` for the package; **no HM `settings`** — delete the
  stale generated keybinds; kdl files are the single source of truth.
- `enableZshIntegration` stays OFF (it auto-starts zellij in every interactive shell;
  rejected — ssh-only auto-attach wanted).

### 2. Config deployment

- `xdg.configFile."zellij".source = config.lib.file.mkOutOfStoreSymlink
  "${scott.dotfiles.path}/base/zellij/.config/zellij"` — one live symlink for the
  whole directory, same pattern emacs.nix uses for the lisp dir.
- Rationale: zellaude writes to its `zellaude.json` settings file (a nix-store copy
  would be read-only); kdl/plugin edits take effect without a rebuild; HM recreates
  the link every rebuild, killing the "hand-installed hook breaks on upgrade" wart.
- Layout's hardcoded `file:/home/scott/.config/zellij/plugins/zellaude.wasm` path and
  the Claude hook path both resolve unchanged. Zero edits to `~/.claude/settings.json`.

### 3. SSH auto-attach

- Zsh init snippet contributed by the module (inside the same `mkIf`):
  interactive shell AND `$SSH_CONNECTION` set AND `$ZELLIJ` unset →
  `zellij attach --create main`.
- NOT `exec`: detach (`Ctrl o, d`) drops to a plain zsh on weasel instead of closing
  the connection. Local WSL shells unaffected.
- Known behavior: attaching the same session from two terminals mirrors it (zellij
  semantics, accepted).

### 4. Rollout & verification

Weasel builds from local `~/dotfiles` (build as scott, activate as root). Order:
edit → rebuild → verify → commit → push (GitHub → datacore mirror stays current;
no rebuild needed on eminix/zord — flag off there).

Verification checklist:
1. `zellij` launches locally with zellaude clock bar (no bottom status bar).
2. A Claude Code session fires the zellaude activity indicator via the hook.
3. `ssh weasel` from eminix lands attached to session `main`.
4. Detach leaves a usable plain shell over ssh.
5. A fresh local Windows Terminal shell does NOT auto-enter zellij.
6. `Ctrl y` opens zellij-forgot cheatsheet.

## Out of scope

- Enabling zellij on eminix/zord (one-line flip later if wanted).
- Rebuilding zellaude.wasm from source (`~/projects/zellaude`; archive bare repo at
  `~/projects/_archive/2026/zellaude.git`) — the pre-built wasm in base/ ships as-is.
- Any change to Debian (dormant fallback).
