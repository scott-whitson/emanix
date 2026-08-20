;;; eminix-web-test.el --- ERT tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'eminix-web)
(require 'cl-lib)
(require 'seq)
(require 'css-mode)
(require 'mhtml-mode)
(require 'html-ts-mode)
(require 'apheleia nil :no-error)

;; --- eminix-web-template-file-p ---------------------------------------

(ert-deftest eminix-web-template-file-p-direct ()
  "A file directly inside a templates/ directory is a template."
  (should (eminix-web-template-file-p
           "/home/s/projects/pearl-platform/pearl/ui/templates/base.html")))

(ert-deftest eminix-web-template-file-p-nested ()
  "Nesting below templates/ does not stop it being a template."
  (should (eminix-web-template-file-p
           "/home/s/projects/pearl-platform/pearl/ui/templates/partials/row.html")))

(ert-deftest eminix-web-template-file-p-weblorg-layout ()
  "weblorg's theme/templates/ layout matches too."
  (should (eminix-web-template-file-p
           "/home/s/docs/org/websites/eminix/theme/templates/layout.html")))

(ert-deftest eminix-web-template-file-p-no-templates-ancestor ()
  "Plain markup outside a templates/ tree is not a template."
  (should-not (eminix-web-template-file-p
               "/home/s/projects/cd-audit-widgets/x/widget.component.html")))

(ert-deftest eminix-web-template-file-p-file-not-directory ()
  "A FILE named `templates' is not a templates DIRECTORY."
  (should-not (eminix-web-template-file-p "/home/s/projects/pearl/templates")))

(ert-deftest eminix-web-template-file-p-similar-prefix ()
  "Only an exact `templates' component counts, not a prefix of one."
  (should-not (eminix-web-template-file-p "/home/s/templatesx/y.html")))

(ert-deftest eminix-web-template-file-p-nil ()
  "A nil path answers nil rather than signalling."
  (should-not (eminix-web-template-file-p nil)))

;; --- config detection -------------------------------------------------

(defmacro eminix-web-test--with-tree (spec &rest body)
  "Build a temp directory tree from SPEC, bind `root' to it, run BODY.
SPEC is a list of (RELATIVE-PATH . CONTENT).  A path ending in `/' is made
as a directory; otherwise CONTENT (or \"\") is written to it, creating
parents as needed.  The tree is deleted afterwards even if BODY signals."
  (declare (indent 1))
  `(let ((root (file-name-as-directory (make-temp-file "eminix-web-test" t))))
     (unwind-protect
         (progn
           (dolist (entry ,spec)
             (let ((path (expand-file-name (car entry) root)))
               (if (string-suffix-p "/" (car entry))
                   (make-directory path t)
                 (make-directory (file-name-directory path) t)
                 (with-temp-file path (insert (or (cdr entry) ""))))))
           ,@body)
       (delete-directory root t))))

(ert-deftest eminix-web-djlint-configured-p-same-dir ()
  "A .djlintrc beside the file opts that directory in."
  (eminix-web-test--with-tree '((".djlintrc" . "profile=jinja\n"))
    (should (eminix-web-djlint-configured-p root))))

(ert-deftest eminix-web-djlint-configured-p-pyproject-section ()
  "A [tool.djlint] section several levels up opts the tree in."
  (eminix-web-test--with-tree
      '(("pyproject.toml" . "[tool.ruff]\nline-length = 88\n\n[tool.djlint]\nprofile = \"jinja\"\n")
        ("pearl/ui/templates/base.html" . "<div></div>\n"))
    (should (eminix-web-djlint-configured-p
             (expand-file-name "pearl/ui/templates/" root)))))

(ert-deftest eminix-web-djlint-configured-p-pyproject-without-section ()
  "A pyproject.toml with no [tool.djlint] is NOT an opt-in.
Every repo in play has a pyproject.toml; only the section counts."
  (eminix-web-test--with-tree
      '(("pyproject.toml" . "[tool.ruff]\nline-length = 88\n")
        ("pearl/ui/templates/base.html" . "<div></div>\n"))
    (should-not (eminix-web-djlint-configured-p
                 (expand-file-name "pearl/ui/templates/" root)))))

(ert-deftest eminix-web-djlint-configured-p-stops-at-git-root ()
  "The walk stops at the project root; config ABOVE it must not leak in.
Otherwise one stray ~/.djlintrc would silently opt in every repo."
  (eminix-web-test--with-tree
      '((".djlintrc" . "profile=jinja\n")
        ("repo/.git/" . nil)
        ("repo/app/templates/base.html" . "<div></div>\n"))
    (should-not (eminix-web-djlint-configured-p
                 (expand-file-name "repo/app/templates/" root)))))

(ert-deftest eminix-web-djlint-configured-p-finds-config-at-git-root ()
  "Config IN the project root directory is found — the root is inclusive."
  (eminix-web-test--with-tree
      '(("repo/.git/" . nil)
        ("repo/.djlintrc" . "profile=jinja\n")
        ("repo/app/templates/base.html" . "<div></div>\n"))
    (should (eminix-web-djlint-configured-p
             (expand-file-name "repo/app/templates/" root)))))

(ert-deftest eminix-web-djlint-configured-p-nothing-anywhere ()
  "No config anywhere is the default state of every repo today."
  (eminix-web-test--with-tree '(("app/templates/base.html" . "<div></div>\n"))
    (should-not (eminix-web-djlint-configured-p
                 (expand-file-name "app/templates/" root)))))

(ert-deftest eminix-web-prettier-configured-p-dotfile ()
  "Any of prettier's own config filenames opts the tree in."
  (eminix-web-test--with-tree '((".prettierrc.json" . "{}\n"))
    (should (eminix-web-prettier-configured-p root))))

(ert-deftest eminix-web-prettier-configured-p-package-json-key ()
  "A top-level `prettier' key in package.json is an opt-in."
  (eminix-web-test--with-tree
      '(("package.json" . "{\"name\":\"x\",\"prettier\":{\"tabWidth\":2}}\n"))
    (should (eminix-web-prettier-configured-p root))))

(ert-deftest eminix-web-prettier-configured-p-devdependency-only ()
  "prettier as a mere devDependency is NOT a formatting opt-in.
This is why package.json is parsed rather than grepped."
  (eminix-web-test--with-tree
      '(("package.json" . "{\"name\":\"x\",\"devDependencies\":{\"prettier\":\"^3.0.0\"}}\n"))
    (should-not (eminix-web-prettier-configured-p root))))

(ert-deftest eminix-web-prettier-configured-p-malformed-package-json ()
  "Unparseable JSON answers nil rather than signalling into a mode hook."
  (eminix-web-test--with-tree '(("package.json" . "{not json\n"))
    (should-not (eminix-web-prettier-configured-p root))))

;; --- mode dispatch ----------------------------------------------------

(ert-deftest eminix-web-html-mode-template-gets-web-mode ()
  "A template gets web-mode when web-mode is available."
  (skip-unless (fboundp 'web-mode))
  (with-temp-buffer
    (setq buffer-file-name "/tmp/p/pearl/ui/templates/base.html")
    (eminix-web-html-mode)
    (should (eq major-mode 'web-mode))))

(ert-deftest eminix-web-html-mode-plain-html-gets-ts-mode ()
  "Non-template markup gets the built-in tree-sitter mode."
  (skip-unless (treesit-language-available-p 'html))
  (with-temp-buffer
    (setq buffer-file-name "/tmp/p/static/widget.component.html")
    (eminix-web-html-mode)
    (should (eq major-mode 'html-ts-mode))))

(ert-deftest eminix-web-html-mode-never-leaves-fundamental ()
  "Every branch activates SOME html mode, even with nothing available.
A dispatch function that fell through would leave the buffer in
fundamental-mode with no error to explain why."
  (with-temp-buffer
    (setq buffer-file-name "/tmp/p/static/x.html")
    (cl-letf (((symbol-function 'treesit-language-available-p)
               (lambda (&rest _) nil)))
      (eminix-web-html-mode))
    (should-not (eq major-mode 'fundamental-mode))))

;; --- setup isolation ----------------------------------------------------
;;
;; `eminix-web-setup' mutates global state: `auto-mode-alist',
;; `major-mode-remap-alist', `web-mode-engines-alist',
;; `apheleia-skip-functions', and four mode hooks.  Every test that calls
;; it must let-bind all of that, or its `add-to-list'/`add-hook' calls
;; leak into the real global and contaminate every later test in the same
;; batch run.  Fix round 2 found exactly this: an injected mutation to
;; `apheleia-mode-alist' inside `eminix-web-setup' passed the guard test
;; silently when the full suite ran, because an earlier setup-calling test
;; had already leaked that mutation into the real global before the guard
;; test ever took its "before" snapshot.  `apheleia-mode-alist' is not
;; written to by `eminix-web-setup' today, but is bound here anyway, so a
;; test calling `eminix-web-setup' can never leak an unintended future
;; mutation into it either, whether or not it currently does.

(defmacro eminix-web-test--with-setup-isolation (&rest body)
  "Run BODY with every global `eminix-web-setup' can touch let-bound."
  (declare (indent 0))
  `(let ((auto-mode-alist (copy-sequence auto-mode-alist))
         (major-mode-remap-alist (copy-sequence major-mode-remap-alist))
         (web-mode-engines-alist nil)
         (web-mode-hook (copy-sequence web-mode-hook))
         (html-ts-mode-hook (copy-sequence html-ts-mode-hook))
         (mhtml-mode-hook (copy-sequence mhtml-mode-hook))
         (css-base-mode-hook (copy-sequence css-base-mode-hook))
         (apheleia-skip-functions (and (boundp 'apheleia-skip-functions)
                                        (copy-tree apheleia-skip-functions)))
         (apheleia-mode-alist (and (boundp 'apheleia-mode-alist)
                                    (copy-tree apheleia-mode-alist))))
     ,@body))

(ert-deftest eminix-web-setup-claims-html-and-is-idempotent ()
  "setup installs the .html dispatch, and calling it twice adds one entry."
  (eminix-web-test--with-setup-isolation
    (eminix-web-setup)
    (eminix-web-setup)
    (should (eq 'eminix-web-html-mode (cdr (assoc "\\.html?\\'" auto-mode-alist))))
    (should (= 1 (seq-count (lambda (c) (eq (cdr c) 'eminix-web-html-mode))
                            auto-mode-alist)))))

(ert-deftest eminix-web-setup-dispatch-precedes-stock-mhtml ()
  "Our .html entry must sit BEFORE any stock entry, or mhtml-mode wins."
  (eminix-web-test--with-setup-isolation
    (eminix-web-setup)
    (should (eq 'eminix-web-html-mode
                (assoc-default "x.html" auto-mode-alist
                                #'string-match-p nil)))))

(ert-deftest eminix-web-setup-does-not-widen-apheleia-mode-alist ()
  "The gate lives in `apheleia-skip-functions', not `apheleia-mode-alist'.
Asserting the alist is unchanged, not that it is empty: apheleia ships its
OWN non-nil entries for these modes (all prettier, discovered in fix round
1 — `web-mode', `html-ts-mode', `css-ts-mode' and `css-mode' all resolve
to a formatter there already, only `mhtml-mode' is nil), so \"these
entries are nil\" was never a true property of this alist and the earlier
version of this test only looked green because it was skipped in the bare
batch harness that never loaded apheleia.

The \"before\" snapshot is `copy-tree', not `copy-sequence': a shallow
copy shares the entry cons cells with the live alist, so a hypothetical
in-place mutation (`setf'/`setcdr' on an EXISTING entry, as opposed to
`add-to-list' consing on a new one) would change the snapshot right along
with the live value and this `equal' would hold vacuously no matter what
`eminix-web-setup' did."
  (skip-unless (boundp 'apheleia-mode-alist))
  (eminix-web-test--with-setup-isolation
    (let ((before (copy-tree apheleia-mode-alist)))
      (eminix-web-setup)
      (should (equal before apheleia-mode-alist)))))

;; --- format-on-save gate ------------------------------------------------

(ert-deftest eminix-web-apheleia-skip-p-closes-gate-for-unconfigured-template ()
  "No djlint config anywhere in the tree: the gate closes for a template."
  (eminix-web-test--with-tree
      '(("repo/.git/" . nil)
        ("repo/app/templates/base.html" . "<div></div>\n"))
    (with-temp-buffer
      (setq buffer-file-name
            (expand-file-name "repo/app/templates/base.html" root))
      (web-mode)
      (should (eminix-web--apheleia-skip-p)))))

(ert-deftest eminix-web-apheleia-skip-p-opens-gate-for-configured-template ()
  "A `.djlintrc' at the project root opens the gate for that template."
  (eminix-web-test--with-tree
      '(("repo/.git/" . nil)
        ("repo/.djlintrc" . "profile=jinja\n")
        ("repo/app/templates/base.html" . "<div></div>\n"))
    (with-temp-buffer
      (setq buffer-file-name
            (expand-file-name "repo/app/templates/base.html" root))
      (web-mode)
      (should-not (eminix-web--apheleia-skip-p)))))

(ert-deftest eminix-web-apheleia-skip-p-closes-gate-for-unconfigured-css ()
  "No prettier config anywhere in the tree: the gate closes for CSS."
  (eminix-web-test--with-tree
      '(("repo/.git/" . nil)
        ("repo/static/widget.css" . "body {}\n"))
    (with-temp-buffer
      (setq buffer-file-name (expand-file-name "repo/static/widget.css" root))
      (css-mode)
      (should (eminix-web--apheleia-skip-p)))))

(ert-deftest eminix-web-apheleia-skip-p-opens-gate-for-configured-css ()
  "A `.prettierrc.json' at the project root opens the gate for that CSS."
  (eminix-web-test--with-tree
      '(("repo/.git/" . nil)
        ("repo/.prettierrc.json" . "{}\n")
        ("repo/static/widget.css" . "body {}\n"))
    (with-temp-buffer
      (setq buffer-file-name (expand-file-name "repo/static/widget.css" root))
      (css-mode)
      (should-not (eminix-web--apheleia-skip-p)))))

(ert-deftest eminix-web-apheleia-skip-p-no-buffer-file-name-does-not-signal ()
  "An unsaved buffer has no ancestor to look a config up from.
Must return nil, not signal — `and' short-circuits on the nil
`buffer-file-name' before `file-name-directory' ever runs."
  (with-temp-buffer
    (web-mode)
    (should-not (eminix-web--apheleia-skip-p))))

(ert-deftest eminix-web-apheleia-skip-p-ignores-unrelated-modes ()
  "A buffer in some other mode entirely is none of this gate's business."
  (with-temp-buffer
    (setq buffer-file-name "/tmp/p/x.py")
    (fundamental-mode)
    (should-not (eminix-web--apheleia-skip-p))))

;; --- the gate, applied ------------------------------------------------

(ert-deftest eminix-web-djlint-formatter-is-defined ()
  "The djlint formatter definition exists and reads from stdin."
  (skip-unless (boundp 'apheleia-formatters))
  (let ((cmd (alist-get 'djlint apheleia-formatters)))
    (should cmd)
    (should (member "-" cmd))
    (should (member "--reformat" cmd))
    (should (member "--quiet" cmd))
    ;; The bare symbol is deliberate: apheleia evaluates non-string list
    ;; elements at invocation, which is what makes the defcustom reachable.
    (should (memq 'eminix-web-djlint-profile cmd))))

(ert-deftest eminix-web-djlint-profile-defaults-to-jinja ()
  (should (equal "jinja" eminix-web-djlint-profile)))

(ert-deftest eminix-web-gate-closed-sets-no-formatter ()
  "An unconfigured repo gets no formatter, so the skip function blocks the save.
`eminix-web--maybe-enable-djlint' still sets no `apheleia-formatter' here,
but it is `eminix-web--apheleia-skip-p' that is now the operative reason
a save on this buffer stays inert; this assertion just confirms the
buffer-local half of that division of labour holds up its end too."
  (eminix-web-test--with-tree '(("app/templates/base.html" . "<div></div>\n"))
    (with-temp-buffer
      (setq buffer-file-name (expand-file-name "app/templates/base.html" root))
      (eminix-web--maybe-enable-djlint)
      (should-not (and (boundp 'apheleia-formatter) apheleia-formatter)))))

(ert-deftest eminix-web-gate-open-sets-djlint ()
  "A repo declaring djlint config gets djlint on its templates."
  (eminix-web-test--with-tree
      '((".djlintrc" . "profile=jinja\n")
        ("app/templates/base.html" . "<div></div>\n"))
    (with-temp-buffer
      (setq buffer-file-name (expand-file-name "app/templates/base.html" root))
      (eminix-web--maybe-enable-djlint)
      (should (eq 'djlint apheleia-formatter)))))

(ert-deftest eminix-web-gate-open-sets-prettier-css ()
  "CSS buffers get the css parser, not the html one."
  (eminix-web-test--with-tree
      '((".prettierrc" . "{}\n") ("style.css" . "a{color:red}\n"))
    (with-temp-buffer
      (setq buffer-file-name (expand-file-name "style.css" root))
      (css-mode)
      (eminix-web--maybe-enable-prettier)
      (should (eq 'prettier-css apheleia-formatter)))))

(ert-deftest eminix-web-gate-open-sets-prettier-html ()
  "Non-CSS buffers get the html parser."
  (eminix-web-test--with-tree
      '((".prettierrc" . "{}\n") ("page.html" . "<div></div>\n"))
    (with-temp-buffer
      (setq buffer-file-name (expand-file-name "page.html" root))
      (eminix-web--maybe-enable-prettier)
      (should (eq 'prettier-html apheleia-formatter)))))

(ert-deftest eminix-web-gate-tolerates-a-buffer-with-no-file ()
  "A hook must not signal in a buffer that has no file yet."
  (with-temp-buffer
    (should-not (eminix-web--maybe-enable-djlint))
    (should-not (eminix-web--maybe-enable-prettier))))

(provide 'eminix-web-test)
;;; eminix-web-test.el ends here
