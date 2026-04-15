# Dotfiles Consolidation Design

**Date**: 2026-03-10
**Context**: Personal laptop moved to native Ubuntu with Sway. Work WSL also runs Sway. Both share base dotfiles — time to reduce duplication and fill gaps.

## A. Sway Config Deduplication

Extract shared keybindings, appearance, and workspace settings into `config-common`. Both `config` (native) and `config-wsl` set environment-specific variables at the top, then `include` the common file.

```
base/sway/.config/sway/
├── config          # native: Mod4, autostart (waybar, mako, autotiling, swayidle), hardware keys
├── config-wsl      # WSL: Mod1, xwayland disable, software rendering
└── config-common   # shared: appearance, keybindings, workspaces (references $mod, $term)
```

Shared content (~80 lines): Tokyo Night colors, gaps/borders/font, all keybindings (apps, window management, focus, move, resize, workspaces, scratchpad, session reload/exit), focus_follows_mouse.

Native-only: monitor positions, swayidle/swaylock, screenshots, media/brightness keys, cursor hide.
WSL-only: xwayland disable, LIBGL_ALWAYS_SOFTWARE for kitty, custom waybar config path.

## B. Helix Stow Package

New `base/helix/.config/helix/` with:

- `config.toml`: tokyo-night theme, line numbers, cursor shape, minimal editor settings
- `languages.toml`: existing zk LSP config for markdown/zettelkasten (copied from live disk)

## C. Kitty Config Sync

Update `base/kitty/.config/kitty/kitty.conf` to match live config on disk:
- Add background_opacity 0.85
- Font size 11.0 (was 12.0)
- Add cursor, selection, tab bar, window border colors
- Clean up structure with section comments

## D. install.sh Debian Tool Gaps

Add to debian apt-get: `fd-find`, `ripgrep`, `bat`
Add helix via snap: `snap install helix --classic`
Add debian name aliases to `.zshrc`:
```zsh
command -v batcat &>/dev/null && ! command -v bat &>/dev/null && alias bat="batcat"
command -v fdfind &>/dev/null && ! command -v fd &>/dev/null && alias fd="fdfind"
```

## E. Commit Existing Local Changes

The 3 uncommitted changes (autotiling-rs exec_always, clock date format, FZF_DEFAULT_COMMAND) are included as part of this work.
