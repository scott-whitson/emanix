# Dotfiles Reorg — Wave 2: Install Modularization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the monolithic `install.sh` with a short orchestrator plus 11 modular install scripts (`install/01-pacman.sh` through `install/11-services.sh`), add re-runnable `bin/dot-*` helpers, integrate them into PATH via `base/zsh/.zshrc.d/dotfiles.zsh`, and bootstrap kickstart.nvim as a sibling repo at `~/.config/nvim/`.

**Architecture:** Current `install.sh` is a 172-line monolith with branching for arch vs debian distros and workstation vs server profiles. Wave 2 slices it into focused scripts under `install/` (each independently runnable, each idempotent, each ~20-60 lines), drops the debian branch per tenet #2, and introduces a new repo-level `bin/` for post-install helpers (`dot-restow`, `dot-theme-set` stub, `dot-update`, `dot-doctor`). Kickstart.nvim lives at `~/.config/nvim/` as its own git repo — NOT stowed — and opts into the theme system via `pcall(require, 'dotfiles-theme')` at the end of its `init.lua`.

**Tech Stack:** Bash, GNU Stow, pacman + paru (Arch AUR helper), git, uv (Python packaging), npm (for Claude Code), cargo (for tools/window-picker), nvm (for Node.js).

**Spec:** `docs/superpowers/specs/2026-04-23-dotfiles-opinionated-reorg-design.md` (Section 5, Wave 2)

**Scope note:** Wave 2 does NOT build the real theme system (that's Wave 3). `install/10-theme.sh` and `bin/dot-theme-set` are *stubs* in Wave 2 — they exist in the layout but delegate to the existing `base/bin/.local/bin/theme-switch` script for now. Wave 3 replaces them with the directory-per-theme symlink system.

---

## Pre-plan checklist

Before starting Task 1, verify:

- [ ] HEAD is on `main` at the latest commit from Wave 1 (`c89dfdec` or later).
- [ ] `pacman -Qi paru | head -1` returns info — paru is installed (the `02-paru.sh` script being written in Task 3 is a no-op on your machine, but must be correct for fresh installs).
- [ ] `command -v nvim` — reports a path or "not found." If not found, Wave 2 will install it via pacman in Task 2. If found, Task 2 is a no-op for that package.
- [ ] You have internet access (several scripts git-clone from github).

### ⚠️ IN-FLIGHT CHANGES WARNING ⚠️

The user has uncommitted changes in several `base/*` files (observed during Wave 1):
- `base/claude/.claude/settings.json`
- `base/ghostty/.config/ghostty/config`, `light.conf`
- `base/helix/.config/helix/config.toml`
- `base/hypr/.config/hypr/colors/dark.conf`, `colors/light.conf`, `hyprland.conf`

**Tasks 1-12 do NOT touch these files** — they're writing new `install/*.sh`, new `bin/*`, and new `base/zsh/.zshrc.d/dotfiles.zsh`. Those tasks can proceed with the in-flight changes unstaged.

**Task 14 runs the full `./install.sh workstation`**, which invokes `install/08-stow-base.sh`. That script (faithfully ported from the existing monolithic install.sh) ends with **`git checkout -- base/`**. That command will **destroy any uncommitted changes in `base/*` files.** This is intentional behavior — the `--adopt` stow call can absorb defaults (like Oh My Zsh's `.zshrc`) into the repo, and `git checkout` restores the repo's intended content. But it is indiscriminate: *all* uncommitted changes in `base/` revert.

**Before Task 14 starts, the user MUST either:**
1. **Commit the in-flight changes.** Preferred — they're legitimate config updates that should land anyway.
2. **Stash them** (`git stash push -- base/`). Restore after Task 14 with `git stash pop`.
3. **Explicitly accept the loss** if the changes are experimental and not worth keeping.

Task 14 has a preflight check that refuses to run if `base/` has uncommitted changes; controller must resolve before re-dispatching.

---

## File Structure

**Files CREATED by this plan:**

| Path | Purpose |
|---|---|
| `install/_common.sh` | Shared helpers (log, need_pkg, stow_pkg, guard functions) sourced by all `install/*.sh` |
| `install/01-pacman.sh` | Core pacman packages: base-devel, git, stow, zsh, neovim, helix, uv, rustup, rclone, fonts |
| `install/02-paru.sh` | Bootstrap paru from AUR if missing; apply user-level paru.conf cache-redirect |
| `install/03-system.sh` | Locale, pam_systemd_home fix, zsh as default shell, Oh My Zsh + plugins |
| `install/04-hyprland.sh` | hyprland, hyprpaper, hyprlock, hypridle, xdg-desktop-portal-hyprland *(workstation only)* |
| `install/05-desktop.sh` | waybar, mako, fuzzel, ghostty, wl-clipboard, grim/slurp, pipewire, fonts *(workstation only)* |
| `install/06-tools.sh` | uv sync tools/, symlink wrappers, build tools/window-picker, nvm + Node LTS, clone kickstart.nvim, add pcall line to init.lua |
| `install/07-claude.sh` | Install Claude Code CLI globally via npm; ensure `~/projects/agent-skills` cloned |
| `install/08-stow-base.sh` | Stow every `base/*/` package (skip desktop pkgs on server) with `--adopt` + `git checkout -- base/` dance |
| `install/09-stow-profile.sh` | Stow every `profiles/$PROFILE/*` package, with base-conflict resolution |
| `install/10-theme.sh` | **Wave 2 stub:** calls existing `theme-switch` if available. Full theme system lands in Wave 3. |
| `install/11-services.sh` | Enable systemd user units (gdrive-bisync timer, any others discovered) |
| `bin/dot-restow` | Re-stow one package or all, scoped to base or profile |
| `bin/dot-theme-set` | **Wave 2 stub:** thin wrapper over existing `theme-switch`. Wave 3 replaces. |
| `bin/dot-update` | `paru -Syu && dot-restow --all` |
| `bin/dot-doctor` | Health check: stow symlinks, gdrive mount, tailscale, fonts, pam fix, PATH, claude, agent-skills, kickstart init |
| `base/zsh/.zshrc.d/dotfiles.zsh` | Prepend `$DOTFILES/bin` to PATH; export `DOTFILES` var |

**Files MODIFIED by this plan:**

| Path | Change |
|---|---|
| `install.sh` | Complete rewrite: 172 lines → ~50-line orchestrator sourcing `install/*.sh` in order |
| `~/.config/nvim/init.lua` | (Live machine only, not in the dotfiles repo) Append one line: `pcall(require, 'dotfiles-theme')` at end |

**Directories CREATED:**

| Path | Purpose |
|---|---|
| `install/` | Houses modular install scripts |
| `bin/` | Houses re-runnable `dot-*` helpers |
| `base/zsh/.zshrc.d/` | May already exist (stowed from base); ensure it has `dotfiles.zsh` |

---

## Task 1: Create `install/_common.sh` (shared helpers)

**Files:**
- Create: `install/_common.sh`

This file is sourced at the top of every other `install/*.sh` script. It exports helpers and guard functions so downstream scripts can remain short and readable.

- [ ] **Step 1: Create `install/` directory and `_common.sh`**

Write `install/_common.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# install/_common.sh — shared helpers for install/*.sh scripts
# Not executable directly; sourced by numbered scripts.

set -euo pipefail

# --- Required env (set by install.sh orchestrator) ---
: "${DOTFILES:?DOTFILES must be set (orchestrator sets this)}"
: "${PROFILE:?PROFILE must be set (orchestrator sets this)}"

# --- Log helpers ---
log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(basename "${BASH_SOURCE[1]:-install}")" "$*"; }
warn() { printf '\033[1;33m[%s]\033[0m %s\n' "$(basename "${BASH_SOURCE[1]:-install}")" "$*" >&2; }
die()  { printf '\033[1;31m[%s]\033[0m %s\n' "$(basename "${BASH_SOURCE[1]:-install}")" "$*" >&2; exit 1; }

# --- Profile guards ---
# Return success if current PROFILE is one of the given names.
profile_is() {
    local p
    for p in "$@"; do
        [[ "$PROFILE" == "$p" ]] && return 0
    done
    return 1
}

# Exit the calling script early if PROFILE is NOT in the given list.
skip_unless_profile() {
    if ! profile_is "$@"; then
        log "skipping on profile=$PROFILE (this script only runs on: $*)"
        exit 0
    fi
}

# --- Package helpers ---
# Install pacman packages idempotently. Accepts a list.
need_pkg() {
    [[ $# -gt 0 ]] || return 0
    sudo pacman -S --noconfirm --needed "$@"
}

# Install from AUR via paru. Accepts a list.
need_aur() {
    [[ $# -gt 0 ]] || return 0
    paru -S --noconfirm --needed "$@"
}

# --- Stow helper ---
# Restow a package. Args: <stow-dir> <pkg-name>
# Uses --no-folding so directories stay real (profile packages can add to them).
stow_pkg() {
    local stow_dir="$1" pkg="$2"
    stow -d "$stow_dir" -t "$HOME" --no-folding -R "$pkg"
}

# --- Clone helper ---
# Clone a git repo if the target directory is missing OR empty.
# Args: <url> <dest> [<branch>]
clone_if_missing() {
    local url="$1" dest="$2" branch="${3:-}"
    if [[ -d "$dest" ]] && [[ -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
        log "clone_if_missing: $dest already populated, skipping"
        return 0
    fi
    log "cloning $url -> $dest"
    if [[ -n "$branch" ]]; then
        git clone --branch "$branch" "$url" "$dest"
    else
        git clone "$url" "$dest"
    fi
}
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n ~/dotfiles/install/_common.sh && echo OK
```

Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
cd ~/dotfiles && git add install/_common.sh
git commit -m "$(cat <<'EOF'
install: add _common.sh shared helpers

Foundation for modular install scripts (Wave 2). Provides log/warn/die,
profile guards, pacman/paru wrappers, stow_pkg, and clone_if_missing.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Create `install/01-pacman.sh`

**Files:**
- Create: `install/01-pacman.sh`

Purpose: install core pacman packages that every profile needs (core shell + dev + editors + rclone + fonts). Does NOT install desktop-specific packages (those are in `04-hyprland.sh` and `05-desktop.sh`).

Port from current `install.sh` lines 43-51 (the Arch pacman block), removing packages that are in the Wave 1 "dropped" list (`micro`), adding the ones that are now baseline (`helix`, `neovim`).

- [ ] **Step 1: Write `install/01-pacman.sh`**

```bash
#!/usr/bin/env bash
# install/01-pacman.sh — core pacman packages (cross-profile)
set -euo pipefail
source "$(dirname "$0")/_common.sh"

log "installing core pacman packages"
need_pkg \
    base-devel git stow zsh \
    curl wget unzip rsync openssh gnupg \
    fzf zoxide rclone \
    rustup uv \
    helix neovim \
    noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd

log "initializing rustup stable toolchain if needed"
if ! rustc --version &>/dev/null; then
    rustup default stable
fi
```

- [ ] **Step 2: Make executable, syntax-check**

```bash
chmod +x ~/dotfiles/install/01-pacman.sh
bash -n ~/dotfiles/install/01-pacman.sh && echo OK
```

Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
cd ~/dotfiles && git add install/01-pacman.sh
git commit -m "$(cat <<'EOF'
install: add 01-pacman.sh (core packages)

Cross-profile pacman base: build tools, shell, editors (helix + neovim),
fzf/zoxide/rclone, rustup + uv, fonts. Drops micro (removed in Wave 1)
and debian branch (tenet #2: Arch only).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Create `install/02-paru.sh`

**Files:**
- Create: `install/02-paru.sh`

Purpose: bootstrap the paru AUR helper if missing. On existing installs where paru already exists (like Scott's current machine), this is a no-op. The existing `base/paru/` config is stowed later in `08-stow-base.sh`.

- [ ] **Step 1: Write `install/02-paru.sh`**

```bash
#!/usr/bin/env bash
# install/02-paru.sh — bootstrap paru from AUR if missing
set -euo pipefail
source "$(dirname "$0")/_common.sh"

if command -v paru &>/dev/null; then
    log "paru already installed ($(paru --version | head -1)); skipping bootstrap"
    exit 0
fi

log "bootstrapping paru from AUR"
need_pkg base-devel git

# Clone + build in a throwaway temp dir
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git clone https://aur.archlinux.org/paru.git "$tmp/paru"
(
    cd "$tmp/paru"
    makepkg -si --noconfirm
)

log "paru bootstrapped: $(paru --version | head -1)"
```

- [ ] **Step 2: Syntax-check + chmod**

```bash
chmod +x ~/dotfiles/install/02-paru.sh
bash -n ~/dotfiles/install/02-paru.sh && echo OK
```

Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
cd ~/dotfiles && git add install/02-paru.sh
git commit -m "$(cat <<'EOF'
install: add 02-paru.sh (AUR helper bootstrap)

Idempotent paru install via makepkg. No-op if paru already on PATH.
Cache-redirect config (base/paru/paru.conf) is applied later by
08-stow-base.sh.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Create `install/03-system.sh`

**Files:**
- Create: `install/03-system.sh`

Purpose: one-time system config — Oh My Zsh install, zsh plugins clone, zsh as default shell, pam_systemd_home fix check. Runs on all profiles.

The pam_systemd_home check is referenced in the user's memory (`pam-sudo-fix.md`) — `/etc/pam.d/system-auth` needs a specific line commented. The script verifies the state and warns (does NOT auto-edit `/etc/pam.d/` — too dangerous).

- [ ] **Step 1: Write `install/03-system.sh`**

```bash
#!/usr/bin/env bash
# install/03-system.sh — user-level system config (Oh My Zsh, plugins, shell, pam warning)
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# --- Oh My Zsh ---
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    log "installing Oh My Zsh"
    RUNZSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    log "Oh My Zsh already installed"
fi

# --- Zsh plugins ---
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
clone_if_missing \
    https://github.com/zsh-users/zsh-autosuggestions.git \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone_if_missing \
    https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# --- Default shell ---
if [[ "$SHELL" != "$(command -v zsh)" ]]; then
    log "setting zsh as default shell for $USER"
    chsh -s "$(command -v zsh)" || warn "chsh failed; run manually: chsh -s \$(which zsh)"
fi

# --- pam_systemd_home sanity check ---
# Per user memory: /etc/pam.d/system-auth must have the pam_systemd_home auth line
# commented out, otherwise sudo/su behave oddly. Pambase updates regress this.
# We do NOT auto-edit /etc/pam.d/*; we only warn.
if [[ -f /etc/pam.d/system-auth ]] \
        && grep -qE '^\s*auth.*pam_systemd_home' /etc/pam.d/system-auth 2>/dev/null; then
    warn "pam_systemd_home auth line is ACTIVE in /etc/pam.d/system-auth"
    warn "  This may regress sudo/su behavior on this system."
    warn "  Comment out the line manually, then verify with: sudo true"
fi
```

- [ ] **Step 2: Syntax-check + chmod**

```bash
chmod +x ~/dotfiles/install/03-system.sh
bash -n ~/dotfiles/install/03-system.sh && echo OK
```

Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
cd ~/dotfiles && git add install/03-system.sh
git commit -m "$(cat <<'EOF'
install: add 03-system.sh (shell + pam sanity)

Oh My Zsh, zsh plugins (autosuggestions, syntax-highlighting), chsh to
zsh, pam_systemd_home regression check with a loud warning (no auto-edit
of /etc/pam.d/*).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Create `install/04-hyprland.sh` and `install/05-desktop.sh`

**Files:**
- Create: `install/04-hyprland.sh`
- Create: `install/05-desktop.sh`

Purpose: install Hyprland compositor stack + desktop support packages. Both scripts are workstation-only (early-exit on server).

Port from current `install.sh` lines 63-74 (the desktop packages block), filtering out obsolete tools (there were none — current list is correct). Split cleanly: compositor-proper (Hyprland + its portal + locker + idle + wallpaper daemon) in one script, desktop support (bar, notifications, launcher, terminal, clipboard, audio, fonts) in the other.

- [ ] **Step 1: Write `install/04-hyprland.sh`**

```bash
#!/usr/bin/env bash
# install/04-hyprland.sh — Hyprland compositor + co-located tools (workstation only)
set -euo pipefail
source "$(dirname "$0")/_common.sh"
skip_unless_profile workstation

log "installing Hyprland stack"
need_pkg \
    hyprland \
    hyprlock \
    hypridle \
    hyprpaper \
    xdg-desktop-portal-hyprland \
    polkit-gnome
```

- [ ] **Step 2: Write `install/05-desktop.sh`**

```bash
#!/usr/bin/env bash
# install/05-desktop.sh — status bar, notifications, launcher, terminal, audio, fonts
set -euo pipefail
source "$(dirname "$0")/_common.sh"
skip_unless_profile workstation

log "installing desktop support packages"
need_pkg \
    waybar mako fuzzel ghostty \
    grim slurp wl-clipboard \
    pipewire wireplumber pipewire-pulse \
    brightnessctl playerctl \
    ttf-jetbrains-mono-nerd
```

- [ ] **Step 3: Syntax-check both + chmod**

```bash
chmod +x ~/dotfiles/install/04-hyprland.sh ~/dotfiles/install/05-desktop.sh
bash -n ~/dotfiles/install/04-hyprland.sh && echo OK
bash -n ~/dotfiles/install/05-desktop.sh && echo OK
```

Expected: `OK` twice.

- [ ] **Step 4: Commit both**

```bash
cd ~/dotfiles && git add install/04-hyprland.sh install/05-desktop.sh
git commit -m "$(cat <<'EOF'
install: add 04-hyprland.sh + 05-desktop.sh (workstation-only)

04: Hyprland compositor stack (hyprland, hyprlock, hypridle, hyprpaper,
portal, polkit-gnome).
05: Desktop support (waybar, mako, fuzzel, ghostty, screenshot tools,
clipboard, pipewire audio, media keys, fonts). Both early-exit on
server profile via skip_unless_profile.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Create `install/06-tools.sh` (developer tooling + kickstart.nvim)

**Files:**
- Create: `install/06-tools.sh`

Purpose: everything developer-tool-adjacent that isn't pacman-managed. uv project sync, window-picker Rust build, nvm + Node LTS (needed for Claude Code npm install in Task 8), kickstart.nvim clone + pcall-require injection.

This is the largest install script. Consider it the "miscellaneous developer stack" step.

- [ ] **Step 1: Write `install/06-tools.sh`**

```bash
#!/usr/bin/env bash
# install/06-tools.sh — uv tools/, window-picker build, nvm+Node, kickstart.nvim bootstrap
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# --- uv sync the tools/ project ---
if [[ -f "$DOTFILES/tools/pyproject.toml" ]]; then
    log "uv sync tools/"
    (cd "$DOTFILES/tools" && uv sync --quiet)
else
    warn "tools/pyproject.toml not found; skipping uv sync"
fi

# Wrapper scripts are expected at $DOTFILES/base/bin/.local/bin/ (stowed later).
# The tools/ project exposes them via uv-managed entry points; no symlinks needed
# beyond what base/bin/ already provides.

# --- Build tools/window-picker (Rust binary) — workstation only ---
if profile_is workstation; then
    WP_DIR="$DOTFILES/tools/window-picker"
    WP_BIN="$WP_DIR/target/release/window-picker"
    if [[ -d "$WP_DIR" ]]; then
        if [[ ! -x "$WP_BIN" ]]; then
            log "building window-picker (Rust release)"
            (cd "$WP_DIR" && cargo build --release)
        else
            log "window-picker already built"
        fi
    fi
fi

# --- nvm + Node LTS (Claude Code is an npm package, needs Node) ---
export NVM_DIR="$HOME/.nvm"
if [[ ! -d "$NVM_DIR" ]]; then
    log "installing nvm"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi
# shellcheck source=/dev/null
. "$NVM_DIR/nvm.sh"
if ! command -v node &>/dev/null; then
    log "installing Node LTS via nvm"
    nvm install --lts
fi

# --- kickstart.nvim bootstrap ---
NVIM_DIR="$HOME/.config/nvim"
KICKSTART_URL="https://github.com/nvim-lua/kickstart.nvim.git"
# NOTE: once Scott forks kickstart on his own GitHub, swap the URL above for
# his fork's clone URL. The fork is the intended long-term source.

if [[ ! -d "$NVIM_DIR" ]] || [[ -z "$(ls -A "$NVIM_DIR" 2>/dev/null)" ]]; then
    log "cloning kickstart.nvim to $NVIM_DIR"
    git clone "$KICKSTART_URL" "$NVIM_DIR"
else
    log "nvim config directory already exists; skipping kickstart clone"
fi

# Ensure the theme opt-in line is present at the end of init.lua.
# Idempotent: only appends if the line isn't already there.
INIT_LUA="$NVIM_DIR/init.lua"
OPT_IN_LINE="pcall(require, 'dotfiles-theme')"
if [[ -f "$INIT_LUA" ]]; then
    if ! grep -qF "$OPT_IN_LINE" "$INIT_LUA"; then
        log "appending theme opt-in to $INIT_LUA"
        printf '\n-- Dotfiles theme opt-in (see themes/*/nvim.lua)\n%s\n' "$OPT_IN_LINE" >> "$INIT_LUA"
    else
        log "theme opt-in line already present in init.lua"
    fi
else
    warn "no init.lua at $INIT_LUA; theme opt-in not injected"
fi
```

- [ ] **Step 2: Syntax-check + chmod**

```bash
chmod +x ~/dotfiles/install/06-tools.sh
bash -n ~/dotfiles/install/06-tools.sh && echo OK
```

Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
cd ~/dotfiles && git add install/06-tools.sh
git commit -m "$(cat <<'EOF'
install: add 06-tools.sh (dev tools + kickstart.nvim)

uv sync tools/, build window-picker Rust binary (workstation only),
install nvm + Node LTS, clone kickstart.nvim to ~/.config/nvim if
missing, idempotently append pcall(require, 'dotfiles-theme') to
init.lua so Wave 3's theme system can hook in.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Create `install/07-claude.sh`

**Files:**
- Create: `install/07-claude.sh`

Purpose: install Claude Code CLI globally (npm), ensure `~/projects/agent-skills` is cloned. This runs AFTER `06-tools.sh` so that Node is available.

The `agent-skills` project is the user's custom Claude Code plugin — its location is `~/projects/agent-skills` per memory. If the directory doesn't exist, this script prints a warning with the clone command but does NOT attempt the clone (the repo URL is user-specific and not fixed).

- [ ] **Step 1: Write `install/07-claude.sh`**

```bash
#!/usr/bin/env bash
# install/07-claude.sh — Claude Code CLI + agent-skills sanity check
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# --- Claude Code CLI (npm global) ---
# nvm must have placed node on PATH by way of 06-tools.sh sourcing nvm.sh.
# Re-source here to be safe when this script is run standalone.
export NVM_DIR="$HOME/.nvm"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"
fi

if ! command -v claude &>/dev/null; then
    log "installing Claude Code CLI via npm"
    npm install -g @anthropic-ai/claude-code
else
    log "Claude Code already on PATH: $(claude --version 2>&1 | head -1)"
fi

# --- agent-skills sanity check ---
AGENT_SKILLS_DIR="$HOME/projects/agent-skills"
if [[ ! -d "$AGENT_SKILLS_DIR/.git" ]]; then
    warn "$AGENT_SKILLS_DIR is not a git repo."
    warn "  Clone it manually once (repo URL is user-specific):"
    warn "    mkdir -p $HOME/projects"
    warn "    git clone <your-agent-skills-url> $AGENT_SKILLS_DIR"
else
    log "agent-skills present at $AGENT_SKILLS_DIR"
fi
```

- [ ] **Step 2: Syntax-check + chmod**

```bash
chmod +x ~/dotfiles/install/07-claude.sh
bash -n ~/dotfiles/install/07-claude.sh && echo OK
```

Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
cd ~/dotfiles && git add install/07-claude.sh
git commit -m "$(cat <<'EOF'
install: add 07-claude.sh (Claude Code + agent-skills check)

npm install -g @anthropic-ai/claude-code if not already on PATH. Warn
(don't attempt) if ~/projects/agent-skills is missing — repo URL is
user-specific and shouldn't be hardcoded.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Create `install/08-stow-base.sh` and `install/09-stow-profile.sh`

**Files:**
- Create: `install/08-stow-base.sh`
- Create: `install/09-stow-profile.sh`

Purpose: porting the stow logic from current `install.sh` lines 131-168. Preserves the `--adopt` + `git checkout` trick that lets stow absorb existing defaults (e.g., Oh My Zsh's default `.zshrc`) and then restores the repo's preferred version.

- [ ] **Step 1: Write `install/08-stow-base.sh`**

```bash
#!/usr/bin/env bash
# install/08-stow-base.sh — stow every base/* package (skip desktop pkgs on server)
set -euo pipefail
source "$(dirname "$0")/_common.sh"

log "stowing base/* packages"
cd "$DOTFILES"

for pkg_path in base/*/; do
    pkg_name="$(basename "$pkg_path")"

    # Skip desktop packages on headless/server
    if ! profile_is workstation; then
        case "$pkg_name" in
            hypr|waybar|mako|ghostty|fuzzel) continue ;;
        esac
    fi

    # --adopt absorbs existing files at $HOME so stow can succeed on fresh
    # installs (Oh My Zsh drops a default .zshrc, etc.); the git checkout
    # below restores the repo's intended content.
    stow -d base -t "$HOME" --no-folding --adopt "$pkg_name" 2>/dev/null \
        || stow -d base -t "$HOME" --no-folding "$pkg_name"
done

# WARNING: this reverts ALL uncommitted changes in base/, including intentional
# edits. Always commit or stash base/ edits before running install.sh; the
# orchestrator preflight doesn't check (but dot-doctor should be able to flag
# the risk on demand in future).
git checkout -- base/
```

- [ ] **Step 2: Write `install/09-stow-profile.sh`**

```bash
#!/usr/bin/env bash
# install/09-stow-profile.sh — stow profiles/$PROFILE/* packages
set -euo pipefail
source "$(dirname "$0")/_common.sh"

PROFILE_DIR="$DOTFILES/profiles/$PROFILE"
if [[ ! -d "$PROFILE_DIR" ]]; then
    die "profile directory not found: $PROFILE_DIR"
fi

log "stowing $PROFILE_DIR/* packages"
cd "$DOTFILES"

for pkg_path in "$PROFILE_DIR"/*/; do
    pkg_name="$(basename "$pkg_path")"
    # Profile packages add to base directories (e.g. zsh adds to ~/.zshrc.d/)
    # If conflict with base, unstow base's version and retry
    if ! stow -d "$PROFILE_DIR" -t "$HOME" --no-folding -R "$pkg_name" 2>/dev/null; then
        log "conflict stowing profile pkg $pkg_name; unstowing base/$pkg_name and retrying"
        stow -d base -t "$HOME" --no-folding -D "$pkg_name" 2>/dev/null || true
        stow -d "$PROFILE_DIR" -t "$HOME" --no-folding -R "$pkg_name"
    fi
done
```

- [ ] **Step 3: Syntax-check both + chmod**

```bash
chmod +x ~/dotfiles/install/08-stow-base.sh ~/dotfiles/install/09-stow-profile.sh
bash -n ~/dotfiles/install/08-stow-base.sh && echo OK
bash -n ~/dotfiles/install/09-stow-profile.sh && echo OK
```

Expected: `OK` twice.

- [ ] **Step 4: Commit**

```bash
cd ~/dotfiles && git add install/08-stow-base.sh install/09-stow-profile.sh
git commit -m "$(cat <<'EOF'
install: add 08/09 stow scripts (base + profile)

Ports stow logic from monolithic install.sh lines 131-168. Preserves
the --adopt + `git checkout -- base/` trick (absorb user defaults so
stow succeeds on fresh installs, then restore repo content). Profile
packages retry with base unstowed on conflict.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Create `install/10-theme.sh` (stub) and `install/11-services.sh`

**Files:**
- Create: `install/10-theme.sh`
- Create: `install/11-services.sh`

Purpose:
- `10-theme.sh` is a *Wave 2 stub*. It reads `~/.config/dotfiles/active-theme` if present and invokes the legacy `theme-switch` script or the future `dot-theme-set`. In Wave 3 this becomes a real script.
- `11-services.sh` enables systemd user units for gdrive-bisync and any others needed.

For systemd services — inspect what exists in `base/systemd/` to know which units to enable. As of Wave 1, that directory contains service/timer files (the gdrive-bisync timer per memory). The script enables each unit found.

- [ ] **Step 1: Inspect existing systemd units**

```bash
find ~/dotfiles/base/systemd -type f -name '*.service' -o -name '*.timer' 2>/dev/null
```

Record the output. The script written below enables each found unit generically.

- [ ] **Step 2: Write `install/10-theme.sh` (stub)**

```bash
#!/usr/bin/env bash
# install/10-theme.sh — apply active theme (Wave 2 STUB; Wave 3 rewrites)
set -euo pipefail
source "$(dirname "$0")/_common.sh"
skip_unless_profile workstation

ACTIVE_THEME_FILE="$HOME/.config/dotfiles/active-theme"

# Wave 2 behavior: delegate to existing theme-switch if it's installed.
# Wave 3 replaces this with a real dot-theme-set invocation that understands
# themes/<name>/ directory layouts.

if [[ -f "$ACTIVE_THEME_FILE" ]]; then
    theme=$(<"$ACTIVE_THEME_FILE")
    log "active theme marker: $theme (Wave 2 stub — no-op; Wave 3 will apply)"
else
    log "no active theme set; Wave 3 will populate $ACTIVE_THEME_FILE"
fi

# Wave 2 intentional no-op: existing theme-switch is invoked manually via
# keybinds the user already has configured. Do not auto-run it here.
exit 0
```

- [ ] **Step 3: Write `install/11-services.sh`**

```bash
#!/usr/bin/env bash
# install/11-services.sh — enable systemd user units stowed from base/systemd/
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# base/systemd/ stows to ~/.config/systemd/user/*.service + *.timer
UNIT_DIR="$HOME/.config/systemd/user"

if [[ ! -d "$UNIT_DIR" ]]; then
    log "no user systemd unit directory ($UNIT_DIR); skipping"
    exit 0
fi

systemctl --user daemon-reload

for unit_file in "$UNIT_DIR"/*.timer "$UNIT_DIR"/*.service; do
    [[ -e "$unit_file" ]] || continue
    unit_name="$(basename "$unit_file")"
    log "enabling $unit_name"
    systemctl --user enable --now "$unit_name" 2>&1 | grep -v '^Created symlink' || true
done
```

- [ ] **Step 4: Syntax-check + chmod**

```bash
chmod +x ~/dotfiles/install/10-theme.sh ~/dotfiles/install/11-services.sh
bash -n ~/dotfiles/install/10-theme.sh && echo OK
bash -n ~/dotfiles/install/11-services.sh && echo OK
```

Expected: `OK` twice.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add install/10-theme.sh install/11-services.sh
git commit -m "$(cat <<'EOF'
install: add 10-theme.sh (stub) + 11-services.sh

10-theme.sh: Wave 2 stub — reads active-theme marker if present,
otherwise no-op. Wave 3 rewrites to apply the directory-per-theme
system via dot-theme-set.
11-services.sh: enable every .service/.timer stowed to
~/.config/systemd/user/ (e.g. gdrive-bisync timer).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Rewrite `install.sh` as the orchestrator

**Files:**
- Modify: `install.sh` (complete rewrite — 172 lines → ~50)

Purpose: `install.sh` becomes a short shell that validates the profile argument, exports `$DOTFILES` and `$PROFILE`, sources `profiles/$PROFILE/profile.conf`, then sources each `install/*.sh` in lexical order.

- [ ] **Step 1: Read current install.sh as reference**

```bash
cat ~/dotfiles/install.sh | head -20
```

Note: the current file will be entirely replaced. The backup is in git history (previous commit `c89dfdec`). No separate backup needed.

- [ ] **Step 2: Write the new install.sh**

Use the `Edit` tool to replace the entire contents:

```bash
#!/usr/bin/env bash
# install.sh — orchestrator that runs install/*.sh in order.
#
# Usage:
#   ./install.sh <workstation|server>
#
# Each install/*.sh is independently runnable. Re-runs are idempotent
# (pacman --needed, stow -R, systemctl --now etc.). See docs/manual/01-install.md
# (Wave 4) for the script-by-script walkthrough.

set -euo pipefail

PROFILE="${1:-}"
DOTFILES="$(cd "$(dirname "$0")" && pwd)"

# --- Usage ---
if [[ -z "$PROFILE" ]] || [[ ! -d "$DOTFILES/profiles/$PROFILE" ]]; then
    echo "Usage: ./install.sh <profile>"
    echo ""
    echo "Available profiles:"
    for p in "$DOTFILES"/profiles/*/; do
        echo "  $(basename "$p")"
    done
    exit 1
fi

export DOTFILES PROFILE

# --- Source profile vars (OBSIDIAN_VAULT, etc.) ---
PROFILE_CONF="$DOTFILES/profiles/$PROFILE/profile.conf"
if [[ -f "$PROFILE_CONF" ]]; then
    # shellcheck source=/dev/null
    source "$PROFILE_CONF"
fi

echo "=== dotfiles bootstrap (profile: $PROFILE) ==="

# --- Run each install/*.sh in lexical order ---
for script in "$DOTFILES"/install/[0-9][0-9]-*.sh; do
    echo ""
    echo ">>> $(basename "$script")"
    bash "$script"
done

echo ""
echo "=== Done! (profile: $PROFILE) ==="
echo "Manual steps:"
echo "  1. Set up SSH keys: ssh-keygen -t ed25519"
echo "  2. Log out and back in for zsh to take effect"
```

- [ ] **Step 3: Verify executable and syntax**

```bash
chmod +x ~/dotfiles/install.sh
bash -n ~/dotfiles/install.sh && echo OK
```

Expected: `OK`.

- [ ] **Step 4: Smoke test — usage output only**

```bash
cd ~/dotfiles && ./install.sh 2>&1 | head -10
```

Expected: prints "Usage: ./install.sh <profile>" + list of available profiles (`workstation`, `server`). Exits 1. Does NOT try to install anything.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add install.sh
git commit -m "$(cat <<'EOF'
install: rewrite install.sh as ~50-line orchestrator

Replaces the 172-line monolith. New install.sh validates profile arg,
exports DOTFILES + PROFILE, sources profile.conf, then runs every
install/[0-9][0-9]-*.sh in lexical order. All real work now lives in
install/*.sh modules.

Drops the debian/apt branch and all distro detection per tenet #2
(Arch + Hyprland, no apologies).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Create `bin/` with four `dot-*` helpers

**Files:**
- Create: `bin/dot-restow`
- Create: `bin/dot-theme-set` (stub)
- Create: `bin/dot-update`
- Create: `bin/dot-doctor`

Purpose: re-runnable helpers added to PATH via Task 12's zshrc.d snippet. Each is independently usable.

- [ ] **Step 1: Write `bin/dot-restow`**

```bash
#!/usr/bin/env bash
# bin/dot-restow — re-stow one or all packages in base/ and the active profile
# Usage:
#   dot-restow <pkg>         # restow a specific package
#   dot-restow --all         # restow everything
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"

ACTIVE_PROFILE=""
if [[ -f "$HOME/.config/dotfiles/active-profile" ]]; then
    ACTIVE_PROFILE=$(<"$HOME/.config/dotfiles/active-profile")
fi

if [[ -z "$ACTIVE_PROFILE" ]]; then
    # Fallback: infer from existing symlinks
    if [[ -L "$HOME/.gitconfig.local" ]]; then
        target=$(readlink "$HOME/.gitconfig.local")
        case "$target" in
            *profiles/workstation*) ACTIVE_PROFILE=workstation ;;
            *profiles/server*)      ACTIVE_PROFILE=server ;;
        esac
    fi
fi

if [[ -z "$ACTIVE_PROFILE" ]]; then
    echo "dot-restow: cannot infer active profile; set one manually:" >&2
    echo "  mkdir -p ~/.config/dotfiles && echo workstation > ~/.config/dotfiles/active-profile" >&2
    exit 1
fi

restow_one() {
    local pkg="$1"
    if [[ -d "$DOTFILES/base/$pkg" ]]; then
        echo "[base] restowing $pkg"
        stow -d "$DOTFILES/base" -t "$HOME" --no-folding -R "$pkg"
    fi
    if [[ -d "$DOTFILES/profiles/$ACTIVE_PROFILE/$pkg" ]]; then
        echo "[profile:$ACTIVE_PROFILE] restowing $pkg"
        stow -d "$DOTFILES/profiles/$ACTIVE_PROFILE" -t "$HOME" --no-folding -R "$pkg"
    fi
}

case "${1:-}" in
    --all)
        for p in "$DOTFILES"/base/*/; do
            restow_one "$(basename "$p")"
        done
        for p in "$DOTFILES"/profiles/"$ACTIVE_PROFILE"/*/; do
            restow_one "$(basename "$p")"
        done
        ;;
    ""|-h|--help)
        echo "Usage: dot-restow <pkg>|--all"
        exit 1
        ;;
    *)
        restow_one "$1"
        ;;
esac
```

- [ ] **Step 2: Write `bin/dot-theme-set` (Wave 2 stub)**

```bash
#!/usr/bin/env bash
# bin/dot-theme-set — switch active theme (Wave 2 STUB; Wave 3 rewrites)
#
# Wave 2 behavior: delegates to the existing theme-switch script if on PATH.
# Wave 3 replaces this with a real implementation that reads themes/<name>/
# and symlinks each per-app snippet into place.
set -euo pipefail

THEME_NAME="${1:-}"

if [[ -z "$THEME_NAME" ]]; then
    echo "Usage: dot-theme-set <theme-name>"
    echo ""
    echo "Wave 2 stub: delegates to 'theme-switch' if present."
    echo "Wave 3 will implement directory-per-theme layout under ~/dotfiles/themes/."
    exit 1
fi

if command -v theme-switch &>/dev/null; then
    echo "[dot-theme-set] (Wave 2 stub) delegating to theme-switch $THEME_NAME"
    exec theme-switch "$THEME_NAME"
fi

echo "dot-theme-set: no theme-switch on PATH and Wave 3 not yet implemented." >&2
echo "Install Wave 3 to get the real dot-theme-set." >&2
exit 1
```

- [ ] **Step 3: Write `bin/dot-update`**

```bash
#!/usr/bin/env bash
# bin/dot-update — system update + re-stow everything
# Runs: paru -Syu, then dot-restow --all.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"

echo "==> paru -Syu (system + AUR update)"
paru -Syu

echo ""
echo "==> dot-restow --all"
"$DOTFILES/bin/dot-restow" --all

echo ""
echo "==> dot-update complete"
```

- [ ] **Step 4: Write `bin/dot-doctor`**

```bash
#!/usr/bin/env bash
# bin/dot-doctor — environment sanity checks for the dotfiles system
# Prints one check per line; green ✓ on success, red ✗ on failure. Non-zero exit
# if any check fails.
set -u  # not -e: we want to keep running after individual check failures

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"

GREEN=$'\033[1;32m'
RED=$'\033[1;31m'
RESET=$'\033[0m'

failures=0

check() {
    local label="$1" cmd="$2"
    if eval "$cmd" &>/dev/null; then
        printf '%s✓%s %s\n' "$GREEN" "$RESET" "$label"
    else
        printf '%s✗%s %s\n' "$RED" "$RESET" "$label"
        failures=$((failures+1))
    fi
}

echo "== dot-doctor =="

check "DOTFILES env var set"          "[[ -n \"\$DOTFILES\" ]]"
check "\$DOTFILES/bin on PATH"         "echo \"\$PATH\" | grep -qF \"\$DOTFILES/bin\""
check "stow installed"                 "command -v stow"
check "paru installed"                 "command -v paru"
check "zsh is default shell"           "[[ \"\$SHELL\" == \"\$(command -v zsh)\" ]]"
check "claude on PATH"                 "command -v claude"
check "~/.gitconfig.local symlink ok" "[[ -L \"\$HOME/.gitconfig.local\" ]] && [[ -e \"\$HOME/.gitconfig.local\" ]]"
check "~/gdrive is mounted"            "mountpoint -q \"\$HOME/gdrive\""
check "tailscale active"               "systemctl is-active --quiet tailscaled"
check "JetBrains Mono Nerd Font installed" "fc-list | grep -qi 'jetbrainsmono nerd font'"
check "pam_systemd_home NOT active"    "! grep -qE '^\\s*auth.*pam_systemd_home' /etc/pam.d/system-auth"
check "~/.local/bin on PATH"           "echo \"\$PATH\" | grep -qE '(^|:)\$HOME/.local/bin(:|\$)'"
check "~/projects/agent-skills is a git repo" "[[ -d \"\$HOME/projects/agent-skills/.git\" ]]"
check "~/.config/nvim/init.lua has theme opt-in" "grep -qF \"pcall(require, 'dotfiles-theme')\" \"\$HOME/.config/nvim/init.lua\""

echo ""
if [[ "$failures" -eq 0 ]]; then
    printf '%sAll checks passed.%s\n' "$GREEN" "$RESET"
    exit 0
else
    printf '%s%d check(s) failed.%s\n' "$RED" "$failures" "$RESET"
    exit 1
fi
```

- [ ] **Step 5: Make all four executable + syntax-check**

```bash
chmod +x ~/dotfiles/bin/dot-restow ~/dotfiles/bin/dot-theme-set ~/dotfiles/bin/dot-update ~/dotfiles/bin/dot-doctor
for f in ~/dotfiles/bin/dot-*; do bash -n "$f" && echo "OK: $f"; done
```

Expected: `OK: ...` for all four.

- [ ] **Step 6: Commit**

```bash
cd ~/dotfiles && git add bin/dot-restow bin/dot-theme-set bin/dot-update bin/dot-doctor
git commit -m "$(cat <<'EOF'
bin: add dot-restow, dot-theme-set (stub), dot-update, dot-doctor

Four re-runnable helpers for post-install operations:

- dot-restow <pkg|--all>: wraps stow invocations for daily use
- dot-theme-set <name>: Wave 2 stub, delegates to existing theme-switch
- dot-update: paru -Syu + dot-restow --all
- dot-doctor: env sanity checks (stow symlinks, PATH, mounts, services,
  pam, claude, agent-skills, nvim theme opt-in)

Path integration comes in Task 12 (base/zsh/.zshrc.d/dotfiles.zsh).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Create `base/zsh/.zshrc.d/dotfiles.zsh` (PATH + env)

**Files:**
- Create: `base/zsh/.zshrc.d/dotfiles.zsh`

Purpose: export `$DOTFILES` and prepend `$DOTFILES/bin` to `$PATH` for interactive shells. Stowed by `08-stow-base.sh` so it ends up at `~/.zshrc.d/dotfiles.zsh`, sourced by the base `.zshrc`.

- [ ] **Step 1: Verify base/zsh/.zshrc.d directory exists**

```bash
ls -la ~/dotfiles/base/zsh/.zshrc.d/ 2>/dev/null
```

If it doesn't exist yet, create it. It should exist (profile zsh fragments live at `profiles/workstation/zsh/.zshrc.d/`, but base zsh/.zshrc.d/ might be empty or not yet present).

```bash
mkdir -p ~/dotfiles/base/zsh/.zshrc.d
```

- [ ] **Step 2: Write `dotfiles.zsh`**

```bash
# base/zsh/.zshrc.d/dotfiles.zsh — exports DOTFILES and prepends $DOTFILES/bin to PATH
# Stowed to ~/.zshrc.d/dotfiles.zsh; sourced by the base .zshrc loop.

# Point to the dotfiles checkout. Follows symlinks to a real directory.
export DOTFILES="${DOTFILES:-$HOME/dotfiles}"

# Prepend $DOTFILES/bin so dot-* helpers win over anything else on PATH.
if [[ -d "$DOTFILES/bin" ]] && [[ ":$PATH:" != *":$DOTFILES/bin:"* ]]; then
    export PATH="$DOTFILES/bin:$PATH"
fi
```

- [ ] **Step 3: Ensure the base .zshrc sources .zshrc.d/*.zsh**

Check the existing base/zsh config:

```bash
cat ~/dotfiles/base/zsh/.zshrc | grep -E 'zshrc\.d' | head -5
```

If there's already a `for f in ~/.zshrc.d/*.zsh; do source "$f"; done` loop or similar, nothing to do. If not, report BLOCKED — the wiring needs manual attention.

Most likely the loop already exists (profile fragments `personal.zsh`/`workstation.zsh` are sourced via this mechanism).

- [ ] **Step 4: Live test (since .zshrc.d/ may or may not currently be symlinked)**

```bash
cd ~/dotfiles && stow -d base -t ~ --no-folding -R zsh
zsh -ic 'echo $DOTFILES; echo $PATH | tr ":" "\n" | head -5'
```

Expected:
- `$DOTFILES` printed (should equal `/home/scott/dotfiles` after this)
- `$PATH` includes `/home/scott/dotfiles/bin` near the front

- [ ] **Step 5: Sanity-check the dot-* helpers resolve**

```bash
which dot-restow
which dot-doctor
```

Expected: both resolve to `/home/scott/dotfiles/bin/dot-{restow,doctor}`.

- [ ] **Step 6: Commit**

```bash
cd ~/dotfiles && git add base/zsh/.zshrc.d/dotfiles.zsh
git commit -m "$(cat <<'EOF'
zsh: add dotfiles.zsh fragment — DOTFILES env + bin/ on PATH

Stows to ~/.zshrc.d/dotfiles.zsh. Exports DOTFILES (defaults to
~/dotfiles) and prepends $DOTFILES/bin so dot-restow/dot-theme-set/
dot-update/dot-doctor are on PATH for interactive shells.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Live kickstart.nvim bootstrap + verify

**Files:** none modified in the dotfiles repo. This task exercises `install/06-tools.sh` on the live machine and confirms the end state.

- [ ] **Step 1: Run 06-tools.sh in isolation**

```bash
cd ~/dotfiles && DOTFILES=~/dotfiles PROFILE=workstation bash install/06-tools.sh
```

Expected output sequence:
- "uv sync tools/" (or skip if already synced)
- "window-picker already built" (or build if missing)
- "installing nvm" (if missing) or skip
- "installing Node LTS via nvm" (if missing) or skip
- "cloning kickstart.nvim to /home/scott/.config/nvim" (if empty) or skip
- "appending theme opt-in to .../init.lua" (if absent) or skip

No errors. Exit 0.

- [ ] **Step 2: Verify kickstart cloned**

```bash
ls -la ~/.config/nvim/ | head
git -C ~/.config/nvim log --oneline -3
```

Expected: directory populated with kickstart's layout (`init.lua`, `lua/`, `README.md`, etc.), git log shows kickstart's upstream history.

- [ ] **Step 3: Verify theme opt-in line is present**

```bash
tail -5 ~/.config/nvim/init.lua
grep -c "pcall(require, 'dotfiles-theme')" ~/.config/nvim/init.lua
```

Expected: tail shows `pcall(require, 'dotfiles-theme')` line; grep count is exactly `1`.

- [ ] **Step 4: Re-run to verify idempotence**

```bash
cd ~/dotfiles && DOTFILES=~/dotfiles PROFILE=workstation bash install/06-tools.sh
```

Expected: every log line says "already installed" / "skipping" / "already present". No re-cloning, no re-install. Exit 0.

- [ ] **Step 5: Open nvim once and verify it starts**

```bash
nvim --headless '+qall' 2>&1 | head
```

Expected: no errors, no "module not found" related to `dotfiles-theme` (the `pcall` catches the missing module silently — that's the whole point of opt-in).

- [ ] **Step 6: No commit (this task only exercises code already committed).**

---

## Task 14: Idempotence test — run full `./install.sh workstation`

**Files:** none in the dotfiles repo. Live-machine validation that the full orchestrator + all modules run cleanly as a re-install.

### ⚠️ Preflight gate

`install/08-stow-base.sh` ends with `git checkout -- base/`, which will destroy uncommitted changes in `base/*`. Refuse to run Task 14 until the following command returns empty:

```bash
cd ~/dotfiles && git status --porcelain -- base/
```

If that command returns any output, STOP and report BLOCKED. The controller must commit, stash, or explicitly accept the loss before re-dispatching Task 14.

- [ ] **Step 0: Preflight — no uncommitted changes in `base/`**

```bash
cd ~/dotfiles && git status --porcelain -- base/
```

Expected: empty output. If non-empty, STOP — do not proceed.

- [ ] **Step 1: Run the full install**

```bash
cd ~/dotfiles && ./install.sh workstation 2>&1 | tee /tmp/dotfiles-install-log.txt
```

Expected:
- Orchestrator prints `=== dotfiles bootstrap (profile: workstation) ===`
- Sources profile.conf silently
- Each of the 11 scripts runs in order with a `>>> ##-name.sh` banner
- Every package `need_pkg` call is a no-op ("there is nothing to do" or silence)
- Every `clone_if_missing` says "already populated, skipping"
- Stow scripts restow everything without errors
- Systemd enables are idempotent (already enabled)
- Final line: `=== Done! (profile: workstation) ===`

- [ ] **Step 2: Check for broken symlinks**

```bash
find ~/.config ~/.local -xtype l 2>/dev/null | grep -vE '/(Lock|lock)$'
```

Expected: empty (filter out Obsidian/Firefox runtime lock files).

- [ ] **Step 3: Run dot-doctor**

```bash
~/dotfiles/bin/dot-doctor
```

Expected: all checks pass (or only the agent-skills check fails if the user hasn't cloned it; that's acceptable for first run).

- [ ] **Step 4: Verify shell session sees PATH changes**

```bash
zsh -ic 'which dot-restow; which dot-doctor; echo $DOTFILES'
```

Expected: both helpers resolve to `$DOTFILES/bin/*`; DOTFILES env is set.

- [ ] **Step 5: Report log size and error grep**

```bash
wc -l /tmp/dotfiles-install-log.txt
grep -iE 'error|warning|failed' /tmp/dotfiles-install-log.txt | grep -vE 'WARNING.*ssl' | head -20
```

Note any errors or warnings that are NOT already expected (pam_systemd_home warning is expected and intentional; npm warnings about deprecation are acceptable).

- [ ] **Step 6: No commit.**

If Steps 1-5 all pass, Wave 2 is functionally complete. If any step fails, report BLOCKED with the specific failure; controller will decide whether to patch forward or revert.

---

## Task 15: Final verification

**Files:** none. Read-only sanity pass on the committed state.

- [ ] **Step 1: `git log` shows all Wave 2 commits**

```bash
cd ~/dotfiles && git log --oneline c89dfdec..HEAD
```

Expected: 12 commits (one per Task 1-12).

- [ ] **Step 2: All install/*.sh files are executable and syntax-valid**

```bash
for f in ~/dotfiles/install/*.sh; do
    [[ -x "$f" ]] || echo "NOT executable: $f"
    bash -n "$f" || echo "SYNTAX FAIL: $f"
done
echo done
```

Expected: just "done" printed (no errors).

- [ ] **Step 3: All bin/dot-* helpers are executable and syntax-valid**

```bash
for f in ~/dotfiles/bin/dot-*; do
    [[ -x "$f" ]] || echo "NOT executable: $f"
    bash -n "$f" || echo "SYNTAX FAIL: $f"
done
echo done
```

Expected: just "done" printed.

- [ ] **Step 4: install.sh usage message works**

```bash
cd ~/dotfiles && ./install.sh 2>&1 | head -5
cd ~/dotfiles && ./install.sh badprofile 2>&1 | head -5
```

Expected: both print usage + available profiles, exit 1.

- [ ] **Step 5: shell session is fully wired**

```bash
zsh -ic 'echo "DOTFILES=$DOTFILES"; echo "PATH entries:"; echo $PATH | tr ":" "\n" | grep -E "(dotfiles|\\.local)"; which dot-doctor'
```

Expected:
- DOTFILES printed
- dotfiles/bin and .local/bin both in PATH
- dot-doctor resolves to `/home/scott/dotfiles/bin/dot-doctor`

- [ ] **Step 6: User's in-flight files preserved**

```bash
cd ~/dotfiles && git status | head -20
```

Expected: "Changes not staged for commit" still contains only the Wave-1-era files (`base/claude/settings.json`, `base/ghostty/*`, `base/helix/config.toml`, `base/hypr/*`) plus possibly a re-absorbed version of `base/zsh/.zshrc` (from the `--adopt` pass in `08-stow-base.sh`, which gets restored by `git checkout -- base/`). If anything unexpected is staged or modified, flag it.

---

## Rollback

If any task introduces breakage that can't be fixed in <15 minutes:

```bash
cd ~/dotfiles && git log --oneline -15
# Identify last known good commit (likely the Wave-1 final commit c89dfdec)
git reset --hard c89dfdec
# Re-stow workstation
./install.sh workstation  # NOTE: this is the OLD monolithic install.sh, which still works
```

Because Wave 2 adds new files (install/, bin/, base/zsh/.zshrc.d/dotfiles.zsh) rather than destroying old ones, reverting is always safe. The monolithic `install.sh` is preserved in every commit that precedes Task 10.

**Between-task checkpointing:** because each task produces a standalone commit, you can also `git revert <sha>` a single problematic commit without unwinding the whole wave.

---

## Out of scope for Wave 2

- No theme system (Wave 3). `10-theme.sh` and `dot-theme-set` are stubs.
- No `docs/manual/*.md` chapters (Wave 4).
- No README rewrite (Wave 4).
- No removal of the old monolithic install.sh content beyond Task 10 — the old logic is preserved in git history only.
- No Debian branch restoration (deliberately deleted per tenet #2).
- No kickstart.nvim customization (user starts with vanilla kickstart + the one pcall line; any plugin/keybind additions are the user's to make).
