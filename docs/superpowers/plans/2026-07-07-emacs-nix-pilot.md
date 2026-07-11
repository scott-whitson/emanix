# Emacs-on-Nix Pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install Nix + Home Manager on zord and deliver Emacs as the pilot HM module — daily-drivable editing (meow + vertico + dired + magit + org), native elisp weather and OpenRouter surfaces, pi in vterm, and the three Hyprland binds swapped.

**Architecture:** `emacs-overlay` is added as a flake input; `modules/home-manager/emacs.nix` installs `emacs-pgtk` with all packages declared in Nix and runs the daemon as a systemd user service. Elisp config lives in the repo (`modules/home-manager/emacs/`) and is linked into `~/.config/emacs` with `mkOutOfStoreSymlink` so it iterates live. Surfaces are `emacsclient -e` entry points from Hyprland.

**Tech Stack:** Nix flakes, Home Manager (standalone), emacs-overlay (`emacs-pgtk`), ERT for elisp tests, existing bash tooling (`dot-theme-set`, `dot-doctor`).

**Spec:** `docs/superpowers/specs/2026-07-07-emacs-nix-design.md`

## Global Constraints

- **Execute on zord** (Debian 13, Hyprland). Repo edits can be authored anywhere, but every verify step (nix build, HM switch, ERT, keybind tests) requires zord. Do not run install/switch steps on any other machine.
- Repo path on zord: `~/projects/dotfiles`. All relative paths below are from the repo root.
- **Eval gate before every HM switch:** `nix build --no-link ~/projects/dotfiles#homeConfigurations.\"scott@zord\".activationPackage` must succeed. (`nix flake check` also evaluates the Phase-2 NixOS stubs, which may fail for out-of-scope reasons — the build command above is the canonical gate.)
- Emacs functions follow the existing `scott/` command + `scott-<pkg>--` private naming convention.
- Stow-managed files are only touched where this plan explicitly says so (`base/hypr/.config/hypr/hyprland.conf`, `bin/dot-theme-set`, `bin/dot-doctor`, `base/bin/.local/bin/hypr-{weather,or-cost}`).
- The old bash surfaces are deleted only **after** their elisp replacements are verified interactively (Task 8).
- Commit after every task; commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

## File Structure

```
flake.nix                                    # MODIFY: emacs-overlay input + overlay
modules/home-manager/default.nix             # MODIFY: pilot trim + emacs import
home/scott/zord.nix                          # MODIFY: comment out package list for pilot
modules/home-manager/emacs.nix               # CREATE: HM module (pgtk, packages, daemon, symlinks)
modules/home-manager/emacs/early-init.el     # CREATE
modules/home-manager/emacs/init.el           # CREATE (minimal in Task 3, full in Task 4)
modules/home-manager/emacs/lisp/scott-theme.el       # CREATE: catppuccin flavor control
modules/home-manager/emacs/lisp/scott-weather.el     # CREATE: super+n surface
modules/home-manager/emacs/lisp/scott-openrouter.el  # CREATE: super+u surface
modules/home-manager/emacs/lisp/scott-pi.el          # CREATE: pi vterm toggle
modules/home-manager/emacs/test/scott-weather-test.el     # CREATE: ERT
modules/home-manager/emacs/test/scott-openrouter-test.el  # CREATE: ERT
bin/dot-theme-set                            # MODIFY: emacsclient flavor hook
bin/dot-doctor                               # MODIFY: nix + emacs daemon checks
base/hypr/.config/hypr/hyprland.conf         # MODIFY: binds 178–180, windowrules 101–102
base/bin/.local/bin/hypr-weather             # DELETE (Task 8, after verification)
base/bin/.local/bin/hypr-or-cost             # DELETE (Task 8, after verification)
docs/manual/02-keybindings.md                # MODIFY: swapped binds
docs/manual/04-tools.md                      # MODIFY: retired scripts, mpv note
```

---

### Task 1: Install Nix daemon + enable flakes (zord, no repo changes)

**Files:** none (system-level only: `/nix`, `/etc/nix/nix.conf`)

**Interfaces:**
- Consumes: nothing
- Produces: working `nix` CLI with `nix-command flakes` enabled; every later task's `nix build` depends on this

- [ ] **Step 1: Confirm Nix is not already installed**

Run: `command -v nix; ls /nix 2>&1`
Expected: no output from `command -v`; `ls: cannot access '/nix'`

- [ ] **Step 2: Run the multi-user installer**

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

Answer yes to the prompts. This creates `/nix`, the `nixbld` users, the `nix-daemon` systemd unit, and `/etc/profile.d/nix.sh`. It does not touch `/usr`.

- [ ] **Step 3: Verify in a fresh shell**

Run: `exec zsh -l` then `nix --version`
Expected: `nix (Nix) 2.x`

- [ ] **Step 4: Enable flakes**

```bash
echo "experimental-features = nix-command flakes" | sudo tee -a /etc/nix/nix.conf
sudo systemctl restart nix-daemon
```

- [ ] **Step 5: Verify flakes work**

Run: `nix flake metadata ~/projects/dotfiles --no-write-lock-file`
Expected: prints the flake description and inputs (nixpkgs, home-manager) with no "experimental feature" error.

No commit — nothing in the repo changed.

---

### Task 2: Flake wiring — emacs-overlay input + pilot trim

**Files:**
- Modify: `flake.nix`
- Modify: `modules/home-manager/default.nix`
- Modify: `home/scott/zord.nix:21-36`
- Create: `flake.lock` (generated)

**Interfaces:**
- Consumes: Task 1's `nix` CLI
- Produces: `pkgs` carries `emacs-overlay` (so `pkgs.emacs-pgtk` exists for Task 3); `modules/home-manager/default.nix` imports only `./theme.nix` (Task 3 adds `./emacs.nix`)

- [ ] **Step 1: Add the emacs-overlay input and overlay to `flake.nix`**

Replace the `inputs` block and the `pkgs` binding:

```nix
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      emacs-overlay,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ emacs-overlay.overlays.default ];
      };

      lib = import ./lib { inherit pkgs; };
    in
```

Everything else in `flake.nix` is unchanged.

- [ ] **Step 2: Trim `modules/home-manager/default.nix` to the pilot set**

Replace the whole file with:

```nix
{
  imports = [
    # Pilot: Emacs is the first real HM module (added in the next commit).
    # The stow-package modules below are re-enabled one at a time per the
    # beat order in docs/manual/07-nix-roadmap.md — do NOT enable them all
    # at once; each one takes ownership of files stow currently manages.
    ./theme.nix
    # ./git.nix
    # ./zsh.nix
    # ./helix.nix
    # ./ghostty.nix
    # ./hyprland.nix
    # ./waybar.nix
    # ./mako.nix
    # ./fuzzel.nix
    # ./btop.nix
    # ./lf.nix
    # ./mpv.nix
    # ./systemd.nix
    # ./packages.nix
    # ./pi.nix
    # ./claude.nix
    # ./xdg.nix
    # ./yt-dlp.nix
    # ./zellij.nix
  ];

  # Give `home-manager` a CLI after the first bootstrap switch.
  programs.home-manager.enable = true;
}
```

- [ ] **Step 3: Comment out the zord package list for the pilot**

In `home/scott/zord.nix`, the `home.packages` list (steam, obs-studio, gimp, …) would make Nix download multi-GB duplicates of apps apt already provides. Comment the entries out:

```nix
  # --- Packages ---
  # Pilot phase: these are still installed via apt. Uncomment one at a time
  # during the stow→HM migration (roadmap beat order), removing the apt copy.
  home.packages = with pkgs; [
    # steam
    # steam-run
    # protonup-qt
    # prismlauncher
    # obs-studio
    # audacity
    # gimp
    # imv
    # zathura
    # pavucontrol
    # blueman
    # networkmanagerapplet
  ];
```

- [ ] **Step 4: Lock and evaluate**

```bash
cd ~/projects/dotfiles
nix flake lock
nix build --no-link .#homeConfigurations.\"scott@zord\".activationPackage
```

Expected: `flake.lock` created; build succeeds (first run downloads nixpkgs — several minutes).

- [ ] **Step 5: Commit**

```bash
git add flake.nix flake.lock modules/home-manager/default.nix home/scott/zord.nix
git commit -m "feat(nix): add emacs-overlay input, trim HM imports to pilot set"
```

---

### Task 3: emacs.nix module + minimal config + first Home Manager switch

**Files:**
- Create: `modules/home-manager/emacs.nix`
- Create: `modules/home-manager/emacs/early-init.el`
- Create: `modules/home-manager/emacs/init.el` (minimal — Task 4 completes it)
- Modify: `modules/home-manager/default.nix` (uncomment/add `./emacs.nix`)

**Interfaces:**
- Consumes: `pkgs.emacs-pgtk` from Task 2's overlay; `config.scott.dotfiles.path` option from `theme.nix`
- Produces: running Emacs daemon (`systemctl --user` unit `emacs`); `~/.nix-profile/bin/emacsclient`; `~/.config/emacs/{early-init.el,init.el,lisp}` symlinked to the repo. Tasks 4–8 all talk to this daemon.

- [ ] **Step 1: Write `modules/home-manager/emacs.nix`**

```nix
{ config, lib, pkgs, ... }:

let
  # Elisp lives in the repo and is symlinked out-of-store so it can be
  # edited live without a home-manager switch. Packages stay declarative.
  emacsDir = "${config.scott.dotfiles.path}/modules/home-manager/emacs";
in
{
  programs.emacs = {
    enable = true;
    package = pkgs.emacs-pgtk; # native Wayland build
    extraPackages = epkgs: with epkgs; [
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
      vterm
      catppuccin-theme
      markdown-mode # transition: vault is still .md until the conversion sub-project
    ];
  };

  services.emacs = {
    enable = true;
    client.enable = true;
    defaultEditor = true;
  };

  xdg.configFile."emacs/early-init.el".source =
    config.lib.file.mkOutOfStoreSymlink "${emacsDir}/early-init.el";
  xdg.configFile."emacs/init.el".source =
    config.lib.file.mkOutOfStoreSymlink "${emacsDir}/init.el";
  xdg.configFile."emacs/lisp".source =
    config.lib.file.mkOutOfStoreSymlink "${emacsDir}/lisp";
}
```

- [ ] **Step 2: Write `modules/home-manager/emacs/early-init.el`**

```elisp
;;; early-init.el --- pre-init settings -*- lexical-binding: t; -*-
;; Packages come from Nix (emacs-overlay), not package.el.
(setq package-enable-at-startup nil)
(setq gc-cons-threshold (* 64 1024 1024))
(setq inhibit-startup-screen t)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
```

- [ ] **Step 3: Write the minimal `modules/home-manager/emacs/init.el`**

```elisp
;;; init.el --- managed in dotfiles repo: modules/home-manager/emacs/ -*- lexical-binding: t; -*-
(add-to-list 'load-path (locate-user-emacs-file "lisp"))
(setq custom-file (locate-user-emacs-file "custom.el"))
(load custom-file :no-error)
```

Also create the (for now empty) lisp dir so the symlink target exists:

```bash
mkdir -p modules/home-manager/emacs/lisp modules/home-manager/emacs/test
touch modules/home-manager/emacs/lisp/.gitkeep
```

- [ ] **Step 4: Enable the module**

In `modules/home-manager/default.nix`, add `./emacs.nix` directly under `./theme.nix` in the imports list.

- [ ] **Step 5: Eval gate, then first switch**

```bash
cd ~/projects/dotfiles
nix build --no-link .#homeConfigurations.\"scott@zord\".activationPackage
nix run github:nix-community/home-manager -- switch -b hm-bak --flake .#scott@zord
```

Expected: activation output ending in a new generation; no clobber errors (`-b hm-bak` backs up any collision — there should be none, `~/.config/emacs` did not previously exist).

- [ ] **Step 6: Verify the daemon and symlinks**

```bash
systemctl --user status emacs --no-pager | head -3
~/.nix-profile/bin/emacsclient -e '(emacs-version)'
readlink ~/.config/emacs/init.el
```

Expected: unit `active (running)`; version string containing `31` (or current overlay version) and no X11 in the build description; readlink resolves through the store into `~/projects/dotfiles/modules/home-manager/emacs/init.el`.

- [ ] **Step 7: Commit**

```bash
git add modules/home-manager/emacs.nix modules/home-manager/emacs modules/home-manager/default.nix
git commit -m "feat(emacs): pilot HM module — pgtk build, nix-declared packages, daemon"
```

---

### Task 4: Living config — meow, vertico stack, dired, magit, org + theme wiring

**Files:**
- Modify: `modules/home-manager/emacs/init.el` (full replacement)
- Create: `modules/home-manager/emacs/lisp/scott-theme.el`
- Modify: `bin/dot-theme-set` (reload section, after the helix block context — insert before the `# --- Reload running apps` block's `echo`; exact snippet below)
- Delete: `modules/home-manager/emacs/lisp/.gitkeep`

**Interfaces:**
- Consumes: daemon + symlinks from Task 3; theme state marker `~/.config/dotfiles/active-theme` and `$VARIANT` variable inside `dot-theme-set`
- Produces: `(scott/theme-set FLAVOR)` where FLAVOR is the string `"mocha"` or `"latte"`; init.el's `(dolist (feature '(scott-theme scott-weather scott-openrouter scott-pi)) (require feature nil :no-error))` hook that auto-loads the files Tasks 5–7 create

- [ ] **Step 1: Write `modules/home-manager/emacs/lisp/scott-theme.el`**

```elisp
;;; scott-theme.el --- catppuccin flavor control -*- lexical-binding: t; -*-
;; Flavor tracks the dotfiles theme system: dot-theme-set calls
;; (scott/theme-set "mocha"|"latte") on switch; on startup we derive the
;; flavor from the active-theme state marker.
(require 'catppuccin-theme)

(defconst scott-theme--state-file "~/.config/dotfiles/active-theme")

(defun scott-theme--flavor-from-state ()
  "Return the catppuccin flavor symbol for the active dotfiles theme."
  (let ((name (when (file-readable-p scott-theme--state-file)
                (string-trim (with-temp-buffer
                               (insert-file-contents scott-theme--state-file)
                               (buffer-string))))))
    (if (and name (string-match-p "latte" name)) 'latte 'mocha)))

(defun scott/theme-set (flavor)
  "Switch the catppuccin FLAVOR (\"mocha\" or \"latte\") in the running session."
  (setq catppuccin-flavor (intern flavor))
  (catppuccin-reload))

(defun scott/theme-init ()
  "Load catppuccin with the flavor matching the dotfiles active theme."
  (setq catppuccin-flavor (scott-theme--flavor-from-state))
  (load-theme 'catppuccin t))

(provide 'scott-theme)
;;; scott-theme.el ends here
```

- [ ] **Step 2: Replace `modules/home-manager/emacs/init.el` with the full config**

```elisp
;;; init.el --- managed in dotfiles repo: modules/home-manager/emacs/ -*- lexical-binding: t; -*-
;; Packages are installed by Nix (modules/home-manager/emacs.nix).
;; This file only configures them.

(add-to-list 'load-path (locate-user-emacs-file "lisp"))
(setq custom-file (locate-user-emacs-file "custom.el"))
(load custom-file :no-error)

;; --- Basics ---
(set-face-attribute 'default nil :family "JetBrainsMono Nerd Font" :height 110)
(setq make-backup-files nil
      auto-save-default nil
      create-lockfiles nil
      use-short-answers t
      ring-bell-function #'ignore)
(savehist-mode 1)
(recentf-mode 1)
(global-auto-revert-mode 1)
(column-number-mode 1)
(setq display-line-numbers-type t)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)

;; --- Minibuffer completion: vertico + orderless + consult + marginalia + embark ---
(vertico-mode 1)
(marginalia-mode 1)
(setq completion-styles '(orderless basic)
      completion-category-defaults nil
      completion-category-overrides '((file (styles partial-completion))))
(global-set-key (kbd "C-s") #'consult-line)
(global-set-key (kbd "C-x b") #'consult-buffer)
(global-set-key (kbd "M-g g") #'consult-goto-line)
(global-set-key (kbd "M-y") #'consult-yank-pop)
(global-set-key (kbd "C-c f") #'consult-ripgrep)
(global-set-key (kbd "C-.") #'embark-act)
(global-set-key (kbd "C-h B") #'embark-bindings)

;; --- In-buffer completion ---
(global-corfu-mode 1)
(setq corfu-auto t corfu-auto-delay 0.15)

;; --- Meow: modal editing (qwerty layout, per meow README) ---
(require 'meow)
(defun meow-setup ()
  (setq meow-cheatsheet-layout meow-cheatsheet-layout-qwerty)
  (meow-motion-define-key
   '("j" . meow-next)
   '("k" . meow-prev)
   '("<escape>" . ignore))
  (meow-leader-define-key
   '("j" . "H-j") '("k" . "H-k")
   '("1" . meow-digit-argument) '("2" . meow-digit-argument)
   '("3" . meow-digit-argument) '("4" . meow-digit-argument)
   '("5" . meow-digit-argument) '("6" . meow-digit-argument)
   '("7" . meow-digit-argument) '("8" . meow-digit-argument)
   '("9" . meow-digit-argument) '("0" . meow-digit-argument)
   '("/" . meow-keypad-describe-key)
   '("?" . meow-cheatsheet))
  (meow-normal-define-key
   '("0" . meow-expand-0) '("9" . meow-expand-9) '("8" . meow-expand-8)
   '("7" . meow-expand-7) '("6" . meow-expand-6) '("5" . meow-expand-5)
   '("4" . meow-expand-4) '("3" . meow-expand-3) '("2" . meow-expand-2)
   '("1" . meow-expand-1)
   '("-" . negative-argument)
   '(";" . meow-reverse)
   '("," . meow-inner-of-thing)
   '("." . meow-bounds-of-thing)
   '("[" . meow-beginning-of-thing)
   '("]" . meow-end-of-thing)
   '("a" . meow-append)
   '("A" . meow-open-below)
   '("b" . meow-back-word)
   '("B" . meow-back-symbol)
   '("c" . meow-change)
   '("d" . meow-delete)
   '("D" . meow-backward-delete)
   '("e" . meow-next-word)
   '("E" . meow-next-symbol)
   '("f" . meow-find)
   '("g" . meow-cancel-selection)
   '("G" . meow-grab)
   '("h" . meow-left)
   '("H" . meow-left-expand)
   '("i" . meow-insert)
   '("I" . meow-open-above)
   '("j" . meow-next)
   '("J" . meow-next-expand)
   '("k" . meow-prev)
   '("K" . meow-prev-expand)
   '("l" . meow-right)
   '("L" . meow-right-expand)
   '("m" . meow-join)
   '("n" . meow-search)
   '("o" . meow-block)
   '("O" . meow-to-block)
   '("p" . meow-yank)
   '("q" . meow-quit)
   '("Q" . meow-goto-line)
   '("r" . meow-replace)
   '("R" . meow-swap-grab)
   '("s" . meow-kill)
   '("t" . meow-till)
   '("u" . meow-undo)
   '("U" . meow-undo-in-selection)
   '("v" . meow-visit)
   '("w" . meow-mark-word)
   '("W" . meow-mark-symbol)
   '("x" . meow-line)
   '("X" . meow-goto-line)
   '("y" . meow-save)
   '("Y" . meow-sync-grab)
   '("z" . meow-pop-selection)
   '("'" . repeat)
   '("<escape>" . ignore)))
(meow-setup)
(meow-global-mode 1)

;; --- Files: dired + dirvish ---
(dirvish-override-dired-mode 1)
(setq dired-listing-switches "-alh --group-directories-first"
      dired-dwim-target t)
(global-set-key (kbd "C-c d") #'dirvish)

;; --- Git ---
(global-set-key (kbd "C-x g") #'magit-status)

;; --- Org + org-roam ---
;; New org notes start here now; the Obsidian vault (~/docs/vault, markdown)
;; migrates in a later sub-project (see the design spec, section 6).
(setq org-directory (expand-file-name "~/docs/org"))
(make-directory org-directory t)
(setq org-roam-directory org-directory)
(org-roam-db-autosync-mode 1)
(global-set-key (kbd "C-c n f") #'org-roam-node-find)
(global-set-key (kbd "C-c n i") #'org-roam-node-insert)
(global-set-key (kbd "C-c n c") #'org-roam-capture)
(global-set-key (kbd "C-c a") #'org-agenda)

;; --- Theme + custom surfaces (files appear as they are implemented) ---
(dolist (feature '(scott-theme scott-weather scott-openrouter scott-pi))
  (require feature nil :no-error))
(when (fboundp 'scott/theme-init)
  (scott/theme-init))
```

Delete `modules/home-manager/emacs/lisp/.gitkeep`.

- [ ] **Step 3: Restart the daemon and verify the config loads**

```bash
systemctl --user restart emacs
sleep 3
~/.nix-profile/bin/emacsclient -e '(list (bound-and-true-p meow-global-mode) (bound-and-true-p vertico-mode) (custom-theme-enabled-p (quote catppuccin)) catppuccin-flavor)'
```

Expected: `(t t t mocha)` (mocha because `active-theme` is `catppuccin-mocha`). If the daemon fails, inspect `journalctl --user -u emacs -e`.

- [ ] **Step 4: Hook `dot-theme-set`**

In `bin/dot-theme-set`, insert this block immediately before the `# --- Reload running apps (best-effort) ---` section:

```bash
# --- Emacs: switch catppuccin flavor in the running daemon (best-effort) ---
EMACSCLIENT="$HOME/.nix-profile/bin/emacsclient"
if [[ -x "$EMACSCLIENT" ]]; then
    emacs_flavor="mocha"
    [[ "$VARIANT" == "light" ]] && emacs_flavor="latte"
    "$EMACSCLIENT" -e "(scott/theme-set \"$emacs_flavor\")" &>/dev/null || true
fi
```

- [ ] **Step 5: Verify the round-trip theme toggle**

```bash
dot-theme-set catppuccin-latte
~/.nix-profile/bin/emacsclient -e 'catppuccin-flavor'
dot-theme-set catppuccin-mocha
~/.nix-profile/bin/emacsclient -e 'catppuccin-flavor'
```

Expected: `latte` then `mocha`, and an open Emacs frame visibly flips light/dark with the rest of the desktop.

- [ ] **Step 6: Live in it (manual smoke test)**

Open `emacsclient -c`, then confirm: meow modal states work (`i` to insert, `ESC` back), `C-x b` fuzzy-switches buffers, `C-c d` opens dirvish, `C-x g` opens magit on the dotfiles repo, `C-c n c` captures an org-roam note into `~/docs/org`.

- [ ] **Step 7: Commit**

```bash
git add modules/home-manager/emacs bin/dot-theme-set
git commit -m "feat(emacs): living config — meow, vertico stack, dirvish, magit, org-roam, catppuccin theme wiring"
```

---

### Task 5: scott-weather.el — native weather surface

**Files:**
- Create: `modules/home-manager/emacs/lisp/scott-weather.el`
- Create: `modules/home-manager/emacs/test/scott-weather-test.el`

**Interfaces:**
- Consumes: init.el's `require` hook from Task 4 (file just needs to exist and `(provide 'scott-weather)`)
- Produces: `(scott/weather)` interactive command rendering buffer `*weather*`; `(scott/weather-frame)` non-interactive entry point for Hyprland (creates a frame titled `emacs-weather`); pure `(scott-weather--format-periods PERIODS &optional ZONE)` → string

- [ ] **Step 1: Write the failing ERT test**

`modules/home-manager/emacs/test/scott-weather-test.el`:

```elisp
;;; scott-weather-test.el --- ERT tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'scott-weather)

(ert-deftest scott-weather-format-periods ()
  "Formats NWS hourly periods: local time, temp, precip %, short forecast."
  (let* ((json "{\"periods\":[
{\"startTime\":\"2026-07-07T15:00:00-04:00\",\"temperature\":78,
 \"probabilityOfPrecipitation\":{\"value\":40},\"shortForecast\":\"Chance Showers\"},
{\"startTime\":\"2026-07-07T16:00:00-04:00\",\"temperature\":77,
 \"probabilityOfPrecipitation\":{\"value\":null},\"shortForecast\":\"Sunny\"}]}")
         (periods (alist-get 'periods
                             (json-parse-string json :object-type 'alist
                                                 :array-type 'list
                                                 :null-object nil)))
         (out (scott-weather--format-periods periods t))) ; zone t = UTC
    ;; 15:00-04:00 is 19:00 UTC
    (should (string-match-p "Tue 7PM" out))
    (should (string-match-p "78°" out))
    (should (string-match-p "40%" out))
    (should (string-match-p "Chance Showers" out))
    ;; null precip probability renders as 0%
    (should (string-match-p "0%" out))
    (should (= 2 (length (split-string out "\n"))))))

(ert-deftest scott-weather-format-periods-caps-at-8 ()
  (let* ((period '((startTime . "2026-07-07T15:00:00-04:00") (temperature . 70)
                   (probabilityOfPrecipitation . ((value . 0)))
                   (shortForecast . "Clear")))
         (out (scott-weather--format-periods (make-list 12 period) t)))
    (should (= 8 (length (split-string out "\n"))))))
```

- [ ] **Step 2: Run the test — expect failure**

```bash
cd ~/projects/dotfiles
~/.nix-profile/bin/emacs --batch -L modules/home-manager/emacs/lisp \
  -l modules/home-manager/emacs/test/scott-weather-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL — `Cannot open load file: ... scott-weather`

- [ ] **Step 3: Write `modules/home-manager/emacs/lisp/scott-weather.el`**

```elisp
;;; scott-weather.el --- Phoenix NY weather surface (super+n) -*- lexical-binding: t; -*-
;; Replaces base/bin hypr-weather: NWS hourly forecast table plus NOAA
;; satellite/radar imagery, rendered in a *weather* buffer.
(require 'url)
(require 'iso8601)
(require 'json)

(defconst scott-weather--lat "43.2312")
(defconst scott-weather--lon "-76.3007")
(defconst scott-weather--images
  '(("satellite.jpg" . "https://cdn.star.nesdis.noaa.gov/GOES16/ABI/SECTOR/ne/GEOCOLOR/latest.jpg")
    ("airmass.jpg"   . "https://cdn.star.nesdis.noaa.gov/GOES16/ABI/SECTOR/ne/AirMass/latest.jpg")
    ("radar.gif"     . "https://radar.weather.gov/ridge/standard/NORTHEAST_loop.gif")))

(defvar url-user-agent)
(setq url-user-agent "(pi-session, scottwhitson@gmail.com)")

(defun scott-weather--fetch-json (url)
  "GET URL and return the body parsed as an alist tree."
  (with-current-buffer (url-retrieve-synchronously url t t 15)
    (goto-char url-http-end-of-headers)
    (prog1 (json-parse-buffer :object-type 'alist :array-type 'list
                              :null-object nil)
      (kill-buffer))))

(defun scott-weather--format-periods (periods &optional zone)
  "Format the first 8 of PERIODS (NWS hourly alists) as table lines.
ZONE is passed to `format-time-string' (nil = local time)."
  (mapconcat
   (lambda (p)
     (let* ((start (alist-get 'startTime p))
            (time (format-time-string
                   "%a %-l%p" (encode-time (iso8601-parse start)) zone))
            (temp (alist-get 'temperature p))
            (pop (or (alist-get 'value (alist-get 'probabilityOfPrecipitation p)) 0))
            (short (alist-get 'shortForecast p)))
       (format "%-9s %3d°  %3d%%  %s" time temp pop short)))
   (seq-take periods 8) "\n"))

(defun scott-weather--cache-dir ()
  (let ((dir (expand-file-name "scott-weather"
                               (or (getenv "XDG_CACHE_HOME") "~/.cache"))))
    (make-directory dir t)
    dir))

(defun scott-weather--insert-images (buf)
  "Asynchronously download NOAA imagery and append it to BUF."
  (let ((dir (scott-weather--cache-dir)))
    (dolist (spec scott-weather--images)
      (let ((file (expand-file-name (car spec) dir)))
        (make-process
         :name (concat "scott-weather-" (car spec))
         :command (list "curl" "-sfLo" file (cdr spec))
         :sentinel
         (lambda (_proc event)
           (when (and (string= event "finished\n") (buffer-live-p buf))
             (with-current-buffer buf
               (let ((inhibit-read-only t))
                 (save-excursion
                   (goto-char (point-max))
                   (insert-image (create-image file nil nil :max-width 950))
                   (insert "\n\n")))))))))))

;;;###autoload
(defun scott/weather ()
  "Show the Phoenix, NY hourly forecast and NOAA imagery."
  (interactive)
  (let* ((points (scott-weather--fetch-json
                  (format "https://api.weather.gov/points/%s,%s"
                          scott-weather--lat scott-weather--lon)))
         (hourly-url (alist-get 'forecastHourly (alist-get 'properties points)))
         (periods (alist-get 'periods
                             (alist-get 'properties
                                        (scott-weather--fetch-json hourly-url))))
         (buf (get-buffer-create "*weather*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "☁ Phoenix, NY — hourly\n\n"
                (scott-weather--format-periods periods)
                "\n\n"))
      (special-mode))
    (pop-to-buffer buf)
    (scott-weather--insert-images buf)))

(defun scott/weather-frame ()
  "Hyprland entry point: `scott/weather' in a dedicated floating frame."
  (let ((frame (make-frame '((name . "emacs-weather")
                             (title . "emacs-weather")))))
    (select-frame-set-input-focus frame)
    (scott/weather)))

(provide 'scott-weather)
;;; scott-weather.el ends here
```

- [ ] **Step 4: Run the tests — expect pass**

Same command as Step 2.
Expected: `Ran 2 tests, 2 results as expected`

- [ ] **Step 5: Interactive verify**

```bash
systemctl --user restart emacs && sleep 3
~/.nix-profile/bin/emacsclient -e '(scott/weather-frame)'
```

Expected: a frame titled `emacs-weather` opens with the 8-row forecast table; satellite/airmass/radar images appear below it within a few seconds.

- [ ] **Step 6: Commit**

```bash
git add modules/home-manager/emacs/lisp/scott-weather.el modules/home-manager/emacs/test/scott-weather-test.el
git commit -m "feat(emacs): scott/weather — native NWS + NOAA surface"
```

---

### Task 6: scott-openrouter.el — cost surface

**Files:**
- Create: `modules/home-manager/emacs/lisp/scott-openrouter.el`
- Create: `modules/home-manager/emacs/test/scott-openrouter-test.el`

**Interfaces:**
- Consumes: `~/.pi/agent/auth.json` (keys `openrouter-management.key`, `openrouter.key` — same as the bash script)
- Produces: `(scott/openrouter-cost)` interactive command rendering buffer `*openrouter*`; `(scott/openrouter-cost-frame)` for Hyprland (frame titled `emacs-openrouter`); pure `(scott-openrouter--summarize ACTIVITY KEY-DATA NOW)` → string

- [ ] **Step 1: Write the failing ERT test**

`modules/home-manager/emacs/test/scott-openrouter-test.el`:

```elisp
;;; scott-openrouter-test.el --- ERT tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'scott-openrouter)

(ert-deftest scott-openrouter-summarize ()
  "7-day window + today's daily usage when activity lags; monthly total."
  (let* ((now (encode-time (iso8601-parse "2026-07-07T12:00:00Z")))
         (activity '(((date . "2026-07-05 00:00:00") (usage . 1.25)
                      (requests . 10) (model . "anthropic/claude-sonnet-5"))
                     ;; outside the 7-day window — excluded
                     ((date . "2026-06-20 00:00:00") (usage . 9.0)
                      (requests . 4) (model . "old/model"))))
         (key-data '((usage_daily . 0.75) (usage_monthly . 3.5)))
         (out (scott-openrouter--summarize activity key-data now)))
    ;; 1.25 in-window + 0.75 daily (today missing from activity) = 2.00
    (should (string-match-p "\\$2\\.00 — last 7 days (10 requests)" out))
    (should (string-match-p "Models: anthropic/claude-sonnet-5" out))
    (should-not (string-match-p "old/model" out))
    (should (string-match-p "\\$3\\.50 — this month" out))))

(ert-deftest scott-openrouter-summarize-no-double-count-today ()
  "When today IS in the activity data, usage_daily is not added again."
  (let* ((now (encode-time (iso8601-parse "2026-07-07T12:00:00Z")))
         (activity '(((date . "2026-07-07 00:00:00") (usage . 2.0)
                      (requests . 5) (model . "anthropic/claude-sonnet-5"))))
         (key-data '((usage_daily . 2.0) (usage_monthly . 2.0)))
         (out (scott-openrouter--summarize activity key-data now)))
    (should (string-match-p "\\$2\\.00 — last 7 days (5 requests)" out))))
```

- [ ] **Step 2: Run the test — expect failure**

```bash
cd ~/projects/dotfiles
~/.nix-profile/bin/emacs --batch -L modules/home-manager/emacs/lisp \
  -l modules/home-manager/emacs/test/scott-openrouter-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL — `Cannot open load file: ... scott-openrouter`

- [ ] **Step 3: Write `modules/home-manager/emacs/lisp/scott-openrouter.el`**

```elisp
;;; scott-openrouter.el --- OpenRouter 7-day cost surface (super+u) -*- lexical-binding: t; -*-
;; Replaces base/bin hypr-or-cost: exact rolling 7-day cost via the
;; management key (activity API, lags ~1 day) topped up with today's
;; usage from the regular key.
(require 'url)
(require 'iso8601)
(require 'json)

(defconst scott-openrouter--auth-file "~/.pi/agent/auth.json")

(defun scott-openrouter--keys ()
  "Return (MANAGEMENT-KEY . REGULAR-KEY) from the pi auth file."
  (let ((auth (json-parse-string
               (with-temp-buffer
                 (insert-file-contents scott-openrouter--auth-file)
                 (buffer-string))
               :object-type 'alist :null-object nil)))
    (cons (alist-get 'key (alist-get 'openrouter-management auth))
          (alist-get 'key (alist-get 'openrouter auth)))))

(defun scott-openrouter--fetch-json (url key)
  "GET URL with bearer KEY; return parsed alist tree."
  (let ((url-request-extra-headers
         `(("Authorization" . ,(concat "Bearer " key)))))
    (with-current-buffer (url-retrieve-synchronously url t t 15)
      (goto-char url-http-end-of-headers)
      (prog1 (json-parse-buffer :object-type 'alist :array-type 'list
                                :null-object nil)
        (kill-buffer)))))

(defun scott-openrouter--summarize (activity key-data now)
  "Summarize ACTIVITY entries and KEY-DATA relative to time NOW.
Mirrors the logic of the retired hypr-or-cost script."
  (let ((cutoff (time-subtract now (days-to-time 7)))
        (today (format-time-string "%Y-%m-%d" now t))
        (rolling 0.0) (requests 0) (models '()) (today-in-activity nil))
    (dolist (e activity)
      (let* ((date-str (car (split-string (or (alist-get 'date e) "") " ")))
             (dt (encode-time (iso8601-parse (concat date-str "T00:00:00Z")))))
        (when (string-prefix-p today (or (alist-get 'date e) ""))
          (setq today-in-activity t))
        (unless (time-less-p dt cutoff)
          (setq rolling (+ rolling (or (alist-get 'usage e) 0))
                requests (+ requests (or (alist-get 'requests e) 0)))
          (push (or (alist-get 'model e) "?") models))))
    (let ((daily (or (alist-get 'usage_daily key-data) 0))
          (monthly (or (alist-get 'usage_monthly key-data) 0))
          (uniq (delete-dups (sort models #'string<))))
      (when (and (not today-in-activity) (> daily 0))
        (setq rolling (+ rolling daily)))
      (concat
       (format "$%.2f — last 7 days (%d requests)\n" rolling requests)
       (if (and uniq (<= (length uniq) 3))
           (format "Models: %s\n" (string-join uniq ", "))
         "")
       (format "$%.2f — this month" monthly)))))

;;;###autoload
(defun scott/openrouter-cost ()
  "Show the rolling 7-day OpenRouter cost summary."
  (interactive)
  (pcase-let ((`(,mgmt . ,regular) (scott-openrouter--keys)))
    (unless (and mgmt regular)
      (user-error "OpenRouter keys missing from %s" scott-openrouter--auth-file))
    (let* ((activity (alist-get 'data (scott-openrouter--fetch-json
                                       "https://openrouter.ai/api/v1/activity?limit=500" mgmt)))
           (key-data (alist-get 'data (scott-openrouter--fetch-json
                                       "https://openrouter.ai/api/v1/auth/key" regular)))
           (buf (get-buffer-create "*openrouter*")))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert "OpenRouter Cost\n\n"
                  (scott-openrouter--summarize activity key-data (current-time))
                  "\n"))
        (special-mode))
      (pop-to-buffer buf))))

(defun scott/openrouter-cost-frame ()
  "Hyprland entry point: `scott/openrouter-cost' in a floating frame."
  (let ((frame (make-frame '((name . "emacs-openrouter")
                             (title . "emacs-openrouter")))))
    (select-frame-set-input-focus frame)
    (scott/openrouter-cost)))

(provide 'scott-openrouter)
;;; scott-openrouter.el ends here
```

- [ ] **Step 4: Run the tests — expect pass**

Same command as Step 2.
Expected: `Ran 2 tests, 2 results as expected`

- [ ] **Step 5: Interactive verify**

```bash
systemctl --user restart emacs && sleep 3
~/.nix-profile/bin/emacsclient -e '(scott/openrouter-cost-frame)'
```

Expected: frame titled `emacs-openrouter` showing the three summary lines; dollar figures plausible against a recent `hypr-or-cost` notification.

- [ ] **Step 6: Commit**

```bash
git add modules/home-manager/emacs/lisp/scott-openrouter.el modules/home-manager/emacs/test/scott-openrouter-test.el
git commit -m "feat(emacs): scott/openrouter-cost — native 7-day cost surface"
```

---

### Task 7: scott-pi.el — pi agent in vterm

**Files:**
- Create: `modules/home-manager/emacs/lisp/scott-pi.el`

**Interfaces:**
- Consumes: `vterm` package (Task 3); `pi` on the login shell's PATH (vterm starts the user's shell, so `.zshrc` PATH setup applies)
- Produces: `(scott/pi-toggle)` interactive command; `(scott/pi-frame)` for Hyprland (frame titled `emacs-pi`)

- [ ] **Step 1: Write `modules/home-manager/emacs/lisp/scott-pi.el`**

```elisp
;;; scott-pi.el --- pi coding agent in vterm -*- lexical-binding: t; -*-
;; Pi stays npm-installed (see nix roadmap: runtime install); Emacs is its
;; house. The buffer starts the user's shell (so .zshrc PATH applies) and
;; launches pi in it.
(require 'vterm nil t)

(defconst scott-pi--buffer "*pi*")

(defun scott-pi--start ()
  "Create the pi vterm buffer and launch pi in it."
  (let ((buf (vterm scott-pi--buffer)))
    (with-current-buffer buf
      (vterm-send-string "pi")
      (vterm-send-return))
    buf))

;;;###autoload
(defun scott/pi-toggle ()
  "Show, hide, or start the pi agent vterm buffer."
  (interactive)
  (let* ((buf (get-buffer scott-pi--buffer))
         (win (and buf (get-buffer-window buf))))
    (cond (win (delete-window win))
          (buf (pop-to-buffer buf))
          (t (pop-to-buffer (scott-pi--start))))))

(defun scott/pi-frame ()
  "Hyprland entry point: pi in a dedicated frame."
  (let ((buf (get-buffer scott-pi--buffer)))
    (select-frame-set-input-focus
     (make-frame '((name . "emacs-pi") (title . "emacs-pi"))))
    (switch-to-buffer (or buf (scott-pi--start)))))

(provide 'scott-pi)
;;; scott-pi.el ends here
```

- [ ] **Step 2: Interactive verify**

```bash
systemctl --user restart emacs && sleep 3
~/.nix-profile/bin/emacsclient -e '(scott/pi-frame)'
```

Expected: frame titled `emacs-pi` opens with pi running in vterm (prompt renders, typing works). Then inside an existing Emacs frame run `M-x scott/pi-toggle` twice: window hides, then reappears with the same session.

- [ ] **Step 3: Commit**

```bash
git add modules/home-manager/emacs/lisp/scott-pi.el
git commit -m "feat(emacs): scott/pi-toggle — pi agent in vterm"
```

---

### Task 8: Hyprland cutover — binds, windowrules, doctor, docs, retire bash surfaces

**Files:**
- Modify: `base/hypr/.config/hypr/hyprland.conf:101-102` (windowrules) and `:178-180` (binds)
- Modify: `bin/dot-doctor` (after the `# --- AI tooling check ---` block)
- Modify: `docs/manual/02-keybindings.md:59-63`
- Modify: `docs/manual/04-tools.md` (tool table rows + mpv note)
- Delete: `base/bin/.local/bin/hypr-weather`, `base/bin/.local/bin/hypr-or-cost`

**Interfaces:**
- Consumes: `scott/weather-frame`, `scott/openrouter-cost-frame`, `scott/pi-frame` (Tasks 5–7); running daemon
- Produces: final keybind surface; `dot-doctor` guards for the new stack

- [ ] **Step 1: Swap the windowrules**

In `base/hypr/.config/hypr/hyprland.conf`, replace lines 101–102:

```
windowrule = match:title hypr-weather-sat, float on
windowrule = match:title hypr-weather-sat, center on
```

with:

```
windowrule = match:title emacs-weather, float on
windowrule = match:title emacs-weather, center on
windowrule = match:title emacs-weather, size 1000 900
windowrule = match:title emacs-openrouter, float on
windowrule = match:title emacs-openrouter, center on
windowrule = match:title emacs-openrouter, size 600 300
```

- [ ] **Step 2: Swap the binds**

Replace lines 178–180:

```
bind = $mod, n, exec, ~/.local/bin/hypr-weather    # Phoenix NY weather + NOAA satellite
bind = $mod, u, exec, ~/.local/bin/hypr-or-cost    # OpenRouter 7-day cost
bind = $mod, p, exec, ghostty -e pi  # Pi AI coding assistant
```

with:

```
bind = $mod, n, exec, ~/.nix-profile/bin/emacsclient -e '(scott/weather-frame)'          # Weather in Emacs
bind = $mod, u, exec, ~/.nix-profile/bin/emacsclient -e '(scott/openrouter-cost-frame)'  # OpenRouter cost in Emacs
bind = $mod, p, exec, ~/.nix-profile/bin/emacsclient -e '(scott/pi-frame)'               # Pi agent in Emacs vterm
```

(Full path because the Hyprland session env may not have sourced the Nix profile PATH.)

- [ ] **Step 3: Reload and test all three binds**

```bash
hyprctl reload
```

Press `super+n` (floating weather frame with images), `super+u` (floating cost frame), `super+p` (pi frame). All three must open, float correctly per the rules, and close with `super+shift+q`.

- [ ] **Step 4: Delete the retired scripts**

```bash
git rm base/bin/.local/bin/hypr-weather base/bin/.local/bin/hypr-or-cost
```

Note: `dot-restow` (or `stow -R bin` from the repo's stow flow) must run so the dead `~/.local/bin` symlinks disappear:

```bash
cd ~/projects/dotfiles && stow -d base -t "$HOME" -R bin
ls ~/.local/bin/hypr-weather 2>&1
```

Expected: `No such file or directory`.

- [ ] **Step 5: Extend `dot-doctor`**

In `bin/dot-doctor`, after the `check "pi on PATH"` line, add:

```bash
# --- Nix + Emacs pilot checks ---
check "nix installed"          "command -v nix || [[ -x /nix/var/nix/profiles/default/bin/nix ]]"
check "emacs daemon active"    "systemctl --user is-active --quiet emacs"
check "emacsclient responds"   "[[ -x \$HOME/.nix-profile/bin/emacsclient ]] && \$HOME/.nix-profile/bin/emacsclient -e t"
check "emacs config symlinked" "[[ -L \$HOME/.config/emacs/init.el ]]"
check "org-roam db present"    "[[ -f \$HOME/.config/emacs/org-roam.db ]]"
```

(org-roam's default `org-roam-db-location` is `org-roam.db` under `user-emacs-directory`; it is created by `org-roam-db-autosync-mode` on first daemon start after Task 4.)

Run: `dot-doctor`
Expected: all five new checks green (pre-existing failures unrelated to this work are out of scope — note them, don't fix them here).

- [ ] **Step 6: Update the manual**

`docs/manual/02-keybindings.md` — update the three rows:

| binding | new text |
|---|---|
| `$mod + n` | Phoenix NY weather + NOAA imagery in Emacs (`scott/weather-frame`) |
| `$mod + u` | OpenRouter 7-day cost in Emacs (`scott/openrouter-cost-frame`) |
| `$mod + p` | Pi agent in Emacs vterm (`scott/pi-frame`) |

`docs/manual/04-tools.md`:
- Remove the `hypr-weather` and `hypr-or-cost` rows from the tool table; add a short "Emacs surfaces" note pointing at `modules/home-manager/emacs/lisp/`.
- Update the "cheatsheet / weather — mpv dependency" section (lines 15–20): only `hypr-cheatsheet` renders through mpv now; weather images render natively in Emacs.

- [ ] **Step 7: Commit**

```bash
git add base/hypr bin/dot-doctor docs/manual/02-keybindings.md docs/manual/04-tools.md
git commit -m "feat(desktop): cut weather/openrouter/pi surfaces over to Emacs, retire bash scripts"
```

---

## Completion criteria

- `dot-doctor` passes including the five new checks
- `super+n`, `super+u`, `super+p` all open Emacs frames per the windowrules
- `dot-theme-set catppuccin-latte` / `catppuccin-mocha` flips Emacs with the desktop
- Both ERT files pass in batch mode
- `nix build --no-link .#homeConfigurations.\"scott@zord\".activationPackage` succeeds from a clean checkout

After this plan: resume the roadmap beat order (`git` → `zsh` → …) for the stow→HM migration, then the vault-conversion sub-project gets its own spec.
