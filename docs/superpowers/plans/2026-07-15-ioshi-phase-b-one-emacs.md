# ioshi Phase B — one-Emacs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the two `emacs-pgtk` builds (system EWM + Home Manager) into a single system-owned build; Home Manager keeps only config delivery. Define the package list + org pin once. Fix the `liveElisp` path regression from Phase A.

**Architecture:** The single Emacs is built in `ioshi/i-intelligence/ewm.nix` (system-owned, EWM's daemon), from a shared package-set helper `ioshi/i-intelligence/emacs/packages.nix`. It is added to `environment.systemPackages` so `emacsclient` is on PATH. `emacs.nix` (HM) is reduced to config-only: elisp delivery + desktop entry.

**Tech Stack:** Nix flakes, NixOS, Home Manager, emacs-overlay, EWM.

## Global Constraints

- **No Nix on the WSL box.** Verify on zord-old via the loop: edit here → `git bundle create $BUNDLE main` → `scp` → on zord-old `cd ~/dotfiles-build && git fetch -q ~/dotfiles.bundle main && git reset -q --hard FETCH_HEAD` → `nix …`.
- **NOT drv-invariant, by design.** Phase B removes a redundant build and a daemon. The gate is *functional*: eminix builds; exactly **one** `emacs-pgtk-with-packages` in the closure (was two); `emacsclient` on PATH; no HM emacs daemon; elisp symlink target valid.
- **Commits:** no `Co-Authored-By`; scope `git add` to named paths, never `git add -A` (unrelated dirty `base/claude/.claude/settings.json`). Push after each task.
- **The org pin stays** (deduplicated, not dropped) — value `org-9.8.7`, `sha256-bYBtYtZkvZYG1qhPWBTBcWoH0xW+NW4m4m5ime5w+vg=`, url `https://elpa.gnu.org/packages/org-9.8.7.tar`.
- **Package list (canonical, from ewm.nix):** `meow vertico orderless consult marginalia embark embark-consult corfu dirvish magit org-roam org catppuccin-theme markdown-mode vterm`.

---

## Task B1: single source of truth for the Emacs build

Extract the package list + org override into one helper; make `ewm.nix` consume it and expose the built Emacs on the system PATH. (The HM build still exists after this task — it is removed in B2. Order matters: guarantee the system Emacs + emacsclient first, remove the redundant one second.)

**Files:**
- Create: `ioshi/i-intelligence/emacs/packages.nix`
- Modify: `ioshi/i-intelligence/ewm.nix`

**Interfaces:**
- Produces: `import ./emacs/packages.nix { inherit pkgs; }` → `{ list = epkgs: [ … ]; orgOverride = eself: esuper: { … }; }`.

- [ ] **Step 1: Capture the baseline closure's Emacs count (before)**

Sync current `main` to zord-old, then:
```bash
sys=$(nix build --no-link --print-out-paths .#nixosConfigurations.eminix.config.system.build.toplevel 2>/dev/null)
nix-store -qR "$sys" | grep -cE 'emacs.*-with-packages'   # record — expected 2 (ewm + HM)
```

- [ ] **Step 2: Create `ioshi/i-intelligence/emacs/packages.nix`**

```nix
# Single source of truth for the eminix Emacs package set + the org pin.
# Consumed by ioshi/i-intelligence/ewm.nix (the sole build site).
{ pkgs, ... }:
{
  # org ELPA pin — the current emacs-overlay snapshot resolves org with a
  # stale hash; override the source until inputs are regenerated upstream.
  orgOverride = _eself: esuper: {
    org = esuper.org.overrideAttrs (_old: {
      src = pkgs.fetchurl {
        url = "https://elpa.gnu.org/packages/org-9.8.7.tar";
        sha256 = "sha256-bYBtYtZkvZYG1qhPWBTBcWoH0xW+NW4m4m5ime5w+vg=";
      };
    });
  };

  list = epkgs: with epkgs; [
    meow
    vertico
    orderless
    consult
    marginalia
    embark
    embark-consult
    corfu
    dirvish
    magit
    org-roam
    org
    catppuccin-theme
    markdown-mode # transition: vault is still .md until the conversion sub-project
    vterm # native module built by nix; M-x package-install can't do this
  ];
}
```

- [ ] **Step 3: Rewire `ewm.nix` to consume the helper and expose Emacs on PATH**

Replace the `emacsPackage = …;` block and augment `environment.systemPackages`. The module head becomes a `let` that binds the built Emacs once:

```nix
{ config, lib, pkgs, ewm, ... }:

let
  emacsPkgs = import ./emacs/packages.nix { inherit pkgs; };
  # The one eminix Emacs: our package set + EWM's module, org pinned.
  theEmacs =
    ((pkgs.emacsPackagesFor pkgs.emacs-pgtk).overrideScope emacsPkgs.orgOverride)
    .emacsWithPackages (epkgs: emacsPkgs.list epkgs ++ [ config.programs.ewm.ewmPackage ]);
in
{
  imports = [ "${ewm}/nix/service.nix" ];

  programs.ewm = {
    enable = true;
    emacsPackage = theEmacs;
    extraEmacsArgs = "--init-directory /home/scott/.config/emacs";
  };
```

Then add `theEmacs` to the existing `environment.systemPackages` list (so `emacsclient` is on PATH now that HM will stop providing it):
```nix
  environment.systemPackages = with pkgs; [
    theEmacs
    wl-clipboard
    brightnessctl
    swaylock
    swayidle
  ];
```
(Note: `theEmacs` is a `let` binding, not from `pkgs`; it sits inside the list but is not part of the `with pkgs;` lookup — that is fine.)

- [ ] **Step 4: Sync + verify (build still works, emacsclient present, still ≥1 Emacs)**

```bash
sys=$(nix build --no-link --print-out-paths .#nixosConfigurations.eminix.config.system.build.toplevel 2>/dev/null)
echo "builds: ${sys:+ok}"
ls "$sys/sw/bin/emacsclient" && echo "emacsclient on system PATH ✓"
nix-store -qR "$sys" | grep -cE 'emacs.*-with-packages'   # still 2 here (HM build not yet removed)
```
Expected: builds; `emacsclient` present in `$sys/sw/bin`; count still 2.

- [ ] **Step 5: Commit + push**

```bash
git add ioshi/i-intelligence/emacs/packages.nix ioshi/i-intelligence/ewm.nix
git commit -m "refactor(i): single Emacs package-set helper; expose emacs on system PATH"
GIT_SSH_COMMAND='ssh -o BatchMode=yes' git push origin main
```

---

## Task B2: reduce Home Manager Emacs to config-only

Remove the redundant HM build + daemon; keep elisp delivery + desktop entry; fix the `liveElisp` path.

**Files:**
- Modify: `ioshi/i-intelligence/emacs.nix`

- [ ] **Step 1: Rewrite `emacs.nix` as config-only**

Full new content (drops `programs.emacs` and `services.emacs`; keeps delivery + desktop entry; fixes `emacsDir`):

```nix
{ config, lib, pkgs, ... }:

let
  # Elisp lives in the repo and is symlinked out-of-store (liveElisp) so it can
  # be edited without a home-manager switch. The Emacs BUILD is system-owned
  # (ioshi/i-intelligence/ewm.nix) — this module only delivers config.
  emacsDir = "${config.scott.dotfiles.path}/ioshi/i-intelligence/emacs";
in
{
  # liveElisp: symlink into the checkout for live editing; otherwise copy the
  # elisp (which lives in-repo next to this module) into the store so hosts
  # without a checkout still get a working config.
  xdg.configFile."emacs/early-init.el".source =
    if config.scott.dotfiles.liveElisp
    then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/early-init.el"
    else ./emacs/early-init.el;
  xdg.configFile."emacs/init.el".source =
    if config.scott.dotfiles.liveElisp
    then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/init.el"
    else ./emacs/init.el;
  xdg.configFile."emacs/lisp".source =
    if config.scott.dotfiles.liveElisp
    then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/lisp"
    else ./emacs/lisp;

  # NO ~/.emacs.d mirror: emacs PREFERS ~/.emacs.d over ~/.config/emacs when
  # both exist, splitting runtime state (a second org-roam.db). ~/.config/emacs
  # is the only config path; ~/.emacs.d must not exist.

  # Launcher entry: terminal-backed client, not the pgtk/X11 frame path.
  home.file.".local/share/applications/emacsclient.desktop".text = ''
    [Desktop Entry]
    Categories=Development;TextEditor;
    Comment=Edit text
    Exec=/usr/bin/env GDK_BACKEND=wayland /usr/bin/emacsclient -c %F
    GenericName=Text Editor
    Icon=emacs
    Keywords=Text;Editor;
    MimeType=text/english;text/plain;text/x-makefile;text/x-c++hdr;text/x-c++src;text/x-chdr;text/x-csrc;text/x-java;text/x-moc;text/x-pascal;text/x-tcl;text/x-tex;application/x-shellscript;text/x-c;text/x-c++;
    Name=Emacs Client
    StartupWMClass=Emacsd
    Terminal=false
    Type=Application
  '';
}
```

- [ ] **Step 2: Sync + verify the collapse (the functional gate)**

```bash
sys=$(nix build --no-link --print-out-paths .#nixosConfigurations.eminix.config.system.build.toplevel 2>/dev/null)
echo "builds: ${sys:+ok}"
echo "emacs-with-packages count (expect 1): $(nix-store -qR "$sys" | grep -cE 'emacs.*-with-packages')"
ls "$sys/sw/bin/emacsclient" && echo "emacsclient still on PATH ✓"
echo "HM emacs daemon (expect false/absent): $(nix eval .#nixosConfigurations.eminix.config.home-manager.users.scott.services.emacs.enable 2>&1 | tail -1)"
echo "elisp symlink target valid: $(nix eval --raw .#nixosConfigurations.eminix.config.home-manager.users.scott.xdg.configFile.\"emacs/init.el\".source 2>/dev/null)"
```
Expected: builds; **count = 1** (the HM build is gone, only EWM's remains); `emacsclient` present; HM `services.emacs.enable` is `false` (or the eval shows the option unset/false); the `init.el` source resolves to a path containing `ioshi/i-intelligence/emacs` (not `modules/home-manager`).

- [ ] **Step 3: Verify eminix still fully builds end-to-end**

```bash
nix build --no-link .#nixosConfigurations.eminix.config.system.build.toplevel && echo "eminix build OK"
nix build --no-link .#nixosConfigurations.zord-old.config.system.build.toplevel && echo "zord-old build OK"
nix flake check 2>&1 | tail -1
```
Expected: both build; `all checks passed!`.

- [ ] **Step 4: Commit + push**

```bash
git add ioshi/i-intelligence/emacs.nix
git commit -m "refactor(i): HM Emacs is config-only; drop redundant build+daemon; fix liveElisp path"
GIT_SSH_COMMAND='ssh -o BatchMode=yes' git push origin main
```

---

## Final acceptance (Phase B)

- [ ] Exactly one `emacs-pgtk-with-packages` derivation in the eminix closure (was two).
- [ ] `emacsclient` present in the built system's `sw/bin`; `EDITOR`/`VISUAL` (from `zsh.nix`) resolve to it.
- [ ] No Home Manager `services.emacs` daemon (EWM's Emacs is the sole daemon).
- [ ] `~/.config/emacs` elisp `source` points at `ioshi/i-intelligence/emacs` (liveElisp regression fixed).
- [ ] org package set defined once (`packages.nix`); the 9.8.7 pin lives in exactly one place.
- [ ] `nix flake check` passes; `eminix` and `zord-old` both build.
