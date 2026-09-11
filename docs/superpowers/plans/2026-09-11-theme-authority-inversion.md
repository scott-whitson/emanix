# Theme Authority Inversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `emanix/theme-set` in Emacs the single authority for a runtime
theme switch, reducing `bin/dot-theme-set` from a 228-line bash orchestrator to
an `emacsclient` wrapper.

**Architecture:** The switch splits into a pure planner (`emanix-theme--plan`,
returns the whole switch as a plist and writes nothing) and a set of small apply
steps, each individually error-wrapped. A defcustom hook,
`emanix/theme-apply-functions`, lets the consuming flake register the personal
side-effects (pi, Claude Code) without the distribution knowing they exist —
the same seam shape as `emanix/modeline-extra-segments`.

**Tech Stack:** Emacs Lisp (Emacs 31), ERT, Nix flakes, Home Manager, bash.

**Spec:** `docs/superpowers/specs/2026-09-11-theme-authority-inversion-design.md`

## Global Constraints

- `emanix/theme-set` **must never signal to its caller.** It runs from
  `config.el:795` during init, on the host where Emacs is the compositor; an
  uncaught error there costs the rest of init, not merely the colours.
- Each apply step is wrapped **individually**, not the function as a whole. One
  failing symlink must not cost the Emacs theme.
- Every new package reference in elisp is soft-required (`(require 'x nil
  :no-error)`). A missing package must cost one feature, never a working Emacs.
- Tests run under `emacs -Q --batch`: **no dbus, no systemd, no network, no
  `gsettings`.** Side effects are stubbed with `cl-letf`.
- Tests must never write to the real `~/.config/dotfiles/`. Every test binds
  `emanix/theme-state-dir` to a temp directory.
- All `.nix` files pass `nixpkgs-fmt --check`.
- `emanix-theme--themes-dir` reads `$EMANIX_THEMES_DIR`. Tests bind it directly;
  they do not set environment variables.
- **Repo sequencing is load-bearing.** Tasks 1–7 are emanix. Tasks 8–10 are
  dotfiles and cannot be applied to a running host until emanix is pushed and
  the dotfiles lock updated (Task 7). Verify locally before that with
  `--override-input emanix path:/home/scott/projects/emanix`.

## One refinement to the spec

The spec says swaylock should get "the ghostty treatment" — every palette
pre-rendered to `~/.config/swaylock/themes/<name>.conf`. Task 6 instead puts
`swaylock.conf` **inside the theme tree**, next to `btop.theme` and `gtk.conf`.

Reason: `lib/themes.nix`'s `mkTheme` already emits swaylock config text
(`lib/themes.nix:405`), and `theme-tree.nix` already writes `btop.theme` into
each theme directory, which `dot-theme-set` symlinks to
`~/.config/btop/themes/active.theme`. Swaylock is that same shape exactly.
Ghostty is pre-rendered to its own directory only because ghostty's config
lives outside the theme tree for unrelated reasons. Following btop gives one
fewer place where per-palette files live.

The load-bearing half of the spec's decision is unchanged and non-negotiable:
`swaylock.nix` **must stop declaring `~/.config/swaylock/config` as
`home.file`**, or Home Manager renames it to `.hm-bak` at every activation and
silently reverts the theme.

## File Structure

**emanix — created**

| Path | Responsibility |
| --- | --- |
| `ioshi/i-intelligence/emacs/test/emanix-theme-test.el` | Every ERT test for the switch |
| `checks/theme-switch.nix` | Runs that suite under `nix flake check` |

**emanix — modified**

| Path | Change |
| --- | --- |
| `ioshi/i-intelligence/emacs/lisp/emanix-theme.el` | Planner, apply steps, hook, toggle, converging init |
| `ioshi/i-intelligence/emacs/config.el` | `C-c v` binding |
| `ioshi/i-intelligence/emacs/lisp/emanix-welcome.el` | Advertise `C-c v` |
| `ioshi/i-intelligence/ghostty.nix` | Delete `home.activation.seedGhosttyTheme` |
| `ioshi/i-intelligence/swaylock.nix` | Drop the `home.file` config |
| `lib/theme-tree.nix` | Emit `swaylock.conf` per theme |
| `flake.nix` | Register `checks.theme-switch` |

**dotfiles — created**

| Path | Responsibility |
| --- | --- |
| `bin/dot-theme-apply-pi` | Patch `~/.pi/agent/settings.json` + symlink the theme JSON |
| `bin/dot-theme-apply-claude` | Patch `~/.claude/settings.json`'s `theme` key |

**dotfiles — modified**

| Path | Change |
| --- | --- |
| `bin/dot-theme-set` | Thin wrapper + `--list` |
| `bin/dot-theme-toggle` | Thin wrapper |
| `home/scott/emacs/personal.el` | Register the hook function |
| `flake.nix` | `nix flake lock --update-input emanix` |
| `docs/manual/01-tools.md`, `03-roll-your-own.md`, `02-philosophy.md`, `docs/manual/README.md` | Doc updates |
| `~/docs/org/websites/emanix/pages/docs/theming.org` | The published manual |

---

### Task 1: The planner, and a state directory tests can write to

**Files:**
- Modify: `ioshi/i-intelligence/emacs/lisp/emanix-theme.el:24` (the state defconst)
- Create: `ioshi/i-intelligence/emacs/test/emanix-theme-test.el`
- Create: `checks/theme-switch.nix`
- Modify: `flake.nix` (checks attrset)

**Interfaces:**
- Consumes: `emanix-theme--read`, `emanix-theme--emacs-theme`,
  `emanix-theme--themes-dir` (all already in the file)
- Produces:
  - `emanix/theme-state-dir` — defcustom string, default `"~/.config/dotfiles"`
  - `emanix-theme--state-file` — function of no args, returns the
    `active-theme` path beneath it (was a defconst)
  - `emanix-theme--last-file (variant)` — returns the `last-<variant>` path
  - `emanix-theme--plan (name)` — plist `(:name :dir :variant :emacs-theme
    :links :gtk)` or nil. `:links` is a list of `(SOURCE . TARGET)` cons cells;
    `:gtk` is an alist of `(KEY . VALUE)` strings.

- [ ] **Step 1: Write the failing tests**

Create `ioshi/i-intelligence/emacs/test/emanix-theme-test.el`:

```elisp
;;; emanix-theme-test.el --- ERT tests for the theme switch -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'emanix-theme)

;;; Fixtures.
;;
;; A theme tree exactly as lib/theme-tree.nix produces one. Built in a temp
;; directory: these tests must never read the real $EMANIX_THEMES_DIR nor write
;; the real ~/.config/dotfiles.

(defvar emanix-theme-test--dirs nil)

(defun emanix-theme-test--make-tree ()
  "Return a temp themes dir holding `duskthorn' (dark) and `dawnthorn' (light)."
  (let ((root (make-temp-file "emanix-theme-test-themes" t)))
    (push root emanix-theme-test--dirs)
    (dolist (spec '(("duskthorn" "dark"  "catppuccin")
                    ("dawnthorn" "light" "modus-operandi")))
      (cl-destructuring-bind (name variant emacs-theme) spec
        (let ((dir (expand-file-name name root)))
          (make-directory dir)
          (write-region (concat variant "\n") nil (expand-file-name "variant" dir))
          (write-region (concat emacs-theme "\n") nil
                        (expand-file-name "emacs-theme" dir))
          (write-region "btop\n" nil (expand-file-name "btop.theme" dir))
          (write-region "swaylock\n" nil (expand-file-name "swaylock.conf" dir))
          (write-region (format "COLOR_SCHEME=prefer-%s\nGTK_THEME=Adwaita%s\n"
                                variant (if (equal variant "dark") ":dark" ""))
                        nil (expand-file-name "gtk.conf" dir)))))
    root))

(defun emanix-theme-test--make-home ()
  "Return a temp HOME holding the ghostty and zellij sources a plan links.
Both live outside the theme tree -- ghostty renders per-palette files
into its own config dir, and zellij's two definitions are written by
zellij.nix -- so a fixture that omits them makes every link assertion
depend on whether the REAL home happens to have them."
  (let ((home (make-temp-file "emanix-theme-test-home" t)))
    (push home emanix-theme-test--dirs)
    (dolist (rel '(".config/ghostty/themes/duskthorn.conf"
                   ".config/ghostty/themes/dawnthorn.conf"
                   ".local/share/emanix/zellij-themes/available/emanix-dark.kdl"
                   ".local/share/emanix/zellij-themes/available/emanix-light.kdl"))
      (let ((path (expand-file-name rel home)))
        (make-directory (file-name-directory path) t)
        (write-region "fixture\n" nil path)))
    home))

(defmacro emanix-theme-test--with-tree (&rest body)
  "Run BODY with a fixture theme tree, temp HOME, and throwaway state dir.
HOME is bound through `process-environment' because the link plan uses
`~'-relative paths, and `expand-file-name' resolves those through
`getenv' -- so without this the tests would read and assert against the
real home directory."
  (declare (indent 0))
  `(let* ((emanix-theme--themes-dir (emanix-theme-test--make-tree))
          (emanix/theme-state-dir (make-temp-file "emanix-theme-test-state" t))
          (process-environment
           (cons (concat "HOME=" (emanix-theme-test--make-home))
                 process-environment)))
     (push emanix/theme-state-dir emanix-theme-test--dirs)
     ,@body))

;;; The state directory.

(ert-deftest emanix-theme-state-dir-defaults-to-the-dotfiles-path ()
  "The default is unchanged by this refactor; only its shape is."
  (should (equal (default-value 'emanix/theme-state-dir) "~/.config/dotfiles")))

(ert-deftest emanix-theme-state-file-resolves-under-the-state-dir ()
  (let ((emanix/theme-state-dir "/tmp/whatever"))
    (should (equal (emanix-theme--state-file)
                   (expand-file-name "active-theme" "/tmp/whatever")))
    (should (equal (emanix-theme--last-file "dark")
                   (expand-file-name "last-dark" "/tmp/whatever")))))

;;; The planner.

(ert-deftest emanix-theme-plan-reads-variant-and-emacs-theme ()
  (emanix-theme-test--with-tree
    (let ((plan (emanix-theme--plan "duskthorn")))
      (should (equal (plist-get plan :name) "duskthorn"))
      (should (equal (plist-get plan :variant) "dark"))
      (should (eq (plist-get plan :emacs-theme) 'catppuccin)))))

(ert-deftest emanix-theme-plan-rejects-an-unknown-theme ()
  "No directory, no plan -- and nothing written."
  (emanix-theme-test--with-tree
    (should-not (emanix-theme--plan "nosuchtheme"))))

(ert-deftest emanix-theme-plan-rejects-a-theme-with-no-variant ()
  "A half-written theme directory must not produce a plan."
  (emanix-theme-test--with-tree
    (make-directory (expand-file-name "halfbaked" emanix-theme--themes-dir))
    (should-not (emanix-theme--plan "halfbaked"))))

(ert-deftest emanix-theme-plan-links-btop-and-swaylock-from-the-theme-dir ()
  (emanix-theme-test--with-tree
    (let* ((plan (emanix-theme--plan "duskthorn"))
           (links (plist-get plan :links))
           (targets (mapcar #'cdr links)))
      (should (member (expand-file-name "~/.config/btop/themes/active.theme") targets))
      (should (member (expand-file-name "~/.config/swaylock/config") targets))
      ;; Sources come from the theme tree, not from a second copy somewhere.
      (should (equal (car (rassoc (expand-file-name "~/.config/btop/themes/active.theme") links))
                     (expand-file-name "btop.theme" (plist-get plan :dir)))))))

(ert-deftest emanix-theme-plan-links-zellij-by-variant-not-by-name ()
  "Both zellij theme definitions are named `emanix'; the variant picks the file."
  (emanix-theme-test--with-tree
    (let* ((plan (emanix-theme--plan "dawnthorn"))
           (links (plist-get plan :links))
           (zellij (seq-find (lambda (l) (string-match-p "zellij" (cdr l))) links)))
      (should zellij)
      (should (string-match-p "emanix-light\\.kdl\\'" (car zellij))))))

(ert-deftest emanix-theme-plan-omits-links-whose-source-is-absent ()
  "link_if_present, in plan form.
ghostty renders per-palette files only where `emanix.ghostty.enable' is
set, and zellij's tree exists only where `emanix.zellij.enable' is --
so a plan must not name a source that is not there."
  (emanix-theme-test--with-tree
    (let ((before (length (plist-get (emanix-theme--plan "duskthorn") :links))))
      (delete-file (expand-file-name "~/.config/ghostty/themes/duskthorn.conf"))
      (let* ((plan (emanix-theme--plan "duskthorn"))
             (links (plist-get plan :links)))
        (should (= (1- before) (length links)))
        (should (cl-every (lambda (l) (file-exists-p (car l))) links))))))

(ert-deftest emanix-theme-plan-parses-gtk-conf ()
  (emanix-theme-test--with-tree
    (let ((gtk (plist-get (emanix-theme--plan "duskthorn") :gtk)))
      (should (equal (alist-get "COLOR_SCHEME" gtk nil nil #'equal) "prefer-dark"))
      (should (equal (alist-get "GTK_THEME" gtk nil nil #'equal) "Adwaita:dark")))))

(ert-deftest emanix-theme-plan-writes-nothing ()
  "The planner is the half that must be safe to call on a bad name."
  (emanix-theme-test--with-tree
    (emanix-theme--plan "duskthorn")
    (emanix-theme--plan "nosuchtheme")
    (should-not (file-exists-p (emanix-theme--state-file)))))
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/projects/emanix/ioshi/i-intelligence/emacs
emacs -Q --batch -L lisp -l ert -l cl-lib \
  -l test/emanix-theme-test.el -f ert-run-tests-batch-and-exit
```

Expected: FAIL — `Symbol's function definition is void: emanix-theme--plan`,
and `emanix/theme-state-dir` void. Ten tests, all failing.

- [ ] **Step 3: Replace the state defconst**

In `emanix-theme.el`, replace:

```elisp
(defconst emanix-theme--state-file "~/.config/dotfiles/active-theme")
```

with:

```elisp
(defcustom emanix/theme-state-dir "~/.config/dotfiles"
  "Directory holding the runtime theme state markers.
Contains `active-theme' and one `last-<variant>' per variant. A
defcustom rather than a constant because Emacs now WRITES here: the
tests bind it to a temp directory, which a hardcoded path made
impossible without writing into the real state.

The name is stow-era and predates Emacs owning what is inside it.
Renaming it is worth doing and is deliberately not folded into this
change -- see the 2026-09-11 theme-authority-inversion spec."
  :type 'directory
  :group 'emanix)

(defun emanix-theme--state-file ()
  "Path of the active-theme marker."
  (expand-file-name "active-theme" emanix/theme-state-dir))

(defun emanix-theme--last-file (variant)
  "Path of the last-VARIANT marker."
  (expand-file-name (concat "last-" variant) emanix/theme-state-dir))
```

Then fix its one existing caller, `emanix-theme--active-name`, to call the
function:

```elisp
(defun emanix-theme--active-name ()
  "Name of the active dotfiles theme."
  (or (emanix-theme--read (emanix-theme--state-file)) emanix-theme--default))
```

If `emanix-theme.el` has no `defgroup`, add one above the defcustom:

```elisp
(defgroup emanix nil
  "The emanix distribution."
  :group 'environment)
```

- [ ] **Step 4: Write the planner**

Add below `emanix-theme--emacs-theme`:

```elisp
(defconst emanix-theme--zellij-themes-dir
  "~/.local/share/emanix/zellij-themes"
  "Where zellij.nix writes its two ANSI-index theme definitions.
Both are named `emanix' inside the KDL -- zellij selects a theme by
NAME, so switching swaps which definition is visible in theme_dir
rather than editing config.kdl, which lives in the checkout and must
stay clean.")

(defun emanix-theme--parse-gtk-conf (path)
  "Parse PATH, a KEY=VALUE file, into an alist of strings.
The bash this replaces `source'd the file; reading it as data instead
means a theme tree cannot execute anything in this Emacs."
  (when (file-readable-p path)
    (with-temp-buffer
      (insert-file-contents path)
      (let (out)
        (goto-char (point-min))
        (while (re-search-forward "^\\([A-Z_]+\\)=\\(.*\\)$" nil t)
          (push (cons (match-string 1) (string-trim (match-string 2))) out))
        (nreverse out)))))

(defun emanix-theme--link-plan (name dir variant)
  "Return the (SOURCE . TARGET) symlinks for theme NAME in DIR at VARIANT.
Sources that do not exist are dropped, which is `link_if_present' from
the bash this replaces: ghostty renders its palettes only on hosts with
`emanix.ghostty.enable', and zellij's tree exists only where
`emanix.zellij.enable' is set."
  (seq-filter
   (lambda (pair) (file-exists-p (car pair)))
   (list
    (cons (expand-file-name (format "~/.config/ghostty/themes/%s.conf" name))
          (expand-file-name "~/.config/ghostty/theme.conf"))
    (cons (expand-file-name "btop.theme" dir)
          (expand-file-name "~/.config/btop/themes/active.theme"))
    (cons (expand-file-name "swaylock.conf" dir)
          (expand-file-name "~/.config/swaylock/config"))
    (cons (expand-file-name (format "available/emanix-%s.kdl" variant)
                            emanix-theme--zellij-themes-dir)
          (expand-file-name "active/theme.kdl"
                            emanix-theme--zellij-themes-dir)))))

(defun emanix-theme--plan (name)
  "Describe the switch to theme NAME as data, or nil if NAME is unusable.
Writes nothing and touches no application state, so it is safe to call
on a name that came from a shell argument. Returning nil here is what
lets `emanix/theme-set' reject a bad name before disabling the theme
that is currently working."
  (let* ((dir (expand-file-name name emanix-theme--themes-dir))
         (variant (emanix-theme--read (expand-file-name "variant" dir))))
    (when (and (file-directory-p dir) (member variant '("dark" "light")))
      (list :name name
            :dir dir
            :variant variant
            :emacs-theme (emanix-theme--emacs-theme name)
            :links (emanix-theme--link-plan name dir variant)
            :gtk (emanix-theme--parse-gtk-conf
                  (expand-file-name "gtk.conf" dir))))))
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
emacs -Q --batch -L lisp -l ert -l cl-lib \
  -l test/emanix-theme-test.el -f ert-run-tests-batch-and-exit
```

Expected: `Ran 10 tests, 10 results as expected, 0 unexpected`.

- [ ] **Step 6: Wire the flake check**

Create `checks/theme-switch.nix`:

```nix
# The theme switch's unit tests. Emacs owns the runtime theme as of
# 2026-09-11, so this is the guard on the thing that used to be a shell script
# nobody could test at all.
#
# No dbus, no systemd, no gsettings and no network: every side effect is
# stubbed, and the fixtures build their own theme tree and state directory in
# temp dirs.
{ pkgs, ... }:
pkgs.runCommand "theme-switch-tests" { } ''
  export HOME=$(mktemp -d)
  ${pkgs.emacs-nox}/bin/emacs -Q --batch \
    -L ${../ioshi/i-intelligence/emacs/lisp} \
    -l ert \
    -l cl-lib \
    -l ${../ioshi/i-intelligence/emacs/test/emanix-theme-test.el} \
    -f ert-run-tests-batch-and-exit
  touch $out
''
```

In `flake.nix`, beside `modeline-segments`:

```nix
          # The theme switch's unit tests. See checks/theme-switch.nix.
          theme-switch = import ./checks/theme-switch.nix { inherit pkgs; };
```

- [ ] **Step 7: Verify the check builds**

```bash
cd ~/projects/emanix
# Explicit paths only -- NEVER `git add -A' or a directory add. The working
# tree carries an unrelated uncommitted change to config.el that is not ours.
git add ioshi/i-intelligence/emacs/test/emanix-theme-test.el checks/theme-switch.nix
nix build .#checks.x86_64-linux.theme-switch -L
nix run nixpkgs#nixpkgs-fmt -- --check flake.nix checks/theme-switch.nix
```

Expected: 10 tests pass inside the sandbox; `0 / 2 would have been reformatted`.

- [ ] **Step 8: Commit**

```bash
git add ioshi/i-intelligence/emacs/lisp/emanix-theme.el \
        ioshi/i-intelligence/emacs/test/emanix-theme-test.el \
        checks/theme-switch.nix flake.nix
git commit -m "theme: a planner that writes nothing, and a state dir tests can use"
```

---

### Task 2: The apply steps

**Files:**
- Modify: `ioshi/i-intelligence/emacs/lisp/emanix-theme.el`
- Modify: `ioshi/i-intelligence/emacs/test/emanix-theme-test.el`

**Interfaces:**
- Consumes: `emanix-theme--plan` (Task 1)
- Produces:
  - `emanix-theme--apply-links (plan)` — returns a list of failure strings
  - `emanix-theme--apply-gtk (plan)` — returns a list of failure strings
  - `emanix-theme--reload-apps ()` — returns a list of failure strings
  - `emanix-theme--write-state (plan)` — writes `active-theme` and
    `last-<variant>`; returns a list of failure strings

Every step returns failures rather than signalling. That is the contract the
orchestration in Task 3 depends on.

- [ ] **Step 1: Write the failing tests**

Append to `test/emanix-theme-test.el`:

```elisp
;;; Apply steps.

(defvar emanix-theme-test--calls nil
  "Calls recorded by `emanix-theme-test--recording'.")

(defmacro emanix-theme-test--recording (&rest body)
  "Run BODY with `call-process' and `make-symbolic-link' stubbed.
Returns the calls made, in order: (:process PROGRAM ARGS...) and
(:link SOURCE TARGET). The value is RETURNED rather than bound into a
caller-named variable, so assertions live outside the stubs -- a
`should' that runs while `call-process' is stubbed reports failures
through a crippled environment."
  (declare (indent 0))
  `(let ((emanix-theme-test--calls nil))
     (cl-letf (((symbol-function 'call-process)
                (lambda (program &optional _in _buf _disp &rest args)
                  (push (cons :process (cons program args))
                        emanix-theme-test--calls)
                  0))
               ((symbol-function 'make-symbolic-link)
                (lambda (source target &optional _ok)
                  (push (list :link source target) emanix-theme-test--calls)
                  nil)))
       ,@body)
     (nreverse emanix-theme-test--calls)))

(ert-deftest emanix-theme-apply-links-symlinks-every-planned-pair ()
  (emanix-theme-test--with-tree
    (let* ((plan (emanix-theme--plan "duskthorn"))
           (failures nil)
           (calls (emanix-theme-test--recording
                    (setq failures (emanix-theme--apply-links plan))))
           (links (seq-filter (lambda (c) (eq (car c) :link)) calls)))
      (should-not failures)
      (should (= (length links) (length (plist-get plan :links)))))))

(ert-deftest emanix-theme-apply-links-reports-a-failure-without-signalling ()
  "One unwritable target must not cost the other links, or the Emacs theme."
  (emanix-theme-test--with-tree
    (let ((plan (emanix-theme--plan "duskthorn"))
          (n 0))
      (cl-letf (((symbol-function 'make-symbolic-link)
                 (lambda (_s _t &optional _ok)
                   (setq n (1+ n))
                   (when (= n 1) (error "read-only file system")))))
        (let ((failures (emanix-theme--apply-links plan)))
          (should (= 1 (length failures)))
          ;; The remaining links were still attempted.
          (should (= n (length (plist-get plan :links)))))))))

(ert-deftest emanix-theme-apply-gtk-sets-each-key-through-gsettings ()
  (emanix-theme-test--with-tree
    (let* ((plan (emanix-theme--plan "duskthorn"))
           (calls (emanix-theme-test--recording (emanix-theme--apply-gtk plan)))
           (cmds (mapcar #'cdr (seq-filter (lambda (c) (eq (car c) :process)) calls))))
      (should (= 2 (length cmds)))
      (should (cl-every (lambda (c) (equal (car c) "gsettings")) cmds))
      (should (seq-find (lambda (c) (member "color-scheme" c)) cmds))
      (should (seq-find (lambda (c) (member "prefer-dark" c)) cmds)))))

(ert-deftest emanix-theme-apply-gtk-tolerates-a-missing-gsettings ()
  "Headless hosts have no GTK to theme; the switch must continue anyway.
Emacs cannot see `emanix.gui' -- see the 2026-09-11 spec -- so the step
runs everywhere and its failure is reported, not raised."
  (emanix-theme-test--with-tree
    (let ((plan (emanix-theme--plan "duskthorn")))
      (cl-letf (((symbol-function 'call-process)
                 (lambda (&rest _) (error "No such file or directory, gsettings"))))
        (let ((failures (emanix-theme--apply-gtk plan)))
          (should (= 2 (length failures)))
          (should (cl-every #'stringp failures)))))))

(ert-deftest emanix-theme-write-state-writes-both-markers ()
  (emanix-theme-test--with-tree
    (let ((plan (emanix-theme--plan "duskthorn")))
      (should-not (emanix-theme--write-state plan))
      (should (equal "duskthorn" (emanix-theme--read (emanix-theme--state-file))))
      (should (equal "duskthorn" (emanix-theme--read (emanix-theme--last-file "dark"))))
      (should-not (file-exists-p (emanix-theme--last-file "light"))))))

(ert-deftest emanix-theme-reload-apps-signals-ghostty ()
  (let ((calls (emanix-theme-test--recording (emanix-theme--reload-apps))))
    (should (seq-find (lambda (c) (and (eq (car c) :process)
                                       (equal (cadr c) "pkill")))
                      calls))))
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
emacs -Q --batch -L lisp -l ert -l cl-lib \
  -l test/emanix-theme-test.el -f ert-run-tests-batch-and-exit
```

Expected: the 10 from Task 1 pass; the 6 new ones fail with
`void-function emanix-theme--apply-links` and friends.

- [ ] **Step 3: Write the apply steps**

Add to `emanix-theme.el`:

```elisp
(defmacro emanix-theme--collecting (failures &rest body)
  "Run BODY, pushing a description of any error onto FAILURES.
Every apply step reports rather than signals: `emanix/theme-set' runs
during init on the host where Emacs is the compositor, so an error
escaping one side-effect must not cost the rest of the switch."
  (declare (indent 1))
  `(condition-case err
       (progn ,@body)
     (error (push (format "%S" err) ,failures))))

(defun emanix-theme--apply-links (plan)
  "Create every symlink in PLAN. Return a list of failure descriptions."
  (let (failures)
    (pcase-dolist (`(,source . ,target) (plist-get plan :links))
      (emanix-theme--collecting failures
        (make-directory (file-name-directory target) t)
        (make-symbolic-link source target :ok-if-already-exists)))
    (nreverse failures)))

(defun emanix-theme--apply-gtk (plan)
  "Apply PLAN's gtk.conf values through gsettings.
Runs unconditionally: Emacs cannot see `emanix.gui', a session variable
would not reach the EWM Emacs (started by a system unit, so it does not
inherit the shell environment), and `display-graphic-p' is nil on a
frameless daemon. A headless host simply fails here and has no GTK to
theme anyway."
  (let ((keys '(("COLOR_SCHEME" . "color-scheme")
                ("GTK_THEME"    . "gtk-theme")))
        failures)
    (pcase-dolist (`(,var . ,key) keys)
      (when-let* ((value (alist-get var (plist-get plan :gtk) nil nil #'equal)))
        (emanix-theme--collecting failures
          (call-process "gsettings" nil nil nil
                        "set" "org.gnome.desktop.interface" key value))))
    (nreverse failures)))

(defun emanix-theme--write-state (plan)
  "Record PLAN as the active theme. Return a list of failure descriptions."
  (let (failures)
    (emanix-theme--collecting failures
      (make-directory emanix/theme-state-dir t)
      (let ((name (plist-get plan :name)))
        (write-region (concat name "\n") nil (emanix-theme--state-file))
        (write-region (concat name "\n") nil
                      (emanix-theme--last-file (plist-get plan :variant)))))
    (nreverse failures)))

(defun emanix-theme--reload-apps ()
  "Tell running apps to re-read their config. Return failure descriptions.
Only ghostty needs this: btop, zellij and swaylock read their theme
when they next start, and GTK apps follow gsettings live."
  (let (failures)
    (emanix-theme--collecting failures
      (call-process "pkill" nil nil nil "-SIGUSR2" "ghostty"))
    (nreverse failures)))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
emacs -Q --batch -L lisp -l ert -l cl-lib \
  -l test/emanix-theme-test.el -f ert-run-tests-batch-and-exit
```

Expected: `Ran 16 tests, 16 results as expected, 0 unexpected`.

- [ ] **Step 5: Commit**

```bash
git add ioshi/i-intelligence/emacs/lisp/emanix-theme.el \
        ioshi/i-intelligence/emacs/test/emanix-theme-test.el
git commit -m "theme: the apply steps, each reporting rather than signalling"
```

---

### Task 3: Orchestration and the consumer hook

**Files:**
- Modify: `ioshi/i-intelligence/emacs/lisp/emanix-theme.el:183` (`emanix/theme-set`)
- Modify: `ioshi/i-intelligence/emacs/test/emanix-theme-test.el`

**Interfaces:**
- Consumes: everything from Tasks 1 and 2
- Produces:
  - `emanix/theme-apply-functions` — defcustom, list of functions of one
    argument (the plan plist)
  - `emanix/theme-set (name)` — unchanged signature and unchanged return value
    (the theme symbol actually enabled, or nil), now performing the whole switch

- [ ] **Step 1: Write the failing tests**

Append to `test/emanix-theme-test.el`:

```elisp
;;; Orchestration.

(ert-deftest emanix-theme-set-rejects-an-unknown-name-without-touching-anything ()
  "A bad name from a shell argument must not disable the working theme."
  (emanix-theme-test--with-tree
    (let (result
          (calls (emanix-theme-test--recording
                   (setq result (emanix/theme-set "nosuchtheme")))))
      (should-not result)
      (should-not calls)
      (should-not (file-exists-p (emanix-theme--state-file))))))

(ert-deftest emanix-theme-set-runs-state-links-gtk-and-reload ()
  (emanix-theme-test--with-tree
    (let ((calls (cl-letf (((symbol-function 'emanix-theme--apply-emacs)
                            (lambda (_) 'catppuccin)))
                   (emanix-theme-test--recording
                     (emanix/theme-set "duskthorn")))))
      (should (equal "duskthorn" (emanix-theme--read (emanix-theme--state-file))))
      (should (seq-find (lambda (c) (eq (car c) :link)) calls))
      (should (seq-find (lambda (c) (and (eq (car c) :process)
                                         (equal (cadr c) "gsettings")))
                        calls))
      (should (seq-find (lambda (c) (and (eq (car c) :process)
                                         (equal (cadr c) "pkill")))
                        calls)))))

(ert-deftest emanix-theme-set-calls-the-consumer-hook-with-the-plan ()
  (emanix-theme-test--with-tree
    (let* ((seen nil)
           (emanix/theme-apply-functions (list (lambda (plan) (setq seen plan)))))
      (cl-letf (((symbol-function 'emanix-theme--apply-emacs) (lambda (_) 'catppuccin)))
        (emanix-theme-test--recording
          (emanix/theme-set "duskthorn")))
      (should (equal (plist-get seen :name) "duskthorn"))
      (should (equal (plist-get seen :variant) "dark")))))

(ert-deftest emanix-theme-set-survives-a-signalling-hook-function ()
  "A consumer's broken registration must not stop the ones after it."
  (emanix-theme-test--with-tree
    (let* ((ran nil)
           (emanix/theme-apply-functions
            (list (lambda (_plan) (error "boom"))
                  (lambda (_plan) (setq ran t)))))
      (let (result)
        (cl-letf (((symbol-function 'emanix-theme--apply-emacs)
                   (lambda (_) 'catppuccin)))
          (emanix-theme-test--recording
            (setq result (emanix/theme-set "duskthorn"))))
        (should (eq 'catppuccin result)))
      (should ran))))

(ert-deftest emanix-theme-set-returns-the-theme-even-when-side-effects-fail ()
  "The colours are the part the user sees; a failed symlink must not mask them."
  (emanix-theme-test--with-tree
    (cl-letf (((symbol-function 'emanix-theme--apply-emacs) (lambda (_) 'catppuccin))
              ((symbol-function 'make-symbolic-link)
               (lambda (&rest _) (error "read-only file system")))
              ((symbol-function 'call-process)
               (lambda (&rest _) (error "not found"))))
      (should (eq 'catppuccin (emanix/theme-set "duskthorn"))))))

(ert-deftest emanix-theme-apply-functions-defaults-empty ()
  "The distribution registers none of its own; this seam is the consumer's."
  (should (null (default-value 'emanix/theme-apply-functions))))
```

- [ ] **Step 2: Run the tests to verify they fail**

Expected: 6 new failures — `emanix/theme-apply-functions` is void, and
`emanix/theme-set` does not yet write state or create links.

- [ ] **Step 3: Extract the current body into `emanix-theme--apply-emacs`**

The existing `emanix/theme-set` body becomes a private step, verbatim except
for its name and docstring:

```elisp
(defun emanix-theme--apply-emacs (plan)
  "Load PLAN's Emacs theme. Return the theme symbol enabled, or nil.
Resolve and confirm the theme is loadable BEFORE disabling whatever is
currently enabled, then wrap `load-theme' itself in `condition-case' as
belt-and-braces, since a theme can be listed as available and still
error while loading. That ordering is what stops a failed switch from
leaving the session themeless."
  (let* ((name (plist-get plan :name))
         (wanted (plist-get plan :emacs-theme))
         (theme (emanix-theme--pick-loadable wanted name)))
    (setq modus-themes-common-palette-overrides
          (emanix-theme--modus-overrides name))
    (when (eq theme 'catppuccin)
      (setq catppuccin-flavor (emanix-theme--catppuccin-flavor name)))
    (when theme
      (condition-case err
          (progn
            (mapc #'disable-theme custom-enabled-themes)
            (load-theme theme :no-confirm)
            (when (eq theme 'catppuccin) (catppuccin-reload))
            theme)
        (error
         (message "emanix-theme: load-theme %S failed: %S" theme err)
         nil)))))
```

- [ ] **Step 4: Add the hook and the new orchestration**

```elisp
(defcustom emanix/theme-apply-functions nil
  "Functions run after a theme switch, each called with the plan plist.
The plist carries :name, :dir, :variant, :emacs-theme, :links and :gtk.

This is the CONSUMER extension point, and the distribution registers
none of its own. Side effects for programs emanix does not install --
the author's pi agent and Claude Code settings, for instance -- belong
here rather than in `emanix/theme-set', which must stay ignorant of
anything `scott.*' declares.

A function that signals is reported and skipped; the switch continues."
  :type '(repeat function)
  :group 'emanix)

(defun emanix-theme--run-hook (plan)
  "Run `emanix/theme-apply-functions' on PLAN. Return failure descriptions."
  (let (failures)
    (dolist (f emanix/theme-apply-functions)
      (condition-case err
          (funcall f plan)
        (error (push (format "%s: %S" f err) failures))))
    (nreverse failures)))

(defun emanix/theme-set (name)
  "Switch the running session to theme NAME, everywhere.
Never signals to its caller. This runs from init on the host where
Emacs is the desktop, so an uncaught error here would abort the rest of
init rather than merely leave colours wrong -- and it now drives six
side-effects rather than one, so each is wrapped individually and
reports instead of raising.

Returns the Emacs theme symbol actually enabled, or nil if the name is
unknown or nothing could be loaded. Side-effect failures do NOT change
the return value: the colours are the part you can see, and a
read-only btop directory must not look like a failed theme switch."
  (interactive
   (list (completing-read
          "Theme: "
          (and (file-directory-p emanix-theme--themes-dir)
               (directory-files emanix-theme--themes-dir nil "\\`[^.]"))
          nil t)))
  (if-let* ((plan (emanix-theme--plan name)))
      (let ((failures (append (emanix-theme--write-state plan)
                              (emanix-theme--apply-links plan)
                              (emanix-theme--apply-gtk plan)
                              (emanix-theme--run-hook plan)
                              (emanix-theme--reload-apps)))
            (theme (emanix-theme--apply-emacs plan)))
        (when failures
          (message "emanix-theme: %s applied with %d failure(s): %s"
                   name (length failures) (string-join failures "; ")))
        theme)
    (message "emanix-theme: no such theme %S in %s"
             name emanix-theme--themes-dir)
    nil))
```

- [ ] **Step 5: Run the tests to verify they pass**

Expected: `Ran 22 tests, 22 results as expected, 0 unexpected`.

- [ ] **Step 6: Commit**

```bash
git add ioshi/i-intelligence/emacs/lisp/emanix-theme.el \
        ioshi/i-intelligence/emacs/test/emanix-theme-test.el
git commit -m "theme: emacs owns the switch, with a hook for the consumer's side"
```

---

### Task 4: The toggle, and a key that binds it

**Files:**
- Modify: `ioshi/i-intelligence/emacs/lisp/emanix-theme.el`
- Modify: `ioshi/i-intelligence/emacs/config.el:795` (near the `theme-init` call)
- Modify: `ioshi/i-intelligence/emacs/lisp/emanix-welcome.el`
- Modify: `ioshi/i-intelligence/emacs/test/emanix-theme-test.el`

**Interfaces:**
- Consumes: `emanix/theme-set`, `emanix-theme--last-file`, `emanix-theme--plan`
- Produces: `emanix/theme-toggle ()` — interactive, returns what `theme-set`
  returned, or nil when no counterpart theme exists

- [ ] **Step 1: Write the failing tests**

```elisp
;;; The toggle.

(ert-deftest emanix-theme-toggle-uses-the-counterpart-marker ()
  (emanix-theme-test--with-tree
    (make-directory emanix/theme-state-dir t)
    (write-region "duskthorn\n" nil (emanix-theme--state-file))
    (write-region "dawnthorn\n" nil (emanix-theme--last-file "light"))
    (let (switched)
      (cl-letf (((symbol-function 'emanix/theme-set)
                 (lambda (name) (setq switched name) 'stub)))
        (should (eq 'stub (emanix/theme-toggle))))
      (should (equal "dawnthorn" switched)))))

(ert-deftest emanix-theme-toggle-falls-back-to-any-opposite-variant ()
  "First toggle on a fresh machine has no counterpart marker yet."
  (emanix-theme-test--with-tree
    (make-directory emanix/theme-state-dir t)
    (write-region "dawnthorn\n" nil (emanix-theme--state-file))
    (let (switched)
      (cl-letf (((symbol-function 'emanix/theme-set)
                 (lambda (name) (setq switched name) 'stub)))
        (emanix/theme-toggle))
      (should (equal "duskthorn" switched)))))

(ert-deftest emanix-theme-toggle-ignores-a-stale-counterpart-marker ()
  "A marker naming a theme that has since been deleted must not be used."
  (emanix-theme-test--with-tree
    (make-directory emanix/theme-state-dir t)
    (write-region "duskthorn\n" nil (emanix-theme--state-file))
    (write-region "deletedtheme\n" nil (emanix-theme--last-file "light"))
    (let (switched)
      (cl-letf (((symbol-function 'emanix/theme-set)
                 (lambda (name) (setq switched name) 'stub)))
        (emanix/theme-toggle))
      (should (equal "dawnthorn" switched)))))

(ert-deftest emanix-theme-toggle-returns-nil-when-there-is-no-counterpart ()
  (emanix-theme-test--with-tree
    (delete-directory (expand-file-name "dawnthorn" emanix-theme--themes-dir) t)
    (make-directory emanix/theme-state-dir t)
    (write-region "duskthorn\n" nil (emanix-theme--state-file))
    (should-not (emanix/theme-toggle))))
```

- [ ] **Step 2: Run the tests to verify they fail**

Expected: 4 failures, `void-function emanix/theme-toggle`.

- [ ] **Step 3: Implement the toggle**

```elisp
(defun emanix-theme--themes-of-variant (variant)
  "Names of every theme in the tree whose variant is VARIANT."
  (when (file-directory-p emanix-theme--themes-dir)
    (seq-filter
     (lambda (name)
       (equal variant (emanix-theme--read
                       (expand-file-name (format "%s/variant" name)
                                         emanix-theme--themes-dir))))
     (directory-files emanix-theme--themes-dir nil "\\`[^.]"))))

;;;###autoload
(defun emanix/theme-toggle ()
  "Flip between the last-used dark theme and the last-used light one.
Prefers the `last-<variant>' marker, then any theme of the opposite
variant. A marker naming a theme that no longer exists is ignored
rather than trusted -- deleting a theme directory is how themes are
retired here, so a stale marker is expected, not exceptional."
  (interactive)
  (let* ((active (emanix-theme--active-name))
         (plan (emanix-theme--plan active))
         (variant (or (plist-get plan :variant) "dark"))
         (other (if (equal variant "dark") "light" "dark"))
         (marked (emanix-theme--read (emanix-theme--last-file other)))
         (target (if (and marked (emanix-theme--plan marked))
                     marked
                   (car (emanix-theme--themes-of-variant other)))))
    (if target
        (emanix/theme-set target)
      (message "emanix-theme: no %s theme in %s"
               other emanix-theme--themes-dir)
      nil)))
```

- [ ] **Step 4: Run the tests to verify they pass**

Expected: `Ran 26 tests, 26 results as expected, 0 unexpected`.

- [ ] **Step 5: Bind it**

In `config.el`, immediately above the existing `emanix/theme-init` call at
line 795:

```elisp
;; C-c v — flip dark/light. "v" for variant, which is what it flips.
;; Lowercase deliberately: checks/welcome-keys.nix extracts `C-[a-z] [a-z?]'
;; and its own comment states an uppercase row will not be extracted at all,
;; so `C-c T' would have advertised an unguarded key.
(when (fboundp 'emanix/theme-toggle)
  (global-set-key (kbd "C-c v") #'emanix/theme-toggle))
```

- [ ] **Step 6: Advertise it in the welcome buffer**

Add a row to `emanix-welcome.el` alongside the other `C-c` rows, matching the
surrounding format exactly:

```
C-c v   toggle dark / light
```

- [ ] **Step 7: Verify the key guard sees it**

```bash
cd ~/projects/emanix
git add ioshi/i-intelligence/emacs/lisp/emanix-welcome.el ioshi/i-intelligence/emacs/config.el
nix build .#checks.x86_64-linux.welcome-keys -L
nix build .#checks.x86_64-linux.theme-switch -L
```

Expected: both succeed. The first proves `C-c v` was extracted from the welcome
buffer **and** found in a live binding form — the guard's whole purpose.

- [ ] **Step 8: Commit**

```bash
git add ioshi/i-intelligence/emacs/lisp/emanix-theme.el \
        ioshi/i-intelligence/emacs/lisp/emanix-welcome.el \
        ioshi/i-intelligence/emacs/config.el \
        ioshi/i-intelligence/emacs/test/emanix-theme-test.el
git commit -m "theme: C-c v toggles the variant, and the welcome buffer says so"
```

---

### Task 5: Converging startup, and the end of seedGhosttyTheme

**Files:**
- Modify: `ioshi/i-intelligence/emacs/lisp/emanix-theme.el` (`emanix/theme-init`)
- Modify: `ioshi/i-intelligence/ghostty.nix:69-76` (delete the activation block)
- Modify: `ioshi/i-intelligence/emacs/test/emanix-theme-test.el`

**Interfaces:**
- Consumes: `emanix/theme-set`, `emanix-theme--apply-emacs`,
  `emanix-theme--plan`
- Produces: `emanix/theme-init ()` — unchanged name and call site

- [ ] **Step 1: Write the failing tests**

```elisp
;;; Startup convergence.

(ert-deftest emanix-theme-init-converges-when-state-is-missing ()
  "A fresh machine has no marker; the first Emacs start themes everything."
  (emanix-theme-test--with-tree
    (let ((emanix-theme--default "duskthorn")
          (switched nil))
      (cl-letf (((symbol-function 'emanix/theme-set)
                 (lambda (name) (setq switched name) 'stub)))
        (emanix/theme-init))
      (should (equal "duskthorn" switched)))))

(ert-deftest emanix-theme-init-converges-when-state-names-a-dead-theme ()
  (emanix-theme-test--with-tree
    (make-directory emanix/theme-state-dir t)
    (write-region "deletedtheme\n" nil (emanix-theme--state-file))
    (let ((emanix-theme--default "duskthorn")
          (switched nil))
      (cl-letf (((symbol-function 'emanix/theme-set)
                 (lambda (name) (setq switched name) 'stub)))
        (emanix/theme-init))
      (should (equal "duskthorn" switched)))))

(ert-deftest emanix-theme-init-only-loads-colours-when-state-is-valid ()
  "Every subsequent start: no gsettings, no relinking, no JSON rewrites."
  (emanix-theme-test--with-tree
    (make-directory emanix/theme-state-dir t)
    (write-region "duskthorn\n" nil (emanix-theme--state-file))
    (let ((full nil) (loaded nil))
      (cl-letf (((symbol-function 'emanix/theme-set)
                 (lambda (name) (setq full name) 'stub))
                ((symbol-function 'emanix-theme--apply-emacs)
                 (lambda (plan) (setq loaded (plist-get plan :name)) 'stub)))
        (emanix/theme-init))
      (should-not full)
      (should (equal "duskthorn" loaded)))))
```

- [ ] **Step 2: Run the tests to verify they fail**

Expected: the first two fail (current `theme-init` always calls `theme-set`, so
`switched` is set — but it is set for the *wrong* reason in test 3, which fails
because `full` is non-nil).

- [ ] **Step 3: Rewrite `emanix/theme-init`**

```elisp
(defun emanix-theme--seed-name ()
  "The theme name a machine with no usable state converges on.

The host's build-time `emanix.theme', delivered as $EMANIX_THEME, and
`emanix-theme--default' only when that is unset or empty.

The Nix value IS reachable here, contrary to what this function's
predecessor asserted. The spec's rejection of `EMANIX_GUI' was about
the EWM Emacs not inheriting a SHELL variable, because it is started
outside the login shell -- but ewm.nix launches it FROM
`environment.loginShellInit' and now exports both $EMANIX_THEME and
$EMANIX_THEMES_DIR through `environment.sessionVariables', which NixOS
writes to /etc/set-environment and /etc/zshenv sources before
/etc/zprofile runs the launch snippet. The non-EWM daemon gets the same
pair from zsh.nix's `systemd.user.sessionVariables'.

Falling back to `emanix-theme--default' rather than requiring the
variable keeps a host that has not rebuilt since this landed working
exactly as it did before."
  (let ((configured (getenv "EMANIX_THEME")))
    (if (and configured (not (equal configured ""))) configured
      emanix-theme--default)))

(defun emanix-theme--colours-only-plan (name)
  "A plan carrying just what `emanix-theme--apply-emacs' reads: NAME and a theme.

Not a real plan -- no :dir, :links or :gtk, so it must never be handed
to the side-effect steps. It exists for the one case `emanix/theme-init'
must survive and `emanix-theme--plan' cannot describe: no theme tree at
all. `emanix-theme--apply-emacs' then resolves the symbol through
`emanix-theme--pick-loadable', which falls back catppuccin ->
`emanix-theme--builtin-fallback', so a session with an unreadable tree
still gets colours."
  (list :name name
        :emacs-theme (condition-case nil
                         (emanix-theme--emacs-theme name)
                       (error 'catppuccin))))

(defun emanix/theme-init ()
  "Apply the active theme at startup. Never signals, and never no-ops.

Converges the whole machine when `active-theme' is missing or names a
theme that is no longer in the tree, seeding from
`emanix-theme--seed-name'. That is the fresh-install case, and it is why
ghostty's `seedGhosttyTheme' activation hook could be deleted: seeding
one application was a narrower version of this.

Otherwise loads only the Emacs theme. Re-running the full switch on
every start would be an idempotent re-base in the spirit of
`nixos-rebuild switch', but it rewrites ~/.claude/settings.json at each
login, and Claude Code rewrites that file at runtime -- repeating the
write when nothing changed only widens that race.

ALWAYS ends with a theme enabled if Emacs can load one at all. The
tree is reached through $EMANIX_THEMES_DIR, and an environment
regression that empties or misdirects that variable makes every plan
nil -- which would otherwise leave the session with NO theme loaded,
the failure mode measured on the EWM host on 2026-09-11 when the
variable never reached the login shell. A themeless desktop is a worse
outcome than the wrong colours, so the last resort is a plan that
describes colours and nothing else."
  (let* ((recorded (emanix-theme--read (emanix-theme--state-file)))
         (plan (and recorded (emanix-theme--plan recorded))))
    (if plan
        (emanix-theme--apply-emacs plan)
      ;; No marker, or one naming a theme no longer in the tree. Converge on
      ;; the seed -- NOT on the recorded name, which is the dead one.
      (let ((seed (emanix-theme--seed-name)))
        (or (emanix/theme-set seed)
            ;; The tree could not describe the seed either, so there is
            ;; nothing to converge. Load colours and stop; writing state for
            ;; a theme whose directory we cannot read would only record a
            ;; second dead marker.
            (emanix-theme--apply-emacs
             (emanix-theme--colours-only-plan seed)))))))
```

The block above is the SHIPPED text, updated 2026-09-11 by the fix wave
that followed this plan. Two things changed from what was planned here,
and both are load-bearing enough that a plan showing the earlier version
would be a trap for anyone reading the two side by side:

- the seed is `emanix-theme--seed-name` ($EMANIX_THEME, falling back to
  `emanix-theme--default`), not `emanix-theme--default` directly. The
  planned comment's claim that Emacs cannot reliably see the host's
  `emanix.theme` stopped being true once `ewm.nix` exported it through
  `environment.sessionVariables`.
- `theme-init` can no longer return without a theme loaded. When no plan
  can be built for any candidate -- an absent or misdirected
  $EMANIX_THEMES_DIR, which is exactly what was measured on the EWM host
  -- it falls through to a colours-only plan rather than nil.

- [ ] **Step 4: Run the tests to verify they pass**

Expected: `Ran 29 tests, 29 results as expected, 0 unexpected`.

- [ ] **Step 5: Delete the ghostty activation hook**

Remove from `ghostty.nix`:

```nix
    # Seed theme.conf only when absent, so a fresh machine has a theme before
    # the first dot-theme-set run. `-e` is false for a dangling symlink, which
    # is the case worth re-seeding, so this is the right test.
    home.activation.seedGhosttyTheme =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        target="$HOME/.config/ghostty/theme.conf"
        if [ ! -e "$target" ]; then
          run ln -sfn "$HOME/.config/ghostty/themes/${config.emanix.theme}.conf" "$target"
        fi
      '';
```

and replace it with:

```nix
    # NO seeding hook. `emanix/theme-init' converges the whole machine on the
    # first Emacs start when ~/.config/dotfiles/active-theme is absent, which
    # is a fresh install -- and it seeds btop, zellij, swaylock, gtk and the
    # consumer's registrations too, not only this one symlink. Removed
    # 2026-09-11 with the theme-authority inversion.
```

Check whether `lib` is still used elsewhere in `ghostty.nix` after the removal;
it is (`lib.mkIf`, `lib.mapAttrs'`), so the argument list is unchanged.

- [ ] **Step 6: Verify**

```bash
cd ~/projects/emanix
git add ioshi/i-intelligence/ghostty.nix
nix run nixpkgs#nixpkgs-fmt -- --check ioshi/i-intelligence/ghostty.nix
nix build .#checks.x86_64-linux.theme-switch -L
nix eval --raw .#nixosConfigurations.x86_64-linux 2>/dev/null || true
```

Expected: formatting clean, 29 tests pass.

- [ ] **Step 7: Commit**

```bash
git add ioshi/i-intelligence/emacs/lisp/emanix-theme.el \
        ioshi/i-intelligence/ghostty.nix \
        ioshi/i-intelligence/emacs/test/emanix-theme-test.el
git commit -m "theme: converge on first start, and retire the ghostty seed hook"
```

---

### Task 6: swaylock follows the switch

**Files:**
- Modify: `lib/theme-tree.nix` (emit `swaylock.conf`)
- Modify: `ioshi/i-intelligence/swaylock.nix` (drop the `home.file` config)

**Interfaces:**
- Consumes: `themeLib.mkTheme`'s existing `swaylock` attribute
  (`lib/themes.nix:405`)
- Produces: `$EMANIX_THEMES_DIR/<name>/swaylock.conf`, which
  `emanix-theme--link-plan` (Task 1) already expects

- [ ] **Step 1: Emit swaylock.conf into the theme tree**

In `lib/theme-tree.nix`'s `mkThemeDir`, beside the `btop.theme` line:

```nix
      cp ${pkgs.writeText "swaylock.conf" t.swaylock}  $out/swaylock.conf
```

`mkTheme` already exposes `swaylock`; no change to `lib/themes.nix`.

- [ ] **Step 2: Verify the tree gains the file**

```bash
cd ~/projects/emanix
tree=$(nix build --no-link --print-out-paths \
  --impure --expr '(builtins.getFlake (toString ./.)).lib.themeTree or null' 2>/dev/null) || true
# Simpler and always available: build a host and read the exported dir.
nix eval --raw .#nixosConfigurations.rafik.config.home-manager.users.scott.home.sessionVariables.EMANIX_THEMES_DIR 2>/dev/null
```

If neither path resolves in your checkout, build any consuming host and list
`$EMANIX_THEMES_DIR/catppuccin-mocha/`. Expected: `swaylock.conf` present
alongside `btop.theme`, `gtk.conf`, `colors.toml`, `variant`, `emacs-theme`,
`pi-agent-theme.json`.

- [ ] **Step 3: Stop Home Manager owning the live path**

Replace the whole `home.file.".config/swaylock/config"` block in
`swaylock.nix` with:

```nix
    # NO `home.file.".config/swaylock/config"'. That path is written by the
    # runtime switcher now (emanix/theme-set symlinks
    # $EMANIX_THEMES_DIR/<name>/swaylock.conf onto it), and a runtime path with
    # two owners is the exact trap ghostty.nix documents: Home Manager renames
    # the switcher's file to config.hm-bak at every activation, silently
    # reverting the active theme on the next rebuild.
    #
    # Until 2026-09-11 this module rendered ONE palette, resolved from the
    # build-time `emanix.theme', so the lock screen never followed a runtime
    # switch at all. Unlike firefox.nix -- which is build-time-only and says so
    # deliberately -- nothing here recorded that; it was drift.
```

The module's `config = lib.mkIf config.emanix.gui { ... }` wrapper now has no
attributes left inside it. Delete the module's body entirely and leave the file
as a documented no-op, or delete the file and its `default.nix` import. **Prefer
deleting the file**: a module that configures nothing is a module that will be
re-grown by accident. The swaylock *package* and its PAM entry are in
`ewm.nix`, not here, so nothing else moves.

If the file is deleted, remove `./swaylock.nix` from
`ioshi/i-intelligence/default.nix` and decrement the module count in its header
comment (it currently reads "17 modules and this list imports 16"; verify with
`ls *.nix | grep -vc '^default.nix$'` and `grep -c '^    \./' default.nix`
rather than trusting the comment).

- [ ] **Step 4: Verify**

```bash
cd ~/projects/emanix
git add lib/theme-tree.nix ioshi/i-intelligence/default.nix ioshi/i-intelligence/swaylock.nix
nix run nixpkgs#nixpkgs-fmt -- --check lib/theme-tree.nix ioshi/i-intelligence/default.nix
nix flake check
```

Expected: `all checks passed!`, including the role evaluations, which is what
proves removing the module did not break the Home Manager aggregate.

- [ ] **Step 5: Commit**

```bash
# Named paths, not the directory: ioshi/i-intelligence/emacs/config.el holds
# an unrelated uncommitted change that is not part of this task.
git add lib/theme-tree.nix ioshi/i-intelligence/default.nix ioshi/i-intelligence/swaylock.nix
git commit -m "theme: swaylock follows the runtime switch, like btop already did"
```

---

### Task 7: emanix header, full check, push, and the dotfiles lock

**Files:**
- Modify: `ioshi/i-intelligence/emacs/lisp/emanix-theme.el:1-15` (header comment)
- Modify: `~/dotfiles/flake.lock`

This is the seam between the two repos. **Do not start Task 8 before this task
completes**, and do not rebuild a host between them: a half-applied inversion is
a machine whose theme state has two writers and no owner.

- [ ] **Step 1: Correct the module header**

`emanix-theme.el` opens by naming bash as the caller:

```elisp
;; The active theme is named in ~/.config/dotfiles/active-theme, and each
;; themes/<name>/ directory carries an `emacs-theme' file naming the Emacs
;; theme to load. bin/dot-theme-set calls (emanix/theme-set "<name>") on switch.
```

Replace the third sentence:

```elisp
;; The active theme is named in ~/.config/dotfiles/active-theme, and each
;; themes/<name>/ directory carries an `emacs-theme' file naming the Emacs
;; theme to load. THIS FILE is the authority for a switch as of 2026-09-11:
;; `emanix/theme-set' writes that marker, links every per-app theme file, calls
;; gsettings, and runs `emanix/theme-apply-functions' for whatever the consuming
;; flake registered. The consumer's bin/dot-theme-set is now a wrapper that
;; calls in here, which is the reverse of the arrangement it replaced.
```

- [ ] **Step 2: Full check and format**

```bash
cd ~/projects/emanix
nix flake check
bash tests/init-guard.sh
nix run nixpkgs#nixpkgs-fmt -- --check $(git ls-files '*.nix')
```

Expected: `all checks passed!`, `init-guard: all checks passed`, no
reformatting. `init-guard.sh` matters here specifically — it loads the real
`config.el` in a real Emacs and proves the new `C-c v` binding did not break
the fallback path.

- [ ] **Step 3: Commit and push**

```bash
git add ioshi/i-intelligence/emacs/lisp/emanix-theme.el
git commit -m "theme: emacs is the switch authority; docs and header follow"
git push origin main
```

- [ ] **Step 4: Update the dotfiles lock**

```bash
cd ~/dotfiles
nix flake lock --update-input emanix
git add flake.lock
git commit -m "flake: pick up the theme-authority inversion from emanix"
```

- [ ] **Step 5: Verify the lock moved**

```bash
grep -A3 '"emanix"' flake.lock | grep rev
cd ~/projects/emanix && git rev-parse HEAD
```

Expected: the two revisions match.

---

### Task 8: Extract the two JSON patchers

**Files:**
- Create: `~/dotfiles/bin/dot-theme-apply-pi`
- Create: `~/dotfiles/bin/dot-theme-apply-claude`
- Modify: `~/dotfiles/bin/dot-theme-set` (source of the heredocs)

**Interfaces:**
- Produces two executables with this contract, which Task 9's elisp depends on:
  - `dot-theme-apply-pi <theme-name> <theme-dir>` — symlinks
    `<theme-dir>/pi-agent-theme.json` into `~/.pi/agent/themes/<name>.json` and
    sets `.theme` in `~/.pi/agent/settings.json`
  - `dot-theme-apply-claude <variant>` — sets `.theme` in
    `~/.claude/settings.json` to `light-ansi` or `dark-ansi`
  - Both exit 0 on success, non-zero with a message on stderr otherwise

- [ ] **Step 1: Create `bin/dot-theme-apply-pi`**

```bash
#!/usr/bin/env bash
# bin/dot-theme-apply-pi — point the pi agent at a theme.
#
# Extracted from dot-theme-set on 2026-09-11, when Emacs became the switch
# authority. It is called from emanix/theme-apply-functions (see
# home/scott/emacs/personal.el), not from a shell script any more.
#
# Usage: dot-theme-apply-pi <theme-name> <theme-dir>
set -euo pipefail

THEME_NAME="${1:?usage: dot-theme-apply-pi <theme-name> <theme-dir>}"
THEME_DIR="${2:?usage: dot-theme-apply-pi <theme-name> <theme-dir>}"

pi_themes_dir="$HOME/.pi/agent/themes"
generated="$THEME_DIR/pi-agent-theme.json"

# The theme tree is a read-only Nix store path, so nothing is written into it:
# the JSON is generated at build time by lib/theme-tree.nix and only linked.
if [[ -f "$generated" ]]; then
    mkdir -p "$pi_themes_dir"
    ln -sfn "$generated" "$pi_themes_dir/$THEME_NAME.json"
else
    echo "dot-theme-apply-pi: no pi-agent-theme.json in $THEME_DIR" >&2
    exit 1
fi

pi_settings="$HOME/.pi/agent/settings.json"
command -v python3 >/dev/null 2>&1 || {
    echo "dot-theme-apply-pi: python3 not found" >&2; exit 1; }

python3 - "$pi_settings" "$THEME_NAME" <<'PY'
import json, sys, os, tempfile, shutil
path, theme = sys.argv[1], sys.argv[2]
try:
    if os.path.exists(path):
        with open(path) as f: data = json.load(f)
    else:
        data = {}
    data["theme"] = theme
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
    with os.fdopen(fd, "w") as f: json.dump(data, f, indent=2)
    # mkstemp creates 0600 and os.replace swaps the whole inode, so without
    # this the file's original mode is silently lost. This one is inside a
    # Syncthing-synced directory, so a mode change would propagate to peers.
    if os.path.exists(path): shutil.copymode(path, tmp)
    os.replace(tmp, path)
except Exception as e:
    print(f"pi settings update failed: {e}", file=sys.stderr)
    sys.exit(1)
PY
```

Note the one deliberate change from the original: the inner script's bare
`except` used `__import__('sys').stderr` and the outer call ended in `|| true`,
so a failure was invisible. It now exits non-zero and the caller reports it.

- [ ] **Step 2: Create `bin/dot-theme-apply-claude`**

```bash
#!/usr/bin/env bash
# bin/dot-theme-apply-claude — follow the terminal palette in Claude Code.
#
# The -ansi theme variants take their colours from the terminal rather than
# Claude's built-ins, so Claude inherits whatever palette ghostty is using,
# including over ssh where the rendering terminal belongs to the client. Only
# the dark/light axis matters; the palette needs no mention.
#
# Extracted from dot-theme-set on 2026-09-11. Writes inside the checkout:
# ~/.claude/settings.json is an out-of-store symlink into it, the documented
# trade-off in claude.nix.
#
# Usage: dot-theme-apply-claude <dark|light>
set -euo pipefail

VARIANT="${1:?usage: dot-theme-apply-claude <dark|light>}"
case "$VARIANT" in
    dark|light) ;;
    *) echo "dot-theme-apply-claude: variant must be dark or light, got '$VARIANT'" >&2
       exit 1 ;;
esac

claude_settings="$HOME/.claude/settings.json"
[[ -f "$claude_settings" ]] || exit 0   # no Claude on this host; nothing to do
command -v python3 >/dev/null 2>&1 || {
    echo "dot-theme-apply-claude: python3 not found" >&2; exit 1; }

python3 - "$claude_settings" "$VARIANT" <<'PY'
import json, sys, os, tempfile, shutil, collections
path, variant = sys.argv[1], sys.argv[2]
tmp = None
try:
    # Resolve the symlink so the checkout file gets replaced, not the
    # symlink itself -- os.replace() onto a symlink path would swap in a
    # plain file and sever the link to version control.
    real = os.path.realpath(path)
    with open(real) as fh:
        data = json.load(fh, object_pairs_hook=collections.OrderedDict)
    data["theme"] = "light-ansi" if variant == "light" else "dark-ansi"
    # Write to a temp file in the same directory, then atomically replace.
    # Claude Code rewrites this file at runtime; a plain truncate-then-write
    # could race it and leave a partial file (dropping hooks/enabledPlugins).
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(real))
    with os.fdopen(fd, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    # Preserve the target's mode: mkstemp creates 0600 and os.replace
    # swaps the inode, which silently dropped settings.json's exec bit the
    # first time this ran.
    shutil.copymode(real, tmp)
    os.replace(tmp, real)
    tmp = None
except Exception as e:
    print(f"claude settings update failed: {e}", file=sys.stderr)
    sys.exit(1)
finally:
    if tmp and os.path.exists(tmp):
        os.unlink(tmp)
PY
```

- [ ] **Step 3: Make them executable and check them**

```bash
cd ~/dotfiles
chmod +x bin/dot-theme-apply-pi bin/dot-theme-apply-claude
nix run nixpkgs#shellcheck -- bin/dot-theme-apply-pi bin/dot-theme-apply-claude
```

Expected: no findings. (`shellcheck` does not parse the Python heredocs; they
are quoted `<<'PY'`, so it treats them as literal text.)

- [ ] **Step 4: Exercise each against a scratch file**

```bash
tmp=$(mktemp -d)
mkdir -p "$tmp/theme" && echo '{"name":"x"}' > "$tmp/theme/pi-agent-theme.json"
HOME="$tmp" bin/dot-theme-apply-pi demo "$tmp/theme" && \
  cat "$tmp/.pi/agent/settings.json"

printf '{"theme":"dark-ansi","hooks":{}}\n' > "$tmp/claude.json"
mkdir -p "$tmp/.claude" && ln -sf "$tmp/claude.json" "$tmp/.claude/settings.json"
HOME="$tmp" bin/dot-theme-apply-claude light && cat "$tmp/claude.json"
ls -l "$tmp/.claude/settings.json"   # must STILL be a symlink
rm -rf "$tmp"
```

Expected: pi settings contain `"theme": "demo"`; the Claude file contains
`"light-ansi"`, retains `hooks`, and `.claude/settings.json` is still a symlink
— that last assertion is the regression the original's comment records.

- [ ] **Step 5: Commit**

```bash
git add bin/dot-theme-apply-pi bin/dot-theme-apply-claude
git commit -m "bin: extract the pi and claude theme patchers from dot-theme-set"
```

---

### Task 9: Register the hook, thin the wrappers

**Files:**
- Modify: `~/dotfiles/home/scott/emacs/personal.el` (append a section)
- Modify: `~/dotfiles/bin/dot-theme-set` (replace wholesale)
- Modify: `~/dotfiles/bin/dot-theme-toggle` (replace wholesale)

**Interfaces:**
- Consumes: `emanix/theme-apply-functions` (Task 3), the two scripts (Task 8),
  `$EMANIX_BIN_DIR` (exported by `zsh.nix`)
- Produces: nothing further depends on this task

- [ ] **Step 1: Register the consumer side in `personal.el`**

Append:

```elisp
;; --- Theme: the personal side-effects ---
;; emanix/theme-set owns the switch as of 2026-09-11 and drives everything the
;; DISTRIBUTION installs. pi and Claude Code are `scott.*' -- declared in this
;; repo, invisible to the distro by the same rule that ejected mu4e and ecomms
;; -- so they are registered here instead.
;;
;; The two patchers stay out-process on purpose. Each does an atomic replace
;; with mode preservation and symlink resolution, and their comments record two
;; bugs they already caused: a dropped exec bit, and an os.replace onto a
;; symlink that severed a file from version control. Re-solving that in elisp
;; would also put a JSON round-trip of Claude's live settings file inside the
;; Emacs that is the desktop.
;;
;; Resolved through EMANIX_BIN_DIR rather than hardcoded: this file is copied
;; into the store, so a literal ~/dotfiles path would be wrong on any host that
;; checks out elsewhere.
(defun scott/theme-apply-personal (plan)
  "Point pi and Claude Code at the theme described by PLAN."
  (let ((bin (or (getenv "EMANIX_BIN_DIR")
                 (expand-file-name "~/dotfiles/bin"))))
    (call-process (expand-file-name "dot-theme-apply-pi" bin) nil nil nil
                  (plist-get plan :name) (plist-get plan :dir))
    (call-process (expand-file-name "dot-theme-apply-claude" bin) nil nil nil
                  (plist-get plan :variant))))

(with-eval-after-load 'emanix-theme
  (add-to-list 'emanix/theme-apply-functions #'scott/theme-apply-personal))
```

- [ ] **Step 2: Replace `bin/dot-theme-set`**

```bash
#!/usr/bin/env bash
# bin/dot-theme-set — apply a theme.
#
# A WRAPPER. The authority is `emanix/theme-set' in Emacs, which writes the
# state markers, links every per-app theme file, calls gsettings, signals
# ghostty and runs the consumer's registrations (see
# home/scott/emacs/personal.el). This script used to be that orchestrator and
# called Emacs last, as a client; the inversion landed 2026-09-11 and the
# design is in the emanix repo at
# docs/superpowers/specs/2026-09-11-theme-authority-inversion-design.md
#
# Every host runs an Emacs -- the EWM build on workstations, a systemd user
# daemon elsewhere (emacs-daemon.nix) -- so there is no host where this cannot
# reach one. If it cannot, that is a broken session, not a missing fallback.
set -euo pipefail

THEME_NAME="${1:-}"

if [[ -z "$THEME_NAME" ]]; then
    echo "Usage: dot-theme-set <theme-name>"
    echo ""
    echo "Available themes:"
    if [[ -n "${EMANIX_THEMES_DIR:-}" ]] && [[ -d "$EMANIX_THEMES_DIR" ]]; then
        for d in "$EMANIX_THEMES_DIR"/*/; do
            n=$(basename "$d")
            v=$(cat "$d/variant" 2>/dev/null || echo "?")
            printf "  %-20s (%s)\n" "$n" "$v"
        done
    else
        echo "  (EMANIX_THEMES_DIR unset or missing — rebuild this host)"
    fi
    exit 1
fi

EMACSCLIENT="$(command -v emacsclient || true)"
if [[ -z "$EMACSCLIENT" ]]; then
    echo "dot-theme-set: no emacsclient on PATH; Emacs owns the theme switch" >&2
    exit 1
fi

result=$("$EMACSCLIENT" -e "(emanix/theme-set \"$THEME_NAME\")" 2>&1) || {
    echo "dot-theme-set: emacsclient failed: $result" >&2
    exit 1
}

# emanix/theme-set returns the Emacs theme symbol, or nil for an unknown name.
if [[ "$result" == "nil" ]]; then
    echo "dot-theme-set: '$THEME_NAME' is not a theme (or no theme could load)" >&2
    exit 1
fi

echo "Switched to $THEME_NAME"
```

- [ ] **Step 3: Replace `bin/dot-theme-toggle`**

```bash
#!/usr/bin/env bash
# bin/dot-theme-toggle — flip between the last-applied dark and light themes.
#
# A WRAPPER, like dot-theme-set. The logic is `emanix/theme-toggle' in Emacs,
# which is also bound to C-c v — this script's predecessor carried a header
# noting that nothing bound it, which the 2026-09-11 inversion fixed by moving
# it somewhere bindable.
set -euo pipefail

EMACSCLIENT="$(command -v emacsclient || true)"
if [[ -z "$EMACSCLIENT" ]]; then
    echo "dot-theme-toggle: no emacsclient on PATH; Emacs owns the theme switch" >&2
    exit 1
fi

result=$("$EMACSCLIENT" -e '(emanix/theme-toggle)' 2>&1) || {
    echo "dot-theme-toggle: emacsclient failed: $result" >&2
    exit 1
}

if [[ "$result" == "nil" ]]; then
    echo "dot-theme-toggle: no theme of the opposite variant is available" >&2
    exit 1
fi
```

- [ ] **Step 4: Check**

```bash
cd ~/dotfiles
nix run nixpkgs#shellcheck -- bin/dot-theme-set bin/dot-theme-toggle
nix flake check --override-input emanix path:/home/scott/projects/emanix
```

Expected: no shellcheck findings; `all checks passed!`.

- [ ] **Step 5: Commit**

```bash
git add bin/dot-theme-set bin/dot-theme-toggle home/scott/emacs/personal.el
git commit -m "theme: dot-theme-set becomes a wrapper; register the personal hook"
```

---

### Task 10: Documentation

**Files:**
- Modify: `~/docs/org/websites/emanix/pages/docs/theming.org`
- Modify: `~/dotfiles/docs/manual/01-tools.md:33,146-147`
- Modify: `~/dotfiles/docs/manual/03-roll-your-own.md:12`
- Modify: `~/dotfiles/docs/manual/02-philosophy.md:115`
- Modify: `~/dotfiles/docs/manual/README.md:25`

- [ ] **Step 1: Rewrite the theming manual's switcher story**

`theming.org` is 304 lines and names `dot-theme-set` as the switcher in roughly
sixteen places. Work through these, which is every one:

| Line | Change |
| --- | --- |
| 11-12, 24-26, 37-39 | The command table and prose: both commands are wrappers; the authority is `emanix/theme-set`, and `C-c v` toggles |
| 76 | The `last-dark` row: source of truth for `emanix/theme-toggle` |
| 94 | `gtk.conf` is now *parsed* by Emacs, not `source`d by bash |
| 111, 131 | pi: `dot-theme-apply-pi`, called from `emanix/theme-apply-functions` |
| 122 | ghostty: the switcher is Emacs |
| 139-140 | Firefox: unchanged, still build-time-only — but the sentence names `dot-theme-set` as "the runtime switcher"; say `emanix/theme-set` |
| 160 | The Emacs handoff paragraph: delete it. There is no handoff any more |
| 182-185 | The `dot-theme-toggle` section: rewrite as the wrapper it now is |
| 213-216 | "Adding a theme": the walkthrough still works; the command is unchanged |
| 244 | **Delete the "No keybinding for `dot-theme-toggle`" known limitation.** This work closes it |

Add a new subsection documenting `emanix/theme-apply-functions` as the consumer
extension point, and a sentence in the swaylock area noting it now follows
runtime switches (it was not previously mentioned at all, because it did not).

- [ ] **Step 2: Publish the site**

```bash
cd ~/docs/org/websites/emanix && emacs --script publish.el
```

Expected: output written under `output/docs/theming.html` with no errors.

- [ ] **Step 3: Update the dotfiles manual rows**

In `01-tools.md`, the two `bin/` table rows:

```markdown
| `dot-theme-set <name>` | Apply a theme. A wrapper — `emanix/theme-set` in Emacs is the authority (see the Emanix manual's theming page) |
| `dot-theme-toggle` | Flip dark/light. A wrapper for `emanix/theme-toggle`, which is bound to `C-c v` |
```

In `03-roll-your-own.md:12`, the `dot-*` helper list is unchanged in membership;
no edit needed unless it describes what the theme helpers do.

- [ ] **Step 4: Fix the four stale `02-theming.md` pointers**

No such file exists in either repo; the manual is `theming.org`, published at
`https://emanix.net/docs/theming.html`. Replace in all four places
(`docs/manual/README.md:25`, `02-philosophy.md:115`, `01-tools.md:33`, and the
two rows just edited) with:

```markdown
the Emanix manual's theming page (https://emanix.net/docs/theming.html)
```

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add docs/
git commit -m "docs: Emacs owns the theme switch; fix four dead manual pointers"
cd ~/docs/org/websites/emanix
# The website tree is syncthing-synced, not a git repo — nothing to commit.
```

---

### Task 11: End-to-end verification on a real host

**Files:** none modified. This task is the acceptance gate.

- [ ] **Step 1: Rebuild**

```bash
cd ~/dotfiles
nix build --no-link .#nixosConfigurations.rafik.config.system.build.toplevel
sudo nixos-rebuild switch --flake .#rafik
```

The `--override-input` used during development is gone: Task 7 updated the
lock, so the plain command is the correct one now. If it is still needed, Task 7
did not complete.

- [ ] **Step 2: Reload the elisp into the running session**

On an EWM host, `nixos-rebuild switch` does not restart Emacs — Emacs is the
compositor. Load the new module in place (this is what `emanix.src.liveElisp`
exists for):

```bash
emacsclient -e '(load (expand-file-name "emanix-theme.el" (file-truename "~/.config/emacs/lisp")) nil t)'
emacsclient -e '(load "~/.config/emacs/personal.el" nil t)'
```

- [ ] **Step 3: Switch, and check every target**

```bash
current=$(cat ~/.config/dotfiles/active-theme)
dot-theme-set high-contrast-light

cat ~/.config/dotfiles/active-theme          # high-contrast-light
cat ~/.config/dotfiles/last-light            # high-contrast-light
readlink ~/.config/ghostty/theme.conf        # .../high-contrast-light.conf
readlink ~/.config/btop/themes/active.theme  # .../high-contrast-light/btop.theme
readlink ~/.config/swaylock/config           # .../high-contrast-light/swaylock.conf
gsettings get org.gnome.desktop.interface color-scheme   # 'prefer-light'
python3 -c 'import json;print(json.load(open("/home/scott/.claude/settings.json"))["theme"])'
python3 -c 'import json;print(json.load(open("/home/scott/.pi/agent/settings.json"))["theme"])'
ls -l ~/.claude/settings.json                # STILL a symlink
```

Expected: every line agrees with the theme just applied. The swaylock line is
the one that could not have passed before this work.

- [ ] **Step 4: Toggle both ways**

```bash
dot-theme-toggle && cat ~/.config/dotfiles/active-theme
emacsclient -e '(emanix/theme-toggle)' && cat ~/.config/dotfiles/active-theme
```

Then press `C-c v` in a live frame and confirm the colours flip.

- [ ] **Step 5: Prove the converging startup path**

```bash
mv ~/.config/dotfiles/active-theme /tmp/active-theme.bak
emacsclient -e '(emanix/theme-init)'
cat ~/.config/dotfiles/active-theme    # recreated, naming the default
readlink ~/.config/swaylock/config     # relinked, not merely the Emacs theme
```

- [ ] **Step 6: Restore**

```bash
dot-theme-set "$current"
rm -f /tmp/active-theme.bak
```

- [ ] **Step 7: Confirm the rebuild does not fight the switcher**

```bash
sudo nixos-rebuild switch --flake .#rafik
ls ~/.config/swaylock/                 # NO config.hm-bak
readlink ~/.config/swaylock/config     # still points at the theme you chose
```

This is the assertion that Task 6 Step 3 exists for. A `config.hm-bak` here
means Home Manager still owns the path and the module was not fully removed.
