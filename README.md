# dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Quick Start

```bash
git clone git@github.com:scottwhitson/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

## Packages

| Package | Files | Notes |
|---------|-------|-------|
| `zsh` | `.zshrc` | Oh My Zsh + autosuggestions + syntax highlighting |
| `git` | `.gitconfig` | User identity + core settings |
| `micro` | `.config/micro/{settings,bindings}.json` | Wikilink plugin bindings; vault path is machine-specific |
| `claude` | `.claude/settings.json` | Claude Code plugin list + preferences |

## Usage

Stow a single package:
```bash
cd ~/dotfiles && stow zsh
```

Unstow (remove symlinks):
```bash
cd ~/dotfiles && stow -D zsh
```

Re-stow after editing:
```bash
cd ~/dotfiles && stow -R zsh
```

## Manual Steps (not in repo)

- **SSH keys**: `ssh-keygen -t ed25519` — never committed to git
- **Oh My Zsh**: installed by `install.sh`, lives at `~/.oh-my-zsh/`
- **Rust/Cargo**: installed by `install.sh` via rustup
- **nvm/Node**: installed by `install.sh`
- **Micro vault path**: edit `micro/.config/micro/settings.json` after stowing
