# Three-Node Home Model — Phase 1 (Stack) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The dotfiles flake produces standalone Home-Manager homes for Debian datacore (`scott@datacore`) and Debian WSL (`scott@work`) with the same Emacs/meow/CLI environment as eminix, minus GUI/EWM pieces.

**Architecture:** Two new booleans in the existing `scott.*` option set — `scott.gui` (gates cursor/Wayland/GUI apps/swaylock/ghostty) and `scott.standalone` (installs the Emacs build user-side, skips agenix-dependent files and the syncthing user service). A new `standalone.nix` HM module builds the same pgtk Emacs from `emacs/packages.nix` (without the EWM package) and runs it as a user daemon. `flake.nix` gains `homeConfigurations` reusing `home/scott/default.nix`. Defaults (`gui=true`, `standalone=false`) keep eminix byte-identical.

**Tech Stack:** Nix flakes, Home-Manager (standalone `homeManagerConfiguration`), emacs-overlay, Debian 13 (datacore + WSL2).

**Spec:** `docs/superpowers/specs/2026-07-19-three-node-home-model-design.md`

## Global Constraints

- **Never** `git add -A` or `git add .` — stage explicit paths only (perpetually-dirty files exist on this machine).
- **No** `Co-Authored-By` trailers in commits, ever.
- Propagation is 3-hop: commit+push on WSL → GitHub → `ssh datacore "cd ~/projects/dotfiles && git pull --ff-only"`. eminix pulls from datacore (final task only).
- `datacore:~/projects/dotfiles` is the git hub (`receive.denyCurrentBranch=updateInstead`) — only ever `git pull --ff-only` there; never edit its tree directly.
- Never touch `~/.pi/agent/settings.json` or `~/.pi/agent/auth.json` contents on datacore — pi state is live there.
- Never handle plaintext API keys; agenix-dependent files are simply gated off on standalone nodes.
- Eminix regression bar: with defaults `gui=true, standalone=false`, `nixosConfigurations.eminix` toplevel drvPath must be **unchanged** by Task 2 (verified) and Task 3.
- This session runs ON the work WSL. `sudo` here needs Scott (interactive); datacore has passwordless sudo (verified). Steps marked **[Scott]** must be given to Scott to run via `!` prefix — report NEEDS_CONTEXT/wait rather than skipping them.
- Node facts: datacore = Debian 13, ssh alias `datacore`, `~/dotfiles → ~/projects/dotfiles`, syncthing/sshd/docker are Debian-managed (leave them). WSL = Debian 13 (trixie), repo at `/home/scott/dotfiles`, tailscale userspace mode. Both nodes: `~/dotfiles` resolves to a checkout, so `scott.dotfiles.path` default (`~/dotfiles` via `home/scott/default.nix`) works everywhere; **do not** set per-node paths.

---

### Task 1: Install Nix (multi-user) on datacore

**Files:** none in repo (remote system change only)

**Interfaces:**
- Produces: working `nix` daemon + flakes on datacore; all later eval/build verification runs there via ssh.

- [ ] **Step 1: Verify precondition (no nix, passwordless sudo)**

Run: `ssh datacore "which nix; sudo -n true && echo sudo-ok"`
Expected: `nix not found` (or empty) then `sudo-ok`. If nix already exists, skip to Step 3.

- [ ] **Step 2: Run the official multi-user installer unattended**

```bash
ssh datacore "curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes"
```

Expected: ends with `Installation finished!`. The installer patches `/etc/zshrc`/`/etc/bashrc` and starts `nix-daemon`.

- [ ] **Step 3: Enable flakes system-wide**

```bash
ssh datacore "grep -q 'experimental-features' /etc/nix/nix.conf 2>/dev/null || echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf; sudo systemctl restart nix-daemon"
```

- [ ] **Step 4: Verify from a fresh login shell**

Run: `ssh datacore "bash -lc 'nix --version && nix eval --expr 1+1'"`
Expected: a nix version line, then `2`.

- [ ] **Step 5: No commit** — nothing in the repo changed. Record completion in the ledger only.

---

### Task 2: Portability flags — `scott.gui` and `scott.standalone`

**Files:**
- Modify: `ioshi/i-intelligence/theme.nix` (option declarations)
- Modify: `ioshi/i-intelligence/packages.nix` (GUI package gate)
- Modify: `ioshi/i-intelligence/swaylock.nix`, `ioshi/i-intelligence/ghostty.nix` (gui gate)
- Modify: `ioshi/i-intelligence/pi.nix` (agenix symlink gate)
- Modify: `ioshi/i-intelligence/systemd.nix` (syncthing user-service gate)
- Modify: `home/scott/default.nix` (pointerCursor gate, `mkDefault` for profile)

**Interfaces:**
- Produces: `config.scott.gui : bool` (default `true`), `config.scott.standalone : bool` (default `false`) — consumed by Task 3's module and flake entries.

- [ ] **Step 1: Record the eminix baseline drvPath (the "failing test" for regressions)**

```bash
ssh datacore "cd ~/projects/dotfiles && bash -lc 'nix eval .#nixosConfigurations.eminix.config.system.build.toplevel.drvPath' > ~/eminix-drv-before.txt; cat ~/eminix-drv-before.txt"
```

(First eval downloads flake inputs on datacore; several minutes is normal.)

- [ ] **Step 2: Declare the options in `theme.nix`**

Inside the existing `options.scott = { ... }` set, alongside `theme`, add:

```nix
    gui = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Machine has a graphical session. Gates cursor theme, Wayland tools, GUI apps, swaylock, and ghostty config.";
    };

    standalone = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Home Manager runs standalone on a foreign distro (no eminix NixOS layer): install the Emacs build user-side, skip agenix-dependent files and the syncthing user service.";
    };
```

- [ ] **Step 3: Gate GUI packages in `packages.nix`**

Replace the whole `home.packages` list with (keep the header comment):

```nix
  home.packages = with pkgs; [
    # CLI essentials
    ripgrep
    fd
    jq
    htop
    btop
    fastfetch
    unzip
    xz
    file

    # Developer tools
    gh
    lazygit
    nodejs # pi coding agent runtime (pi itself installed via npm, post-install)
    just
    nixd
    nixpkgs-fmt
    deadnix
    statix

    # Media (CLI)
    ffmpeg
    imagemagick

    # Network
    curl
    wget
    mosh
    nmap
    iperf3

    # Fonts — every node: pgtk emacs under WSLg reads nix-profile fonts
    jetbrains-mono
    nerd-fonts.jetbrains-mono
  ] ++ lib.optionals config.scott.gui [
    # Wayland tools
    grim
    slurp
    wl-clipboard
    wf-recorder
    swappy

    # Notifications
    libnotify

    # Media (GUI)
    mpv

    # Terminal — config lives in ghostty.nix; the package (and its XDG
    # desktop entry, which EWM's s-d launcher needs) is installed here.
    ghostty

    # GUI apps
    firefox
    bitwarden-desktop
  ];
```

- [ ] **Step 4: Gate swaylock.nix and ghostty.nix bodies**

Both modules keep their `let` blocks; wrap the returned attrset in a `config = lib.mkIf config.scott.gui { ... }`. swaylock.nix becomes:

```nix
{
  config = lib.mkIf config.scott.gui {
    # Config only — the swaylock package and its PAM entry are host-level
    # (modules/nixos/ewm.nix): unlocking auths through PAM, and a swaylock
    # installed without security.pam.services.swaylock can never unlock.
    home.file.".config/swaylock/config" = {
      text = ''
        # -----------------------------------------------
        # Swaylock Configuration — managed by Home Manager
        # -----------------------------------------------
        daemonize
        ${themeLib.swaylock activePalette}
      '';
    };
  };
}
```

ghostty.nix identically: `config = lib.mkIf config.scott.gui { home.file.".config/ghostty/config" = ...; home.file.".config/ghostty/theme.conf" = ...; home.file.".config/ghostty/themes/catppuccin-mocha.conf" = ...; home.file.".config/ghostty/themes/catppuccin-latte.conf" = ...; };` — same four file entries as today, unchanged text.

- [ ] **Step 5: Gate the agenix symlink in `pi.nix`**

Replace:

```nix
  home.file.".pi/agent/auth.json".source =
    config.lib.file.mkOutOfStoreSymlink "/run/agenix/openrouter-auth";
```

with:

```nix
  # agenix only exists on the NixOS nodes; standalone nodes manage
  # ~/.pi/agent/auth.json by hand (it is stignored from sync anyway).
  home.file.".pi/agent/auth.json" = lib.mkIf (!config.scott.standalone) {
    source = config.lib.file.mkOutOfStoreSymlink "/run/agenix/openrouter-auth";
  };
```

- [ ] **Step 6: Gate the syncthing user service in `systemd.nix`**

```nix
    # Standalone nodes: datacore's syncthing is Debian-managed (it is the
    # hub); the work WSL gets syncthing in Phase 3. Neither wants this unit.
    syncthing = lib.mkIf (!config.scott.standalone) {
```

(only the `syncthing = {` line changes; body unchanged).

- [ ] **Step 7: Gate pointerCursor and soften profile in `home/scott/default.nix`**

```nix
  home.pointerCursor = lib.mkIf config.scott.gui {
    enable = true;
    package = pkgs.catppuccin-cursors.mochaDark;
    name = "catppuccin-mocha-dark-cursors"; # must match the dir in share/icons
    size = 24;
    gtk.enable = true;
  };
```

and in `scott.dotfiles`, change `profile = "desktop";` to `profile = lib.mkDefault "desktop";` so per-node modules can override without a conflict.

- [ ] **Step 8: Commit and propagate to datacore**

```bash
cd /home/scott/dotfiles
git add ioshi/i-intelligence/theme.nix ioshi/i-intelligence/packages.nix ioshi/i-intelligence/swaylock.nix ioshi/i-intelligence/ghostty.nix ioshi/i-intelligence/pi.nix ioshi/i-intelligence/systemd.nix home/scott/default.nix
git commit -m "feat(hm): scott.gui + scott.standalone portability flags"
git push
ssh datacore "cd ~/projects/dotfiles && git pull --ff-only"
```

- [ ] **Step 9: Verify eminix drvPath is unchanged**

```bash
ssh datacore "cd ~/projects/dotfiles && bash -lc 'nix eval .#nixosConfigurations.eminix.config.system.build.toplevel.drvPath' > ~/eminix-drv-after.txt; diff ~/eminix-drv-before.txt ~/eminix-drv-after.txt && echo IDENTICAL"
```

Expected: `IDENTICAL`. If drvPaths differ, a gate changed eminix behavior — find and fix before proceeding (do not rationalize a difference away).

---

### Task 3: `standalone.nix` module + `homeConfigurations` in the flake

**Files:**
- Create: `ioshi/i-intelligence/standalone.nix`
- Modify: `ioshi/i-intelligence/default.nix` (import it)
- Modify: `flake.nix` (homeConfigurations output)

**Interfaces:**
- Consumes: `config.scott.standalone` (Task 2).
- Produces: flake outputs `homeConfigurations."scott@datacore"` and `homeConfigurations."scott@work"`; each has an `.activationPackage` used by Tasks 4–5. `scott@datacore` sets `profile="server"`; `scott@work` sets `profile="wsl"`; both set `gui=false; standalone=true`.

- [ ] **Step 1: Create `ioshi/i-intelligence/standalone.nix`**

```nix
{ config, lib, pkgs, ... }:

let
  # Same package set as the eminix system build (ewm.nix), minus the EWM
  # package — standalone nodes have no compositor role.
  emacsPkgs = import ./emacs/packages.nix { inherit pkgs; };
  standaloneEmacs =
    ((pkgs.emacsPackagesFor pkgs.emacs-pgtk).overrideScope emacsPkgs.orgOverride)
      .emacsWithPackages emacsPkgs.list;
in
{
  config = lib.mkIf config.scott.standalone {
    # On eminix the Emacs build is system-owned (ewm.nix). Standalone nodes
    # install it user-side and run the daemon as a systemd user service.
    programs.emacs = {
      enable = true;
      package = standaloneEmacs;
    };

    services.emacs = {
      enable = true;
      client.enable = true;
      startWithUserSession = true;
    };

    # elisa's sqlite-vec extension path — set by ewm.nix on eminix. Chat is
    # non-functional until the node has an Ollama (deferred per the spec),
    # but requiring elisa must not error.
    home.sessionVariables.ELISA_VEC0_PATH = "${pkgs.sqlite-vec}/lib/vec0.so";
  };
}
```

- [ ] **Step 2: Import it from `ioshi/i-intelligence/default.nix`**

In the "Core — always enabled" import list, after `./xdg.nix`, add:

```nix
    ./standalone.nix
```

(Its body is `mkIf scott.standalone`, so eminix is unaffected.)

- [ ] **Step 3: Add `homeConfigurations` to `flake.nix`**

In the `let` block after `mkHost`, add:

```nix
      # Standalone Home-Manager homes for the foreign-distro nodes
      # (Debian datacore, Debian WSL). Same home layer as eminix, headless.
      hmPkgs = import nixpkgs {
        inherit system;
        overlays = [ emacs-overlay.overlays.default ];
        config.allowUnfree = true;
      };
      mkHome = profile:
        home-manager.lib.homeManagerConfiguration {
          pkgs = hmPkgs;
          extraSpecialArgs = sharedSpecialArgs;
          modules = [
            ./home/scott/default.nix
            {
              scott.gui = false;
              scott.standalone = true;
              scott.dotfiles.profile = profile;
            }
          ];
        };
```

and in the outputs attrset, after `nixosConfigurations = { ... };`:

```nix
      # --- Standalone Home-Manager configurations (foreign distros) ---
      homeConfigurations = {
        "scott@datacore" = mkHome "server";
        "scott@work" = mkHome "wsl";
      };
```

- [ ] **Step 4: Commit and propagate to datacore**

```bash
cd /home/scott/dotfiles
git add ioshi/i-intelligence/standalone.nix ioshi/i-intelligence/default.nix flake.nix
git commit -m "feat(flake): standalone HM homes for datacore and work-WSL"
git push
ssh datacore "cd ~/projects/dotfiles && git pull --ff-only"
```

- [ ] **Step 5: Verify both homes evaluate and eminix still doesn't change**

```bash
ssh datacore "cd ~/projects/dotfiles && bash -lc 'nix build --dry-run .#homeConfigurations.\"scott@datacore\".activationPackage && nix build --dry-run .#homeConfigurations.\"scott@work\".activationPackage && nix eval .#nixosConfigurations.eminix.config.system.build.toplevel.drvPath'"
```

Expected: two dry-run derivation listings (no eval errors), and the same drvPath recorded in Task 2 Step 9.

---

### Task 4: First switch on datacore

**Files:** none in repo (remote activation). Backups on datacore: `~/.zshrc.pre-hm`, `~/.gitconfig-global.pre-hm.txt`.

**Interfaces:**
- Consumes: `homeConfigurations."scott@datacore".activationPackage` (Task 3).
- Produces: a working HM home on datacore (`home-manager` CLI on PATH afterwards via `programs.home-manager.enable`).

- [ ] **Step 1: Snapshot current shell/git state (pre-activation evidence)**

```bash
ssh datacore "git config --global --list > ~/.gitconfig-global.pre-hm.txt 2>/dev/null; cat ~/.gitconfig-global.pre-hm.txt; ls -la ~/.zshrc ~/.zshenv ~/.zprofile ~/.gitconfig ~/.emacs.d ~/.config/emacs 2>&1"
```

Record output in the task report. `~/.zshrc` is a real file (server-local content possible — the backup in Step 2 preserves it; flag anything meaningful, e.g. PATH exports, in your report).

- [ ] **Step 2: Move collisions aside**

```bash
ssh datacore "mv ~/.zshrc ~/.zshrc.pre-hm 2>/dev/null; rm -f ~/.gitconfig; rm -rf ~/.emacs.d; true"
```

(`~/.gitconfig` is a stow symlink into the repo — removing the symlink loses nothing; the values were captured in Step 1. `~/.emacs.d` must not exist or Emacs prefers it over `~/.config/emacs`.)

- [ ] **Step 3: Build and activate**

```bash
ssh datacore "cd ~/projects/dotfiles && bash -lc 'nix build .#homeConfigurations.\"scott@datacore\".activationPackage && ./result/activate'"
```

Expected: ends with activation output, no `collision`/`existing file` errors. If activation aborts listing existing files, move each listed file to `<name>.pre-hm` and re-run this step.

- [ ] **Step 4: Verify shell, git, emacs**

```bash
ssh datacore "zsh -lic 'which home-manager emacsclient && git config user.email && echo SHELL-OK'"
ssh datacore "bash -lc 'systemctl --user status emacs --no-pager | head -5; emacsclient -e \"(emacs-version)\" '"
```

Expected: paths under `~/.nix-profile/bin` (or `/nix/store/...`), `scott@scottwhitson.com`, `SHELL-OK`; emacs service `active (running)` (start it with `systemctl --user start emacs` if this was the first activation), and a version string from `emacsclient`. If `git config user.email` differs from the Step 1 capture in a way that matters, write the old value into `~/.gitconfig.local` (git.nix includes it).

- [ ] **Step 5: Verify init.el loaded cleanly and pi state untouched**

```bash
ssh datacore "bash -lc 'emacsclient -e \"(progn (featurep (quote meow)))\"; ls -la ~/.config/emacs/init.el; head -c 80 ~/.pi/agent/settings.json; echo'"
```

Expected: `t` (meow loaded), `init.el -> …/dotfiles/ioshi/i-intelligence/emacs/init.el` (liveElisp symlink through `~/dotfiles`), and settings.json still real pi JSON (not a fresh seed).

- [ ] **Step 6: No commit** — record in ledger (`Task 4: datacore activated`).

---

### Task 5: Nix + first switch on the work WSL

**Files:** none in repo. Local backups: `~/.zshrc.pre-hm` etc.; creates `~/.gitconfig.local`.

**Interfaces:**
- Consumes: `homeConfigurations."scott@work"` (Task 3).
- Produces: working HM home on this machine; emacs user daemon for Task 6.

- [ ] **Step 1: Preconditions**

```bash
ps -p 1 -o comm=; systemctl --user is-system-running; git config --global --list | tee ~/.gitconfig-global.pre-hm.txt
```

Expected: `systemd`, then `running` (or `degraded` — acceptable), then current git values. If PID 1 is not systemd, STOP and report BLOCKED (nix-daemon needs systemd here).

- [ ] **Step 2 [Scott]: Run the Nix installer (needs interactive sudo)**

Ask Scott to run:

```
! curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes
```

Wait for his confirmation/output. Then verify: `bash -lc 'nix --version'`.

- [ ] **Step 3 [Scott]: Enable flakes**

Ask Scott to run:

```
! echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf && sudo systemctl restart nix-daemon
```

Verify: `bash -lc 'nix eval --expr 1+1'` → `2`.

- [ ] **Step 4: Preserve work git identity, move collisions aside**

```bash
printf '[user]\n\temail = %s\n' "$(git config user.email)" > ~/.gitconfig.local
rm -f ~/.zshrc ~/.gitconfig   # both are stow symlinks into ~/dotfiles/base (verified)
rm -rf ~/.emacs.d
```

Note: `~/.config/ghostty/config` stays — `gui=false` means HM doesn't manage it, and the stow symlink is inert. Do NOT touch anything under `~/.claude` or `base/claude`.

- [ ] **Step 5: Build and activate**

```bash
cd /home/scott/dotfiles && bash -lc 'nix build ".#homeConfigurations.\"scott@work\".activationPackage" && ./result/activate'
```

Expected: activation completes. Same collision-handling rule as Task 4 Step 3 (move listed files to `*.pre-hm`, re-run). The emacs build may take a while (elisp compilation; emacs-pgtk itself comes from the binary cache).

- [ ] **Step 6: Verify shell, git identity, daemon**

```bash
zsh -lic 'which home-manager emacsclient && git config user.email && echo SHELL-OK'
bash -lc 'systemctl --user start emacs; systemctl --user status emacs --no-pager | head -5; emacsclient -e "(emacs-version)"'
```

Expected: nix-profile paths, `swhitson@centraldata.com` (from `~/.gitconfig.local` — this MUST override git.nix's personal default), `SHELL-OK`, service running, version string.

- [ ] **Step 7: No commit** — ledger only.

---

### Task 6: Emacs access verification on WSL + docs

**Files:**
- Create: `docs/ioshi/standalone-hm.md`

**Interfaces:**
- Consumes: running emacs user daemon on the WSL (Task 5).
- Produces: documented, verified access path (WSLg GUI or terminal fallback).

- [ ] **Step 1: Detect WSLg**

```bash
echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"; ls /mnt/wslg 2>/dev/null | head -3
```

Expected if WSLg present: `WAYLAND_DISPLAY=wayland-0` and directory contents. If absent, note it and treat terminal as the access path (Step 3 still runs).

- [ ] **Step 2 [Scott] (only if WSLg present): GUI frame smoke test**

Ask Scott to run and confirm a GUI Emacs window opens as a normal Windows window:

```
! emacsclient -c ~/dotfiles/README.md
```

Ask him to confirm: window appears, JetBrains Mono renders, meow normal mode works (`x` selects a line), `C-c d` opens Dirvish. Record his answer verbatim in the report.

- [ ] **Step 3: Terminal client smoke test**

```bash
emacsclient -t -e '(kill-emacs)' 2>/dev/null; systemctl --user restart emacs; sleep 2; emacsclient -e '(featurep (quote meow))'
```

Expected: `t`. (Restart proves the daemon comes back cleanly; `-t` interactive use is Scott's to try, not scriptable here.)

- [ ] **Step 4: Write `docs/ioshi/standalone-hm.md`**

```markdown
# Standalone Home-Manager nodes (datacore, work-WSL)

Debian nodes run the eminix home layer (Emacs/meow/CLI) via standalone
Home-Manager from the same flake. See the spec:
`docs/superpowers/specs/2026-07-19-three-node-home-model-design.md`.

| Node | Flake attr | Profile | Notes |
| --- | --- | --- | --- |
| datacore | `scott@datacore` | server | syncthing/docker stay Debian-managed |
| work-WSL | `scott@work` | wsl | EWM never; Windows is the compositor |

## Bootstrap (once per node)

1. `curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes`
2. `echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf && sudo systemctl restart nix-daemon`
3. Move aside `~/.zshrc`, `~/.gitconfig`, `~/.emacs.d`; keep work identity in `~/.gitconfig.local`
4. `cd ~/dotfiles && nix build '.#homeConfigurations."scott@<node>".activationPackage' && ./result/activate`

## Day 2

- `home-manager switch --flake ~/dotfiles#scott@<node>` after pulling repo changes
- Emacs runs as a user daemon: `systemctl --user {status,restart} emacs`
- Access on WSL: `emacsclient -c` (WSLg GUI window) or `emacsclient -t` (terminal)
- elisa: `ELISA_VEC0_PATH` is set, but chat needs an Ollama — deferred; not available on these nodes yet
```

Replace the "Access on WSL" line with whatever Step 1–3 actually found (e.g. note if WSLg was absent).

- [ ] **Step 5: Commit, propagate everywhere (including eminix)**

```bash
cd /home/scott/dotfiles
git add docs/ioshi/standalone-hm.md
git commit -m "docs: standalone HM node bootstrap + access reference"
git push
ssh datacore "cd ~/projects/dotfiles && git pull --ff-only"
ssh -o ConnectTimeout=5 eminix "cd ~/dotfiles && git fetch origin && git merge --ff-only origin/main"
```

Expected: all three nodes at the same commit (eminix may be off — retry or report if unreachable).
