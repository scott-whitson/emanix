# Work Quarterly Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `C-c q` open a work quarterly tracker on the work laptop, and consolidate the six scattered work quarter notes into `~/docs/org/work/Quarterly/` with clean filenames and `(Work)`-suffixed titles.

**Architecture:** The quarterly tracker moves out of `init.el` into `lisp/scott-quarterly.el`, matching the eight `scott-*.el` modules already in that directory, and gains an ERT test file. One command serves two scopes — `personal` at the org root, `work` under `work/Quarterly/` — choosing between them by looking at which trees exist on the filesystem, so there is no per-machine configuration to keep in sync. A separate one-shot bash script performs the file migration.

**Tech Stack:** Emacs Lisp (ERT for tests), bash, org-roam, Syncthing.

**Spec:** `docs/superpowers/specs/2026-08-06-work-quarterly-tracker-design.md`

## Global Constraints

- **Preserve every `:ID:` exactly.** All inbound links to quarter notes are `[[id:]]` links; the IDs are the only thing making the renames safe. Never regenerate an ID for an existing note.
- **Never silently create and save an empty quarter note.** A missing note must be confirmed via `yes-or-no-p` first. On 2026-07-16 an empty `2026-Q3` won a Syncthing conflict and quarantined the real populated note.
- **Work note titles get the ` (Work)` suffix; personal titles are untouched.** Format: `#+title: 2026-Q3 (Work)`.
- **Work directory is `Quarterly` — capital Q**, matching the personal side. Not `quarterly`, not `Quarterly Notes`.
- **Filenames are clean:** `YYYY-QN.org`, no org-roam `20260718100853-` timestamp prefix.
- **Personal scope behavior must not change.** `C-c q` on zord and eminix must resolve exactly as it does today: `<org>/YYYY-QN.org`, falling back to `<org>/Quarterly/YYYY-QN.org`.
- **Elisp is live-symlinked** (`scott.dotfiles.liveElisp` defaults to `true`, no host overrides; `~/.config/emacs/init.el` and `~/.config/emacs/lisp` resolve into `~/dotfiles/ioshi/i-intelligence/emacs/`). Editing repo files takes effect on Emacs restart with no `home-manager switch`. Adding a new file to `lisp/` needs no rebuild.
- **Test command** (run from `~/dotfiles/ioshi/i-intelligence/emacs`):
  `emacs -Q --batch -L lisp -L test -l test/scott-quarterly-test.el -f ert-run-tests-batch-and-exit`
- **Commit style:** no `Co-Authored-By` trailers.

## File Structure

| File | Responsibility |
|---|---|
| `ioshi/i-intelligence/emacs/lisp/scott-quarterly.el` | **Create.** All quarterly tracker logic: quarter naming, scope resolution, template generation, the interactive command. |
| `ioshi/i-intelligence/emacs/test/scott-quarterly-test.el` | **Create.** ERT tests. Pure functions tested directly; filesystem behavior tested against a temp `org-directory`. |
| `ioshi/i-intelligence/emacs/init.el:205-250` | **Modify.** Delete the three inline `scott/…quarter…` functions, `require` the module, keep the `C-c q` binding here with the other global bindings. |
| `tools/migrate-work-quarters.sh` | **Create.** One-shot migration with `--dry-run`. Lives in the repo as a record of what was done. |

Nothing else changes. The module is self-contained: it depends only on `org-id` (for `org-id-new`) and the `org-directory` variable.

**Note on deviation from the spec:** the spec says the changes land in `init.el`. This plan extracts to a module instead, because (a) `lisp/scott-*.el` + `test/scott-*-test.el` is the established pattern for every other self-contained feature in this config, and (b) the spec's verification section requires exercising template creation against a throwaway `org-directory`, which needs a `require`-able unit. Behavior is identical either way.

---

### Task 1: Extract the tracker into a module, unchanged

Behavior-preserving move. No new features — this task exists so the refactor is reviewable separately from the behavior change, and so later tasks have a tested module to build on.

**Files:**
- Create: `ioshi/i-intelligence/emacs/lisp/scott-quarterly.el`
- Create: `ioshi/i-intelligence/emacs/test/scott-quarterly-test.el`
- Modify: `ioshi/i-intelligence/emacs/init.el:205-250`

**Interfaces:**
- Consumes: nothing.
- Produces: `(scott-quarterly-name &optional TIME)` → string `"YYYY-QN"`. `(scott-quarterly--prev-name NAME)` → string, the preceding quarter.

- [ ] **Step 1: Write the failing test**

Create `test/scott-quarterly-test.el`:

```elisp
;;; scott-quarterly-test.el --- ERT tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
;; `org' must be loaded before the tests bind `org-directory'. Under
;; lexical-binding, `let' over a symbol that is not globally special creates a
;; lexical binding the module cannot see — the filesystem tests would then
;; silently exercise the real ~/docs/org instead of the temp tree. Requiring
;; org defvars `org-directory' with a value, making it truly special.
(require 'org)
(require 'scott-quarterly)

(ert-deftest scott-quarterly-name-maps-months-to-quarters ()
  "Each month maps to its calendar quarter."
  ;; encode-time: (SEC MIN HOUR DAY MONTH YEAR)
  (should (equal "2026-Q1" (scott-quarterly-name (encode-time 0 0 12 15 1 2026))))
  (should (equal "2026-Q1" (scott-quarterly-name (encode-time 0 0 12 31 3 2026))))
  (should (equal "2026-Q2" (scott-quarterly-name (encode-time 0 0 12 1 4 2026))))
  (should (equal "2026-Q3" (scott-quarterly-name (encode-time 0 0 12 6 8 2026))))
  (should (equal "2026-Q4" (scott-quarterly-name (encode-time 0 0 12 31 12 2026)))))

(ert-deftest scott-quarterly-prev-name-wraps-the-year ()
  "The quarter before Q1 is Q4 of the previous year."
  (should (equal "2026-Q2" (scott-quarterly--prev-name "2026-Q3")))
  (should (equal "2025-Q4" (scott-quarterly--prev-name "2026-Q1"))))
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd ~/dotfiles/ioshi/i-intelligence/emacs
emacs -Q --batch -L lisp -L test -l test/scott-quarterly-test.el -f ert-run-tests-batch-and-exit
```

Expected: FAIL — `Cannot open load file: scott-quarterly`.

- [ ] **Step 3: Write minimal implementation**

Create `lisp/scott-quarterly.el`:

```elisp
;;; scott-quarterly.el --- Quarterly tracker notes -*- lexical-binding: t; -*-

;;; Commentary:
;; The quarterly tracker is the "main page" tying together a quarter's work.
;; Two scopes share one command: `personal' notes live at the org root,
;; `work' notes under work/Quarterly/.  Extracted from init.el 2026-08-06.

;;; Code:

(require 'org-id)

(defvar org-directory)

(defun scott-quarterly-name (&optional time)
  "Return the quarter name for TIME in YYYY-QN format.
TIME defaults to now."
  (let* ((time (or time (current-time)))
         (month (string-to-number (format-time-string "%m" time)))
         (quarter (1+ (/ (1- month) 3))))
    (format "%s-Q%d" (format-time-string "%Y" time) quarter)))

(defun scott-quarterly--prev-name (name)
  "Return the quarter name preceding NAME, wrapping across the year."
  (let ((year (string-to-number (substring name 0 4)))
        (quarter (string-to-number (substring name 6 7))))
    (if (= quarter 1)
        (format "%d-Q4" (1- year))
      (format "%d-Q%d" year (1- quarter)))))

(provide 'scott-quarterly)
;;; scott-quarterly.el ends here
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd ~/dotfiles/ioshi/i-intelligence/emacs
emacs -Q --batch -L lisp -L test -l test/scott-quarterly-test.el -f ert-run-tests-batch-and-exit
```

Expected: `Ran 2 tests, 2 results as expected, 0 unexpected`.

- [ ] **Step 5: Move the remaining two functions into the module**

Append to `lisp/scott-quarterly.el`, immediately before the `(provide 'scott-quarterly)` line — these are verbatim copies of `scott/current-quarter-file` and `scott/open-quarterly-tracker` from `init.el`, renamed into the module's namespace. Tasks 2-4 rewrite them; this step only moves them.

```elisp
(defun scott-quarterly--file (&optional name)
  "Return the current-quarter note path, preferring root then Quarterly/."
  (let* ((name (or name (scott-quarterly-name)))
         (root (expand-file-name (concat name ".org") org-directory))
         (archived (expand-file-name (concat "Quarterly/" name ".org") org-directory)))
    (cond ((file-exists-p root) root)
          ((file-exists-p archived) archived)
          (t root))))

(defun scott-quarterly-open ()
  "Open the current-quarter tracker note.
If the note does not exist on this machine, do NOT silently create and
save an empty template — that races with Syncthing: on a freshly-synced
box the empty file can win the conflict and quarantine the real,
populated note (happened 2026-07-16 with 2026-Q3). Instead confirm
first, so an unsynced note gets a chance to arrive rather than be
clobbered; only a genuinely new quarter gets a fresh template."
  (interactive)
  (let* ((name (scott-quarterly-name))
         (file (scott-quarterly--file name)))
    (if (file-exists-p file)
        (find-file file)
      (if (yes-or-no-p
           (format "No %s note here — create it? (choose no if it may just be unsynced) "
                   name))
          (progn
            (find-file file)
            (when (zerop (buffer-size))
              (insert ":PROPERTIES:\n:ID:       " (org-id-new) "\n:END:\n")
              (insert "#+title: " name "\n\n")
              (insert "* Goals\n\n")
              (insert "* Active work\n\n")
              (insert "* Notes\n\n")
              (save-buffer)))
        (message
         "Not creating %s — waiting for sync. Re-run C-c q once it arrives."
         name)))))
```

- [ ] **Step 6: Point init.el at the module**

In `ioshi/i-intelligence/emacs/init.el`, delete lines 205-250 in their entirety — the `scott/current-quarter-name`, `scott/current-quarter-file`, and `scott/open-quarterly-tracker` definitions and the `global-set-key` that follows them. Replace with:

```elisp
(require 'scott-quarterly nil :no-error)
(global-set-key (kbd "C-c q") #'scott-quarterly-open)
```

- [ ] **Step 7: Verify the config still loads and the binding resolves**

```bash
emacs -Q --batch --eval '(progn (add-to-list (quote load-path) (expand-file-name "~/dotfiles/ioshi/i-intelligence/emacs/lisp")) (require (quote scott-quarterly)) (message "name=%s prev=%s" (scott-quarterly-name) (scott-quarterly--prev-name (scott-quarterly-name))))'
```

Expected: `name=2026-Q3 prev=2026-Q2`.

Then confirm no stale references remain:

```bash
grep -n "scott/current-quarter\|scott/open-quarterly" ~/dotfiles/ioshi/i-intelligence/emacs/init.el
```

Expected: no output.

- [ ] **Step 8: Commit**

```bash
cd ~/dotfiles
git add ioshi/i-intelligence/emacs/lisp/scott-quarterly.el \
        ioshi/i-intelligence/emacs/test/scott-quarterly-test.el \
        ioshi/i-intelligence/emacs/init.el
git commit -m "refactor(emacs): extract quarterly tracker into scott-quarterly.el

Behavior unchanged. Moves the three inline init.el functions into a
module matching the other lisp/scott-*.el features, with ERT tests."
```

---

### Task 2: Scope-aware path resolution

**Files:**
- Modify: `ioshi/i-intelligence/emacs/lisp/scott-quarterly.el`
- Modify: `ioshi/i-intelligence/emacs/test/scott-quarterly-test.el`

**Interfaces:**
- Consumes: `scott-quarterly-name` from Task 1.
- Produces: `(scott-quarterly--dir SCOPE)` → directory path. `(scott-quarterly--file SCOPE &optional NAME)` → file path; note the **new leading SCOPE argument**, which changes Task 1's signature. `(scott-quarterly--scope-available-p SCOPE)` → boolean. `(scott-quarterly--default-scope)` → `personal` or `work`. SCOPE is always one of the symbols `personal` or `work`.

- [ ] **Step 1: Write the failing tests**

Append to `test/scott-quarterly-test.el`:

```elisp
(defmacro scott-quarterly-test--with-org-dir (spec &rest body)
  "Run BODY with `org-directory' bound to a temp tree built from SPEC.
SPEC is a list of relative paths; a trailing slash makes a directory,
anything else an empty file."
  (declare (indent 1))
  `(let* ((org-directory (make-temp-file "scott-quarterly-test" t)))
     (unwind-protect
         (progn
           (dolist (entry ,spec)
             (let ((path (expand-file-name entry org-directory)))
               (if (string-suffix-p "/" entry)
                   (make-directory path t)
                 (make-directory (file-name-directory path) t)
                 (write-region "" nil path nil 'silent))))
           ,@body)
       (delete-directory org-directory t))))

(ert-deftest scott-quarterly-work-path-is-always-constructed ()
  "Work notes have exactly one location, whether or not the file exists."
  (scott-quarterly-test--with-org-dir '("work/Quarterly/")
    (should (equal (expand-file-name "work/Quarterly/2026-Q3.org" org-directory)
                   (scott-quarterly--file 'work "2026-Q3")))))

(ert-deftest scott-quarterly-personal-path-prefers-root-then-archive ()
  "Personal resolution is unchanged: root file wins, then Quarterly/, then root."
  (scott-quarterly-test--with-org-dir '("2026-Q3.org" "Quarterly/")
    (should (equal (expand-file-name "2026-Q3.org" org-directory)
                   (scott-quarterly--file 'personal "2026-Q3"))))
  (scott-quarterly-test--with-org-dir '("Quarterly/2026-Q3.org")
    (should (equal (expand-file-name "Quarterly/2026-Q3.org" org-directory)
                   (scott-quarterly--file 'personal "2026-Q3"))))
  ;; Neither exists yet: fall back to the root path, as today.
  (scott-quarterly-test--with-org-dir '("Quarterly/")
    (should (equal (expand-file-name "2026-Q3.org" org-directory)
                   (scott-quarterly--file 'personal "2026-Q3")))))

(ert-deftest scott-quarterly-availability-reads-the-tree-not-the-note ()
  "A scope is available when its tree exists, even with no note for this quarter."
  ;; Work laptop: only the work tree is synced here.
  (scott-quarterly-test--with-org-dir '("work/Quarterly/")
    (should (scott-quarterly--scope-available-p 'work))
    (should-not (scott-quarterly--scope-available-p 'personal))
    (should (eq 'work (scott-quarterly--default-scope))))
  ;; Home machines: both trees present, personal wins by default.
  (scott-quarterly-test--with-org-dir '("Quarterly/" "work/Quarterly/")
    (should (scott-quarterly--scope-available-p 'work))
    (should (scott-quarterly--scope-available-p 'personal))
    (should (eq 'personal (scott-quarterly--default-scope))))
  ;; Personal with no Quarterly/ archive yet — a loose root note counts.
  (scott-quarterly-test--with-org-dir '("2025-Q4.org")
    (should (scott-quarterly--scope-available-p 'personal)))
  ;; Empty tree: work is the fallback so the guard can offer to create it.
  (scott-quarterly-test--with-org-dir '()
    (should (eq 'work (scott-quarterly--default-scope)))))
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/dotfiles/ioshi/i-intelligence/emacs
emacs -Q --batch -L lisp -L test -l test/scott-quarterly-test.el -f ert-run-tests-batch-and-exit
```

Expected: FAIL — `scott-quarterly--dir` / `scott-quarterly--scope-available-p` void, and `scott-quarterly--file` called with 2 args when it accepts 1.

- [ ] **Step 3: Write the implementation**

In `lisp/scott-quarterly.el`, replace the Task 1 `scott-quarterly--file` definition with:

```elisp
(defun scott-quarterly--dir (scope)
  "Return the quarterly directory for SCOPE (`personal' or `work')."
  (pcase scope
    ('work (expand-file-name "work/Quarterly" org-directory))
    ('personal (expand-file-name "Quarterly" org-directory))
    (_ (error "Unknown quarterly scope: %S" scope))))

(defun scott-quarterly--file (scope &optional name)
  "Return the note path for quarter NAME in SCOPE.
NAME defaults to the current quarter.  Work notes have exactly one
location.  Personal notes keep their historical resolution: the org root
holds the current quarter, Quarterly/ holds archived ones."
  (let ((name (or name (scott-quarterly-name))))
    (pcase scope
      ('work (expand-file-name (concat name ".org") (scott-quarterly--dir 'work)))
      ('personal
       (let ((root (expand-file-name (concat name ".org") org-directory))
             (archived (expand-file-name (concat name ".org")
                                         (scott-quarterly--dir 'personal))))
         (cond ((file-exists-p root) root)
               ((file-exists-p archived) archived)
               (t root))))
      (_ (error "Unknown quarterly scope: %S" scope)))))

(defun scott-quarterly--scope-available-p (scope)
  "Return non-nil when SCOPE's note tree exists on this machine.
This asks whether the tree is here at all, not whether this quarter's
note has been written yet — otherwise the first `scott-quarterly-open'
of a new quarter would resolve to the wrong scope."
  (pcase scope
    ('work (file-directory-p (scott-quarterly--dir 'work)))
    ('personal
     (or (file-directory-p (scott-quarterly--dir 'personal))
         (and (file-directory-p org-directory)
              (consp (directory-files
                      org-directory nil "\\`[0-9]\\{4\\}-Q[1-4]\\.org\\'" t)))))
    (_ (error "Unknown quarterly scope: %S" scope))))

(defun scott-quarterly--default-scope ()
  "Return `personal' when that tree is present here, otherwise `work'."
  (if (scott-quarterly--scope-available-p 'personal) 'personal 'work))
```

Also update the `scott-quarterly-open` call site so the module still loads — change `(scott-quarterly--file name)` to `(scott-quarterly--file (scott-quarterly--default-scope) name)`. Task 4 rewrites this function properly.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/dotfiles/ioshi/i-intelligence/emacs
emacs -Q --batch -L lisp -L test -l test/scott-quarterly-test.el -f ert-run-tests-batch-and-exit
```

Expected: `Ran 5 tests, 5 results as expected, 0 unexpected`.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add ioshi/i-intelligence/emacs/lisp/scott-quarterly.el \
        ioshi/i-intelligence/emacs/test/scott-quarterly-test.el
git commit -m "feat(emacs): scope-aware quarterly path resolution

Work notes resolve to work/Quarterly/YYYY-QN.org; personal resolution is
unchanged. Scope defaults by which trees exist on the machine, so there
is no per-host configuration."
```

---

### Task 3: New-quarter template with back-link

**Files:**
- Modify: `ioshi/i-intelligence/emacs/lisp/scott-quarterly.el`
- Modify: `ioshi/i-intelligence/emacs/test/scott-quarterly-test.el`

**Interfaces:**
- Consumes: `scott-quarterly--prev-name` (Task 1), `scott-quarterly--file` (Task 2).
- Produces: `scott-quarterly-sections` (list of strings). `(scott-quarterly--file-id FILE)` → ID string or nil. `(scott-quarterly--template SCOPE NAME &optional PREV-ID PREV-NAME)` → the full buffer text for a new note.

- [ ] **Step 1: Write the failing tests**

Append to `test/scott-quarterly-test.el`:

```elisp
(ert-deftest scott-quarterly-file-id-reads-the-top-level-id ()
  "The :ID: property is read out of an existing note."
  (let ((file (make-temp-file "quarter" nil ".org"
                              ":PROPERTIES:\n:ID:       abc-123\n:END:\n#+title: 2026-Q2 (Work)\n")))
    (unwind-protect
        (should (equal "abc-123" (scott-quarterly--file-id file)))
      (delete-file file)))
  ;; A note with no ID yields nil rather than erroring.
  (let ((file (make-temp-file "quarter" nil ".org" "#+title: 2026-Q2 (Work)\n")))
    (unwind-protect
        (should-not (scott-quarterly--file-id file))
      (delete-file file))))

(ert-deftest scott-quarterly-template-work-title-is-suffixed ()
  "Work notes are titled `NAME (Work)'; personal notes are not."
  (let ((work (scott-quarterly--template 'work "2026-Q4"))
        (personal (scott-quarterly--template 'personal "2026-Q4")))
    (should (string-match-p "^#\\+title: 2026-Q4 (Work)$" work))
    (should (string-match-p "^#\\+title: 2026-Q4$" personal))))

(ert-deftest scott-quarterly-template-has-the-agreed-sections ()
  "Rock / Top of Mind / New This Quarter / Workspace, and no Review."
  (let ((out (scott-quarterly--template 'work "2026-Q4")))
    (should (string-match-p "^\\* Rock$" out))
    (should (string-match-p "^\\* Top of Mind$" out))
    (should (string-match-p "^\\* New This Quarter$" out))
    (should (string-match-p "^\\* Workspace$" out))
    (should-not (string-match-p "^\\* Review$" out))
    ;; Exactly four top-level headings.
    (should (= 4 (length (seq-filter (lambda (l) (string-prefix-p "* " l))
                                     (split-string out "\n")))))))

(ert-deftest scott-quarterly-template-carries-a-fresh-id ()
  "Every new note gets its own org-id."
  (let ((a (scott-quarterly--template 'work "2026-Q4"))
        (b (scott-quarterly--template 'work "2026-Q4")))
    (should (string-match-p "^:ID:       [0-9a-zA-Z-]+$" a))
    (should-not (equal a b))))

(ert-deftest scott-quarterly-template-back-links-to-the-prior-quarter ()
  "The prior quarter is linked by id when known, and omitted when not."
  (let ((with-prev (scott-quarterly--template 'work "2026-Q4" "prev-id-9" "2026-Q3"))
        (without (scott-quarterly--template 'work "2026-Q4")))
    (should (string-match-p "\\[\\[id:prev-id-9\\]\\[2026-Q3\\]\\]" with-prev))
    (should-not (string-match-p "\\[\\[id:" without))))
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/dotfiles/ioshi/i-intelligence/emacs
emacs -Q --batch -L lisp -L test -l test/scott-quarterly-test.el -f ert-run-tests-batch-and-exit
```

Expected: FAIL — `scott-quarterly--file-id` and `scott-quarterly--template` are void functions.

- [ ] **Step 3: Write the implementation**

Add to `lisp/scott-quarterly.el`, after `scott-quarterly--default-scope`:

```elisp
(defconst scott-quarterly-sections
  '("Rock" "Top of Mind" "New This Quarter" "Workspace")
  "Top-level headings stamped into a new quarter note.
These are the sections past quarters converged on: Rock is the one big
thing, Top of Mind holds `[[id:]]' links to client and initiative nodes
with Context/P1/P2/Parking lot beneath each, New This Quarter is the
mid-quarter inbox, Workspace is tooling and environment work.")

(defun scott-quarterly--file-id (file)
  "Return the top-level :ID: property of FILE, or nil if it has none."
  (when (and file (file-readable-p file))
    (with-temp-buffer
      (insert-file-contents file nil 0 4096)
      (goto-char (point-min))
      (when (re-search-forward "^:ID:[ \t]+\\([^ \t\n]+\\)" nil t)
        (match-string 1)))))

(defun scott-quarterly--template (scope name &optional prev-id prev-name)
  "Return the buffer text for a new quarter NAME note in SCOPE.
When PREV-ID and PREV-NAME are given, append a link back to that note."
  (concat ":PROPERTIES:\n:ID:       " (org-id-new) "\n:END:\n"
          "#+title: " name (if (eq scope 'work) " (Work)" "") "\n\n"
          (mapconcat (lambda (section) (format "* %s\n\n" section))
                     scott-quarterly-sections "")
          (when (and prev-id prev-name)
            (format "[[id:%s][%s]]\n" prev-id prev-name))))
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/dotfiles/ioshi/i-intelligence/emacs
emacs -Q --batch -L lisp -L test -l test/scott-quarterly-test.el -f ert-run-tests-batch-and-exit
```

Expected: `Ran 10 tests, 10 results as expected, 0 unexpected`.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add ioshi/i-intelligence/emacs/lisp/scott-quarterly.el \
        ioshi/i-intelligence/emacs/test/scott-quarterly-test.el
git commit -m "feat(emacs): quarterly template with sections and prior-quarter back-link

Rock / Top of Mind / New This Quarter / Workspace, work titles suffixed
'(Work)', and an automatic [[id:]] link to the previous quarter."
```

---

### Task 4: Wire up the command — prefix arg and Syncthing guard

**Files:**
- Modify: `ioshi/i-intelligence/emacs/lisp/scott-quarterly.el`
- Modify: `ioshi/i-intelligence/emacs/test/scott-quarterly-test.el`

**Interfaces:**
- Consumes: everything from Tasks 1-3.
- Produces: `(scott-quarterly--create SCOPE NAME FILE)` → creates and visits the note. `(scott-quarterly-open &optional ARG)` — the interactive command bound to `C-c q`.

- [ ] **Step 1: Write the failing tests**

Append to `test/scott-quarterly-test.el`:

```elisp
(ert-deftest scott-quarterly-open-declining-creates-nothing ()
  "Answering no to the create prompt must leave the tree untouched.
An empty note saved here can win a Syncthing conflict against the real
one still in flight (2026-07-16, 2026-Q3)."
  (scott-quarterly-test--with-org-dir '("work/Quarterly/")
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil))
              ((symbol-function 'find-file) (lambda (&rest _) (error "must not visit"))))
      (scott-quarterly-open)
      (should-not (directory-files (expand-file-name "work/Quarterly" org-directory)
                                   nil "\\.org\\'")))))

(ert-deftest scott-quarterly-open-accepting-writes-the-template ()
  "Answering yes creates the note for the current quarter with template text."
  (scott-quarterly-test--with-org-dir '("work/Quarterly/")
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
      (let ((name (scott-quarterly-name)))
        (unwind-protect
            (progn
              (scott-quarterly-open)
              (let ((file (expand-file-name (concat "work/Quarterly/" name ".org")
                                            org-directory)))
                (should (file-exists-p file))
                (with-temp-buffer
                  (insert-file-contents file)
                  (let ((text (buffer-string)))
                    (should (string-match-p (concat "#\\+title: " name " (Work)") text))
                    (should (string-match-p "^\\* Rock$" text))))))
          (dolist (buf (buffer-list))
            (when (and (buffer-file-name buf)
                       (string-prefix-p org-directory (buffer-file-name buf)))
              (kill-buffer buf))))))))

(ert-deftest scott-quarterly-open-links-back-when-prior-quarter-exists ()
  "A prior-quarter note in the same scope is linked from the new note."
  (scott-quarterly-test--with-org-dir '("work/Quarterly/")
    (let* ((name (scott-quarterly-name))
           (prev (scott-quarterly--prev-name name))
           (prev-file (expand-file-name (concat "work/Quarterly/" prev ".org")
                                        org-directory)))
      (write-region (concat ":PROPERTIES:\n:ID:       older-id-7\n:END:\n#+title: "
                            prev " (Work)\n")
                    nil prev-file nil 'silent)
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
        (unwind-protect
            (progn
              (scott-quarterly-open)
              (with-temp-buffer
                (insert-file-contents
                 (expand-file-name (concat "work/Quarterly/" name ".org") org-directory))
                (should (string-match-p
                         (concat "\\[\\[id:older-id-7\\]\\[" prev "\\]\\]")
                         (buffer-string)))))
          (dolist (buf (buffer-list))
            (when (and (buffer-file-name buf)
                       (string-prefix-p org-directory (buffer-file-name buf)))
              (kill-buffer buf))))))))

(ert-deftest scott-quarterly-open-prefix-arg-forces-work-scope ()
  "C-u opens work even when personal is available and would be the default."
  (scott-quarterly-test--with-org-dir '("Quarterly/" "work/Quarterly/")
    (let (visited)
      (cl-letf (((symbol-function 'find-file) (lambda (f) (setq visited f)))
                ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
        (let ((name (scott-quarterly-name)))
          ;; Both notes exist, so no create prompt is involved.
          (write-region "" nil (expand-file-name (concat name ".org") org-directory)
                        nil 'silent)
          (write-region "" nil (expand-file-name (concat "work/Quarterly/" name ".org")
                                                 org-directory)
                        nil 'silent)
          (scott-quarterly-open)
          (should (equal visited (expand-file-name (concat name ".org") org-directory)))
          (scott-quarterly-open '(4))
          (should (equal visited (expand-file-name (concat "work/Quarterly/" name ".org")
                                                   org-directory))))))))
```

These tests use `cl-letf`, so `cl-lib` must already be required at the top of the test file — Task 1 Step 1 added it along with `org`. Confirm both are present before running.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/dotfiles/ioshi/i-intelligence/emacs
emacs -Q --batch -L lisp -L test -l test/scott-quarterly-test.el -f ert-run-tests-batch-and-exit
```

Expected: FAIL — `scott-quarterly-open` takes no prefix argument and writes the old Goals/Active work/Notes template.

- [ ] **Step 3: Write the implementation**

In `lisp/scott-quarterly.el`, replace the whole `scott-quarterly-open` definition carried over in Task 1 with:

```elisp
(defun scott-quarterly--create (scope name file)
  "Create and visit the quarter NAME note for SCOPE at FILE."
  (make-directory (file-name-directory file) t)
  (let* ((prev-name (scott-quarterly--prev-name name))
         (prev-file (scott-quarterly--file scope prev-name))
         (prev-id (and (file-exists-p prev-file)
                       (scott-quarterly--file-id prev-file))))
    (find-file file)
    (when (zerop (buffer-size))
      (insert (scott-quarterly--template scope name prev-id prev-name))
      (save-buffer))))

(defun scott-quarterly-open (&optional arg)
  "Open the current quarter's tracker note.

Scope is chosen by what is on this machine: personal when that tree is
present, work otherwise.  With prefix ARG, always open the work tracker
— that is how the work note is reached on a machine that has both.

If the note does not exist here, do NOT silently create and save an
empty template — that races with Syncthing: on a freshly-synced box the
empty file can win the conflict and quarantine the real, populated note
\(happened 2026-07-16 with 2026-Q3).  Confirm first, so an unsynced note
gets a chance to arrive rather than be clobbered; only a genuinely new
quarter gets a fresh template."
  (interactive "P")
  (let* ((scope (if arg 'work (scott-quarterly--default-scope)))
         (name (scott-quarterly-name))
         (file (scott-quarterly--file scope name)))
    (if (file-exists-p file)
        (find-file file)
      (if (yes-or-no-p
           (format "No %s (%s) note here — create it? (choose no if it may just be unsynced) "
                   name scope))
          (scott-quarterly--create scope name file)
        (message
         "Not creating %s — waiting for sync. Re-run C-c q once it arrives."
         name)))))
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/dotfiles/ioshi/i-intelligence/emacs
emacs -Q --batch -L lisp -L test -l test/scott-quarterly-test.el -f ert-run-tests-batch-and-exit
```

Expected: `Ran 14 tests, 14 results as expected, 0 unexpected`.

- [ ] **Step 5: Byte-compile clean**

```bash
cd ~/dotfiles/ioshi/i-intelligence/emacs
emacs -Q --batch -L lisp --eval '(byte-compile-file "lisp/scott-quarterly.el")' 2>&1 | grep -i "warning\|error"
rm -f lisp/scott-quarterly.elc
```

Expected: no warnings or errors printed.

- [ ] **Step 6: Commit**

```bash
cd ~/dotfiles
git add ioshi/i-intelligence/emacs/lisp/scott-quarterly.el \
        ioshi/i-intelligence/emacs/test/scott-quarterly-test.el
git commit -m "feat(emacs): C-c q opens work tracker where personal is absent

No prefix picks the scope from the trees present on the machine; C-u
forces work. The Syncthing create-guard is preserved for both scopes."
```

---

### Task 5: Migration script, dry run only

Writes the script and proves it correct without touching the synced tree. Execution is Task 6 — a reviewer can approve this script and still reject running it now.

**Files:**
- Create: `tools/migrate-work-quarters.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: an executable script accepting `--dry-run`; honors `WORK_ORG_DIR` (default `$HOME/docs/org/work`) so it can be pointed at a fixture.

- [ ] **Step 1: Write the script**

Create `tools/migrate-work-quarters.sh`:

```bash
#!/usr/bin/env bash
# One-shot: consolidate work quarter notes into $WORK_ORG_DIR/Quarterly/.
#
# Renames <timestamp>-YYYY_qN.org (loose in the work root, or in
# "Quarterly Notes/") to Quarterly/YYYY-QN.org and appends " (Work)" to the
# title. The :ID: property is never touched — every inbound link to these
# notes is an [[id:]] link and resolves through the roam DB by ID.
#
# Usage: migrate-work-quarters.sh [--dry-run]
set -euo pipefail

WORK="${WORK_ORG_DIR:-$HOME/docs/org/work}"
DEST="$WORK/Quarterly"
LEGACY="$WORK/Quarterly Notes"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

[[ -d "$WORK" ]] || { echo "no such work dir: $WORK" >&2; exit 1; }

mapfile -t files < <(find "$WORK" -maxdepth 2 -type f -regextype posix-extended \
  -regex '.*/[0-9]{14}-[0-9]{4}_q[1-4]\.org' | sort)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "nothing to migrate — no <timestamp>-YYYY_qN.org files under $WORK"
  exit 0
fi

for src in "${files[@]}"; do
  base=$(basename "$src" .org)   # 20260718100853-2026_q3
  stem=${base#*-}                # 2026_q3
  year=${stem%%_*}               # 2026
  quarter=${stem##*_q}           # 3
  name="${year}-Q${quarter}"     # 2026-Q3
  target="$DEST/$name.org"

  if [[ -e "$target" ]]; then
    echo "ABORT: $target already exists (would clobber)" >&2
    exit 1
  fi

  # awk, not `grep -oP`: grep here is ugrep, whose PCRE support is partial.
  # ID extraction is what makes these renames link-safe — it must not be clever.
  id=$(awk '/^:ID:/{print $2; exit}' "$src")
  if [[ -z "$id" ]]; then
    echo "ABORT: $src has no :ID: — refusing to move a note whose links cannot resolve" >&2
    exit 1
  fi

  if [[ $DRY -eq 1 ]]; then
    echo "would move: $src"
    echo "        ->: $target"
    echo "      title: #+title: $name (Work)   (id $id preserved)"
    continue
  fi

  mkdir -p "$DEST"
  mv "$src" "$target"
  # Rewrite only the first #+title: line.
  sed -i "0,/^#+title:/s//#+title: $name (Work)/" "$target"
  echo "moved: $name"
done

if [[ $DRY -eq 1 ]]; then
  echo "(dry run — nothing changed)"
  exit 0
fi

if [[ -d "$LEGACY" ]]; then
  if [[ -z "$(ls -A "$LEGACY")" ]]; then
    rmdir "$LEGACY"
    echo "removed empty: $LEGACY"
  else
    echo "NOTE: $LEGACY still has files, leaving it in place:" >&2
    ls -A "$LEGACY" >&2
  fi
fi
```

```bash
chmod +x ~/dotfiles/tools/migrate-work-quarters.sh
```

- [ ] **Step 2: Prove it on a fixture, not the real tree**

```bash
FIX=$(mktemp -d)
mkdir -p "$FIX/Quarterly Notes"
printf ':PROPERTIES:\n:ID:       aaa-111\n:END:\n#+title: 2026-Q3\n\nbody\n' \
  > "$FIX/20260718100853-2026_q3.org"
printf ':PROPERTIES:\n:ID:       bbb-222\n:END:\n#+title: 2025-Q4\n\nbody\n' \
  > "$FIX/Quarterly Notes/20260426142616-2025_q4.org"

WORK_ORG_DIR="$FIX" ~/dotfiles/tools/migrate-work-quarters.sh --dry-run
echo "--- fixture unchanged after dry run? ---"
find "$FIX" -name '*.org' | sort
```

Expected: two `would move:` blocks naming `Quarterly/2026-Q3.org` and `Quarterly/2025-Q4.org`, then the original two paths still listed unchanged.

- [ ] **Step 3: Run it for real against the fixture**

```bash
WORK_ORG_DIR="$FIX" ~/dotfiles/tools/migrate-work-quarters.sh
echo "--- result ---"
find "$FIX" -name '*.org' | sort
grep -H '^#+title:\|^:ID:' "$FIX"/Quarterly/*.org
```

Expected: exactly `$FIX/Quarterly/2025-Q4.org` and `$FIX/Quarterly/2026-Q3.org`; titles `2025-Q4 (Work)` and `2026-Q3 (Work)`; IDs still `bbb-222` and `aaa-111`; `Quarterly Notes/` removed.

- [ ] **Step 4: Verify the clobber guard**

```bash
FIX2=$(mktemp -d)
mkdir -p "$FIX2/Quarterly"
printf ':PROPERTIES:\n:ID:       ccc-333\n:END:\n#+title: 2026-Q3\n' \
  > "$FIX2/20260718100853-2026_q3.org"
touch "$FIX2/Quarterly/2026-Q3.org"
WORK_ORG_DIR="$FIX2" ~/dotfiles/tools/migrate-work-quarters.sh; echo "exit=$?"
rm -rf "$FIX" "$FIX2"
```

Expected: `ABORT: …/Quarterly/2026-Q3.org already exists (would clobber)` and `exit=1`.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add tools/migrate-work-quarters.sh
git commit -m "tools: script to consolidate work quarter notes into Quarterly/

Renames timestamp-prefixed YYYY_qN.org notes to Quarterly/YYYY-QN.org and
suffixes titles with '(Work)'. Preserves :ID:, aborts on clobber."
```

---

### Task 6: Run the migration on the real tree

The only task that touches `~/docs/org/work`. Not reversible by git — that tree has no history.

**Files:**
- Modify: `~/docs/org/work/**` (six note moves, outside the repo)

**Interfaces:**
- Consumes: `tools/migrate-work-quarters.sh` (Task 5), `scott-quarterly-open` (Task 4).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Confirm Syncthing is idle before touching anything**

```bash
key=$(grep -oPm1 '(?<=<apikey>)[^<]+' ~/.local/state/syncthing/config.xml)
addr=$(sed -n '/<gui /,/<\/gui>/p' ~/.local/state/syncthing/config.xml | grep -oPm1 '(?<=<address>)[^<]+')
curl -sf -H "X-API-Key: $key" "http://$addr/rest/db/status?folder=work-docs" \
  | grep -oE '"(state|needFiles|needBytes|globalFiles|localFiles|errors)":[^,}]*'
find ~/docs/org/work -name '*sync-conflict*'
```

Expected: `"state": "idle"`, `needFiles: 0`, `needBytes: 0`, `errors: 0`, `globalFiles` equal to `localFiles`, and no sync-conflict files. **If any of these differ, stop** — a peer has changes in flight and renaming now would race them.

- [ ] **Step 2: Snapshot the tree**

```bash
SCRATCH=/tmp/claude-1000/-home-scott/39f477d3-4a41-436e-a04f-8e64548f5a3a/scratchpad
tar czf "$SCRATCH/work-org-pre-migration.tar.gz" -C ~/docs/org work
ls -la "$SCRATCH/work-org-pre-migration.tar.gz"
```

Expected: an archive of a few MB. This is the only undo.

- [ ] **Step 3: Record the IDs before**

```bash
SCRATCH=/tmp/claude-1000/-home-scott/39f477d3-4a41-436e-a04f-8e64548f5a3a/scratchpad
find ~/docs/org/work -maxdepth 2 -type f -regextype posix-extended \
  -regex '.*/[0-9]{14}-[0-9]{4}_q[1-4]\.org' \
  -exec awk '/^:ID:/{print $2; exit}' {} \; | sort > "$SCRATCH/ids-before.txt"
cat "$SCRATCH/ids-before.txt"; wc -l < "$SCRATCH/ids-before.txt"
```

Expected: 6 IDs — `08e344a6-476d-474f-a2ef-842be7f67658`, `3b7aafda-0001-4936-96d7-b9498b1b176d`, `693fb16d-d670-46ee-ac80-70efccc190ba`, `a23c3e96-84e1-4bc5-bed2-f9e759121b93`, `a3923d75-5e80-4b3a-a0ae-4d0a61f519ac`, `a6798de2-88b0-4d80-b259-194ce2363342`.

- [ ] **Step 4: Dry run against the real tree**

```bash
~/dotfiles/tools/migrate-work-quarters.sh --dry-run
```

Expected: six `would move:` blocks producing `2025-Q2`, `2025-Q3`, `2025-Q4`, `2026-Q1`, `2026-Q2`, `2026-Q3` under `~/docs/org/work/Quarterly/`, and `(dry run — nothing changed)`.

- [ ] **Step 5: Run the migration**

```bash
~/dotfiles/tools/migrate-work-quarters.sh
```

Expected: six `moved:` lines and `removed empty: /home/scott/docs/org/work/Quarterly Notes`.

- [ ] **Step 6: Verify IDs survived and titles are right**

```bash
SCRATCH=/tmp/claude-1000/-home-scott/39f477d3-4a41-436e-a04f-8e64548f5a3a/scratchpad
awk 'FNR==1{found=0} /^:ID:/ && !found {print $2; found=1}' \
  ~/docs/org/work/Quarterly/*.org | sort > "$SCRATCH/ids-after.txt"
diff "$SCRATCH/ids-before.txt" "$SCRATCH/ids-after.txt" && echo "IDS IDENTICAL"
grep -H -m1 '^#+title:' ~/docs/org/work/Quarterly/*.org
ls ~/docs/org/work/Quarterly/
find ~/docs/org/work -maxdepth 2 -regextype posix-extended \
  -regex '.*/[0-9]{14}-[0-9]{4}_q[1-4]\.org'
ls -d "$HOME/docs/org/work/Quarterly Notes" 2>&1
```

Expected: `IDS IDENTICAL`; six titles all ending in ` (Work)`; six files `2025-Q2.org` … `2026-Q3.org`; no timestamp-prefixed quarter files remaining; `Quarterly Notes` reported as missing.

- [ ] **Step 7: Rebuild the org-roam DB and confirm the nodes**

```bash
emacs --batch --eval '(progn
  (require (quote org-roam))
  (setq org-roam-directory (expand-file-name "~/docs/org"))
  (org-roam-db-sync)
  (message "work quarter nodes: %s"
    (org-roam-db-query [:select [title] :from nodes :where (like file $s1)]
                       "%/work/Quarterly/%")))' 2>&1 | tail -3
```

Expected: six titles listed, each suffixed `(Work)`.

- [ ] **Step 8: End-to-end check of the command**

```bash
emacs -Q --batch --eval '(progn
  (add-to-list (quote load-path) (expand-file-name "~/dotfiles/ioshi/i-intelligence/emacs/lisp"))
  (setq org-directory (expand-file-name "~/docs/org"))
  (require (quote scott-quarterly))
  (message "scope=%s file=%s exists=%s"
    (scott-quarterly--default-scope)
    (scott-quarterly--file (scott-quarterly--default-scope))
    (file-exists-p (scott-quarterly--file (scott-quarterly--default-scope)))))'
```

Expected: `scope=work file=/home/scott/docs/org/work/Quarterly/2026-Q3.org exists=t`.

Then in a live Emacs: restart it (the elisp is live-symlinked, so no rebuild is needed) and press `C-c q`. Expect `work/Quarterly/2026-Q3.org` to open with no prompt.

- [ ] **Step 9: Confirm the renames replicated**

```bash
key=$(grep -oPm1 '(?<=<apikey>)[^<]+' ~/.local/state/syncthing/config.xml)
addr=$(sed -n '/<gui /,/<\/gui>/p' ~/.local/state/syncthing/config.xml | grep -oPm1 '(?<=<address>)[^<]+')
curl -sf -H "X-API-Key: $key" "http://$addr/rest/db/status?folder=work-docs" \
  | grep -oE '"(state|needFiles|needBytes|errors)":[^,}]*'
find ~/docs/org/work -name '*sync-conflict*'
```

Expected: back to `"state": "idle"`, `needFiles: 0`, `errors: 0`, no conflict files. **Do not edit quarter notes on another machine until this passes.**

- [ ] **Step 10: Commit the plan's completion note**

Nothing in `~/docs/org/work` is under git, so there is no migration commit. Record the outcome in the repo instead:

```bash
cd ~/dotfiles
git commit --allow-empty -m "chore: work quarter notes migrated to work/Quarterly/

Six notes consolidated, IDs verified identical before and after, roam DB
resynced, Syncthing settled clean. See
docs/superpowers/plans/2026-08-06-work-quarterly-tracker.md."
```

---

## Rollback

If Task 6 goes wrong, restore from the snapshot taken in Step 2 — before letting Syncthing propagate further.

**Stop Syncthing first.** The restore moves the whole folder aside, and a live Syncthing would see that as a mass deletion and replicate it to datacore, destroying the good copy you are trying to recover from:

```bash
systemctl --user stop syncthing.service
systemctl --user is-active syncthing.service   # expect: inactive
```

Then restore:

```bash
SCRATCH=/tmp/claude-1000/-home-scott/39f477d3-4a41-436e-a04f-8e64548f5a3a/scratchpad
mv ~/docs/org/work ~/docs/org/work.broken
tar xzf "$SCRATCH/work-org-pre-migration.tar.gz" -C ~/docs/org
ls ~/docs/org/work | head
```

Confirm the six timestamp-prefixed quarter notes are back, then restart syncing and watch it settle:

```bash
systemctl --user start syncthing.service
```

Recheck folder status with the Step 9 command until it reports `idle` with `needFiles: 0`, then remove `~/docs/org/work.broken`. Rerun the Step 7 roam sync. The elisp from Tasks 1-4 is harmless with an unmigrated tree: `work/Quarterly/` simply will not exist, and `C-c q` falls back to prompting.
