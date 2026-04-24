# Dotfiles Reorg — Wave 4: Docs Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the stopgap README + nonexistent `docs/manual/` with a topic-based 8-chapter manual and a tight README front door. Retire all "mid-reorg" language; the reorg ends with this wave.

**Architecture:** Pure documentation. Zero runtime impact, zero config changes, zero risk to the live machine. Each chapter is a self-contained markdown file owning one concern; the README becomes a front door that links to them. Tone: matter-of-fact, opinionated, tight. Private repo, but public-shaped writing (stranger could fork and understand).

**Tech Stack:** Markdown.

**Spec:** `docs/superpowers/specs/2026-04-23-dotfiles-opinionated-reorg-design.md` (Section 4)

**Scope note:** This wave produces ~8 markdown files under `docs/manual/` + a rewritten `README.md`. No other files touched. No live-machine operations.

---

## Pre-plan checklist

- [ ] HEAD is on `main` at `48e988b` or later (post-Wave-3 state).
- [ ] `cd ~/dotfiles && git status` — working tree clean.
- [ ] `docs/manual/` does NOT yet exist (`ls docs/` shows only `plans/` and `superpowers/`).
- [ ] `dot-doctor` returns 17/17 green.

---

## File Structure

**Files CREATED:**

| Path | Purpose |
|---|---|
| `docs/manual/01-install.md` | Fresh Arch → running workstation. Walk through `install/*.sh`. |
| `docs/manual/02-keybindings.md` | Every binding: Hyprland, Zellij, editors, Claude Code. |
| `docs/manual/03-theming.md` | Theme system: how it works, adding themes, dot-theme-set + dot-theme-toggle. |
| `docs/manual/04-tools.md` | The `tools/` uv project + `base/bin/` wrappers. |
| `docs/manual/05-claude-code.md` | Tenet #4 made concrete: plugins, skills, agent-skills, hooks. |
| `docs/manual/06-recovery.md` | Dead-laptop → functional in <1 hour. References the DR spec. |
| `docs/manual/07-philosophy.md` | The 6 tenets with reasoning. |
| `docs/manual/08-roll-your-own.md` | Fork guide for the hypothetical stranger. |

**Files MODIFIED:**

| Path | Change |
|---|---|
| `README.md` | Complete rewrite: manifesto link + quickstart + manual table-of-contents + status line. Retire stopgap banner. Fix git clone URL typo (`scottwhitson` → `scott-whitson`). |

---

## Writing style (applies to all chapters)

- **Voice:** matter-of-fact, opinionated where it matters, no hedging. Same voice as the spec.
- **Audience:** future-Scott at 2am (the real audience) written for a public-shaped reader (the discipline audience).
- **Length:** chapter-scoped. A chapter is done when it covers its topic completely; no filler to hit a word count.
- **Code blocks:** use them for every command, config snippet, or file path. Prefer runnable blocks over prose descriptions.
- **Tables:** use for anything enumerable (keybindings, packages, file lists, options).
- **Cross-references:** `[Chapter N](0N-name.md)` syntax; relative links within `docs/manual/`. Link *into* the repo for `install/` scripts, `bin/` helpers, `base/` packages.
- **No emojis** unless the user explicitly asks (they haven't).
- **No "in this chapter we'll cover" meta-paragraphs.** Each chapter gets straight to the content.
- **No filler phrases:** cut "simply", "just", "easy", "straightforward". If something is easy, it's obvious from context.
- **Tense:** present. "The installer runs pacman," not "The installer will run pacman."

---

## Task 1: Chapter 01 — `docs/manual/01-install.md`

**Files:**
- Create: `docs/manual/01-install.md` (also creates `docs/manual/` directory by virtue of the first file)

**Scope:** A script-by-script walkthrough of `install/*.sh`. Someone following this should be able to go from a freshly-booted Arch live USB to a running workstation in an hour or less.

### Step 1: Inspect the repo to build the walkthrough from ground truth

```bash
ls ~/dotfiles/install/
for f in ~/dotfiles/install/[0-9][0-9]-*.sh; do
    echo "=== $f ==="
    head -5 "$f"
done
```

Use this as the source of truth for the chapter. Don't invent steps that aren't in the scripts; don't skip steps that are.

### Step 2: Write `docs/manual/01-install.md` with this structure

```markdown
# Chapter 01 — Install

From an Arch live USB to a running workstation in about an hour. The installer is a ~50-line orchestrator (`install.sh`) that runs 11 modular scripts in order. Each script is independently runnable and idempotent; re-running `./install.sh workstation` is safe.

## Prerequisites

- A clean Arch Linux install with sudo access and a working internet connection
- The Claude Code + Anthropic workflow is optional for a first-pass install; the 07-claude.sh step can be skipped if you don't have an API key yet
- You know your hostname and timezone

## Bootstrap

\`\`\`bash
git clone git@github.com:scott-whitson/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh workstation
\`\`\`

That's it. The orchestrator takes over and runs every `install/NN-*.sh` in order.

## What each script does

A table with one row per script. For each row: number, filename, one-sentence purpose, any user interaction required.

| # | Script | Purpose | Interactive? |
|---|--------|---------|---|
| 01 | `pacman.sh` | Core pacman packages (base-devel, git, stow, zsh, helix, neovim, fonts) | sudo password |
| 02 | `paru.sh` | Bootstrap paru AUR helper if missing | sudo password (first run only) |
| 03 | `system.sh` | Oh My Zsh, zsh plugins, chsh to zsh, pam_systemd_home check | sudo (chsh) |
| 04 | `hyprland.sh` | Hyprland stack *(workstation only)* | sudo password |
| 05 | `desktop.sh` | waybar, mako, fuzzel, ghostty, pipewire, fonts *(workstation only)* | sudo password |
| 06 | `tools.sh` | uv + `tools/` project, window-picker Rust build, nvm + Node LTS, kickstart.nvim clone | no |
| 07 | `claude.sh` | Claude Code CLI (`npm install -g`) + agent-skills check | no (if npm ok) |
| 08 | `stow-base.sh` | Stow every `base/*/` package | no |
| 09 | `stow-profile.sh` | Stow `profiles/workstation/*` | no |
| 10 | `theme.sh` | Apply active theme (defaults to catppuccin-mocha) | no |
| 11 | `services.sh` | Enable systemd user units (gdrive-bisync timer, etc.) | no |

## Interactive gotchas

- Sudo prompts multiple times. The orchestrator does not cache sudo credentials across scripts. If you want fewer prompts, prepend a `sudo -v` loop or run with NOPASSWD for pacman.
- Agent context (non-TTY) cannot drive sudo — see `docs/superpowers/plans/2026-04-24-dotfiles-reorg-wave-2-install-modularization.md` Task 14 for why the full orchestrator doesn't run under subagent dispatch.

## Failure recovery

Because each `install/*.sh` is independently runnable:

\`\`\`bash
# After fixing whatever caused a specific step to fail:
bash ~/dotfiles/install/NN-name.sh
# Or just re-run the whole orchestrator (idempotent):
./install.sh workstation
\`\`\`

## First-run manual steps

The orchestrator ends by printing these; listed here for completeness:

1. Set up SSH keys: `ssh-keygen -t ed25519`
2. Log out and back in for zsh to take effect
3. If this is a fresh machine and `~/projects/agent-skills` is missing, clone it manually (repo URL is user-specific; see Chapter 05)

## What the orchestrator does NOT do

- Set up disk encryption, partitioning, or bootloader (see Chapter 06 — Recovery)
- Generate SSH keys (explicit manual step — never committed to git)
- Populate `~/gdrive` (mounted from encrypted fstab; initial rclone bisync is a one-time `--resync` run)
- Install your kickstart.nvim fork specifically — defaults to upstream `nvim-lua/kickstart.nvim`. If you fork on your own GitHub, edit `install/06-tools.sh`'s `KICKSTART_URL` variable.
- Configure Tailscale (`sudo tailscale up`) — explicit manual step after install
```

### Step 3: Verify + commit

```bash
wc -l ~/dotfiles/docs/manual/01-install.md
```

Expected: 80-120 lines of markdown.

```bash
cd ~/dotfiles && git add docs/manual/01-install.md
git commit -m "$(cat <<'EOF'
docs/manual: chapter 01 — Install

Script-by-script walkthrough of install/*.sh + first-run manual steps +
recovery path. Sources from the actual install/ scripts; no invented
claims.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Chapter 02 — `docs/manual/02-keybindings.md`

**Files:**
- Create: `docs/manual/02-keybindings.md`

**Scope:** Every binding the user has, organized by surface. This is a cheat-sheet — someone grep'ing for "how do I switch workspaces" should find the answer in one scroll.

### Step 1: Extract bindings from the source of truth

```bash
grep -nE '^bind\s*=' ~/dotfiles/base/hypr/.config/hypr/hyprland.conf | head -50
```

Use this as source of truth. Do NOT invent bindings not present in the config.

Also inspect Ghostty + Zellij configs briefly:

```bash
ls ~/dotfiles/base/ghostty/.config/ghostty/
ls ~/.config/zellij/ 2>/dev/null || echo "no zellij config"
```

### Step 2: Write `docs/manual/02-keybindings.md`

Structure:

```markdown
# Chapter 02 — Keybindings

All system-level bindings. `$mod` is Super (Windows key) on this machine.

## Hyprland

### Window management

| Binding | Action |
|---|---|
| `$mod + H/J/K/L` | Focus left / down / up / right |
| `$mod + Shift + H/J/K/L` | Move window in direction |
| `$mod + R` | Enter resize mode (H/J/K/L to resize) |
| `$mod + F` | Toggle fullscreen |
| `$mod + Shift + Space` | Toggle floating |
| `$mod + Shift + Q` | Close active window |

(Populate from the actual grep output in Step 1. Do NOT copy the examples above if the real bindings differ — check the config.)

### Workspaces

| Binding | Action |
|---|---|
| `$mod + 1..9` | Switch to workspace N |
| `$mod + Shift + 1..9` | Move window to workspace N (silent — no follow) |
| `$mod + S / A` | Next / previous workspace |
| `$mod + -` | Show scratchpad |

### Launchers

| Binding | Action |
|---|---|
| `$mod + Return` | Ghostty terminal |
| `$mod + D` | Fuzzel launcher |
| `$mod + W` | Firefox |
| `$mod + Escape` | Lock screen (hyprlock) |
| `Print` | Screenshot region to clipboard |

### Theme

| Binding | Action |
|---|---|
| `$mod + Shift + T` | `dot-theme-toggle` — flip between last-dark and last-light theme |

(See [Chapter 03 — Theming](03-theming.md).)

### Anything else

List any other bindings (e.g. brightness keys, media keys, custom scripts) that appear in the config. If you added the binding, document it.

## Ghostty

Ghostty uses its built-in defaults. No custom keybinds are configured in `base/ghostty/.config/ghostty/config`. Refer to [Ghostty docs](https://ghostty.org/docs/) for the stock set.

## Helix

Helix bindings are Helix-default; no overrides are in `base/helix/.config/helix/config.toml`. See `:help` inside Helix or the [upstream docs](https://docs.helix-editor.com/).

## Neovim (kickstart)

Kickstart's defaults plus whatever customization lives in your fork at `~/.config/nvim/lua/custom/`. Not documented here because your fork is its own repo.

## Zellij

Zellij uses its default bindings. If you add a custom layout or keybind config under `~/.config/zellij/`, document it here.

## Claude Code

- In session: `/help` lists the session commands (`/plan`, `/resume`, `/review`, `/clear`, `/compact`, etc.). These are Claude Code built-ins, not dotfiles config.
- Hooks: configured in `base/claude/.claude/settings.json`. See [Chapter 05 — Claude Code](05-claude-code.md).
```

### Step 3: Commit

```bash
cd ~/dotfiles && git add docs/manual/02-keybindings.md
git commit -m "$(cat <<'EOF'
docs/manual: chapter 02 — Keybindings

Extracted from base/hypr/.config/hypr/hyprland.conf. One table per
surface (Hyprland window/workspace/launcher/theme, Ghostty, Helix,
Neovim, Zellij, Claude Code). Sourced from live config; no invented
bindings.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Chapter 03 — `docs/manual/03-theming.md`

**Files:**
- Create: `docs/manual/03-theming.md`

**Scope:** The theme system built in Wave 3, explained completely. Someone grep'ing for "how do I add a theme" finds the full answer here.

### Step 1: Write `docs/manual/03-theming.md`

```markdown
# Chapter 03 — Theming

The theme system is Omarchy-style (directory-per-theme) plus a dark/light toggle layer. Applying a theme is one command; switching between dark and light is one hotkey.

## Commands

\`\`\`bash
dot-theme-set <name>      # apply a specific theme
dot-theme-toggle          # flip between last-dark and last-light (bound to $mod+Shift+T)
dot-theme-set             # (no arg) prints usage + lists available themes
\`\`\`

## Shipped themes

\`\`\`
themes/
├── catppuccin-mocha/     # dark
└── catppuccin-latte/     # light
\`\`\`

## State files

Three files in `~/.config/dotfiles/`:

| File | Contents |
|---|---|
| `active-theme` | Currently applied theme (used by `install/10-theme.sh` on re-install) |
| `last-dark` | Most recent dark theme (source of truth for `dot-theme-toggle` when flipping to dark) |
| `last-light` | Most recent light theme |

## Theme directory anatomy

Each theme is a self-contained directory. All files are pre-rendered; there's no templating step.

\`\`\`
themes/catppuccin-mocha/
├── variant            # "dark" or "light" — single word
├── palette.sh         # colors as shell vars (reference only; not consumed)
├── hypr.conf          # border colors → symlinked to ~/.config/hypr/theme.conf
├── hyprlock.conf      # full hyprlock screen → ~/.config/hypr/hyprlock.conf
├── ghostty.conf       # terminal palette → ~/.config/ghostty/theme.conf
├── waybar.css         # status bar styles → ~/.config/waybar/style.css
├── mako.conf          # notification colors → ~/.config/mako/config
├── fuzzel.ini         # launcher colors → ~/.config/fuzzel/fuzzel.ini
├── btop.theme         # btop theme → ~/.config/btop/themes/active.theme
├── nvim.lua           # `vim.cmd.colorscheme('…')` → ~/.config/nvim/lua/dotfiles-theme.lua
├── helix-theme        # one word: Helix theme name (sed-rewrites config.toml)
├── obsidian-theme     # one word: Obsidian theme name (JSON-patches appearance.json)
├── gtk.conf           # GTK_THEME + COLOR_SCHEME (sourced by dot-theme-set, applied via gsettings)
├── fragpaper.conf     # BG_COLOR + PALETTE for fragpaper wallpaper daemon
├── README.md          # theme origin, extra font/plugin requirements
└── post-set.sh        # optional hook run at the end of dot-theme-set
\`\`\`

## How `dot-theme-set <name>` works

1. Validates `themes/<name>/` exists; refuses unknown names.
2. Reads `variant` (must be `dark` or `light`).
3. Writes `~/.config/dotfiles/active-theme` = `<name>` and `last-<variant>` = `<name>`.
4. Symlinks each per-app file into its target location (see anatomy table above).
5. Sed-rewrites the `theme = "..."` line in `~/.config/helix/config.toml` to the value in `helix-theme`.
6. If `$OBSIDIAN_VAULT` is set in the active profile's `profile.conf`, JSON-patches the vault's `.obsidian/appearance.json` with the value in `obsidian-theme`.
7. Sources `gtk.conf` and runs `gsettings` for `color-scheme` and `gtk-theme`.
8. Kills + relaunches fragpaper via `fragpaper-launch` (which reads the new `active-theme` marker).
9. Runs `themes/<name>/post-set.sh` if present and executable.
10. Sends reload signals: `hyprctl reload`, `SIGUSR2` to waybar/ghostty, `makoctl reload`, `SIGUSR1` to helix.

## How `dot-theme-toggle` works

1. Reads `active-theme`, looks up its variant.
2. Applies the theme named in `last-<opposite-variant>` via `dot-theme-set`.
3. If `last-<opposite>` is empty (first-ever toggle to that variant): falls back to the first theme in `themes/*/` with the opposite variant, warns on stderr.

The first toggle after a fresh install will use the fallback path. Every subsequent toggle reads the markers cleanly.

## Adding a new theme

\`\`\`bash
cp -r ~/dotfiles/themes/catppuccin-mocha ~/dotfiles/themes/<new-theme>
\`\`\`

Then edit each file in the new directory:

1. `variant` — `dark` or `light`
2. `palette.sh` — the new palette as shell vars (for humans)
3. All the per-app files — replace color values with the new palette
4. `helix-theme` — Helix upstream theme name (or a custom one if you ship it with kickstart)
5. `obsidian-theme` — Obsidian theme name
6. `gtk.conf` — GTK preferences
7. `fragpaper.conf` — fragpaper bg color + palette hint
8. `README.md` — describe the theme

Then apply:

\`\`\`bash
dot-theme-set <new-theme>
\`\`\`

No code changes needed. `dot-theme-set` discovers themes dynamically via `ls themes/`.

## The Helix drift caveat

`dot-theme-set` sed-rewrites `~/.config/helix/config.toml`. Because that file is a stow symlink, sed follows it and modifies `base/helix/.config/helix/config.toml` in the repo.

**Consequence:** every time you `dot-theme-toggle` away from your committed default, `git status` shows one modified line in that file. Toggling back cleans the working tree.

The committed default is currently `catppuccin_mocha`. Drift appears when you're in light mode; disappears when you flip back to dark.

If this ever annoys you enough, three escape hatches:

1. Commit the current drift (sets the new value as the default)
2. `git checkout -- base/helix/.config/helix/config.toml` to revert
3. Switch Helix to a colorscheme management plugin that can source an include file — not shipped here.

## Fragpaper integration

Fragpaper is a GPU shader wallpaper generator (not a static image). Each theme provides `BG_COLOR` and `PALETTE` (`dark` or `light`) via `fragpaper.conf`. `fragpaper-launch` reads the active theme and passes them to the fragpaper binary.

If fragpaper isn't installed, theme switching still works — fragpaper relaunch is `|| true` guarded and the rest of the system doesn't care.
```

### Step 2: Commit

```bash
cd ~/dotfiles && git add docs/manual/03-theming.md
git commit -m "$(cat <<'EOF'
docs/manual: chapter 03 — Theming

Full documentation of the Wave 3 theme system: commands, state files,
theme directory anatomy, dot-theme-set + dot-theme-toggle behavior,
adding themes, the helix-drift caveat, fragpaper integration.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Chapter 04 — `docs/manual/04-tools.md`

**Files:**
- Create: `docs/manual/04-tools.md`

**Scope:** The `tools/` uv project (`yt_transcript`, `web_extract`, `news`) + `base/bin/` wrappers + the `bin/dot-*` helpers.

### Step 1: Inspect the state

```bash
ls ~/dotfiles/tools/
cat ~/dotfiles/tools/pyproject.toml | head -40
ls ~/dotfiles/base/bin/.local/bin/
ls ~/dotfiles/bin/
```

### Step 2: Write the chapter

Structure:

```markdown
# Chapter 04 — Tools

Two flavors of user-space tooling in this repo:

1. **`tools/` — a uv Python project** with CLI utilities (`yt_transcript`, `web_extract`, `news`) plus a Rust binary (`window-picker`).
2. **`base/bin/`** — small wrapper scripts that live on `$HOME/.local/bin` via stow.
3. **`bin/dot-*`** — re-runnable dotfiles helpers (`dot-restow`, `dot-theme-set`, `dot-theme-toggle`, `dot-update`, `dot-doctor`) on `$DOTFILES/bin` via zshrc.d.

## tools/

A uv-managed Python project. `pyproject.toml` declares entry points; `uv sync` (run by `install/06-tools.sh`) creates a project venv and wires the entry points.

### yt_transcript

Extracts YouTube transcripts. No API key.

\`\`\`bash
yt_transcript "https://www.youtube.com/watch?v=VIDEO_ID"
yt_transcript "VIDEO_ID" --timestamps
yt_transcript "VIDEO_ID" -o transcript.md
yt_transcript "VIDEO_ID" -l es -l en
\`\`\`

Accepts full URLs, youtu.be short links, or bare video IDs.

### web_extract

Pulls clean article text from a URL, stripping ads/nav/boilerplate.

\`\`\`bash
web_extract "https://example.com/article"
web_extract "https://example.com/article" -o article.md
web_extract "https://example.com/article" -f text
web_extract "https://example.com/article" --precision
\`\`\`

### news

Tech news briefing. Pulls from Hacker News, Reddit, and Lobsters via RSS / public APIs.

\`\`\`bash
news            # all sources
news hn
news reddit
news lobsters
news -n 5       # limit items per feed
\`\`\`

Default subreddits live in `REDDIT_SUBS` in `tools/news.py`.

### window-picker

A small Rust binary that renders a window picker overlay for Hyprland. Built by `install/06-tools.sh`. Binary path: `~/dotfiles/tools/window-picker/target/release/window-picker`.

## base/bin/ — stowed wrappers

Every file in `base/bin/.local/bin/` is symlinked to `~/.local/bin/<name>` by `install/08-stow-base.sh`. Currently:

| Wrapper | Purpose |
|---|---|
| `fragpaper-launch` | Launches fragpaper with the active theme's BG_COLOR + PALETTE |
| `news` | Calls the uv-managed `news` entry point |
| `trackpad-toggle` | Toggle trackpad on/off |
| `web_extract` | Calls the uv-managed `web_extract` entry point |
| `window-picker` | Calls the Rust binary at `tools/window-picker/target/release/` |
| `yt_transcript` | Calls the uv-managed entry point |

## bin/dot-* — repo-level helpers

These live at `$DOTFILES/bin/` and are on PATH via `base/zsh/.zshrc.d/dotfiles.zsh` (which prepends `$DOTFILES/bin`). They are NOT stowed — they live in the repo and ride along with your clone.

| Helper | Purpose |
|---|---|
| `dot-restow <pkg\|--all>` | Re-stow one package or everything (base + active profile) |
| `dot-theme-set <name>` | Apply a theme (see Chapter 03) |
| `dot-theme-toggle` | Flip between last-dark and last-light (Chapter 03) |
| `dot-update` | `paru -Syu && dot-restow --all` — weekly housekeeping |
| `dot-doctor` | 17-check health scan: stow links, mounts, services, fonts, PATH, claude, agent-skills, active theme |

## Adding a new tool

- **Python CLI that should ship with the dotfiles:** add it to `tools/`, declare an entry point in `pyproject.toml`, add a wrapper in `base/bin/.local/bin/<name>` that calls it. Run `install/06-tools.sh` (or just `uv sync` in `tools/`) to wire the venv.
- **Small shell script:** drop it in `base/bin/.local/bin/<name>`, `chmod +x`, commit.
- **Dotfiles-specific re-runnable helper:** add it to `bin/`, `chmod +x`, commit. No stow needed — it's on PATH via `$DOTFILES/bin`.
```

### Step 3: Commit

```bash
cd ~/dotfiles && git add docs/manual/04-tools.md
git commit -m "$(cat <<'EOF'
docs/manual: chapter 04 — Tools

Covers tools/ uv project (yt_transcript, web_extract, news, window-
picker), base/bin/ wrappers, and bin/dot-* helpers. How to add a new
tool in each flavor.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Chapter 05 — `docs/manual/05-claude-code.md`

**Files:**
- Create: `docs/manual/05-claude-code.md`

**Scope:** Tenet #4 ("AI-augmented by default") made concrete. This is the chapter that distinguishes this system from Omarchy.

### Step 1: Inspect Claude Code state

```bash
cat ~/dotfiles/base/claude/.claude/settings.json
ls ~/dotfiles/base/claude/.claude/
ls ~/projects/agent-skills/ 2>/dev/null | head -10
```

### Step 2: Write the chapter

Structure:

```markdown
# Chapter 05 — Claude Code

Tenet #4: **AI-augmented by default.** Claude Code is a first-class tool in this setup, not a bolt-on. The `base/claude/` stow package ships configuration, plugins, and hook settings as part of the dotfiles.

## What's installed

- **Claude Code CLI** — `npm install -g @anthropic-ai/claude-code`, run by `install/07-claude.sh`
- **Settings file** — `base/claude/.claude/settings.json`, stowed to `~/.claude/settings.json`
- **Plugins** — declared in settings; Claude Code handles the fetch+install on first invocation
- **Custom skills (`sew` plugin)** — lives at `~/projects/agent-skills/` as a separate git repo, loaded via plugin declaration

## Active plugins

List from `base/claude/.claude/settings.json` (regenerate this list by reading the file):

| Plugin | Source | Purpose |
|---|---|---|
| `superpowers@claude-plugins-official` | official | Brainstorming, writing-plans, executing-plans, TDD, requesting/receiving code review |
| `claude-md-management@claude-plugins-official` | official | Manage CLAUDE.md files across projects |
| `mind@memvid` | memvid | Local durable memory via .mv2 files |
| (...any others in settings.json) | ... | ... |

(Read the actual settings.json in Step 1 and regenerate the table from ground truth.)

## Hook settings

`base/claude/.claude/settings.json` declares hooks that fire on events (SessionStart, UserPromptSubmit, etc.). Non-obvious ones:

- **Mind autosave** — captures context from recent tool use into `.claude/mind.mv2`
- **Status line** — (see `/config` for current config)
- **Agent push notifications** — `agentPushNotifEnabled: true` pings when background agents finish

## agent-skills (the sew plugin)

`~/projects/agent-skills/` is a separate git repo declaring the `sew` plugin. Loaded via settings.json. Houses skills specific to this user's workflows:

- (Skills present — regenerate by listing `~/projects/agent-skills/skills/`)

**If this directory is missing,** clone it manually — the URL is user-specific and not hardcoded in `install/07-claude.sh`. See the warning that `07-claude.sh` prints on first run.

## Authoring a new skill

Skills live in `~/projects/agent-skills/skills/<name>/`. Structure:

\`\`\`
~/projects/agent-skills/skills/<name>/
├── SKILL.md        # YAML frontmatter + prose instructions
├── scripts/        # optional helper scripts
└── references/     # optional reference material
\`\`\`

`SKILL.md` frontmatter minimum:

\`\`\`yaml
---
name: <skill-name>
description: <when this skill applies — the matcher Claude uses to decide relevance>
---
\`\`\`

Use the `superpowers:writing-skills` skill (`/writing-skills` in a Claude Code session) to scaffold + test.

## Commit discipline

- Changes to `base/claude/.claude/settings.json` → commit in this dotfiles repo
- Changes to `~/projects/agent-skills/` → commit in that repo (separate)
- Memory files (`.claude/mind.mv2`) → NOT committed (they're in `.gitignore`)

## Relationship to Omarchy

Omarchy does not have this tenet. If you fork this system to a non-Scott audience, [Chapter 08 — Roll Your Own](08-roll-your-own.md) notes that the `base/claude/` package and tenet #4 are the most Scott-specific piece — a forker will either adopt a similar AI-augmented workflow or delete the package and settle for Omarchy-parity.
```

### Step 3: Commit

```bash
cd ~/dotfiles && git add docs/manual/05-claude-code.md
git commit -m "$(cat <<'EOF'
docs/manual: chapter 05 — Claude Code

Tenet #4 made concrete. Covers CLI install, settings.json, active
plugins, hooks, agent-skills repo (sew plugin), authoring a new skill,
commit discipline, and the forkability caveat.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Chapter 06 — `docs/manual/06-recovery.md`

**Files:**
- Create: `docs/manual/06-recovery.md`

**Scope:** Dead laptop → functional in <1 hour. This chapter is a pointer + summary; the full detail lives in `docs/superpowers/specs/2026-04-18-arch-dr-design.md`.

### Step 1: Write the chapter

Keep it short — most content is in the DR spec. This chapter is navigation.

```markdown
# Chapter 06 — Recovery

Dead laptop → functional workstation in ~1 hour, given the backups are intact.

## Runbook

The full disaster-recovery design is at [`docs/superpowers/specs/2026-04-18-arch-dr-design.md`](../superpowers/specs/2026-04-18-arch-dr-design.md) (read the runbook at [`recovery/README.md`](../../recovery/README.md) first). This chapter is a pointer + quick reference.

## Three recovery scenarios

| Scenario | Trigger | Path |
|---|---|---|
| **B** (primary) | Wipe + reinstall same hardware | `recovery/README.md` → archinstall → partition.sh → post-install.sh → restore from backup |
| **A** (secondary) | Replacement hardware after loss/destruction | Same as B, with the added steps of re-enrolling Tailscale, re-adding SSH keys, re-cloning `agent-skills` |
| **C** (low-priority) | Offline recovery, no internet | Deferred — needs work |

## What's in backup

Backup lives on Google Drive via `dr_backup.sh` + rclone. Includes:

- `~/` minus caches/junk (see exclusion list in `tools/dr_backup.sh`)
- Selected `/etc/` files via allowlist (see `recovery/etc-allowlist.txt`)
- LUKS header (when root is encrypted)

Does NOT include:

- `/var/` caches
- Snap/flatpak app data (tolerable loss)
- Running process state

## What's in this repo (no backup needed)

- `~/dotfiles/` itself — clone from `git@github.com:scott-whitson/dotfiles.git`
- All `install/*.sh`, `bin/dot-*`, `themes/*` — in the repo
- `recovery/archinstall.json`, `recovery/partition.sh`, `recovery/post-install.sh` — in the repo

## First-time user vs recovery

| First-time install | Recovery install |
|---|---|
| Fresh `./install.sh workstation` | Same, but preceded by `recovery/partition.sh` + archinstall |
| No restore step | `dr_restore.sh` runs after stow-base to replay the backup |
| Manual SSH keygen | SSH keys come out of the backup (`.ssh/` is backed up) |
| `sudo tailscale up` prompts auth | `sudo tailscale up --auth-key=<pre-generated>` for headless |

## Testing recovery

Rehearse on a throwaway Arch VM before you need it for real. The spec's `tests/` directory has a fake-backup generator + VM setup doc. If you haven't tested in 6+ months, trust nothing.

## When this chapter is wrong

If `dr_backup.sh` / `dr_restore.sh` change, or the backup target moves off Google Drive, this chapter goes stale fast. The spec is the source of truth; this chapter summarizes. Update both if you touch DR.
```

### Step 2: Commit

```bash
cd ~/dotfiles && git add docs/manual/06-recovery.md
git commit -m "$(cat <<'EOF'
docs/manual: chapter 06 — Recovery

Pointer chapter: summary of recovery scenarios + what's in backup + the
first-time-install vs recovery-install difference. Full detail in the
DR spec; this chapter is navigation.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Chapter 07 — `docs/manual/07-philosophy.md`

**Files:**
- Create: `docs/manual/07-philosophy.md`

**Scope:** The 6 tenets with reasoning + concrete consequences. This chapter is the "why" document — the thing future-you reads when tempted to add Ubuntu fallback code or make everything "work for more platforms."

### Step 1: Read the tenets from the spec

```bash
grep -A1 '^[0-9]\. \*\*' ~/dotfiles/docs/superpowers/specs/2026-04-23-dotfiles-opinionated-reorg-design.md | head -30
```

The 6 tenets are authoritative as stated in the spec's Tenets section. Don't paraphrase the headline; expand each with reasoning + what it eliminates.

### Step 2: Write the chapter

```markdown
# Chapter 07 — Philosophy

Six tenets. Each should eliminate at least one decision. The goal is not to be comprehensive — it's to be *decided*.

## 1. Local-first, data-owned

Files live on disk first. Cloud is a backup destination, never the source of truth. Three copies (local, gdrive-bisync, USB-when-built) with zero trust in any single provider.

**What this eliminates:**
- The temptation to cloud-sync dotfiles via Dropbox/iCloud/syncthing-only
- Schemes that treat your machine as a cache of the cloud
- Dependencies on a provider remaining in business

**Concrete consequences:**
- `~/gdrive` is a mounted partition with rclone bisync every 15 minutes, not a streamed-on-demand mount
- `dr_backup.sh` treats the backup as a point-in-time copy, not a live sync

## 2. Arch + Hyprland, no apologies

Bleeding-edge is a feature, not a bug. Rolling release matches how you work.

**What this eliminates:**
- Distro detection in `install.sh` (it's Arch-only now)
- Ubuntu/Debian fallback code (deleted in Wave 2)
- Sway/Wofi/Kitty legacy (deleted in Wave 1)
- Compromise package selections that worked across both (just pick the best Arch package)

**Concrete consequences:**
- `install.sh` is 49 lines. If it were distro-agnostic, it would be 200+.
- `01-pacman.sh` can list `helix`, `neovim`, `rclone`, `uv` without worrying whether a given Debian version ships them

## 3. Terminal-centric, keyboard-driven

Ghostty + Zellij + Helix/Neovim + lf. GUI apps are tolerated, not celebrated. Every frequent action has a keybind.

**What this eliminates:**
- "Which GUI menu is this option in?"
- Needing a mouse for any day-to-day task
- File-browser-clicking as a workflow

**Concrete consequences:**
- `fuzzel` (keyboard launcher) is in base/, not a mouse-driven app menu
- Helix + kickstart-Neovim are both installed; GUI editors are not

## 4. AI-augmented by default

Claude Code is a first-class tool, not a bolt-on. Custom skills, plugins, and the `agent-skills` project are part of the OS.

**What this eliminates:**
- Treating AI-assisted workflows as an afterthought to configure per-project
- Re-learning your Claude plugin layout on a fresh machine

**Concrete consequences:**
- `base/claude/.claude/settings.json` ships with the dotfiles
- `install/07-claude.sh` is a dedicated step (not folded into `06-tools.sh`)
- See [Chapter 05 — Claude Code](05-claude-code.md) for the concrete setup

**This is the tenet most specific to this user.** A fork would either adopt a similar AI-augmented workflow or delete `base/claude/` and retire this tenet.

## 5. Reversible and recoverable

`recovery/` directory exists. Any machine is rebuildable from the repo in <1 hour. No snowflake state that only lives on one laptop.

**What this eliminates:**
- "I'll just tweak this live and remember to commit later" (the source of all snowflakes)
- Fear of reinstalling when the current install gets weird
- The laptop being a single point of failure

**Concrete consequences:**
- `./install.sh workstation` is idempotent — run it after any manual tweak to re-base
- `dot-doctor` exists to catch drift (17 checks, last verified 2026-04-24)
- `dr_backup.sh` runs on a systemd timer

## 6. Modular like Framework

Every piece is swappable. No lock-in to a tool that can't be ripped out in an afternoon.

**What this eliminates:**
- Tools that require data migration to remove (proprietary note-taking apps, etc.)
- Workflows that only work if a specific combination of apps is installed
- Plugin systems that assume everything

**Concrete consequences:**
- The theme system (Chapter 03) is directory-per-theme — remove a theme by deleting a directory
- `bin/dot-*` helpers each do one thing; `dot-update` composes `paru -Syu` + `dot-restow --all` rather than baking them together
- Kickstart.nvim is a separate repo, not a stow package — so you can ditch it without disturbing the dotfiles

## What this document is *not*

Not a roadmap. Not a prediction. The tenets describe how decisions are made now. They could change; if they do, rewrite them here.

Tenet edits require a concrete reason: "this tenet led me astray in situation X" or "this tenet no longer matches how I work." Without that, tenet drift is just aesthetic preference.
```

### Step 3: Commit

```bash
cd ~/dotfiles && git add docs/manual/07-philosophy.md
git commit -m "$(cat <<'EOF'
docs/manual: chapter 07 — Philosophy

The 6 tenets expanded. Each one states what it eliminates + its concrete
consequences in the current repo. Tenet #4 (AI-augmented) explicitly
flagged as the most user-specific.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Chapter 08 — `docs/manual/08-roll-your-own.md`

**Files:**
- Create: `docs/manual/08-roll-your-own.md`

**Scope:** Fork guide for the hypothetical stranger. What's Scott-specific, what's generalizable, which tenets a forker would likely rewrite.

### Step 1: Write the chapter

```markdown
# Chapter 08 — Roll Your Own

This system is private and personal. But it was written public-shaped — with the discipline of an outside reader in mind — so if you want to fork it, you can. This chapter is your map.

## Generalizable (works for anyone)

These pieces don't depend on being Scott:

- **The install structure** (`install.sh` orchestrator + `install/NN-*.sh` modules) — swap the package list to your taste
- **The stow layout** (`base/` + `profiles/`) — rename profiles to match your machines
- **The theme system** (`themes/<name>/` + `bin/dot-theme-set` + `bin/dot-theme-toggle`) — works with any palette; ship the themes you care about
- **The `bin/dot-*` helpers** (`dot-restow`, `dot-update`, `dot-doctor`) — generic operations, not personal
- **The recovery structure** (`recovery/`) — fill in your own partition layout + allowlist
- **The Hyprland/Waybar/Mako/Fuzzel/Ghostty/btop base configs** — generic Wayland desktop, re-theme freely

## Scott-specific (rip out or replace)

These have personal state:

- **`profiles/workstation/git/.gitconfig.local`** — git identity (name + email). Replace.
- **`profiles/workstation/profile.conf`** — `OBSIDIAN_VAULT` path, possibly other env. Replace.
- **`profiles/workstation/zsh/.zshrc.d/workstation.zsh`** — any personal aliases, functions, tool integrations.
- **`profiles/workstation/zsh/.zshrc.d/claude.zsh`** — Claude Code aliases and agent-skills loader. Keep or drop depending on whether you use Claude.
- **`base/claude/.claude/settings.json`** — full Claude Code plugin + hook config. This is the biggest Scott-ism in the repo. Replace wholesale or delete.
- **`~/projects/agent-skills/`** — a separate git repo Scott maintains. Not in this repo. If you see references to the `sew` plugin or custom skills, they come from there.
- **`tools/` uv project entry points** — `yt_transcript`, `web_extract`, `news`. Keep, modify defaults, or delete.
- **`tools/window-picker/`** — a Rust window-picker. Useful for any Hyprland user; keep or remove.
- **`recovery/` specifics** — Scott's disk layout (nvme0n1, p8 preserved for gdrive). Replace.
- **Tailscale** — your tailnet, your IPs. Re-enroll.

## Which tenets you'd likely rewrite

[Chapter 07 — Philosophy](07-philosophy.md) lists six tenets. A forker's path through them:

| Tenet | Forker's likely response |
|---|---|
| 1. Local-first, data-owned | Probably keep — good tenet for anyone who values sovereignty |
| 2. Arch + Hyprland, no apologies | Keep if you're also Arch; rewrite to `<your-distro>` otherwise |
| 3. Terminal-centric, keyboard-driven | Keep if this is how you work |
| 4. AI-augmented by default | **Drop or rewrite.** This is the most Scott-specific. Fork it to `<your-AI-tool>` or retire. |
| 5. Reversible and recoverable | Keep — this one is load-bearing for anyone |
| 6. Modular like Framework | Keep — makes forking easier, which you're doing right now |

## Minimal fork path

If you want the cheapest possible fork that still works:

1. `git clone <this repo>` to your own.
2. Edit `profiles/workstation/profile.conf` — set `OBSIDIAN_VAULT` or unset it, edit other env vars.
3. Edit `profiles/workstation/git/.gitconfig.local` — your name + email.
4. Edit `profiles/workstation/zsh/.zshrc.d/workstation.zsh` — your aliases.
5. Delete `base/claude/` and `install/07-claude.sh`, and remove tenet #4 from `docs/manual/07-philosophy.md`. OR set up your own Claude Code config if you use it.
6. Edit `install/01-pacman.sh` to match your desired package set.
7. Rewrite `README.md` — the file you're reading points at docs Scott wrote for himself. You need your own.
8. `./install.sh workstation`.

## Deeper fork path

- Rename `workstation` to whatever you call your main machine
- Add new profiles as needed (`laptop`, `desktop`, `server`, etc.)
- Add your own themes in `themes/`
- Swap out tools you don't use (`lf`, `btop`, `yt-dlp`, `mpv`)

## Attribution

Fork freely; attribution appreciated but not required. The spec + plans in `docs/superpowers/` walk through how this system was built, which may save you time if you're making similar decisions.
```

### Step 2: Commit

```bash
cd ~/dotfiles && git add docs/manual/08-roll-your-own.md
git commit -m "$(cat <<'EOF'
docs/manual: chapter 08 — Roll Your Own

Fork guide: what's generalizable, what's Scott-specific, which tenets a
forker would likely rewrite, minimal vs deeper fork paths.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Rewrite `README.md`

**Files:**
- Modify: `README.md` (full rewrite from 104-line stopgap to tight front door)

### Step 1: Write the new README

Use `Write` tool (full replacement). Target length: 40-60 lines. The README is the front door, not the house.

```markdown
# dotfiles

Scott Whitson's personal Linux setup. Arch + Hyprland. Opinionated, documented, reversible.

This is a private repo built for one user, but written as if a stranger could fork it. See [`docs/manual/08-roll-your-own.md`](docs/manual/08-roll-your-own.md) if you're that stranger.

## Quickstart

\`\`\`bash
git clone git@github.com:scott-whitson/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh workstation
\`\`\`

On first install, that's the full path from fresh Arch to a running Hyprland workstation with Catppuccin Mocha applied. Subsequent runs are idempotent no-ops.

## Philosophy

Six tenets. Read [`docs/manual/07-philosophy.md`](docs/manual/07-philosophy.md) for the expanded version:

1. Local-first, data-owned
2. Arch + Hyprland, no apologies
3. Terminal-centric, keyboard-driven
4. AI-augmented by default (Claude Code is a first-class tool)
5. Reversible and recoverable
6. Modular like Framework

## Manual

| Chapter | Topic |
|---|---|
| [01 — Install](docs/manual/01-install.md) | Fresh Arch → running workstation |
| [02 — Keybindings](docs/manual/02-keybindings.md) | Every binding, by surface |
| [03 — Theming](docs/manual/03-theming.md) | Theme system + `dot-theme-set` + `dot-theme-toggle` |
| [04 — Tools](docs/manual/04-tools.md) | `tools/` uv project + `bin/dot-*` helpers |
| [05 — Claude Code](docs/manual/05-claude-code.md) | Plugins, skills, agent-skills |
| [06 — Recovery](docs/manual/06-recovery.md) | Dead laptop → functional in <1 hour |
| [07 — Philosophy](docs/manual/07-philosophy.md) | The 6 tenets, expanded |
| [08 — Roll Your Own](docs/manual/08-roll-your-own.md) | Fork guide |

## Structure

\`\`\`
~/dotfiles/
├── install.sh               # ~50-line orchestrator
├── install/                 # modular NN-<name>.sh scripts
├── bin/                     # dot-* helpers (on $PATH via zshrc.d)
├── base/                    # stow packages for every profile
├── profiles/                # workstation + server
├── themes/                  # catppuccin-mocha + catppuccin-latte
├── tools/                   # uv project + Rust window-picker
├── recovery/                # disaster-recovery runbook
├── docs/                    # this manual + specs + plans
└── .claude/                 # Claude Code skills/plugins specific to this repo
\`\`\`

## Status

- **Last reorg:** Wave 4 docs overhaul, 2026-04-24
- **Active theme:** catppuccin-mocha (toggle with `$mod+Shift+T`)
- **Health check:** `dot-doctor` (17 checks)
- **License:** none — private repo
```

### Step 2: Commit

```bash
cd ~/dotfiles && git add README.md
git commit -m "$(cat <<'EOF'
readme: rewrite as tight front door

Replaces the 104-line Wave-1-stopgap with a ~55-line index: manifesto
→ quickstart → tenets → manual ToC → structure → status. Retires the
"mid-reorg" banner. Fixes the git clone URL typo (scottwhitson →
scott-whitson).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Final verification

- [ ] **Step 1:** All 8 chapters exist and render:

```bash
ls ~/dotfiles/docs/manual/
wc -l ~/dotfiles/docs/manual/*.md
```

Expected: 8 files, each 80-300 lines.

- [ ] **Step 2:** README is trim:

```bash
wc -l ~/dotfiles/README.md
grep -i 'stopgap\|mid-reorg' ~/dotfiles/README.md && echo "STOPGAP STILL PRESENT" || echo "stopgap retired"
```

Expected: 40-70 lines; stopgap retired.

- [ ] **Step 3:** All internal links resolve:

```bash
cd ~/dotfiles
grep -oE '\(\.\./[^)]+\)|\(docs/[^)]+\)|\(0[0-9]-[^)]+\)' docs/manual/*.md README.md | awk -F'(' '{print $2}' | sed 's/)$//' | sort -u | while read link; do
    base=$(echo "$link" | sed 's#^\./##')
    if [[ "$base" == ../* ]]; then
        # chapter references; resolve relative to docs/manual/
        test -e "docs/manual/$base" || echo "BROKEN LINK (relative from manual): $link"
    elif [[ "$base" == docs/* ]]; then
        test -e "$base" || echo "BROKEN LINK (from readme): $link"
    else
        # intra-manual link
        test -e "docs/manual/$base" || echo "BROKEN LINK (intra-manual): $link"
    fi
done
```

Report any broken links. Ideally none.

- [ ] **Step 4:** git log shows 9 Wave 4 commits:

```bash
cd ~/dotfiles && git log --oneline 48e988b..HEAD
```

Expected: 9 commits (8 chapters + 1 README rewrite).

- [ ] **Step 5:** Working tree clean:

```bash
cd ~/dotfiles && git status
```

Expected: "nothing to commit, working tree clean".

- [ ] **Step 6:** Rough consistency sanity:

```bash
grep -l 'stopgap\|mid-reorg' ~/dotfiles/ -r --include='*.md' 2>/dev/null | grep -v docs/superpowers/plans/ | grep -v docs/superpowers/specs/
```

Expected: empty (no stopgap/mid-reorg references remain outside of plan/spec files where they're historical).

---

## Rollback

Wave 4 is purely additive (new files + README rewrite). Revert with:

```bash
cd ~/dotfiles && git log --oneline -12
git reset --hard 48e988b   # pre-Wave-4
```

The old stopgap README returns. No runtime state affected.

---

## Out of scope for Wave 4

- A static site / MkDocs build of `docs/manual/` (spec explicitly defers)
- LICENSE file (private repo)
- CONTRIBUTING.md (private repo; fork guide in Ch. 08 covers this informally)
- Per-profile manual sections (server profile doesn't have its own manual; it's a subset of workstation)
- Images / screenshots (text-only docs; if you want screenshots, add them later)
