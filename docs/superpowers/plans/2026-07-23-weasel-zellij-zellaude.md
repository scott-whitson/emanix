# Weasel zellij + zellaude Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give weasel the Debian-WSL zellij experience (zellaude bar, persistent sessions) with SSH auto-attach, driven by a `scott.zellij.enable` flag.

**Architecture:** Opt-in HM module (ghostty pattern) in the shared i-intelligence stack; `~/.config/zellij` is one live `mkOutOfStoreSymlink` into `base/zellij/.config/zellij`; a zsh `initContent` snippet auto-attaches SSH shells. Only weasel flips the flag (flake.nix home-manager block).

**Tech Stack:** Nix flake / Home Manager, zellij, zsh. No test framework — verification is `nix eval`/`nix build` assertions plus a manual smoke checklist.

**Spec:** `docs/superpowers/specs/2026-07-23-weasel-zellij-zellaude-design.md`

## Global Constraints

- Flag defaults **off**: eminix/zord/datacore closures must be byte-identical before vs after Task 1 (they don't set the flag).
- No HM `programs.zellij.settings` — the kdl files in `base/zellij/.config/zellij/` are the single source of truth.
- `enableZshIntegration` must stay unset/false (it auto-starts zellij in every interactive shell).
- Auto-attach must NOT trigger for: local (non-SSH) shells, shells already inside zellij, or `TERM=dumb` (eminix TRAMP would hang otherwise).
- Not `exec zellij` — detach must drop to a plain shell, not close the connection.
- Weasel rebuild flow: build as scott, activate as root (root can't read scott's repo — libgit2 ownership). Weasel sudo is passwordless.
- Commit messages: plain conventional commits, **no Co-Authored-By trailers**.
- `~/.claude/settings.json` must not be modified — it already points at the hook path.

---

### Task 1: Rewrite zellij.nix as an opt-in module and import it

**Files:**
- Modify: `ioshi/i-intelligence/zellij.nix` (full rewrite, currently stale HM settings)
- Modify: `ioshi/i-intelligence/default.nix:27` (uncomment `./zellij.nix`)

**Interfaces:**
- Consumes: `config.scott.dotfiles.path` (string, set in `home/scott/default.nix`), zsh module's `programs.zsh.initContent` (lines type, merges).
- Produces: `options.scott.zellij.enable` (bool, default false) — Task 2 sets it true for weasel.

- [ ] **Step 1: Replace the entire contents of `ioshi/i-intelligence/zellij.nix`**

```nix
{ config, lib, ... }:

{
  options.scott.zellij.enable = lib.mkEnableOption
    "zellij with the zellaude bar, deployed live from base/zellij";

  config = lib.mkIf config.scott.zellij.enable {
    # Package only — no `settings`: the kdl files in base/zellij are the
    # single source of truth, and zellaude writes to its own settings json
    # (a store copy would be read-only). enableZshIntegration stays off;
    # it would auto-start zellij in every interactive shell.
    programs.zellij.enable = true;

    # One live symlink for the whole config dir (same pattern as the
    # emacs lisp dir). HM recreates it every rebuild, so plugin upgrades
    # can't strand a stale hand-made link.
    xdg.configFile."zellij".source = config.lib.file.mkOutOfStoreSymlink
      "${config.scott.dotfiles.path}/base/zellij/.config/zellij";

    # SSH logins land in the persistent session. Guards: never inside an
    # existing zellij, never for TRAMP (TERM=dumb). Not `exec`: detaching
    # should drop to a plain shell, not close the connection.
    programs.zsh.initContent = lib.mkAfter ''
      if [[ -n "$SSH_CONNECTION" && -z "$ZELLIJ" && "$TERM" != "dumb" ]]; then
        zellij attach --create main
      fi
    '';
  };
}
```

- [ ] **Step 2: Uncomment the import in `ioshi/i-intelligence/default.nix`**

Change line 27 from `# ./zellij.nix` to `./zellij.nix` (leave it in the "Optional" block; the flag gates it).

- [ ] **Step 3: Verify the flag exists and defaults off, and eminix is unaffected**

```bash
cd ~/dotfiles
nix eval .#nixosConfigurations.weasel.config.home-manager.users.scott.scott.zellij.enable
nix eval .#nixosConfigurations.eminix.config.home-manager.users.scott.scott.zellij.enable
```

Expected: both print `false`. (Weasel flips in Task 2.)

- [ ] **Step 4: Verify eminix closure is unchanged (flag-off no-op proof)**

**Amended 2026-07-23:** the original full-build comparison compiled eminix's desktop
closure (bitwarden-desktop, ewm-core — not in the public cache) from source inside
weasel's 7.6 GiB VM and OOM-crashed WSL twice. Compare derivation paths via eval
instead — an identical `.drvPath` proves identical output with nothing built:

```bash
git stash && nix eval --raw .#nixosConfigurations.eminix.config.system.build.toplevel.drvPath > /tmp/claude-1000/-home-scott/2ed4dea7-a466-43b2-ad9d-8edf005738c1/scratchpad/eminix-drv-before
git stash pop && nix eval --raw .#nixosConfigurations.eminix.config.system.build.toplevel.drvPath > /tmp/claude-1000/-home-scott/2ed4dea7-a466-43b2-ad9d-8edf005738c1/scratchpad/eminix-drv-after
diff /tmp/claude-1000/-home-scott/2ed4dea7-a466-43b2-ad9d-8edf005738c1/scratchpad/eminix-drv-before /tmp/claude-1000/-home-scott/2ed4dea7-a466-43b2-ad9d-8edf005738c1/scratchpad/eminix-drv-after
```

Expected: `diff` prints nothing (identical .drv path). Never `nix build` the eminix
toplevel on weasel — it OOMs the VM.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add ioshi/i-intelligence/zellij.nix ioshi/i-intelligence/default.nix
git commit -m "feat(zellij): opt-in module deploying base/zellij live, ssh auto-attach"
```

---

### Task 2: Enable on weasel and rebuild

**Files:**
- Modify: `flake.nix:148` area (weasel `home-manager.users.scott` block)

**Interfaces:**
- Consumes: `scott.zellij.enable` option from Task 1.
- Produces: activated weasel system with `zellij` on PATH and `~/.config/zellij` symlink — Task 3 verifies behavior.

- [ ] **Step 1: Set the flag in the weasel block of `flake.nix`**

Directly under `scott.ghostty.enable = true;` (flake.nix:148) add:

```nix
                # Persistent ssh sessions from eminix land in zellij
                # (zellaude bar; config deployed live from base/zellij).
                scott.zellij.enable = true;
```

- [ ] **Step 2: Verify the flag evaluates true for weasel**

```bash
cd ~/dotfiles
nix eval .#nixosConfigurations.weasel.config.home-manager.users.scott.scott.zellij.enable
```

Expected: `true`

- [ ] **Step 3: Build and activate (build as scott, activate as root)**

```bash
cd ~/dotfiles
nix build .#nixosConfigurations.weasel.config.system.build.toplevel
sudo nix-env -p /nix/var/nix/profiles/system --set "$(readlink -f result)"
sudo "$(readlink -f result)/bin/switch-to-configuration" switch
```

Expected: activation completes; watch for a home-manager activation failure mentioning an existing `~/.config/zellij` (there is none today, so it should link cleanly).

- [ ] **Step 4: Verify deployment on disk**

```bash
readlink ~/.config/zellij
zellij --version
test -x ~/.config/zellij/plugins/zellaude-hook.sh && echo hook-ok
```

Expected: symlink → `/home/scott/dotfiles/base/zellij/.config/zellij`; a zellij version prints; `hook-ok`.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add flake.nix
git commit -m "feat(weasel): enable zellij + zellaude"
```

---

### Task 3: End-to-end verification and push

**Files:** none (verification + push only)

**Interfaces:**
- Consumes: activated weasel from Task 2; eminix→weasel ssh (port 2222 + key, working since 2026-07-23).

- [ ] **Step 1: Assert the auto-attach snippet deployed into the generated zshrc**

(The positive attach case can't be scripted: `ssh weasel "cmd"` shells are non-interactive so `.zshrc` never runs, and a forced interactive shell would hang the test inside the zellij TUI. Assert deployment here; Step 4 verifies the real attach interactively.)

```bash
grep -n 'zellij attach --create main' ~/.zshrc
```

Expected: one match, inside the `SSH_CONNECTION`/`ZELLIJ`/`TERM != dumb` guard.

- [ ] **Step 2: TRAMP guard check (TERM=dumb must NOT attach)**

```bash
ssh -o ProxyCommand='tailscale nc %h %p' eminix \
  'ssh weasel "TERM=dumb zsh -ic \"echo ZJ=[\$ZELLIJ]\"" 2>/dev/null' | grep ZJ=
```

Expected: `ZJ=[]` (no zellij started).

- [ ] **Step 3: Local shells stay zellij-free**

```bash
zsh -ic 'echo ZJ=[$ZELLIJ]'
```

Expected (no SSH_CONNECTION in a local/session shell): `ZJ=[]`.

- [ ] **Step 4: Manual smoke checklist (Scott, interactive — cannot be automated)**

From eminix ghostty: `ssh weasel` → lands in zellij session `main` with the zellaude clock bar on top and no bottom status bar; `Ctrl y` opens the zellij-forgot cheatsheet; start a Claude Code session and confirm the zellaude activity indicator fires; `Ctrl o, d` detaches to a plain weasel zsh.

Contingency: if the bar pane is blank or errors, the pre-built `zellaude.wasm` may mismatch the nixpkgs zellij version — rebuild from `~/projects/zellaude` (`install.sh`) into `base/zellij/.config/zellij/plugins/` and re-test (spec lists rebuild as out of scope, so surface this to Scott before doing it).

- [ ] **Step 5: Push**

```bash
cd ~/dotfiles && git push
```

Expected: push succeeds; datacore mirror picks it up on its normal sync. No rebuild needed on eminix/zord (flag off; Task 1 proved no-op).
