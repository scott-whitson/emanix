# Retire zellij Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace zellij's two jobs with Emacs (an `agents` waiting-signal, an OpenRig seat viewer, an `uplink` launcher), then delete zellij and zellaude from emanix, dotfiles, every host and the fork.

**Architecture:** Phase 1 adds three consumer pieces in dotfiles (`scott-agents.el`, `scott/rig-watch` in `scott-rig.el`, `bin/uplink`). Phase 2 removes zellaude's hooks first (they point into a live emanix path), then deletes the zellij module, tree and theme output from emanix together with the host enables in dotfiles, relayed, locked and rebuilt in one sequence.

**Tech Stack:** Emacs Lisp (ERT), Nix flakes / Home Manager / NixOS, bash, agent-shell, ghostel, OpenRig daemon HTTP API, mosh.

**Spec:** `~/projects/emanix/docs/superpowers/specs/2026-09-29-retire-zellij-design.md`

## Global Constraints

- The soak gate between phases is **waived** — Scott, 2026-09-29: *"retire it already"*. Phase 2 follows Phase 1's acceptance directly.
- Tab-bar label is `agents` (not `claude`); launcher is `uplink`; neither command gets a key binding.
- `blocked` is read live from `agent-shell-status`; only `done` is stored.
- No timer and no subprocess in `scott-agents.el`.
- A segment function must never signal: under EWM this Emacs is the compositor.
- `uplink` never starts an Emacs daemon (`emacsclient` without `-a`); on no server it falls back to `exec "${SHELL:-/bin/sh}" -l`.
- Never `nix build` rafik's toplevel on whistle (it OOMs WSL). Cross-host proofs on whistle use `nix eval --raw …drvPath` or build datacore's toplevel only.
- whistle cannot push emanix; use the rafik bare-clone relay (Task 8). Never fast-forward rafik's own `~/projects/emanix`.
- dotfiles is never locked to an emanix commit that is not on GitHub.
- Commits carry **no** `Co-Authored-By` trailer.
- The emanix website manual is edited, **never deployed**, and `~/docs/org/websites` commits happen on rafik only.
- The zellaude fork (`~/projects/work/zellaude`) is deleted last, after both repos are pushed.

## Review Focus

1. **An agent-shell buffer killed while marked done** — expected: it drops out of the count and `scott/agents-next-waiting` never tries to show a dead buffer. Pinned in Task 1 (`scott-agents-killed-buffer-drops-out`).
2. **`agent-shell-status` signalling on a half-initialised buffer** (no ACP session yet) — expected: that buffer counts as not blocked; the segment still renders. Pinned in Task 1 (`scott-agents-status-error-is-not-blocked`).
3. **A second `turn-complete` for an already-done buffer** — expected: it keeps its original timestamp, so "longest waiting" stays honest. Pinned in Task 1 (`scott-agents-done-keeps-first-time`).
4. **`scott/rig-watch` on a seat whose `*rig: …*` buffer already has a live tmux client** — expected: it re-shows that buffer rather than spawning a second attach. Pinned in Task 3 (`scott-rig-watch-reuses-live-buffer`).
5. **`uplink` to a host with no Emacs server** (datacore before console login) — expected: a login shell, not an error and not a new daemon. Pinned in Task 4's live check.

---

## Phase 1 — replacements (dotfiles)

### Task 1: `scott-agents.el` — state, subscription and segment

**Files:**
- Create: `~/dotfiles/home/scott/emacs/personal-lisp/scott-agents.el`
- Create: `~/dotfiles/home/scott/emacs/test/scott-agents-test.el`
- Modify: `~/dotfiles/flake.nix` (add `agents-elisp` beside `rig-elisp`)

**Interfaces:**
- Consumes (from agent-shell, stubbed in tests): `(agent-shell-status &key shell-buffer)` → `busy|blocked|ready`; `(agent-shell-buffers)` → list of buffers; `(agent-shell-subscribe-to &key shell-buffer event on-event)`, ON-EVENT called with an alist whose `:event` is a symbol.
- Produces: `scott/agents--done` (alist `(BUFFER . TIME)`, oldest first); `(scott/agents--on-event BUFFER EVENT)`; `(scott/agents--sweep &optional _frame)`; `(scott/agents--blocked-buffers)`; `(scott/agents--done-buffers)`; `(scott/agents--segment)` → string or nil; `(scott/agents--subscribe BUFFER)`; `(scott/agents-setup)`.

- [ ] **Step 1: Write the failing tests** — `test/scott-agents-test.el`:

```elisp
;;; scott-agents-test.el --- ERT tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'scott-agents)

(defmacro scott-agents-test--with (spec &rest body)
  "Run BODY with fresh state and stubbed agent-shell.
SPEC is (BUFFERS STATUS-ALIST VISIBLE-LIST): BUFFERS are bound buffer
variables created fresh; STATUS-ALIST maps buffer -> status symbol;
VISIBLE-LIST names buffers `get-buffer-window' reports as shown."
  (declare (indent 1))
  `(let ((scott/agents--done nil))
     (cl-letf* (((symbol-function 'agent-shell-buffers)
                 (lambda () (seq-filter #'buffer-live-p ,(nth 0 spec))))
                ((symbol-function 'agent-shell-status)
                 (lambda (&rest args)
                   (alist-get (plist-get args :shell-buffer) ,(nth 1 spec) 'ready)))
                ((symbol-function 'get-buffer-window)
                 (lambda (buf &optional _all) (and (memq buf ,(nth 2 spec)) 'win))))
       ,@body)))

(defun scott-agents-test--buf (name)
  (generate-new-buffer (format " *agents-test %s*" name)))

(ert-deftest scott-agents-turn-complete-hidden-marks-done ()
  (let ((a (scott-agents-test--buf "a")))
    (unwind-protect
        (scott-agents-test--with ((list a) nil nil)
          (scott/agents--on-event a '((:event . turn-complete)))
          (should (equal (scott/agents--done-buffers) (list a))))
      (kill-buffer a))))

(ert-deftest scott-agents-turn-complete-visible-does-not-mark ()
  (let ((a (scott-agents-test--buf "a")))
    (unwind-protect
        (scott-agents-test--with ((list a) nil (list a))
          (scott/agents--on-event a '((:event . turn-complete)))
          (should (null (scott/agents--done-buffers))))
      (kill-buffer a))))

(ert-deftest scott-agents-visible-in-any-frame-counts-as-seen ()
  "get-buffer-window is asked with ALL-FRAMES non-nil (rafik's tty frame)."
  (let ((a (scott-agents-test--buf "a")) asked)
    (unwind-protect
        (let ((scott/agents--done nil))
          (cl-letf (((symbol-function 'get-buffer-window)
                     (lambda (_buf &optional all) (setq asked all) nil)))
            (scott/agents--on-event a '((:event . turn-complete)))
            (should (eq asked t))))
      (kill-buffer a))))

(ert-deftest scott-agents-input-submitted-clears ()
  (let ((a (scott-agents-test--buf "a")))
    (unwind-protect
        (scott-agents-test--with ((list a) nil nil)
          (scott/agents--on-event a '((:event . turn-complete)))
          (scott/agents--on-event a '((:event . input-submitted)))
          (should (null (scott/agents--done-buffers))))
      (kill-buffer a))))

(ert-deftest scott-agents-becoming-visible-clears ()
  (let* ((a (scott-agents-test--buf "a")) (shown nil))
    (unwind-protect
        (scott-agents-test--with ((list a) nil shown)
          (scott/agents--on-event a '((:event . turn-complete)))
          (setq shown (list a))
          (scott/agents--sweep)
          (should (null (scott/agents--done-buffers))))
      (kill-buffer a))))

(ert-deftest scott-agents-killed-buffer-drops-out ()
  (let ((a (scott-agents-test--buf "a")))
    (scott-agents-test--with ((list a) nil nil)
      (scott/agents--on-event a '((:event . turn-complete)))
      (kill-buffer a)
      (should (null (scott/agents--done-buffers)))
      (should (null (scott/agents--segment))))))

(ert-deftest scott-agents-done-keeps-first-time ()
  (let ((a (scott-agents-test--buf "a")))
    (unwind-protect
        (scott-agents-test--with ((list a) nil nil)
          (scott/agents--on-event a '((:event . turn-complete)))
          (let ((first (cdr (assq a scott/agents--done))))
            (sleep-for 0.01)
            (scott/agents--on-event a '((:event . turn-complete)))
            (should (equal (cdr (assq a scott/agents--done)) first))))
      (kill-buffer a))))

(ert-deftest scott-agents-blocked-is-read-live-never-stored ()
  (let ((a (scott-agents-test--buf "a")))
    (unwind-protect
        (scott-agents-test--with ((list a) (list (cons a 'blocked)) nil)
          (should (equal (scott/agents--blocked-buffers) (list a)))
          (should (null scott/agents--done)))
      (kill-buffer a))))

(ert-deftest scott-agents-status-error-is-not-blocked ()
  (let ((a (scott-agents-test--buf "a")))
    (unwind-protect
        (cl-letf (((symbol-function 'agent-shell-buffers) (lambda () (list a)))
                  ((symbol-function 'agent-shell-status)
                   (lambda (&rest _) (error "no session yet"))))
          (should (null (scott/agents--blocked-buffers)))
          (should (null (scott/agents--segment))))
      (kill-buffer a))))

(ert-deftest scott-agents-segment-says-what-waits ()
  (let ((a (scott-agents-test--buf "a")) (b (scott-agents-test--buf "b"))
        (c (scott-agents-test--buf "c")))
    (unwind-protect
        (scott-agents-test--with ((list a b c) (list (cons a 'blocked)) nil)
          (scott/agents--on-event b '((:event . turn-complete)))
          (scott/agents--on-event c '((:event . turn-complete)))
          (should (equal (substring-no-properties (scott/agents--segment))
                         "agents 1 blocked 2 done")))
      (mapc #'kill-buffer (list a b c)))))

(ert-deftest scott-agents-segment-nil-when-clear ()
  (let ((a (scott-agents-test--buf "a")))
    (unwind-protect
        (scott-agents-test--with ((list a) nil nil)
          (should (null (scott/agents--segment))))
      (kill-buffer a))))

(ert-deftest scott-agents-subscribe-once-per-buffer ()
  (let ((a (scott-agents-test--buf "a")) (calls 0))
    (unwind-protect
        (cl-letf (((symbol-function 'agent-shell-subscribe-to)
                   (lambda (&rest _) (cl-incf calls))))
          (scott/agents--subscribe a)
          (scott/agents--subscribe a)
          (should (= calls 1)))
      (kill-buffer a))))
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ~/dotfiles/home/scott/emacs && emacs -Q --batch -L personal-lisp -l ert -l cl-lib -l test/scott-agents-test.el -f ert-run-tests-batch-and-exit`
Expected: FAIL — `Cannot open load file ... scott-agents`.

- [ ] **Step 3: Implement** — `personal-lisp/scott-agents.el`:

```elisp
;;; scott-agents.el --- Which agent-shell sessions are waiting on you -*- lexical-binding: t; -*-

;; Replaces zellaude, the zellij status-bar plugin that answered "which Claude
;; session is waiting on me" -- retired with zellij 2026-09-29 (emanix spec
;; 2026-09-29-retire-zellij-design.md). Every agent session in this fleet is
;; now an agent-shell buffer (Claude Code on whistle, pi on rafik), so the
;; question is answered from Emacs's own state.
;;
;; Two kinds of waiting:
;;   blocked -- a permission request is pending. Read LIVE from
;;              `agent-shell-status' at render time, never stored, so it cannot
;;              go stale (contrast OpenRig's seat state; see scott-rig.el).
;;   done    -- a turn finished while the buffer was not on screen. An edge,
;;              not a state, so it is recorded: on `turn-complete', cleared on
;;              `input-submitted', on becoming visible, or when killed.
;;
;; Event-driven: no timer, no subprocess.

(require 'seq)
(require 'map)
(require 'subr-x)

(declare-function agent-shell-status "agent-shell")
(declare-function agent-shell-buffers "agent-shell")
(declare-function agent-shell-subscribe-to "agent-shell")

(defvar scott/agents--done nil
  "Alist of (BUFFER . TIME) for turns that finished unseen, oldest first.")

(defvar-local scott/agents--subscribed nil
  "Non-nil once this buffer's events are being watched.")

(defun scott/agents--visible-p (buffer)
  "Non-nil when BUFFER is shown in any window of any frame.
ALL-FRAMES t, because the frame looking at it may be a tty frame opened
from another machine over `uplink'."
  (and (get-buffer-window buffer t) t))

(defun scott/agents--mark-done (buffer)
  "Record that BUFFER finished a turn unseen, keeping the first time."
  (when (and (buffer-live-p buffer)
             (not (scott/agents--visible-p buffer))
             (not (assq buffer scott/agents--done)))
    (setq scott/agents--done
          (append scott/agents--done (list (cons buffer (current-time)))))))

(defun scott/agents--clear (buffer)
  (setq scott/agents--done (assq-delete-all buffer scott/agents--done)))

(defun scott/agents--on-event (buffer event)
  "Update waiting state for BUFFER from agent-shell EVENT."
  (pcase (map-elt event :event)
    ('turn-complete (scott/agents--mark-done buffer))
    ((or 'input-submitted 'clean-up) (scott/agents--clear buffer))))

(defun scott/agents--sweep (&optional _frame)
  "Drop done entries that are now visible or dead.
On `window-buffer-change-functions', which passes a FRAME."
  (setq scott/agents--done
        (seq-remove (lambda (entry)
                      (or (not (buffer-live-p (car entry)))
                          (scott/agents--visible-p (car entry))))
                    scott/agents--done)))

(defun scott/agents--done-buffers ()
  "Live, unseen done buffers, oldest first."
  (scott/agents--sweep)
  (mapcar #'car scott/agents--done))

(defun scott/agents--blocked-buffers ()
  "Agent-shell buffers with a pending permission request, read live.
A buffer whose status cannot be read (no ACP session yet) is not blocked."
  (and (fboundp 'agent-shell-buffers)
       (seq-filter (lambda (buffer)
                     (eq (condition-case nil
                             (agent-shell-status :shell-buffer buffer)
                           (error nil))
                         'blocked))
                   (agent-shell-buffers))))

(defun scott/agents--segment ()
  "Waiting agents for the tab-bar, or nil when none wait. Never signals."
  (condition-case nil
      (let* ((blocked (length (scott/agents--blocked-buffers)))
             (done (length (scott/agents--done-buffers)))
             (parts (delq nil
                          (list (and (> blocked 0)
                                     (propertize (format "%d blocked" blocked)
                                                 'face 'warning))
                                (and (> done 0) (format "%d done" done))))))
        (and parts (concat "agents " (string-join parts " "))))
    (error nil)))

(defun scott/agents--subscribe (buffer)
  "Watch BUFFER's agent-shell events, once."
  (with-current-buffer buffer
    (unless scott/agents--subscribed
      (setq scott/agents--subscribed t)
      (agent-shell-subscribe-to
       :shell-buffer buffer
       :on-event (lambda (event) (scott/agents--on-event buffer event))))))

(defun scott/agents--subscribe-current ()
  "For `agent-shell-mode-hook'."
  (scott/agents--subscribe (current-buffer)))

(defun scott/agents-setup ()
  "Watch every agent-shell buffer, present and future."
  (add-hook 'agent-shell-mode-hook #'scott/agents--subscribe-current)
  (add-hook 'window-buffer-change-functions #'scott/agents--sweep)
  (when (fboundp 'agent-shell-buffers)
    (mapc #'scott/agents--subscribe (agent-shell-buffers))))

(when (boundp 'emanix/modeline-extra-segments)
  (add-to-list 'emanix/modeline-extra-segments #'scott/agents--segment))

(provide 'scott-agents)
;;; scott-agents.el ends here
```

Note on `scott-agents-segment-says-what-waits`: the segment string is `agents 1 blocked 2 done`; `substring-no-properties` strips the `warning` face on the blocked part.

- [ ] **Step 4: Run to verify it passes**

Run: the Step 2 command. Expected: `Ran 12 tests, 12 results as expected`.
Also: `emacs -Q --batch -L personal-lisp --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile personal-lisp/scott-agents.el && rm personal-lisp/scott-agents.elc` — expected exit 0.

- [ ] **Step 5: Add the flake check** — in `~/dotfiles/flake.nix`, directly after the `rig-elisp = …;` block:

```nix
        # agents: which agent-shell sessions wait on the human. agent-shell is
        # stubbed; the REAL API it relies on is asserted in emanix's
        # checks/agent-shell-api.nix, against the build the hosts run.
        agents-elisp = pkgs.runCommand "agents-elisp-tests" { } ''
          export HOME=$(mktemp -d)
          ${pkgs.emacs-nox}/bin/emacs -Q --batch \
            -L ${./home/scott/emacs/personal-lisp} \
            -l ert \
            -l cl-lib \
            -l ${./home/scott/emacs/test/scott-agents-test.el} \
            -f ert-run-tests-batch-and-exit
          touch $out
        '';
```

Run: `cd ~/dotfiles && git add -N home/scott/emacs/personal-lisp/scott-agents.el home/scott/emacs/test/scott-agents-test.el && nix build .#checks.x86_64-linux.agents-elisp --no-link -L 2>&1 | tail -3`
Expected: `Ran 12 tests, 12 results as expected`.

- [ ] **Step 6: Commit**

```bash
cd ~/dotfiles
git add flake.nix home/scott/emacs/personal-lisp/scott-agents.el home/scott/emacs/test/scott-agents-test.el
git commit -m "scott-agents: which agent-shell sessions wait on you, replacing zellaude"
```

### Task 2: `scott/agents-next-waiting`

**Files:**
- Modify: `~/dotfiles/home/scott/emacs/personal-lisp/scott-agents.el` (before `(provide …)`)
- Test: `~/dotfiles/home/scott/emacs/test/scott-agents-test.el`

**Interfaces:**
- Consumes: `scott/agents--blocked-buffers`, `scott/agents--done-buffers`, `scott/agents--clear` (Task 1).
- Produces: interactive `scott/agents-next-waiting` → shows a buffer or signals `user-error`.

- [ ] **Step 1: Write the failing tests** (append):

```elisp
(ert-deftest scott-agents-next-prefers-blocked-then-oldest-done ()
  (let ((a (scott-agents-test--buf "a")) (b (scott-agents-test--buf "b"))
        (c (scott-agents-test--buf "c")) shown)
    (unwind-protect
        (scott-agents-test--with ((list a b c) (list (cons c 'blocked)) nil)
          (scott/agents--on-event a '((:event . turn-complete)))
          (scott/agents--on-event b '((:event . turn-complete)))
          (cl-letf (((symbol-function 'pop-to-buffer)
                     (lambda (buf &rest _) (setq shown buf))))
            (scott/agents-next-waiting)
            (should (eq shown c))
            (cl-letf (((symbol-function 'agent-shell-status) (lambda (&rest _) 'ready)))
              (scott/agents-next-waiting)
              (should (eq shown a))
              (should (equal (scott/agents--done-buffers) (list b))))))
      (mapc #'kill-buffer (list a b c)))))

(ert-deftest scott-agents-next-nothing-waiting ()
  (let ((a (scott-agents-test--buf "a")))
    (unwind-protect
        (scott-agents-test--with ((list a) nil nil)
          (should-error (scott/agents-next-waiting) :type 'user-error))
      (kill-buffer a))))
```

- [ ] **Step 2: Run to verify it fails** — Task 1 Step 2 command. Expected: FAIL, `void-function scott/agents-next-waiting`.

- [ ] **Step 3: Implement** (insert before `(when (boundp 'emanix/modeline-extra-segments)`):

```elisp
;;;###autoload
(defun scott/agents-next-waiting ()
  "Show the agent-shell buffer waiting longest for you.
A blocked buffer (pending permission) comes before any done one; among
done buffers, the one that finished first. Showing it clears its done."
  (interactive)
  (let ((buffer (or (car (scott/agents--blocked-buffers))
                    (car (scott/agents--done-buffers)))))
    (unless buffer
      (user-error "No agent is waiting on you"))
    (scott/agents--clear buffer)
    (pop-to-buffer buffer)))
```

- [ ] **Step 4: Run to verify it passes** — Expected: `Ran 14 tests, 14 results as expected`; strict byte-compile exit 0.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add home/scott/emacs/personal-lisp/scott-agents.el home/scott/emacs/test/scott-agents-test.el
git commit -m "scott-agents: jump to the session waiting longest, blocked first"
```

### Task 3: `scott/rig-watch`

**Files:**
- Modify: `~/dotfiles/home/scott/emacs/personal-lisp/scott-rig.el` (before `;;; The tab-bar indicator`)
- Test: `~/dotfiles/home/scott/emacs/test/scott-rig-test.el`

**Interfaces:**
- Consumes: `(scott/rig--request METHOD PATH &optional BODY)` → `(STATUS . JSON)` (exists); `(ghostel-exec BUFFER PROGRAM &optional ARGS IDENTITY)` (ghostel).
- Produces: `(scott/rig--seats)` → list of node alists with `canonicalSessionName`; `(scott/rig--watch-argv SESSION READ-WRITE)` → list of strings; interactive `(scott/rig-watch READ-WRITE)`.

- [ ] **Step 1: Write the failing tests** (append to `scott-rig-test.el`):

```elisp
(ert-deftest scott-rig-watch-argv-read-only-by-default ()
  (should (equal (scott/rig--watch-argv "dev-check@r" nil)
                 '("attach" "-r" "-t" "dev-check@r")))
  (should (equal (scott/rig--watch-argv "dev-check@r" t)
                 '("attach" "-t" "dev-check@r"))))

(ert-deftest scott-rig-seats-across-rigs ()
  (cl-letf (((symbol-function 'scott/rig--request)
             (lambda (_m path &rest _)
               (pcase path
                 ("/api/ps" '(200 . (((rigId . "r1")) ((rigId . "r2")))))
                 ("/api/rigs/r1/nodes" '(200 . (((canonicalSessionName . "a@r1")))))
                 ("/api/rigs/r2/nodes" '(200 . (((canonicalSessionName . "b@r2"))
                                                ((logicalId . "no-session")))))))))
    (should (equal (mapcar (lambda (n) (alist-get 'canonicalSessionName n))
                           (scott/rig--seats))
                   '("a@r1" "b@r2")))))

(ert-deftest scott-rig-watch-execs-tmux-in-ghostel ()
  (let (exec-args)
    (cl-letf (((symbol-function 'scott/rig--seats)
               (lambda () '(((canonicalSessionName . "dev-check@r")
                             (agentActivity . ((state . "needs_input")))))))
              ((symbol-function 'completing-read) (lambda (&rest _) "dev-check@r — needs_input"))
              ((symbol-function 'pop-to-buffer) #'ignore)
              ((symbol-function 'require) (lambda (&rest _) t))
              ((symbol-function 'ghostel-exec)
               (lambda (buf prog &optional args &rest _) (setq exec-args (list (buffer-name buf) prog args)))))
      (unwind-protect
          (progn
            (scott/rig-watch nil)
            (should (equal exec-args '("*rig: dev-check@r*" "tmux" ("attach" "-r" "-t" "dev-check@r")))))
        (when (get-buffer "*rig: dev-check@r*") (kill-buffer "*rig: dev-check@r*"))))))

(ert-deftest scott-rig-watch-reuses-live-buffer ()
  (let ((buf (get-buffer-create "*rig: dev-check@r*")) (execs 0) proc)
    (unwind-protect
        (progn
          (setq proc (start-process "rig-watch-test" buf "sleep" "30"))
          (cl-letf (((symbol-function 'scott/rig--seats)
                     (lambda () '(((canonicalSessionName . "dev-check@r")))))
                    ((symbol-function 'completing-read) (lambda (&rest _) "dev-check@r — ?"))
                    ((symbol-function 'pop-to-buffer) #'ignore)
                    ((symbol-function 'require) (lambda (&rest _) t))
                    ((symbol-function 'ghostel-exec) (lambda (&rest _) (cl-incf execs))))
            (scott/rig-watch nil)
            (should (= execs 0))))
      (when (process-live-p proc) (delete-process proc))
      (kill-buffer buf))))
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ~/dotfiles/home/scott/emacs && emacs -Q --batch -L personal-lisp -l ert -l cl-lib -l test/scott-rig-test.el -f ert-run-tests-batch-and-exit`
Expected: FAIL, `void-function scott/rig--watch-argv`.

- [ ] **Step 3: Implement** (in `scott-rig.el`, before `;;; The tab-bar indicator`):

```elisp
;;; Watching a seat
;;
;; A harness permission prompt is not a qitem, so `scott/rig-decide' cannot
;; answer it; the seat's terminal is the only place it can be. This opens that
;; terminal in a ghostel buffer -- read-only unless asked -- replacing
;; `tmux attach' inside zellij, where zellij's Ctrl-b swallowed tmux's prefix.

(declare-function ghostel-exec "ghostel")

(defun scott/rig--seats ()
  "Every seat across every rig, as /api/rigs/<id>/nodes rows with a session."
  (let ((ps (cdr (scott/rig--request "GET" "/api/ps"))))
    (seq-filter
     (lambda (node) (alist-get 'canonicalSessionName node))
     (apply #'append
            (mapcar (lambda (rig)
                      (let ((nodes (cdr (scott/rig--request
                                         "GET" (concat "/api/rigs/"
                                                       (url-hexify-string (alist-get 'rigId rig))
                                                       "/nodes")))))
                        (and (listp nodes) nodes)))
                    (and (listp ps) ps))))))

(defun scott/rig--watch-argv (session read-write)
  "tmux arguments to attach to SESSION, read-only unless READ-WRITE."
  (append '("attach") (unless read-write '("-r")) (list "-t" session)))

;;;###autoload
(defun scott/rig-watch (read-write)
  "Show an OpenRig seat's terminal in a ghostel buffer.
Read-only, so a stray key cannot type into an agent. With a prefix
argument (READ-WRITE), attach read-write -- to answer a permission
prompt. Killing the buffer ends only this view; the seat keeps running."
  (interactive "P")
  (let* ((seats (or (scott/rig--seats) (user-error "No OpenRig seats are running")))
         (table (mapcar (lambda (node)
                          (cons (format "%s — %s"
                                        (alist-get 'canonicalSessionName node)
                                        (or (alist-get 'state (alist-get 'agentActivity node)) "?"))
                                (alist-get 'canonicalSessionName node)))
                        seats))
         (session (cdr (assoc (completing-read (if read-write "Attach (read-write): " "Watch: ")
                                               table nil t)
                              table)))
         (buffer (get-buffer-create (format "*rig: %s*" session))))
    (pop-to-buffer buffer)
    (unless (process-live-p (get-buffer-process buffer))
      (require 'ghostel)
      (ghostel-exec buffer "tmux" (scott/rig--watch-argv session read-write)))))
```

- [ ] **Step 4: Run to verify it passes** — Expected: all rig tests pass (`Ran 16 tests, 16 results as expected`); strict byte-compile of `scott-rig.el` exit 0.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add home/scott/emacs/personal-lisp/scott-rig.el home/scott/emacs/test/scott-rig-test.el
git commit -m "scott-rig: watch a seat's terminal in ghostel, read-only unless asked"
```

### Task 4: `bin/uplink`

**Files:**
- Create: `~/dotfiles/bin/uplink` (mode 0755)
- Modify: `~/dotfiles/README.md` (the `bin/` table, after the `dot-wslg-redock` row)

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# uplink -- open HOST's Emacs (default: whistle) as a terminal frame, over mosh.
#
# The no-zellij remote workspace (emanix spec 2026-09-29-retire-zellij): the
# far side's Emacs daemon holds every buffer, mosh survives a closed lid, and
# this frame is only a view onto it.
#
# Run it in a FULLSCREEN ghostty on rafik (s-f). EWM intercepts C-x C-u C-h
# M-x from any windowed surface; only in fullscreen do they reach the far
# Emacs (ewm-intercept-prefixes, :fullscreen entries).
#
# Never starts a daemon: no `-a'. A second Emacs on an EWM host stops EWM.
# With no server there (datacore before a console login) you get a shell.
set -euo pipefail
host="${1:-whistle}"
printf 'uplink: %s  (s-f for fullscreen, or EWM keeps C-x C-u C-h M-x)\n' "$host" >&2
exec mosh "$host" -- sh -c 'emacsclient -t || exec "${SHELL:-/bin/sh}" -l'
```

Run: `chmod +x ~/dotfiles/bin/uplink && bash -n ~/dotfiles/bin/uplink && command -v shellcheck >/dev/null && shellcheck ~/dotfiles/bin/uplink`
Expected: no output, exit 0 (skip shellcheck if absent).

- [ ] **Step 2: README row** — add after the `dot-wslg-redock` row in `~/dotfiles/README.md`:

```markdown
| `uplink [host]` | Open `host`'s Emacs (default whistle) as a terminal frame over mosh; run it in a fullscreen ghostty (`s-f`) |
```

- [ ] **Step 3: Commit**

```bash
cd ~/dotfiles
git add bin/uplink README.md
git commit -m "uplink: HOST's Emacs as a terminal frame over mosh, a shell when none runs"
```

### Task 5: Wire Phase 1 in, deploy, accept

**Files:**
- Modify: `~/dotfiles/home/scott/emacs/personal.el` (the OpenRig block that ends `(scott/rig-mode 1))`)

- [ ] **Step 1: Wire** — replace the comment above `(require 'scott-rig)` and add the agents block after the rig block:

```elisp
;; OpenRig (trial, whistle). `scott/rig-decide' answers a decision a seat parked
;; on the human; `scott/rig-watch' shows a seat's terminal (C-u: read-write, to
;; answer a permission prompt). The tab-bar indicator ("rig 1 decide 1 stuck")
;; polls only where the `rig' CLI is installed, so rafik and datacore run no
;; timer and spawn no curl. All unbound on purpose -- Scott picks the keys.
(require 'scott-rig)
(when (executable-find "rig")
  (scott/rig-mode 1))

;; Which agent-shell sessions wait on you: "agents 1 blocked 2 done" in the
;; tab-bar, `scott/agents-next-waiting' to go there. Replaces zellaude. Every
;; host, since agent-shell runs everywhere. Unbound -- Scott picks the key.
(require 'scott-agents)
(with-eval-after-load 'agent-shell
  (scott/agents-setup))
```

- [ ] **Step 2: Deploy** — `cd ~/dotfiles && sudo nixos-rebuild switch --flake ~/dotfiles#whistle 2>&1 | tail -1` → `Done.`; then load into the running daemon (a switch never bounces it):

```bash
emacsclient -e '(progn (dolist (f (quote ("scott-rig" "scott-agents"))) (load (expand-file-name (concat "~/.config/emacs/personal-lisp/" f ".el")) nil t)) (with-eval-after-load (quote agent-shell) (scott/agents-setup)) (list (fboundp (quote scott/agents-next-waiting)) (fboundp (quote scott/rig-watch))))'
```
Expected: `(t t)`.

- [ ] **Step 3: Phase 1 acceptance (live, with Scott)** — each must be observed, not assumed:
  1. In an agent-shell session, ask for a shell command → tab-bar shows `agents 1 blocked`; answer → it clears.
  2. Send a prompt, switch that buffer out of every window before it finishes → `agents 1 done`; show it → clears.
  3. With one blocked and one done, `M-x scott/agents-next-waiting` goes to the blocked one.
  4. `M-x scott/rig-watch` → a `pearl-idm13` seat opens read-only; typing sends nothing (the seat's pane is unchanged in `rig capture`); `C-u M-x scott/rig-watch` attaches read-write; killing the buffer leaves the seat `run` in `rig ps`.
  5. From rafik (fullscreen ghostty): `uplink` → whistle's Emacs; `uplink datacore` → datacore's Emacs (EWM is up there).

- [ ] **Step 4: Commit and push**

```bash
cd ~/dotfiles
git add home/scott/emacs/personal.el
git commit -m "personal: wire scott-agents and rig-watch in"
git fetch -q origin && git push origin main
```

---

## Phase 2 — removal

### Task 6: Remove zellaude's hooks first, everywhere

The hooks call `~/.config/zellij/plugins/zellaude-hook.sh`, a live symlink into
the emanix checkout. Task 7 deletes that directory the moment it runs, but the
hooks only leave a host when it rebuilds. So they go first. (This reorders the
spec's rollout; the spec's own risk — no half-state — is what requires it.)

**Files:**
- Modify: `~/dotfiles/home/scott/claude/settings.json`
- Delete: `~/dotfiles/bin/dot-zellaude-build`
- Modify: `~/dotfiles/bin/dot-context:53`, `~/dotfiles/README.md:342`

- [ ] **Step 1: Strip the ten hook entries**, dropping groups and events left empty:

```bash
cd ~/dotfiles
f=home/scott/claude/settings.json
jq '.hooks |= ( with_entries(.value |= ( map(.hooks |= map(select((.command // "") | contains("zellaude-hook.sh") | not))) | map(select((.hooks | length) > 0)) )) | with_entries(select((.value | length) > 0)) )' "$f" > "$f.new" && mv "$f.new" "$f"
grep -c zellaude "$f"
```
Expected: `0`. Then `jq -e . "$f" >/dev/null` exits 0, and `git diff --stat` shows only this file shrinking.

- [ ] **Step 2: Delete the build script and its references**

```bash
cd ~/dotfiles
git rm -q bin/dot-zellaude-build
sed -i '/"\$HOME\/.config\/zellij" \\/d' bin/dot-context
sed -i '/^| `dot-zellaude-build` |/d' README.md
git grep -n -i zellaude
```
Expected: no hits except `home/scott/claude.nix` comments (Task 9) — none in `bin/`, `README.md` or `settings.json`.

- [ ] **Step 3: Commit, push, deploy to every Claude host**

```bash
cd ~/dotfiles
git add -A home/scott/claude/settings.json bin/dot-context README.md
git commit -m "claude: drop zellaude's ten hooks, which exit on line one in every session"
git push origin main
sudo nixos-rebuild switch --flake ~/dotfiles#whistle 2>&1 | tail -1
ssh datacore 'cd ~/dotfiles && git pull -q --ff-only origin main && sudo nixos-rebuild switch --flake ~/dotfiles#datacore 2>&1 | tail -1'
ssh rafik 'cd ~/dotfiles && git pull -q --ff-only origin main && sudo nixos-rebuild switch --flake ~/dotfiles#rafik 2>&1 | tail -1'
grep -c zellaude ~/.claude/settings.json
for h in datacore rafik; do ssh -o BatchMode=yes $h 'grep -c zellaude ~/.claude/settings.json'; done
```
Expected: three `Done.` lines, then `0` three times. If a remote `sudo` prompts, stop and hand that host's command to Scott.

### Task 7: emanix — delete zellij, its theme output, its prose; guard the agents API

**Files:**
- Delete: `~/projects/emanix/home/zellij.nix`, `~/projects/emanix/zellij/` (whole tree)
- Modify: `home/default.nix:36`, `emacs/lisp/emanix-theme.el:188-227,255`, `emacs/test/emanix-theme-test.el:34-44,129-141`, `emacs/config.el:167,183,270`, `home/ghostty.nix:72`, `lib/themes.nix:163`, `README.md:71,135`, `WALKTHROUGH.md:161,176`, `checks/agent-shell-api.nix`

**Interfaces:**
- Produces: `(emanix-theme--link-plan NAME DIR)` — the `variant` parameter is removed (zellij was its only user); `emanix-theme--plan` still returns `:variant`.

- [ ] **Step 1: Snapshot live sessions before the binary disappears**

```bash
zellij delete-all-sessions -y 2>/dev/null; zellij list-sessions 2>&1 | head -1
ssh datacore 'zellij delete-all-sessions -y 2>/dev/null; zellij list-sessions 2>&1 | head -1'
```
Expected: `No active zellij sessions found.` (or equivalent) on both.

- [ ] **Step 2: Theme test first** — in `emacs/test/emanix-theme-test.el`: delete the two `.local/share/emanix/zellij-themes/available/emanix-*.kdl` lines from `emanix-theme-test--make-home` and reword its docstring to *"Return a temp HOME holding the ghostty sources a plan links. They live outside the theme tree -- ghostty renders per-palette files into its own config dir -- so a fixture that omits them makes every link assertion depend on whether the REAL home happens to have them."*; delete `emanix-theme-plan-links-zellij-by-variant-not-by-name` entirely; in `emanix-theme-plan-omits-links-whose-source-is-absent` change the docstring's middle to *"ghostty renders per-palette files only where `emanix.ghostty.enable' is set, so a plan must not name a source that is not there."* Add:

```elisp
(ert-deftest emanix-theme-plan-links-nothing-of-zellij ()
  "zellij was retired 2026-09-29; no plan may name its theme tree."
  (emanix-theme-test--with-tree
    (let ((links (plist-get (emanix-theme--plan "duskthorn") :links)))
      (should-not (seq-find (lambda (l) (string-match-p "zellij" (concat (car l) (cdr l)))) links)))))
```

Run: `cd ~/projects/emanix && emacs -Q --batch -L emacs/lisp -l ert -l emacs/test/emanix-theme-test.el -f ert-run-tests-batch-and-exit 2>&1 | grep -E '^Ran|FAILED'`
Expected: FAIL on `emanix-theme-plan-links-nothing-of-zellij` (the fixture no longer creates the zellij files, so this may already pass by `file-exists-p` filtering — if it passes, that is acceptable: it pins the behaviour for Step 3).

- [ ] **Step 3: Theme code** — in `emacs/lisp/emanix-theme.el`: delete the `emanix-theme--zellij-themes-dir` defconst (lines 188–194); in `emanix-theme--link-plan` change the signature to `(name dir)`, delete the final zellij `cons`, and end the docstring at *"…ghostty renders its palettes only on hosts with `emanix.ghostty.enable'."*; at the call site (~line 255) change `(emanix-theme--link-plan name dir variant)` to `(emanix-theme--link-plan name dir)`; in the docstring near line 550 change *"btop, zellij and swaylock"* to *"btop and swaylock"*.

Run: the Step 2 command, plus `emacs -Q --batch -L emacs/lisp --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile emacs/lisp/emanix-theme.el; rm -f emacs/lisp/emanix-theme.elc`
Expected: all theme tests pass; compile exit 0.

- [ ] **Step 4: Delete the module and tree**

```bash
cd ~/projects/emanix
git rm -rq home/zellij.nix zellij
sed -i '/\.\/zellij\.nix/d' home/default.nix
```

- [ ] **Step 5: Prose** —
  - `emacs/config.el:167`: *"M-hjkl mirrors zellij, and GlazeWM's"* → *"M-hjkl mirrors GlazeWM's"*.
  - `emacs/config.el:183`: *"M-hjkl is zellij's own pane motion."* → *"M-hjkl belongs to whatever runs in the terminal."*
  - `emacs/config.el:270`: *"every frame across every zellij session."* → *"every frame, including tty frames opened over `uplink'."*
  - `home/ghostty.nix:72`: *"it seeds btop, zellij, swaylock, gtk"* → *"it seeds btop, swaylock, gtk"*.
  - `lib/themes.nix:163`: *"zellij themes and Claude Code's -ansi themes read"* → *"Claude Code's -ansi themes read"*.
  - `README.md`: delete line 71 (`zellij/ …`) and the `emanix.zellij.enable` row (line 135).
  - `WALKTHROUGH.md`: delete the `emanix.zellij.enable` row (line 161) and the `zellij/` line (176).

- [ ] **Step 6: Guard the API scott-agents relies on** — in `checks/agent-shell-api.nix`, add `agent-shell-status` and `agent-shell-buffers` to the `fboundp` symbol list, and after the `tool-call-update` documentation assertion add:

```elisp
    ;; dotfiles scott-agents.el (the zellaude replacement) counts on these.
    (dolist (ev (quote ("turn-complete" "input-submitted" "clean-up")))
      (unless (string-match-p ev (documentation (quote agent-shell-subscribe-to)))
        (error "agent-shell no longer documents the %s event" ev)))
```

- [ ] **Step 7: Verify emanix** —

```bash
cd ~/projects/emanix
git grep -n -i -E 'zellij|zellaude' -- . ':!docs/superpowers'
nix flake check 2>&1 | tail -5
```
Expected: grep prints nothing; flake check ends without errors. (Do NOT commit yet — Task 8 verifies dotfiles against this tree first.)

### Task 8: dotfiles enables + prose, verified against local emanix, then relay, lock, rebuild

**Files:**
- Modify: `~/dotfiles/hosts/whistle/configuration.nix:5-12`, `hosts/datacore/configuration.nix:57-66`, `modules/ssh.nix:48-55`, `home/scott/claude.nix:74,100`, `home/scott/emacs/personal.el:547,663`, `home/scott/ssh.nix:47`, `bin/dot-wslg-redock:24,28`, `README.md:79,153,181`, `WALKTHROUGH.md:87`

- [ ] **Step 1: Host enables** — whistle: delete `zellij.enable = true;` and change its comment to *"No GUI app suite (WSLg draws individual windows, there is no desktop here), but ghostty IS wanted: it is how a WSL box gets a usable terminal window, and the distro gates it on its own option rather than on emanix.gui for exactly this case."* datacore: delete lines 57–66 (the comment block and `home-manager.users.scott.emanix.zellij.enable = true;`).

- [ ] **Step 2: `modules/ssh.nix`** — replace the paragraph *"Safe on whistle and datacore because both run zellij: … if that ever stops being the case."* with:

```nix
  #    Safe everywhere because what outlives a timed-out mosh-server is the
  #    Emacs daemon, not the shell: `uplink' opens a terminal FRAME onto it, and
  #    a timeout costs that frame and nothing in it. On datacore before anyone
  #    has logged in at the console there is no daemon (its Emacs is the EWM
  #    session, and datacore does not autologin), so a timeout there costs a
  #    plain shell -- accepted 2026-09-29 (emanix spec retire-zellij).
```

- [ ] **Step 3: Prose** —
  - `home/scott/claude.nix:74`: *"Same lesson as the zellij plugin dir."* → delete the sentence.
  - `home/scott/claude.nix:100`: *"Same live-symlink pattern as zellij.nix and the emacs lisp dir"* → *"Same live-symlink pattern as the emacs lisp dir"*.
  - `home/scott/emacs/personal.el:547`: *"taking every zellij and Claude session with it"* → *"taking every Emacs frame and Claude session with it"*.
  - `home/scott/emacs/personal.el:663`: *"is the no-zellij path (2026-09-29)"* → *"is the remote-workspace path (2026-09-29; `uplink')"*.
  - `home/scott/ssh.nix:47`: *"no longer strands a zellij session"* → *"no longer strands a session"*.
  - `bin/dot-wslg-redock:24`: *"the emacs daemon / zellij / open Wayland surfaces"* → *"the emacs daemon / open Wayland surfaces"*; line 28: *"every zellij session and Claude session with it"* → *"every Emacs frame and Claude session with it"*.
  - `README.md:79`: *"Ghostty and Zellij."* → *"Ghostty."*; delete the `emanix.zellij.enable` row (153); line 181: *"Live Emacs Lisp and Zellij plugins resolve through it, so a host with either needs this present"* → *"Live Emacs Lisp resolves through it, so every host needs this present"*.
  - `WALKTHROUGH.md:87`: *"It uses Ghostty and Zellij"* → *"It uses Ghostty"*.

Run: `cd ~/dotfiles && git grep -n -i -E 'zellij|zellaude'` → no hits.

- [ ] **Step 4: Verify dotfiles against the local emanix tree**

```bash
cd ~/dotfiles
nix build .#nixosConfigurations.whistle.config.system.build.toplevel --no-link --override-input emanix path:/home/scott/projects/emanix 2>&1 | tail -2
nix build .#nixosConfigurations.datacore.config.system.build.toplevel --no-link --override-input emanix path:/home/scott/projects/emanix 2>&1 | tail -2
nix eval --raw .#nixosConfigurations.rafik.config.system.build.toplevel.drvPath --override-input emanix path:/home/scott/projects/emanix
nix flake check --override-input emanix path:/home/scott/projects/emanix 2>&1 | tail -3
```
Expected: both builds succeed, rafik prints a `.drv` path (evaluation only — never build rafik on whistle), flake check passes.

- [ ] **Step 5: Commit emanix and relay it through rafik**

```bash
cd ~/projects/emanix
git add -A
git commit -m "retire zellij: the module, its tree and theme output, and the prose that assumed it"
ssh rafik 'rm -rf /tmp/emanix-relay.git && git clone --bare -q git@github.com:scott-whitson/emanix.git /tmp/emanix-relay.git'
git push --dry-run ssh://scott@rafik/tmp/emanix-relay.git main:main
git push ssh://scott@rafik/tmp/emanix-relay.git main:main
ssh rafik 'cd /tmp/emanix-relay.git && git push origin main && cd / && rm -rf /tmp/emanix-relay.git'
git fetch -q origin && git status -sb | head -1
```
Expected: last line `## main...origin/main` with no `ahead` — the spec commit `09930ef` and this one are both on GitHub.

- [ ] **Step 6: Lock, commit, push dotfiles**

```bash
cd ~/dotfiles
nix flake lock --update-input emanix
git add -A flake.lock hosts modules home bin README.md WALKTHROUGH.md
git commit -m "retire zellij: drop the host enables and the prose that assumed a multiplexer"
git push origin main
```

- [ ] **Step 7: Rebuild every host**

```bash
sudo nixos-rebuild switch --flake ~/dotfiles#whistle 2>&1 | tail -1
ssh datacore 'cd ~/dotfiles && git pull -q --ff-only origin main && sudo nixos-rebuild switch --flake ~/dotfiles#datacore 2>&1 | tail -1'
ssh rafik 'cd ~/dotfiles && git pull -q --ff-only origin main && sudo nixos-rebuild switch --flake ~/dotfiles#rafik 2>&1 | tail -1'
```
Expected: three `Done.` lines. If a remote `sudo` prompts, stop and hand that host's command to Scott. On rafik, `~/projects/emanix` is a live-elisp source: pull it only by `git -C ~/projects/emanix pull --ff-only` if clean, and only after the rebuild; if dirty, leave it and tell Scott.

### Task 9: Clean-up, documentation, memory, and Phase 2 acceptance

**Files:**
- Modify: `~/docs/org/websites/emanix/pages/docs/{theming,keybindings,glossary,options}.org`
- Modify: `~/.claude/projects/-home-scott/memory/{reference_zellij_plugins,reference_zellaude_no_push_target,reference_mosh_reconnect_protocol}.md`, `MEMORY.md`

- [ ] **Step 1: Leftover live state**

```bash
rm -rf ~/.local/share/emanix/zellij-themes ~/.config/zellij
ssh datacore 'rm -rf ~/.local/share/emanix/zellij-themes ~/.config/zellij'
command -v zellij || echo none
for h in datacore rafik; do ssh -o BatchMode=yes $h 'command -v zellij || echo none'; done
```
Expected: `none` three times. (`~/.config/zellij` is only a dangling Home Manager link once the module is gone; removing it is safe.)

- [ ] **Step 2: Website manual — edit only, no deploy.** `grep -n -i zellij ~/docs/org/websites/emanix/pages/docs/*.org` and, in each of the 16 lines: delete `emanix.zellij.enable` rows/entries (`options.org`, `glossary.org`); in `keybindings.org` remove zellij from any "mirrors" wording exactly as Task 7 Step 5 did for `config.el`; in `theming.org` remove zellij from the lists of themed applications and delete any section devoted to the zellij theme. Re-run the grep → no hits. Do NOT commit here: `~/docs/org/websites` commits happen on rafik; tell Scott the files are edited and synced.

- [ ] **Step 3: Memory** — rewrite `reference_zellij_plugins.md` to a short tombstone: *"zellij and zellaude were RETIRED 2026-09-29 (emanix spec retire-zellij). Remote workspace = `uplink` (mosh + emacsclient -t, fullscreen ghostty); waiting-signal = `agents` tab-bar segment (scott-agents.el). Do not reinstate."*; delete `reference_zellaude_no_push_target.md` and its `MEMORY.md` line; in `reference_mosh_reconnect_protocol.md` replace the zellij sentences (lines 8–15) with *"Closing a lid on `ssh` leaves a half-open TCP session. Use `mosh` (via `uplink` for Emacs): mosh-server keeps the session and the client resumes."*; update the `MEMORY.md` index line for `reference_zellij_plugins`.

- [ ] **Step 4: Phase 2 acceptance** —

```bash
git -C ~/projects/emanix grep -n -i -E 'zellij|zellaude' -- . ':!docs/superpowers'
git -C ~/dotfiles grep -n -i -E 'zellij|zellaude'
zsh -ic 'dot-doctor >/dev/null 2>&1 && echo "$(hostname) doctor ok" || echo "$(hostname) doctor FAIL"'
for h in datacore rafik; do ssh -o BatchMode=yes $h "zsh -ic 'dot-doctor >/dev/null 2>&1 && echo \$(hostname) doctor ok || echo \$(hostname) doctor FAIL'"; done
```
Expected: both greps empty; three `doctor ok` (`zsh -ic` because `$EMANIX_BIN_DIR` is on PATH in interactive shells only). Then, live: start a fresh agent-shell Claude session on whistle and a pi session on rafik — no hook errors; `uplink` from rafik still opens whistle's Emacs.

- [ ] **Step 5: Delete the zellaude fork — last**

```bash
ls ~/projects/work/zellaude >/dev/null && rm -rf ~/projects/work/zellaude
timeout 300 bash -c 'until ssh -o BatchMode=yes datacore "test ! -e ~/projects/work/zellaude"; do sleep 10; done'; echo replicated=$?
```
Expected: `replicated=0` once Syncthing has carried the deletion to datacore.
