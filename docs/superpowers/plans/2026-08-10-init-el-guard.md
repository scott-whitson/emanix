# init.el Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a failure anywhere in Scott's Emacs configuration cost the failing feature and nothing else, so a bad form can no longer take down the EWM desktop.

**Architecture:** `init.el` becomes a ~25-line loader that `load`s `config.el` inside a `condition-case`; on failure it records the error and loads `fallback.el`, which restores the minimum viable desktop from `lisp/` modules. The 8 `scott/ewm-*` window commands move to `lisp/scott-ewm-slots.el` first so the fallback requires them rather than duplicating them.

**Tech Stack:** Emacs 30.2 elisp, Home Manager (`xdg.configFile`), `emacs --batch` for tests.

**Spec:** `docs/superpowers/specs/2026-08-10-init-el-guard-design.md`. Read its Decisions and "Facts that shape the design" sections before starting.

## Global Constraints

- **Never add `Co-Authored-By` or tool-attribution trailers to commits.**
- All `.nix` files must pass `nixpkgs-fmt --check` before commit.
- **Never use `forward-sexp` in a loop to check parens** — it does not terminate at end-of-buffer and hangs the process. To check a file reads cleanly, use `read` in a `condition-case` catching `end-of-file`.
- **Never send anything to a running Emacs via `emacsclient`.** A live EWM session is the user's desktop; an errant eval can wedge it. All testing is `emacs --batch` in a fresh process.
- **`lisp/scott-ewm-slots.el` must NOT `(require 'ewm)`.** Emacs is started `--fg-daemon --eval (require 'ewm) --eval (ewm-start-module)`, and Emacs processes `--eval` *after* loading init — so `ewm` does not exist yet while init runs. The existing code resolves `ewm--focused-frame`, `ewm-frame-new`, `ewm--strip-frames` and `ewm-workspace-rename` at **call** time behind `fboundp`/`bound-and-true-p`. Preserve that.
- `~/.config/emacs/init.el` is an out-of-store symlink into the checkout (`liveElisp`), so **edits to the repo are immediately live on rafik**. Never leave the working tree in a state where init.el is broken.
- Build check: `for h in rafik whistle datacore; do nix build --no-link --print-out-paths .#nixosConfigurations.$h.config.system.build.toplevel; done`
- `datacore`'s closure must remain `kj54bwyp7i0clcw3zy0j2mcfrfl14vx4-nixos-system-datacore-26.11.20260705.d407951`.

## File Structure

| File | Responsibility |
|---|---|
| `ioshi/i-intelligence/emacs/lisp/scott-ewm-slots.el` | **Create.** The 8 `scott/ewm-*` commands, extracted. `provide`s `scott-ewm-slots`. |
| `ioshi/i-intelligence/emacs/fallback.el` | **Create.** Minimum viable desktop; nothing that can fail. |
| `ioshi/i-intelligence/emacs/config.el` | **Create** (from `init.el`). All current configuration. Free to break. |
| `ioshi/i-intelligence/emacs/init.el` | **Rewrite.** Loader only. |
| `ioshi/i-intelligence/emacs.nix` | **Modify.** Deploy `config.el` and `fallback.el` alongside `init.el`. |
| `tests/init-guard.sh` | **Create.** The regression suite: healthy path plus both 2026-08-10 faults. |
| `docs/manual/01-keybindings.md` | **Modify.** Document the split; fix two now-stale `init.el` references. That chapter is the EWM chapter, not `03-tools.md`. |
| `bin/dot-context` | **Modify.** Add the two new live symlinks to its inventory. |
| `bin/dot-doctor` | **Modify.** Check `config.el`/`fallback.el` are present; fix two Emacs checks that are false on rafik. |
| `ioshi/i-intelligence/emacs/packages.nix` | **Modify.** Two comments name `init.el` for code now in `config.el`. |

---

## Task 1: Extract the EWM slot commands into `lisp/scott-ewm-slots.el`

**Agent-executable.**

**Files:**
- Create: `ioshi/i-intelligence/emacs/lisp/scott-ewm-slots.el`
- Modify: `ioshi/i-intelligence/emacs/init.el` (remove the extracted functions, add a `require`)

**Interfaces:**
- Produces: feature `scott-ewm-slots`, providing `scott/ewm-launch-firefox`, `scott/ewm--slot-frame`, `scott/ewm--goto`, `scott/ewm-close-slot`, `scott/ewm-select-slot`, `scott/ewm-rename-workspace`, `scott/ewm--slot-label`, `scott/ewm-tab-bar-slots`. Task 2's `fallback.el` requires this feature; `init.el` (later `config.el`) requires it too.

**Why this is first:** it is what keeps the fallback thin. A fallback that redefines these would be a second copy of working window-management code, and it would rot.

- [ ] **Step 1: Record the exact current surface, so the extraction can be proved lossless**

```bash
cd ~/dotfiles/ioshi/i-intelligence/emacs
timeout 180 emacs --batch -l init.el --eval '(message "BEFORE %S" (sort (delq nil (mapcar (lambda (f) (and (fboundp f) f)) (list (quote scott/ewm-launch-firefox) (quote scott/ewm--slot-frame) (quote scott/ewm--goto) (quote scott/ewm-close-slot) (quote scott/ewm-select-slot) (quote scott/ewm-rename-workspace) (quote scott/ewm--slot-label) (quote scott/ewm-tab-bar-slots)))) (lambda (a b) (string< (symbol-name a) (symbol-name b)))))' 2>&1 | grep "^BEFORE"
```

Expected: all eight symbols listed. Save that line — Step 5 compares against it.

- [ ] **Step 2: Create the module with the extracted functions**

Create `lisp/scott-ewm-slots.el`. Move the **entire region from the `(defun scott/ewm-launch-firefox ...)` form through the end of the `(defun scott/ewm-tab-bar-slots ...)` form** out of `init.el` and into this file, between the header and the `provide` below. Move the code verbatim — do not reformat, rename, or "improve" it.

```elisp
;;; scott-ewm-slots.el --- EWM slot navigation and the tab-bar slot list -*- lexical-binding: t; -*-

;; Extracted from init.el on 2026-08-10. These commands ARE the window
;; management on rafik, where Emacs is the Wayland compositor, and they used to
;; sit below every package `require' in init.el — so any package that failed to
;; load took them with it. They live here so both the normal path (config.el)
;; and the fallback (fallback.el) can require them instead of one duplicating
;; the other.
;;
;; DELIBERATELY NO (require 'ewm). Emacs is started
;;   --fg-daemon --eval (require 'ewm) --eval (ewm-start-module)
;; and Emacs processes --eval arguments AFTER loading init, so `ewm' does not
;; exist while this file loads. The ewm--focused-frame / ewm-frame-new /
;; ewm--strip-frames / ewm-workspace-rename references below are resolved at
;; CALL time, guarded by fboundp / bound-and-true-p. Adding a require here
;; would break startup on every host.

;;; <-- extracted functions go here, verbatim -->

(provide 'scott-ewm-slots)
;;; scott-ewm-slots.el ends here
```

- [ ] **Step 3: Require the new module from `init.el`**

At the point in `init.el` where the extracted block used to begin, put:

```elisp
;; Window-management commands, extracted 2026-08-10 to lisp/scott-ewm-slots.el
;; so fallback.el can require them too. See that file's header for why it must
;; not require `ewm'.
(require 'scott-ewm-slots nil :no-error)
```

`:no-error` deliberately: this is the file that must not be able to abort init.

- [ ] **Step 4: Confirm the module does not pull in `ewm`**

```bash
cd ~/dotfiles/ioshi/i-intelligence/emacs
grep -n "require 'ewm\|require (quote ewm)" lisp/scott-ewm-slots.el && echo "FAIL: must not require ewm" || echo "correct: no ewm require"
timeout 120 emacs --batch -L lisp --eval '(progn (require (quote scott-ewm-slots)) (message "LOADS-STANDALONE ewm-loaded=%s slot-fns=%d" (featurep (quote ewm)) (length (delq nil (mapcar (function fboundp) (list (quote scott/ewm--goto) (quote scott/ewm-close-slot) (quote scott/ewm-select-slot) (quote scott/ewm-tab-bar-slots)))))))' 2>&1 | grep "^LOADS-STANDALONE"
```

Expected: `correct: no ewm require`, then `LOADS-STANDALONE ewm-loaded=nil slot-fns=4`. The module must load with `ewm` **absent** — that is the startup condition on every host.

- [ ] **Step 5: Prove the extraction is lossless**

```bash
cd ~/dotfiles/ioshi/i-intelligence/emacs
timeout 180 emacs --batch -l init.el --eval '(message "AFTER %S" (sort (delq nil (mapcar (lambda (f) (and (fboundp f) f)) (list (quote scott/ewm-launch-firefox) (quote scott/ewm--slot-frame) (quote scott/ewm--goto) (quote scott/ewm-close-slot) (quote scott/ewm-select-slot) (quote scott/ewm-rename-workspace) (quote scott/ewm--slot-label) (quote scott/ewm-tab-bar-slots)))) (lambda (a b) (string< (symbol-name a) (symbol-name b)))))' 2>&1 | grep "^AFTER"
```

Expected: the same eight symbols as Step 1, and `tab-bar-format` still wires `scott/ewm-tab-bar-slots`:

```bash
timeout 180 emacs --batch -l init.el --eval '(message "TABBAR %S show=%s" tab-bar-format tab-bar-show)' 2>&1 | grep "^TABBAR"
```

Expected: `(scott/ewm-tab-bar-slots tab-bar-format-align-right scott/tab-bar-status)` and `show=t`.

- [ ] **Step 6: Confirm init.el still reads cleanly and all three hosts build**

```bash
cd ~/dotfiles
timeout 120 emacs --batch --eval '(with-temp-buffer (insert-file-contents "ioshi/i-intelligence/emacs/init.el") (goto-char (point-min)) (let ((n 0)) (condition-case e (while t (read (current-buffer)) (setq n (1+ n))) (end-of-file (message "READS-CLEAN %d forms" n)) (error (message "PARSE ERROR: %S" e)))))' 2>&1 | grep -E "READS-CLEAN|PARSE"
for h in rafik whistle datacore; do printf "%-9s " $h; nix build --no-link --print-out-paths .#nixosConfigurations.$h.config.system.build.toplevel; done
```

- [ ] **Step 7: Commit**

```bash
cd ~/dotfiles
git add ioshi/i-intelligence/emacs/lisp/scott-ewm-slots.el ioshi/i-intelligence/emacs/init.el
git commit -m "refactor(emacs): extract the EWM slot commands into lisp/

The 8 scott/ewm-* commands are window management on rafik, where Emacs is the
Wayland compositor, and they sat below every package require in init.el — so
any package that failed to load took window navigation with it. That happened
twice on 2026-08-10.

Moving them to lisp/scott-ewm-slots.el lets the upcoming fallback require them
instead of duplicating them, which is what keeps the fallback thin enough to
stay correct.

The module deliberately does NOT require ewm: Emacs is started with
--eval (require 'ewm), which is processed AFTER init loads, so ewm does not
exist yet. The ewm-* references resolve at call time behind fboundp, exactly as
before. Verified the module loads standalone with ewm absent.

Extraction proved lossless: the same eight symbols are defined after as before,
and tab-bar-format still wires scott/ewm-tab-bar-slots."
```

---

## Task 2: Create `fallback.el` and deploy it

**Agent-executable.**

**Files:**
- Create: `ioshi/i-intelligence/emacs/fallback.el`
- Modify: `ioshi/i-intelligence/emacs.nix`

**Interfaces:**
- Consumes: feature `scott-ewm-slots` from Task 1.
- Produces: `fallback.el` at `~/.config/emacs/fallback.el`, and `scott/fallback-tab-bar-item`. Task 3's loader loads this file by name.

**Why the fallback is built before the loader:** it is independently testable. Loading it directly must produce a working desktop surface, and that can be proved before anything depends on it.

- [ ] **Step 1: Write the fallback**

Create `ioshi/i-intelligence/emacs/fallback.el`:

```elisp
;;; fallback.el --- minimum viable desktop -*- lexical-binding: t; -*-

;; Loaded by init.el ONLY when config.el failed to load. On rafik Emacs is the
;; Wayland compositor, so "config.el has an error" means "no top bar, no s-d,
;; no window navigation" — which happened twice on 2026-08-10 from unrelated
;; faults (an unbalanced paren, and a bare require that signalled).
;;
;; Two rules for this file:
;;
;; 1. Nothing here may fail. No package requires, no :vc, no network. Only
;;    lisp/ modules, which are plain elisp from the checkout.
;; 2. Every form is individually guarded, so a fault in one still leaves the
;;    rest applied. A fallback that collapses is not a fallback.
;;
;; Scope is what was actually lost in those incidents, not a guess: the top bar,
;; the launcher, the EWM slot commands and a theme. Completion, meow, magit,
;; org, apheleia and the rest are recoverable by fixing config.el and are not
;; the desktop.

(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

;; require with :no-error returns nil for a missing file, but can still signal
;; on an error INSIDE the file — hence the condition-case as well.
(dolist (feature '(scott-ewm-slots scott-modeline scott-launcher scott-theme))
  (condition-case e
      (require feature nil :no-error)
    (error (message "fallback: %s failed to load: %S" feature e))))

(condition-case e
    (when (fboundp 'scott/theme-init) (scott/theme-init))
  (error (message "fallback: theme-init failed: %S" e)))

(condition-case e
    (when (fboundp 'scott/modeline-mode) (scott/modeline-mode 1))
  (error (message "fallback: modeline-mode failed: %S" e)))

(condition-case e
    (when (fboundp 'scott/launch-app)
      (global-set-key (kbd "C-c o") #'scott/launch-app))
  (error (message "fallback: launcher binding failed: %S" e)))

(defun scott/fallback-tab-bar-item ()
  "Tab-bar item announcing that `config.el' failed to load.
Deliberately loud. A silent degraded mode is worse than a hard failure: on
2026-08-10 a broken config survived a reboot without being noticed, and the
visible symptoms pointed somewhere other than the fault."
  `((fallback menu-item
              ,(propertize " ⚠ CONFIG FAILED — see scott/init-error "
                           'face 'error)
              ignore)))

(condition-case e
    (progn
      (setq tab-bar-format
            (append '(scott/fallback-tab-bar-item)
                    (and (fboundp 'scott/ewm-tab-bar-slots)
                         '(scott/ewm-tab-bar-slots))
                    '(tab-bar-format-align-right)
                    (and (fboundp 'scott/tab-bar-status)
                         '(scott/tab-bar-status))))
      (setq tab-bar-show t)
      (tab-bar-mode 1))
  (error (message "fallback: tab-bar setup failed: %S" e)))

(provide 'fallback)
;;; fallback.el ends here
```

- [ ] **Step 2: Prove the fallback alone yields a working desktop surface**

```bash
cd ~/dotfiles/ioshi/i-intelligence/emacs
timeout 180 emacs --batch --init-directory "$PWD" --eval '(progn (load (expand-file-name "fallback.el" user-emacs-directory) nil :nomessage) (message "FALLBACK-ALONE modeline=%s launch=%s ewmgoto=%s slots=%s theme=%s marker=%s tabbar=%S" (fboundp (quote scott/modeline-mode)) (fboundp (quote scott/launch-app)) (fboundp (quote scott/ewm--goto)) (fboundp (quote scott/ewm-tab-bar-slots)) (if custom-enabled-themes "yes" "no") (fboundp (quote scott/fallback-tab-bar-item)) (car tab-bar-format)))' 2>&1 | grep "^FALLBACK-ALONE"
```

Expected: every capability `t`, `theme=yes`, and `tabbar=scott/fallback-tab-bar-item` **first** in the list so the warning is leftmost.

- [ ] **Step 3: Prove the fallback degrades rather than collapses**

Break one form inside a copy and confirm the others still apply:

```bash
cd ~/dotfiles/ioshi/i-intelligence/emacs
D=$(mktemp -d); cp fallback.el "$D/"; cp -r lisp "$D/lisp"
# make the theme step signal, leaving the rest of the file intact
python3 - "$D/fallback.el" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("(when (fboundp 'scott/theme-init) (scott/theme-init))",
              "(error \"deliberate test failure\")", 1)
open(p, "w").write(s)
PY
timeout 180 emacs --batch --init-directory "$D" --eval '(progn (load (expand-file-name "fallback.el" user-emacs-directory) nil :nomessage) (message "DEGRADED modeline=%s launch=%s marker=%s" (fboundp (quote scott/modeline-mode)) (fboundp (quote scott/launch-app)) (fboundp (quote scott/fallback-tab-bar-item))))' 2>&1 | grep -E "^DEGRADED|theme-init failed"
```

Expected: a `fallback: theme-init failed:` message **and** `DEGRADED modeline=t launch=t marker=t`. If the later forms are missing, the per-form guarding is wrong.

- [ ] **Step 4: Deploy it via `emacs.nix`**

In `ioshi/i-intelligence/emacs.nix`, after the existing `xdg.configFile."emacs/init.el"` block, add — following the same `liveElisp` shape as its siblings:

```nix
  # config.el and fallback.el are deployed exactly like init.el. If fallback.el
  # is ever missing, the loader's (load ... :noerror) degrades to "no fallback"
  # silently — so a missing entry here would make the guard look fine until the
  # moment it is needed. tests/init-guard.sh asserts against a deployed layout.
  xdg.configFile."emacs/config.el".source =
    if config.scott.dotfiles.liveElisp
    then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/config.el"
    else ./emacs/config.el;
  xdg.configFile."emacs/fallback.el".source =
    if config.scott.dotfiles.liveElisp
    then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/fallback.el"
    else ./emacs/fallback.el;
```

**`config.el` does not exist until Task 3.** A `mkOutOfStoreSymlink` to a missing path is a dangling symlink, which evaluates and builds fine (it is only a string), but the non-`liveElisp` branch `./emacs/config.el` would fail to evaluate. So in **this** task add only the `fallback.el` block, and add the `config.el` block in Task 3 alongside creating the file. Note that ordering in the commit message.

- [ ] **Step 5: Build and commit**

```bash
cd ~/dotfiles
nixpkgs-fmt --check ioshi/i-intelligence/emacs.nix
for h in rafik whistle datacore; do printf "%-9s " $h; nix build --no-link --print-out-paths .#nixosConfigurations.$h.config.system.build.toplevel; done
nix eval --json .#nixosConfigurations.rafik.config.home-manager.users.scott.xdg.configFile --apply 'f: builtins.filter (n: builtins.match "emacs/.*" n != null) (builtins.attrNames f)'
```

Expected: the eval lists `emacs/early-init.el`, `emacs/init.el`, `emacs/lisp` and `emacs/fallback.el`.

```bash
git add ioshi/i-intelligence/emacs/fallback.el ioshi/i-intelligence/emacs.nix
git commit -m "feat(emacs): add fallback.el, a minimum viable desktop

Loaded only when config.el fails (Task 3 wires the loader). Restores what was
actually lost when init.el aborted on 2026-08-10: the top bar, the launcher,
the EWM slot commands and a theme. Everything else — completion, meow, magit,
org — is recoverable by fixing config.el and is not the desktop.

Contains nothing that can fail: no package requires, no :vc, no network, only
lisp/ modules. Every form is individually guarded, verified by deliberately
breaking one form and confirming the rest still apply.

Announces itself with a leftmost tab-bar warning. A silent degraded mode is
worse than a hard failure: the broken config survived a reboot unnoticed,
and the visible symptoms pointed away from the fault.

Only fallback.el is deployed here. config.el does not exist yet, and the
non-liveElisp branch of emacs.nix would fail to evaluate on a missing path, so
its xdg.configFile entry lands in Task 3 with the file itself."
```

---

## Task 3: Split `init.el` into a loader plus `config.el`

**Agent-executable, and the one that changes how Emacs starts. Read the whole task before editing anything.**

**Files:**
- Create: `ioshi/i-intelligence/emacs/config.el` (from the current `init.el`)
- Rewrite: `ioshi/i-intelligence/emacs/init.el`
- Modify: `ioshi/i-intelligence/emacs.nix`
- Create: `tests/init-guard.sh`

**Interfaces:**
- Consumes: `fallback.el` and `scott/fallback-tab-bar-item` from Task 2; feature `scott-ewm-slots` from Task 1.
- Produces: `scott/init-error` — nil on a healthy boot, otherwise the error object that aborted `config.el`. Queryable over ssh.

**The hazard:** `~/.config/emacs/init.el` is an out-of-store symlink into the checkout, so **the moment you write init.el the running Emacs on rafik will use it on next start.** Do the rename first, verify, and never leave the tree with a broken init.el.

- [ ] **Step 1: Write the regression suite first — it must fail before the loader exists**

Create `tests/init-guard.sh` (mode 755):

```bash
#!/usr/bin/env bash
# Asserts that a broken config.el cannot take the desktop down.
#
# Both faults tested here really happened on 2026-08-10 and both cost the top
# bar, s-d and window navigation:
#   - a read-time failure  (unbalanced paren -> "End of file during parsing")
#   - a load-time failure  (a bare require that signalled)
#
# Everything runs in emacs --batch against a temp directory. Never point this
# at ~/.config/emacs, and never use emacsclient: a live EWM session is the
# user's desktop.
set -uo pipefail

EMACS="${EMACS:-emacs}"
SRC="$(cd "$(dirname "$0")/.." && pwd)/ioshi/i-intelligence/emacs"
FAILURES=0

PROBE='(message "PROBE fellback=%s modeline=%s launch=%s ewmgoto=%s theme=%s"
         (if scott/init-error "yes" "no")
         (fboundp (quote scott/modeline-mode))
         (fboundp (quote scott/launch-app))
         (fboundp (quote scott/ewm--goto))
         (if custom-enabled-themes "yes" "no"))'

layout() {  # $1 = destination dir; build a deployed-shaped config tree
  mkdir -p "$1"
  cp "$SRC/init.el" "$SRC/config.el" "$SRC/fallback.el" "$1/"
  cp -r "$SRC/lisp" "$1/lisp"
}

probe() {   # $1 = init dir
  timeout 240 "$EMACS" --batch --init-directory "$1" --eval "$PROBE" 2>&1 \
    | grep '^PROBE' | tail -1
}

check() {   # $1 = label, $2 = expected substring, $3 = actual
  if [[ "$3" == *"$2"* ]]; then
    echo "  PASS  $1"
  else
    echo "  FAIL  $1"
    echo "        expected to contain: $2"
    echo "        got:                 $3"
    FAILURES=$((FAILURES + 1))
  fi
}

echo "1. healthy path — must be unchanged, and must NOT report a fallback"
D=$(mktemp -d); layout "$D"
R=$(probe "$D")
check "healthy: no fallback"   "fellback=no"  "$R"
check "healthy: modeline"      "modeline=t"   "$R"
check "healthy: launcher"      "launch=t"     "$R"
check "healthy: ewm commands"  "ewmgoto=t"    "$R"
check "healthy: theme"         "theme=yes"    "$R"

echo "2. read-time failure — unbalanced paren (the 2026-08-10 morning fault)"
D=$(mktemp -d); layout "$D"
printf '\n(when t\n' >> "$D/config.el"   # deliberately unclosed
R=$(probe "$D")
check "paren: fell back"       "fellback=yes" "$R"
check "paren: modeline"        "modeline=t"   "$R"
check "paren: launcher"        "launch=t"     "$R"
check "paren: ewm commands"    "ewmgoto=t"    "$R"

echo "3. load-time failure — a require that signals (the evening fault)"
D=$(mktemp -d); layout "$D"
python3 - "$D/config.el" <<'PY'
import sys
p = sys.argv[1]; lines = open(p).read().split("\n")
lines.insert(1, "(require 'a-package-that-does-not-exist)")
open(p, "w").write("\n".join(lines))
PY
R=$(probe "$D")
check "require: fell back"     "fellback=yes" "$R"
check "require: modeline"      "modeline=t"   "$R"
check "require: launcher"      "launch=t"     "$R"
check "require: ewm commands"  "ewmgoto=t"    "$R"

echo
if (( FAILURES == 0 )); then
  echo "init-guard: all checks passed"
else
  echo "init-guard: $FAILURES check(s) failed"
  exit 1
fi
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd ~/dotfiles && chmod 755 tests/init-guard.sh && ./tests/init-guard.sh
```

Expected: **failures**. `config.el` does not exist yet, so `layout` cannot copy it and every probe comes back empty or wrong. That is the correct starting state — it proves the test can detect the absence of the guard.

- [ ] **Step 3: Rename `init.el` to `config.el` with git, preserving history**

```bash
cd ~/dotfiles/ioshi/i-intelligence/emacs
git mv init.el config.el
git status --short
```

- [ ] **Step 4: Write the new loader**

Create `ioshi/i-intelligence/emacs/init.el`:

```elisp
;;; init.el --- loader -*- lexical-binding: t; -*-

;; This file must never break, so it is deliberately tiny and rarely edited.
;; The real configuration is config.el; a failure there is caught here.
;;
;; Why a separate file rather than a condition-case inside the config: a signal
;; raised inside a `load'ed file propagates to its CALLER, so this catches both
;; failure modes seen on 2026-08-10 —
;;
;;   read-time  an unbalanced paren, "End of file during parsing". Nothing
;;              inside config.el could ever catch this, because none of it runs.
;;   load-time  a bare (require 'gdocs) that signalled because
;;              ~/.config/emacs/elpa is not on load-path.
;;
;; Both aborted every remaining form, and on rafik — where Emacs is the Wayland
;; compositor — that meant no top bar, no s-d and no window navigation. EWM
;; itself survived both times, because it is started from --eval on the command
;; line, which Emacs processes after init.
;;
;; Keep this under ~30 lines. It is unguarded by construction: there is no
;; outer file to catch a mistake made here.

(defvar scott/init-error nil
  "The error that aborted `config.el', or nil on a healthy boot.
Check it with: emacsclient -e \\='scott/init-error\\='.
When non-nil, `fallback.el' ran and the tab bar says so.")

(condition-case err
    ;; NOERROR nil on purpose: config.el MUST signal so the handler runs.
    (load (expand-file-name "config.el" user-emacs-directory) nil :nomessage)
  (error
   (setq scott/init-error err)
   (message "scott/init: config.el FAILED (%S) — loading fallback.el" err)
   ;; NOERROR t here: if fallback.el is missing too, do not cascade.
   (load (expand-file-name "fallback.el" user-emacs-directory)
         :noerror :nomessage)))

;;; init.el ends here
```

- [ ] **Step 5: Add the `config.el` deployment to `emacs.nix`**

Add, beside the `fallback.el` entry from Task 2:

```nix
  xdg.configFile."emacs/config.el".source =
    if config.scott.dotfiles.liveElisp
    then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/config.el"
    else ./emacs/config.el;
```

- [ ] **Step 6: Run the regression suite — it must now pass**

```bash
cd ~/dotfiles && ./tests/init-guard.sh
```

Expected: `init-guard: all checks passed`, with 13 PASS lines. In particular the healthy case must report `fellback=no` — if it reports `yes`, the loader is catching an error on the normal path and something in the split went wrong.

- [ ] **Step 7: Confirm both new files read cleanly and the hosts build**

```bash
cd ~/dotfiles
for f in ioshi/i-intelligence/emacs/init.el ioshi/i-intelligence/emacs/config.el ioshi/i-intelligence/emacs/fallback.el; do
  printf "%-50s " "$f"
  timeout 120 emacs --batch --eval "(with-temp-buffer (insert-file-contents \"$f\") (goto-char (point-min)) (let ((n 0)) (condition-case e (while t (read (current-buffer)) (setq n (1+ n))) (end-of-file (message \"READS-CLEAN %d forms\" n)) (error (message \"PARSE ERROR %S\" e)))))" 2>&1 | grep -E "READS-CLEAN|PARSE"
done
wc -l ioshi/i-intelligence/emacs/init.el
nixpkgs-fmt --check ioshi/i-intelligence/emacs.nix
for h in rafik whistle datacore; do printf "%-9s " $h; nix build --no-link --print-out-paths .#nixosConfigurations.$h.config.system.build.toplevel; done
```

Expected: all three read clean, `init.el` under 40 lines, datacore unchanged.

- [ ] **Step 8: Commit**

```bash
cd ~/dotfiles
git add ioshi/i-intelligence/emacs/init.el ioshi/i-intelligence/emacs/config.el ioshi/i-intelligence/emacs.nix tests/init-guard.sh
git commit -m "feat(emacs): load config.el behind a guard so a bad form cannot kill the desktop

init.el becomes a ~25-line loader; the configuration moves to config.el
(git mv, so history follows). A signal raised inside a load'ed file propagates
to its caller, which is the only structure that catches BOTH failure modes seen
on 2026-08-10: an unbalanced paren, which nothing inside config.el could ever
catch because none of it runs, and a bare require that signalled.

On failure the error is recorded in scott/init-error and fallback.el runs,
restoring the top bar, the launcher, the EWM slot commands and a theme.

tests/init-guard.sh reproduces both faults against a temp copy and asserts the
desktop-critical surface survives each. It also asserts the healthy path is
unchanged and does NOT report a fallback — the likeliest way this work could do
harm is by changing behaviour when nothing is wrong."
```

---

## Task 4: Update every reference the split invalidates

**Agent-executable.**

**Files:**
- Modify: `docs/manual/01-keybindings.md`
- Modify: `bin/dot-context`
- Modify: `bin/dot-doctor`
- Modify: `ioshi/i-intelligence/emacs/packages.nix` (comments only)

**Interfaces:**
- Consumes: `scott/init-error` from Task 3; `tests/init-guard.sh`; the deployed `config.el` and `fallback.el`.

**This task is wider than documentation.** Splitting `init.el` invalidates references in two live scripts, and one of them is the natural place to detect the failure mode the whole project is guarding against.

- [ ] **Step 1: Add the section to `01-keybindings.md`**

That chapter is the EWM chapter — it opens "eminix runs **EWM** — Emacs *is* the Wayland compositor" — and is where both existing `init.el` references live. Do **not** create a new chapter, and do not put this in `03-tools.md`, which is about `bin/` wrappers.

```markdown
## Config layout: a loader, a config, and a fallback

`~/.config/emacs/` holds three top-level files. The split is a safety boundary,
not organisation:

| File | Role |
| --- | --- |
| `init.el` | ~25-line loader. Loads `config.el` inside a `condition-case`. Must never break, so it is rarely edited. |
| `config.el` | All actual configuration. Free to be edited and to break. |
| `fallback.el` | Minimum viable desktop, loaded only when `config.el` fails. |

**Why the loader is a separate file.** A signal raised inside a `load`ed file
propagates to its caller, so `init.el` catches two failures that no guard
*inside* the config could:

- a **read-time** failure such as an unbalanced paren — nothing in `config.el`
  runs, so nothing in it can catch anything;
- a **load-time** failure such as a `require` that signals.

Both happened on 2026-08-10 and both presented identically — no top bar, `s-d`
dead, no window navigation — because Emacs is the compositor here. EWM itself
survived both, since it starts from `--eval` on the command line, which Emacs
processes after init.

**How to tell you are in the fallback.** The tab bar shows a red
`⚠ CONFIG FAILED` item at the far left. For the reason:

```bash
emacsclient -e 'scott/init-error'
```

`nil` is a healthy boot. Anything else is the error that aborted `config.el`.

**What the fallback restores:** the top bar (`scott/modeline-mode`), the
launcher (`C-c o`), the `scott/ewm-*` slot commands and a theme. Not completion,
meow, magit, org or apheleia — recoverable by fixing `config.el`, and not the
desktop.

**Editing caution.** `config.el` is an out-of-store symlink into the checkout
(`liveElisp`), so an edit is live on the next Emacs start with no rebuild. That
is why the guard is a runtime one: both 2026-08-10 incidents were uncommitted
live edits, which no build-time or pre-commit check would have caught.

**Testing it:** `./tests/init-guard.sh` reproduces both faults against a temp
copy and asserts the desktop survives each, plus that a healthy config is
unaffected.
```

- [ ] **Step 2: Fix the two now-stale references in the same chapter**

Both point at `init.el` for things that now live in `config.el`:

- line ~64: "additions are in the `with-eval-after-load 'ewm` block of `init.el`" → `config.el`
- line ~85: "Config: `meow-normal-define-key` in `init.el`" → `config.el`

Verify by grep that the named forms really are in `config.el` after the split before changing the text:

```bash
cd ~/dotfiles
grep -c "with-eval-after-load 'ewm" ioshi/i-intelligence/emacs/config.el
grep -c "meow-normal-define-key" ioshi/i-intelligence/emacs/config.el
grep -n "init\.el" docs/manual/01-keybindings.md
```

Expected: both counts ≥1, and after editing, the only `init.el` mentions left in that chapter are ones that genuinely mean the loader.

- [ ] **Step 3: Add the new live symlinks to `bin/dot-context`**

Its `symlinks:` block is an inventory of the out-of-store symlinks that break when the checkout moves. Two new ones now exist and are missing from it. In the `for path in \` list, after the `init.el` entry, add:

```bash
    "$HOME/.config/emacs/config.el" \
    "$HOME/.config/emacs/fallback.el" \
```

- [ ] **Step 4: Make `bin/dot-doctor` detect a missing fallback — and stop crying wolf**

The spec's stated risk is that if `fallback.el` is not deployed, the guard looks fine until the moment it is needed. `dot-doctor` is where that belongs.

But it currently reports **9 failures on rafik**, two of them false, which makes any new check worthless — nobody reads a doctor that always fails. Both false checks are the same bug already fixed in `bin/dot-theme-set`: a hardcoded `~/.nix-profile/bin/emacsclient` that does not exist on rafik, whose EWM client is at `/run/current-system/sw/bin/emacsclient`.

Replace these two lines:

```bash
check "emacs daemon active"    "systemctl --user is-active --quiet emacs"
check "emacsclient responds"   "[[ -x \$HOME/.nix-profile/bin/emacsclient ]] && \$HOME/.nix-profile/bin/emacsclient -e t"
```

with one check that works on every host:

```bash
# One check, not two: resolving emacsclient from PATH and getting a reply proves
# the daemon is up, whereas `systemctl --user is-active emacs` is false on rafik
# (EWM's Emacs is not that unit) and ~/.nix-profile/bin/emacsclient does not
# exist there at all. Same hardcoded-path bug that was fixed in dot-theme-set.
check "emacs daemon responds"  "command -v emacsclient >/dev/null && emacsclient -e t"
```

Then add the fallback check beside the existing config-symlink one:

```bash
check "emacs config symlinked" "[[ -L \$HOME/.config/emacs/init.el ]]"
check "emacs config.el present"   "[[ -e \$HOME/.config/emacs/config.el ]]"
check "emacs fallback.el present" "[[ -e \$HOME/.config/emacs/fallback.el ]]"
```

`-e` rather than `-L`: a dangling symlink is exactly the failure worth catching, and `-e` is false for one.

- [ ] **Step 5: Fix the `packages.nix` comments**

Two comments say "fixup in init.el" and "init.el discovers whatever this list provides", referring to the tree-sitter grammar block that now lives in `config.el`. Update both to say `config.el`. Comments only — no code change.

- [ ] **Step 6: Verify every claim, and that dot-doctor improved**

```bash
cd ~/dotfiles
wc -l ioshi/i-intelligence/emacs/init.el                      # the "~25-line" claim
grep -n "CONFIG FAILED" ioshi/i-intelligence/emacs/fallback.el
grep -n "C-c o" ioshi/i-intelligence/emacs/fallback.el
grep -rn "init\.el" docs/manual/01-keybindings.md            # only loader references left
bash -n bin/dot-doctor && bash -n bin/dot-context && echo "both scripts parse"
./tests/init-guard.sh | tail -2
```

Then confirm on the host that the two false failures are gone and the new checks pass. This needs rafik, so if it is unreachable, report that rather than claiming it:

```bash
ssh rafik 'cd ~/dotfiles && ./bin/dot-doctor 2>&1 | grep -iE "emacs|failed"'
```

Expected: `emacs daemon responds` ✓, `emacs config symlinked` ✓, `config.el present` ✓, `fallback.el present` ✓, and the total failure count **lower than 9**. Report the remaining failures without fixing them — they are unrelated to this work.

- [ ] **Step 7: Commit**

```bash
cd ~/dotfiles
git add docs/manual/01-keybindings.md bin/dot-context bin/dot-doctor ioshi/i-intelligence/emacs/packages.nix
git commit -m "docs+tools: follow the init.el split through every reference

Documents the loader/config/fallback split in the EWM chapter: why the loader
must be a separate file (a signal inside a load'ed file propagates to its
caller, which is the only way to catch a read-time failure), and how to tell
you are in the fallback.

Fixes the references the split invalidated. Two in the same chapter pointed at
init.el for the ewm keybinding block and meow-normal-define-key, both now in
config.el, as do two comments in packages.nix. dot-context's symlink inventory
gained config.el and fallback.el, which are new out-of-store symlinks.

dot-doctor now checks that config.el and fallback.el are present, using -e so a
dangling symlink counts as missing. That is the mitigation for the spec risk
that an undeployed fallback leaves the guard looking fine until it is needed.

It also collapses two Emacs checks into one that actually works. Both were
false on rafik: systemctl --user is-active emacs is wrong because EWM's Emacs
is not that unit, and ~/.nix-profile/bin/emacsclient does not exist there — the
same hardcoded-path bug already fixed in dot-theme-set. A doctor reporting nine
failures, two of them false, is a doctor nobody reads, which would have made
the new fallback check worthless."
```

---

## Self-Review Notes

**Spec coverage.** Every spec component maps to a task: `lisp/scott-ewm-slots.el` → Task 1; `fallback.el` → Task 2; `init.el` loader and `config.el` → Task 3; `emacs.nix` → Tasks 2 and 3; docs → Task 4. All five spec verification items appear: normal path (Task 3 Step 6, test 1), read-time regression (test 2), load-time regression (test 3), fallback resilience (Task 2 Step 3), and the live rafik check — which is **operational and belongs to Scott**, since it needs the running desktop and a rebuild with `sudo`.

**The spec's one open question is resolved.** It left "how the marker surfaces in the modeline" undecided. Answer: it does not touch the modeline. `scott-modeline.el` renders `scott/tab-bar-status` as a right-aligned tab-bar item, so `fallback.el` prepends its **own** `tab-bar-format` entry instead. `scott-modeline.el` is unchanged and the marker exists only when the fallback ran.

**One ordering constraint discovered while writing.** `emacs.nix`'s non-`liveElisp` branch uses a literal path (`./emacs/config.el`), which fails to evaluate if the file is absent — so the `config.el` deployment cannot land before the file exists. Task 2 therefore adds only `fallback.el`, and Task 3 adds `config.el` with the file. Stated in both tasks.

**Naming consistency.** `scott/init-error` is defined in Task 3 and referenced in Task 4 and the test's probe. `scott/fallback-tab-bar-item` is defined in Task 2 and asserted in Task 2 Step 2. The feature is `scott-ewm-slots` everywhere.

**Task 4 grew during self-review, from evidence.** It began as "add a docs section" and became "follow the split through every reference", because the split invalidates two *live scripts*: `bin/dot-context`'s symlink inventory would silently omit the two new out-of-store symlinks, and `bin/dot-doctor` knows nothing about `fallback.el` — the very failure the spec flags as "looks fine until the moment it is needed". While checking that, `dot-doctor` turned out to report **9 failures on rafik**, two of them false for the same hardcoded-`~/.nix-profile/bin/emacsclient` reason already fixed in `dot-theme-set`. Fixing those two is in scope because a doctor nobody reads cannot mitigate anything; the other 7 failures are unrelated and explicitly left alone, to be reported rather than fixed.

**Deliberately not verified from the desk:** that the red tab-bar marker is legible against the active theme. It uses the `error` face, which every theme defines, but only looking at it settles whether it reads as a warning — folded into Scott's live check.
