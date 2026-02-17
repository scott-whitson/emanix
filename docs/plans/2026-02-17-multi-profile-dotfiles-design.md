# Multi-Profile Dotfiles Design

## Problem

The current dotfiles are a single flat set of stow packages targeting one machine (personal WSL). We need to support three machines with different configurations:

| Machine | OS | Scope |
|---------|-----|-------|
| Personal | WSL (Ubuntu) | Full setup: ollama, jrnl, fzf, Google Drive, Obsidian vault |
| Work | WSL (Ubuntu) | Base tools + micro + Claude Code, different git email, no personal tools, different Obsidian vault path |
| Minne (server) | Native Ubuntu/Debian | Base tools + micro + Claude Code (trimmed plugins), no WSL or personal stuff |

## Approach: Source-directory pattern with stow

Profiles are independent stow packages that layer on top of a shared base. No hostname detection or conditional logic in config files.

## Directory Structure

```
~/dotfiles/
├── install.sh                          # ./install.sh <profile>
├── base/
│   ├── zsh/
│   │   ├── .zshrc                      # core config, sources ~/.zshrc.d/*.zsh
│   │   └── .zshrc.d/
│   │       └── .gitkeep
│   ├── git/
│   │   └── .gitconfig                  # shared settings, includes ~/.gitconfig.local
│   ├── micro/
│   │   └── .config/micro/
│   │       └── bindings.json
│   └── claude/
│       └── .claude/
│           └── settings.json           # full plugin set (default)
├── profiles/
│   ├── personal/
│   │   ├── profile.conf                # OBSIDIAN_VAULT path
│   │   ├── zsh/
│   │   │   └── .zshrc.d/
│   │   │       └── personal.zsh        # ollama, jrnl, fzf, google drive, OBSIDIAN_VAULT
│   │   └── git/
│   │       └── .gitconfig.local        # personal email
│   ├── work/
│   │   ├── profile.conf                # OBSIDIAN_VAULT path
│   │   ├── zsh/
│   │   │   └── .zshrc.d/
│   │   │       └── work.zsh            # OBSIDIAN_VAULT
│   │   └── git/
│   │       └── .gitconfig.local        # work email
│   └── server/
│       ├── profile.conf                # no vault (or optional)
│       ├── zsh/
│       │   └── .zshrc.d/
│       │       └── server.zsh          # server-specific config
│       ├── git/
│       │   └── .gitconfig.local        # personal email
│       └── claude/
│           └── .claude/
│               └── settings.json       # trimmed plugins (no playwright, frontend-design, rust-analyzer-lsp)
└── docs/
```

## .zshrc Split

### Base .zshrc (shared)

- Oh My Zsh setup (theme, plugins, prompt)
- PATH exports
- History settings (HISTSIZE, SAVEHIST, dedup, share)
- Navigation (AUTO_CD, AUTO_PUSHD, etc.)
- Completion settings + case-insensitive matching
- LS_COLORS fix (harmless on native Linux)
- Core aliases: ll, gs, gd, gl, .., ..., vact, dvact, calc
- qt() function referencing $OBSIDIAN_VAULT (gracefully errors if unset)
- Tools: cargo env, zoxide init, nvm
- `for f in ~/.zshrc.d/*.zsh; do source "$f"; done` (near the end)

### profiles/personal/zsh/.zshrc.d/personal.zsh

- `export OBSIDIAN_VAULT="/mnt/h/My Drive/SEW/Obsidian/Whitsgrove"`
- Ollama auto-start
- jrnl aliases + HIST_IGNORE_SPACE
- fzf key-bindings and completion sourcing
- Google Drive mount (/mnt/h)

### profiles/work/zsh/.zshrc.d/work.zsh

- `export OBSIDIAN_VAULT="/path/to/work/vault"` (to be filled in)

### profiles/server/zsh/.zshrc.d/server.zsh

- Server-specific config (placeholder, can be empty initially)

## Git Config Layering

Base `.gitconfig`:
```ini
[core]
    autocrlf = input
[include]
    path = ~/.gitconfig.local
```

Each profile provides `.gitconfig.local` with `[user]` name and email.

## Micro Settings

Base stow provides `bindings.json` only. The `settings.json` (containing `wikilink.vault`) is templated by `install.sh` at install time using the `OBSIDIAN_VAULT` value from `profile.conf`.

Wikilink plugin is installed in `install.sh` (base). micro-llm is dropped.

## Claude Code Settings

Base provides the full plugin set in `settings.json`. The server profile overrides this with its own `settings.json` that excludes:
- playwright
- frontend-design
- rust-analyzer-lsp

Since the server profile's `claude/` stow package targets the same file, it is stowed *instead of* the base claude package (install.sh skips base claude when the profile provides its own).

## Install Script

```
./install.sh personal|work|server
```

Flow:
1. Install system packages (zsh, stow, git, curl, wget, unzip)
2. Install tools (Oh My Zsh, zsh plugins, rust, uv, zoxide, nvm, micro, Claude Code)
3. Install micro wikilink plugin
4. Stow base packages (zsh, git, micro, claude — skip any that the profile overrides)
5. Stow profile packages (only dirs that exist for that profile)
6. Source profile.conf and template micro settings.json with OBSIDIAN_VAULT
7. Set default shell to zsh

## Adding a New Machine

1. Create `profiles/<name>/` with the relevant override files
2. Add `profile.conf` with any variables (OBSIDIAN_VAULT, etc.)
3. Clone the repo on the new machine and run `./install.sh <name>`
