# Dotfiles Reorg — Wave 1: Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drop dead configuration (WSL/Windows, Ubuntu-era tooling, unused apps) and rename `profiles/personal` → `profiles/workstation` without breaking the live machine.

**Architecture:** Strictly destructive + rename work — no new code. Each task follows a pattern of *verify pre-state → make filesystem change → verify post-state → commit*. Stow unstow steps precede directory deletion so no dangling symlinks are left behind in `~/.config/`. Every change is committed independently so any mistake can be `git revert`'d cleanly.

**Tech Stack:** Bash, `git`, `stow`, `rm`, `grep`, `find`.

**Spec:** `docs/superpowers/specs/2026-04-23-dotfiles-opinionated-reorg-design.md` (Section 5, Wave 1)

**Scope note:** This plan covers only Wave 1. Waves 2 (install modularization), 3 (theme system), and 4 (docs overhaul) will each get their own plan, written just-in-time after the previous wave ships.

---

## Pre-plan checklist

Before starting Task 1, verify:

- [ ] `cd ~/dotfiles && git status` — working tree clean *or* uncommitted changes are in files unrelated to this plan (the known unstaged files `base/claude/.claude/settings.json`, `base/ghostty/.config/ghostty/config`, `base/ghostty/.config/ghostty/light.conf`, `base/hypr/.config/hypr/colors/dark.conf`, `base/hypr/.config/hypr/colors/light.conf`, `base/hypr/.config/hypr/hyprland.conf` are OK to leave — this plan does not touch them).
- [ ] `stow --version` works
- [ ] You are on branch `main` and ahead of origin is acceptable (the spec commit is local-only).

If unrelated uncommitted work exists and you'd rather quarantine it: `git stash push -m "pre-wave1-quarantine"` before starting, `git stash pop` after.

---

## File Structure

**Files and directories DELETED by this plan:**

| Path | Why |
|---|---|
| `base/micro/` | Unused — wikilink-plugin-only; user moved away |
| `base/qalculate/` | Unused — one-time experiment, didn't work |
| `base/windows/` | Work laptop out of scope (spec Section: Audience) |
| `profiles/work/` | WSL dies with tenet #2 (Arch + Hyprland, no apologies) |
| `sync-windows.sh` | Windows-side sync; work laptop excluded |

**Directories RENAMED by this plan:**

| From | To | Why |
|---|---|---|
| `profiles/personal/` | `profiles/workstation/` | Axis is "has display" vs "headless", not "which of Scott's jobs" |
| `profiles/personal/zsh/.zshrc.d/personal.zsh` | `profiles/workstation/zsh/.zshrc.d/workstation.zsh` | Filename should match profile name |

**Files MODIFIED by this plan:**

| Path | Change |
|---|---|
| `install.sh` | Update comment on line 196 ("personal/zsh" → "workstation/zsh") and any other profile-name references in prose comments |
| `README.md` | Stopgap update — replace Sway/Wofi/Kitty/Ubuntu references with Hyprland/Fuzzel/Ghostty/Arch. Not a full rewrite (that comes in Wave 4). |

---

## Task 1: Confirm the filesystem state before starting

**Files:** none modified — read-only inspection.

- [ ] **Step 1: Verify the dead directories actually exist**

Run: `ls -d ~/dotfiles/base/micro ~/dotfiles/base/qalculate ~/dotfiles/base/windows ~/dotfiles/profiles/work ~/dotfiles/sync-windows.sh 2>&1`

Expected: all 5 paths listed (not "No such file or directory").

If any are already missing, note it and skip the corresponding delete step in Task 3 — don't fail.

- [ ] **Step 2: Verify `profiles/personal/` exists and `profiles/workstation/` does NOT**

Run: `ls -d ~/dotfiles/profiles/personal ~/dotfiles/profiles/workstation 2>&1`

Expected: `profiles/personal` listed, `profiles/workstation` reports "No such file or directory".

If `profiles/workstation` already exists, stop and investigate — the plan has been partially run before.

- [ ] **Step 3: Snapshot the symlinks currently provided by the packages we are about to remove**

Run:
```bash
find ~/.config/micro -maxdepth 2 -type l 2>/dev/null
find ~/.config/qalculate -maxdepth 2 -type l 2>/dev/null
```

Expected: zero or more symlinks pointing into `~/dotfiles/base/micro/` or `~/dotfiles/base/qalculate/`. Record the count — Task 2 will unstow these.

---

## Task 2: Unstow dead base packages

**Files:** removes symlinks from `~/.config/micro/` and `~/.config/qalculate/`.

- [ ] **Step 1: Unstow `micro`**

Run:
```bash
cd ~/dotfiles && stow -d base -t ~ --no-folding -D micro
```

Expected: no error output. `stow` silently succeeds or reports "BUG in find_stowed_paths?" only if nothing was stowed (acceptable).

- [ ] **Step 2: Unstow `qalculate`**

Run:
```bash
cd ~/dotfiles && stow -d base -t ~ --no-folding -D qalculate
```

Expected: same as above.

- [ ] **Step 3: Verify the symlinks are gone**

Run:
```bash
find ~/.config/micro -maxdepth 2 -type l 2>/dev/null
find ~/.config/qalculate -maxdepth 2 -type l 2>/dev/null
```

Expected: zero symlinks that still point into `~/dotfiles/`.

It is normal for the directories themselves to still exist if they contain other files. If empty, leaving them is also fine — Arch will recreate as needed.

- [ ] **Step 4: No commit yet — nothing has changed in the repo.** Proceed to Task 3.

---

## Task 3: Delete dead directories and files

**Files:** removes `base/micro/`, `base/qalculate/`, `base/windows/`, `profiles/work/`, `sync-windows.sh`.

- [ ] **Step 1: Verify once more that nothing outside these paths will be affected**

Run:
```bash
cd ~/dotfiles && ls -la base/windows base/micro base/qalculate profiles/work sync-windows.sh
```

Expected: each path listed with contents. If any path is already gone, `rm -rf` in the next step will silently no-op — safe.

- [ ] **Step 2: Delete all five**

Run:
```bash
cd ~/dotfiles && rm -rf base/windows base/micro base/qalculate profiles/work sync-windows.sh
```

Expected: no output. No "permission denied", no "device busy".

- [ ] **Step 3: Verify deletion**

Run:
```bash
cd ~/dotfiles && ls -d base/windows base/micro base/qalculate profiles/work sync-windows.sh 2>&1 | grep -c "No such file"
```

Expected: `5` (every path reported missing).

- [ ] **Step 4: Stage and commit**

Run:
```bash
cd ~/dotfiles && git add -A base/windows base/micro base/qalculate profiles/work sync-windows.sh
git status
```

Expected: `git status` shows 5 deletions staged.

Then:
```bash
git commit -m "$(cat <<'EOF'
cleanup: drop dead configs (windows, micro, qalculate, work profile, sync-windows)

Per 2026-04-23 dotfiles reorg spec:
- base/windows/: work laptop excluded from repo
- base/micro/: unused (wikilink-plugin-only, abandoned)
- base/qalculate/: unused (one-time experiment)
- profiles/work/: WSL retired; tenet #2 (Arch + Hyprland only)
- sync-windows.sh: no Windows targets remain

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Expected: commit succeeds.

---

## Task 4: Unstow the current `personal` profile

**Files:** removes all symlinks currently provided by `profiles/personal/*` from `$HOME`.

- [ ] **Step 1: List packages inside `profiles/personal/`**

Run:
```bash
cd ~/dotfiles && ls profiles/personal/
```

Expected: `git`, `zsh` (and possibly `profile.conf` — `profile.conf` is a file, not a stow package, so it won't appear if you use `ls -d profiles/personal/*/`). Use this command to list directory stow packages only:
```bash
cd ~/dotfiles && find profiles/personal -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
```

Record the output list — this is the list of packages to unstow.

- [ ] **Step 2: Unstow every package from `profiles/personal/`**

For each package `<pkg>` from Step 1, run:
```bash
cd ~/dotfiles && stow -d profiles/personal -t ~ --no-folding -D <pkg>
```

Example (substitute actual packages from Step 1):
```bash
cd ~/dotfiles && stow -d profiles/personal -t ~ --no-folding -D git
cd ~/dotfiles && stow -d profiles/personal -t ~ --no-folding -D zsh
```

Expected: no error output for any package.

- [ ] **Step 3: Verify no symlinks remain that target `profiles/personal/`**

Run:
```bash
find ~ -maxdepth 5 -type l -lname '*dotfiles/profiles/personal/*' 2>/dev/null
```

Expected: no output (empty result).

If any symlinks remain, investigate before proceeding — manual cleanup may be needed.

- [ ] **Step 4: No commit yet.** The repo state hasn't changed. Proceed to Task 5.

---

## Task 5: Rename `profiles/personal/` → `profiles/workstation/`

**Files:** renames `profiles/personal/` to `profiles/workstation/`, renames inner file `personal.zsh` → `workstation.zsh`, updates `install.sh` prose comments.

- [ ] **Step 1: Rename the directory using `git mv` (preserves history)**

Run:
```bash
cd ~/dotfiles && git mv profiles/personal profiles/workstation
```

Expected: no output. `git status` now shows renames.

- [ ] **Step 2: Rename the `personal.zsh` file inside it**

Run:
```bash
cd ~/dotfiles && git mv profiles/workstation/zsh/.zshrc.d/personal.zsh profiles/workstation/zsh/.zshrc.d/workstation.zsh
```

Expected: no output.

Verify:
```bash
cd ~/dotfiles && ls profiles/workstation/zsh/.zshrc.d/
```

Expected output includes `workstation.zsh` (and possibly `claude.zsh`). Does NOT include `personal.zsh`.

- [ ] **Step 3: Update prose comments in `install.sh` that mention "personal"**

Run:
```bash
grep -n "personal" ~/dotfiles/install.sh
```

Expected: at least one line (per design-time inspection, line 196: `# Profile packages add to base directories (e.g. personal/zsh adds to ~/.zshrc.d/)`).

For each line in the output, edit `install.sh` to replace `personal` with `workstation` in the comment text. Do NOT change code logic — this step is comment-only.

If `grep` returns additional matches beyond prose comments (e.g., in code paths that hardcode the profile name), STOP — this indicates the install script has tighter coupling than expected. Escalate before continuing.

- [ ] **Step 4: Verify install.sh still passes a basic syntax check**

Run:
```bash
bash -n ~/dotfiles/install.sh && echo OK
```

Expected: `OK`.

- [ ] **Step 5: Verify no files in the repo still reference the old profile name**

Run:
```bash
cd ~/dotfiles && grep -rln "personal" --include='*.sh' --include='*.conf' --include='*.zsh' --include='*.md' . 2>/dev/null | grep -v '^./docs/' | grep -v '^./\.git/'
```

Expected: empty. Any hit outside `docs/` and `.git/` should be investigated and likely updated.

(We exclude `docs/` because the spec file legitimately discusses the rename and uses the word "personal" in that context.)

- [ ] **Step 6: Stage and commit the rename + comment update**

Run:
```bash
cd ~/dotfiles && git add -A profiles install.sh
git status
```

Expected: `git status` shows renames from `profiles/personal/` to `profiles/workstation/` and `install.sh` modified.

Then:
```bash
git commit -m "$(cat <<'EOF'
profile: rename personal → workstation

Per 2026-04-23 dotfiles reorg spec: the axis between profiles is "has
display" vs "headless", not "which of Scott's jobs". `workstation`
names the machine role honestly.

- profiles/personal/ → profiles/workstation/
- zshrc.d/personal.zsh → zshrc.d/workstation.zsh
- install.sh prose comments updated

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Expected: commit succeeds.

---

## Task 6: Re-stow the renamed profile and verify the machine still works

**Files:** creates symlinks from `~` into `~/dotfiles/profiles/workstation/*`.

- [ ] **Step 1: Stow each package from the renamed profile**

Run:
```bash
cd ~/dotfiles && find profiles/workstation -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
```

Record the package list. For each package `<pkg>`, run:
```bash
cd ~/dotfiles && stow -d profiles/workstation -t ~ --no-folding -R <pkg>
```

Example:
```bash
cd ~/dotfiles && stow -d profiles/workstation -t ~ --no-folding -R git
cd ~/dotfiles && stow -d profiles/workstation -t ~ --no-folding -R zsh
```

Expected: no error output.

- [ ] **Step 2: Verify the new symlinks point to `workstation/`**

Run:
```bash
find ~ -maxdepth 5 -type l -lname '*dotfiles/profiles/workstation/*' 2>/dev/null
```

Expected: one or more symlinks listed (at least `~/.gitconfig.local` and `~/.zshrc.d/workstation.zsh`).

- [ ] **Step 3: Verify no symlinks point to the old `personal/` path**

Run:
```bash
find ~ -maxdepth 5 -type l -lname '*dotfiles/profiles/personal/*' 2>/dev/null
```

Expected: empty output.

- [ ] **Step 4: Sanity-check that the live shell environment still works**

Open a new terminal (or run `exec zsh` in the current one) and verify:
```bash
echo $USER
git config --get user.email
```

Expected: correct user and the `profiles/workstation/git/.gitconfig.local` email address (whatever is set there).

Also verify the profile zshrc fragment is sourced:
```bash
zsh -ic 'echo $ZSH_VERSION; ls ~/.zshrc.d/'
```

Expected: zsh version printed, `workstation.zsh` listed in the directory.

- [ ] **Step 5: No commit in this task.** The repo state is unchanged; only the live filesystem's symlinks were refreshed.

---

## Task 7: Sweep the repo for residual stale references

**Files:** potentially modifies any file with stale references; no deletions.

- [ ] **Step 1: Grep for stale window-manager and distro names**

Run:
```bash
cd ~/dotfiles && grep -rln --include='*.sh' --include='*.md' --include='*.conf' --include='*.ini' --include='*.zsh' -E '\b(sway|wofi|kitty|ubuntu|debian|micro|qalculate)\b' . 2>/dev/null | grep -v '^./docs/' | grep -v '^./\.git/'
```

Expected: may return hits. For each hit:
1. Read the line with `grep -n` in that file.
2. If the match is a stale reference (e.g., `# Works on Ubuntu` in a script for Arch), update it.
3. If the match is a legitimate use (e.g., "mako" or "mika" substring matching — unlikely but possible), leave it.

False positives to expect: `.mako` theme directory files may contain the substring "kitty" or similar in CSS color names — investigate each hit; don't rewrite blindly.

- [ ] **Step 2: Grep for `sync-windows` (the deleted script)**

Run:
```bash
cd ~/dotfiles && grep -rln "sync-windows" --include='*.sh' --include='*.md' --include='*.conf' . 2>/dev/null | grep -v '^./docs/' | grep -v '^./\.git/'
```

Expected: empty, or only in `docs/` / `.git/`. Any remaining reference in an executable script should be removed.

- [ ] **Step 3: If any files were modified, commit them**

Run:
```bash
cd ~/dotfiles && git status
```

If files are modified:
```bash
cd ~/dotfiles && git add -A
git commit -m "$(cat <<'EOF'
cleanup: sweep residual stale references

Remove leftover mentions of removed tools/configs (sway, wofi, kitty,
ubuntu, debian, micro, qalculate, sync-windows) in scripts and prose.
Docs intentionally preserved — the spec discusses them legitimately.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

If nothing was modified, skip the commit step and continue.

---

## Task 8: Stopgap README update

**Files:** `README.md` (rewrite selected sections only).

This is a *stopgap* — Wave 4 will fully rewrite `README.md` as part of the docs overhaul. For now the goal is only to make the README not lie about the current system.

- [ ] **Step 1: Read the current README**

Run:
```bash
cat ~/dotfiles/README.md
```

Identify sections mentioning Sway, Wofi, Kitty, Ubuntu, WSL, `sync-windows.sh`, or `profiles/work/`.

- [ ] **Step 2: Edit the README to reflect current reality**

Specific edits expected:

1. The "Structure" tree currently lists `sway/`, `wofi/`, `kitty/`, `windows/` under `base/` — replace with the actual base packages: `hypr/`, `fuzzel/`, `ghostty/`, `waybar/`, `mako/`, `btop/`, `helix/`, `lf/`, `mpv/`, `yt-dlp/`, `claude/`, `paru/`, `xdg/`, `systemd/`, `bin/`, `zsh/`, `git/`. Drop `windows/`. Drop `micro/` and `qalculate/` (deleted in Task 3).

2. The "Profiles" table currently lists `personal` (Ubuntu+Sway), `work` (WSL), `server`. Replace with:

| Profile | Machine | What it adds |
|---------|---------|-------------|
| `workstation` | This Arch laptop | Personal git identity, Obsidian vault path, Google Drive bisync, custom zsh fragments |
| `server` | Headless Arch server | Server git identity, trimmed Claude Code plugin set |

Remove `work` row entirely.

3. The "Sway Desktop" section is entirely obsolete — the compositor is Hyprland, not Sway. Replace the header with "Hyprland Desktop" and the table rows with the real components:

| Component | Config | Purpose |
|-----------|--------|---------|
| **Hyprland** | `base/hypr/` | Wayland compositor — tiling, keybindings, hyprpaper, hyprlock |
| **Waybar** | `base/waybar/` | Status bar |
| **Fuzzel** | `base/fuzzel/` | App launcher |
| **Mako** | `base/mako/` | Notifications |
| **Ghostty** | `base/ghostty/` | Terminal emulator |

The keybindings table can stay as-is if accurate, or be shortened to "See `~/.config/hypr/hyprland.conf` for current bindings" — Wave 4 restores a full table in `docs/manual/02-keybindings.md`.

4. "Adding a New Profile" section: replace every `<name>` example that used `personal` with `workstation`.

5. "Windows Configs" section: DELETE entirely. Windows is gone.

6. "Manual Steps" section: remove the `~/gdrive` paragraph if it references Ubuntu-specific paths; keep the generic substance. If unclear, leave as-is for Wave 4.

7. Add a one-line banner near the top:
   > **Status (2026-04-23):** mid-reorg. This README is a stopgap — a proper manual at `docs/manual/` is planned in Wave 4 of the reorg. See `docs/superpowers/specs/2026-04-23-dotfiles-opinionated-reorg-design.md`.

- [ ] **Step 3: Verify the README renders correctly**

Run:
```bash
cd ~/dotfiles && head -80 README.md
```

Spot-check:
- No "sway", "wofi", "kitty", "Ubuntu" references
- Profile table shows `workstation` and `server` only
- Hyprland section replaces Sway section
- Stopgap banner present

- [ ] **Step 4: Commit**

Run:
```bash
cd ~/dotfiles && git add README.md
git commit -m "$(cat <<'EOF'
readme: stopgap update — reflect Arch/Hyprland/Ghostty reality

Wave-1 cleanup companion: fix structure tree, profile table, desktop
section, and adding-profile examples to match post-rename state.
Stopgap only — full manual comes in Wave 4.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Expected: commit succeeds.

---

## Task 9: Final verification

**Files:** none modified — read-only sanity pass.

- [ ] **Step 1: `git log` shows all Wave 1 commits**

Run:
```bash
cd ~/dotfiles && git log --oneline -10
```

Expected: at least four new commits (cleanup, profile rename, optional sweep, readme stopgap) on top of the spec commit.

- [ ] **Step 2: The repo still has a working `install.sh`**

Run:
```bash
bash -n ~/dotfiles/install.sh && echo OK
```

Expected: `OK`.

- [ ] **Step 3: No broken symlinks in `~/.config/`**

Run:
```bash
find ~/.config -xtype l 2>/dev/null
```

Expected: empty (no broken links).

If any broken link is reported and it points into `~/dotfiles/`, investigate — likely a package unstow was missed.

- [ ] **Step 4: The machine is still live**

Open a new terminal, launch Ghostty, run `hyprctl monitors`, open the zsh prompt, confirm git identity. If anything is broken, `git revert` the offending commit and investigate.

- [ ] **Step 5: Celebrate Wave 1 shipped, write the Wave 2 plan next.**

---

## Rollback

If any task causes visible breakage that can't be fixed in <10 minutes:

```bash
cd ~/dotfiles && git log --oneline -10
# Identify the last-known-good commit hash (likely the spec commit 907b370 or earlier)
git reset --hard <hash>
# Re-stow from the now-old state
./install.sh workstation
```

The repo's history preserves everything deleted in Task 3 — nothing is permanently lost.

---

## Out of scope for Wave 1

- No install-script modularization (Wave 2).
- No theme system work (Wave 3).
- No `docs/manual/*.md` chapters (Wave 4).
- No Neovim/kickstart setup (Wave 2).
- No full README rewrite — only the stopgap edit in Task 8.
