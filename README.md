# dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/) and a multi-profile system. One shared base config, with profile-specific overrides for different machines.

## Quick Start

```bash
git clone git@github.com:scottwhitson/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh <profile>
```

This installs system packages, developer tools (Rust, Node, micro, Claude Code, etc.), stows the base config, then layers the chosen profile on top.

## Structure

```
~/dotfiles/
├── install.sh              # bootstrap script: ./install.sh <profile>
├── base/                   # shared config, applied to every machine
│   ├── zsh/.zshrc          # Oh My Zsh, aliases, tools; sources ~/.zshrc.d/*.zsh
│   ├── git/.gitconfig      # core git settings; includes ~/.gitconfig.local
│   ├── micro/              # keybindings (wikilink plugin)
│   └── claude/             # Claude Code settings (full plugin set)
└── profiles/
    ├── personal/           # desktop / personal machine
    ├── work/               # work machine
    └── server/             # headless / remote server
```

**Base** is stowed first with `--no-folding`, so directories like `~/.zshrc.d/` and `~/.claude/` are real directories (not symlinks). Profile packages then add or replace files inside those same directories.

## Profiles

| Profile | What it adds |
|---------|-------------|
| `personal` | Personal git identity, Obsidian vault path, ollama auto-start, jrnl alias, fzf keybindings, Google Drive mount |
| `work` | Work git identity (placeholder) |
| `server` | Server git identity, trimmed Claude Code plugin set (overrides base) |

Each profile can include:
- `profile.conf` -- variables sourced by `install.sh` (e.g. `OBSIDIAN_VAULT` for micro wikilink)
- `git/.gitconfig.local` -- profile-specific `[user]` identity
- `zsh/.zshrc.d/<profile>.zsh` -- shell config sourced after base `.zshrc`
- `claude/.claude/settings.json` -- override base Claude settings

## Adding a New Profile

1. Create `profiles/<name>/`
2. Add a `profile.conf` (set `OBSIDIAN_VAULT` if using micro wikilinks, or leave empty)
3. Add any stow packages you need (e.g. `git/.gitconfig.local`, `zsh/.zshrc.d/<name>.zsh`)
4. Run `./install.sh <name>`

The directory layout inside a profile mirrors `$HOME`, same as base packages.

## Common Operations

```bash
# Re-stow base after editing
cd ~/dotfiles && stow -d base -t ~ --no-folding -R zsh

# Re-stow a profile package
cd ~/dotfiles && stow -d profiles/personal -t ~ --no-folding -R zsh

# Unstow a package
cd ~/dotfiles && stow -d base -t ~ --no-folding -D zsh
```

## Manual Steps

- **SSH keys**: `ssh-keygen -t ed25519` -- never committed to git
- **Oh My Zsh**: installed automatically by `install.sh`
- **Default shell**: `install.sh` runs `chsh -s $(which zsh)`; log out and back in to take effect
