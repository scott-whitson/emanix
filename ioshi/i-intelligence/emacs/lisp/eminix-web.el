;;; eminix-web.el --- Jinja2/HTML/CSS modes and gated formatting -*- lexical-binding: t; -*-

;; Jinja2 in this world is 134 plain `.html' files under `templates'
;; directories (FastAPI `Jinja2Templates' in pearl-platform, cd-audit and
;; distrosim).  There is not one `.j2' in the tree, so the file extension
;; cannot pick the major mode.  This file supplies the rule that can.
;;
;; It also gates format-on-save behind the repo's own declared config, and
;; the gate is the point: none of those repos declares any formatter config,
;; and `apheleia-global-mode' is already on.  The gate cannot be "leave
;; `apheleia-mode-alist' untouched" alone: apheleia ships its OWN non-nil
;; entries for `web-mode', `html-ts-mode', `css-ts-mode' and `css-mode' (all
;; prettier), and only `mhtml-mode' formats to nil.  Before this file, every
;; `.html' opened in `mhtml-mode' by the stock `auto-mode-alist' entry, so
;; the "leave it nil" mhtml behaviour was never tested against anything else.
;; Once this file routes `.html' to `web-mode'/`html-ts-mode' on path, that
;; accidental protection is gone, so `eminix-web--apheleia-skip-p' on
;; `apheleia-skip-functions' is the actual gate: it, not
;; `apheleia-mode-alist', decides whether a save formats at all.  The repo
;; owns its formatting — exactly as ruff + pyproject.toml already decides
;; Python line length per repo (pearl 88, distrosim 120) without this config
;; knowing either number.
;;
;; web-mode is soft-required.  A missing package must cost template-aware
;; editing and nothing else; on rafik this Emacs is the compositor.

(require 'treesit)
(require 'seq)
(require 'web-mode nil :no-error)
(require 'apheleia nil :no-error)
;; Loaded here, eagerly, for its SIDE EFFECT and not for any symbol.
;; `html-ts-mode.el' runs (add-to-list 'auto-mode-alist '("\\.html\\'" .
;; html-ts-mode)) at FILE LOAD time, and it is autoloaded — so without this
;; require it first loads the moment `eminix-web-html-mode' dispatches a
;; plain `.html' buffer to `html-ts-mode', and its entry lands AHEAD of the
;; one `eminix-web-setup' prepended.  Our dispatch is then never consulted
;; again: on a daemon, one plain `.html' visit permanently routes every
;; later `.html' — templates included — to `html-ts-mode'.  That is not
;; merely the wrong keymap; it sends templates to the PRETTIER half of the
;; gate, so a `[tool.djlint]'-only repo silently stops formatting and a repo
;; declaring both configs gets prettier run on Jinja2, joining `{% extends
;; %}' and `{% block %}' onto one line.  Requiring it up here means its
;; entry is already installed before ours is prepended, and ours stays in
;; front for the life of the session.
(require 'html-ts-mode nil :no-error)

(defgroup eminix-web nil
  "Major modes and gated format-on-save for Jinja2, HTML and CSS."
  :group 'tools)

(defcustom eminix-web-djlint-profile "jinja"
  "Template language passed to djlint's --profile.

Default suits Jinja2, which is every template tree here.  A tree using a
different template language sets this in .dir-locals.el rather than
patching the distro.

Note that a CLI --profile overrides one set in a repo's own djlint config.
That precedence is intended: the default is correct for every Jinja2 tree,
and a tree that needs otherwise says so locally."
  :type 'string :group 'eminix-web)

(defun eminix-web-template-file-p (file)
  "Non-nil when FILE sits under a directory named `templates'.

A pure function of the path: FILE need not exist.  That is what lets it be
called from `auto-mode-alist' before the buffer is fully set up, and tested
without touching disk.

The check is on path COMPONENTS, not a substring, so `templatesx/' does not
match.  Only the directory part is examined, so a plain file named
`templates' is correctly not a template."
  (and file
       (let ((dir (file-name-directory (expand-file-name file))))
         (and dir
              (member "templates"
                      (split-string (directory-file-name dir) "/" t))
              t))))

;; --- Is this repo asking to be formatted? -----------------------------
;;
;; The gate.  A repo that declares no formatter config is left alone, so
;; installing this feature reformats nothing and the decision to start
;; formatting a tree stays an explicit act in that tree.

(defconst eminix-web--prettier-config-files
  '(".prettierrc" ".prettierrc.json" ".prettierrc.yml" ".prettierrc.yaml"
    ".prettierrc.json5" ".prettierrc.js" ".prettierrc.cjs" ".prettierrc.mjs"
    ".prettierrc.toml" "prettier.config.js" "prettier.config.cjs"
    "prettier.config.mjs")
  "Config filenames prettier itself looks for.
Deliberately prettier's own list: the opt-in signal has to be something
prettier would also honour from the CLI, or editor and command line could
disagree about whether a tree is formatted at all.")

(defun eminix-web--locate-upward (dir predicate)
  "Return the first directory at or above DIR satisfying PREDICATE.

The walk stops after examining a directory containing a `.git' entry —
that directory is the project root and IS itself examined — or at the
filesystem root.  Returns nil when PREDICATE never matches.

Stopping at the project root is deliberate: without it a single stray
~/.djlintrc would silently opt in every repo below it.

Written as an explicit walk rather than through `project-current' so the
predicates stay pure functions of a path, testable against a temporary
tree with no project.el state involved."
  (let ((dir (file-name-as-directory (expand-file-name dir)))
        (result nil)
        (done nil))
    (while (not done)
      (when (funcall predicate dir)
        (setq result dir))
      (cond
       (result (setq done t))
       ((file-exists-p (expand-file-name ".git" dir)) (setq done t))
       (t
        (let ((parent (file-name-directory (directory-file-name dir))))
          (if (or (null parent) (string= parent dir))
              (setq done t)
            (setq dir parent))))))
    result))

(defun eminix-web--pyproject-declares-djlint-p (dir)
  "Non-nil when DIR/pyproject.toml carries a [tool.djlint] section.
The section, not the file: every repo in play has a pyproject.toml, so the
file's mere presence says nothing about formatting."
  (let ((f (expand-file-name "pyproject.toml" dir)))
    (and (file-readable-p f)
         (with-temp-buffer
           (insert-file-contents f)
           (goto-char (point-min))
           (and (re-search-forward "^[ \t]*\\[tool\\.djlint\\]" nil t) t)))))

(defun eminix-web--package-json-declares-prettier-p (dir)
  "Non-nil when DIR/package.json carries a top-level `prettier' key.
Parsed, not grepped: \"prettier\" also appears as a dependency name, and a
devDependency is a build-tool choice, not a request to reformat on save.
Malformed JSON answers nil — this runs from a mode hook and must not
signal on a file someone is mid-edit."
  (let ((f (expand-file-name "package.json" dir)))
    (and (file-readable-p f)
         (with-temp-buffer
           (insert-file-contents f)
           (goto-char (point-min))
           (let ((json (ignore-errors (json-parse-buffer :object-type 'alist))))
             (and json (assq 'prettier json) t))))))

(defun eminix-web-djlint-configured-p (dir)
  "Non-nil when DIR or an ancestor up to the project root declares djlint."
  (and dir
       (eminix-web--locate-upward
        dir
        (lambda (d)
          (or (file-exists-p (expand-file-name ".djlintrc" d))
              (eminix-web--pyproject-declares-djlint-p d))))
       t))

(defun eminix-web-prettier-configured-p (dir)
  "Non-nil when DIR or an ancestor up to the project root declares prettier."
  (and dir
       (eminix-web--locate-upward
        dir
        (lambda (d)
          (or (seq-some (lambda (name)
                          (file-exists-p (expand-file-name name d)))
                        eminix-web--prettier-config-files)
              (eminix-web--package-json-declares-prettier-p d))))
       t))

;; --- Major modes ------------------------------------------------------

(defun eminix-web-html-mode ()
  "Select a major mode for the `.html' file in this buffer.

Installed as the cdr of an `auto-mode-alist' entry, which Emacs calls with
no arguments.  Jinja2 templates and plain markup share the `.html'
extension here, so the choice is made on path.

Every branch activates a mode.  A fall-through would leave the buffer in
`fundamental-mode' with nothing to explain why, so the last clause is the
stock `mhtml-mode' rather than nothing."
  (cond
   ((and (eminix-web-template-file-p buffer-file-name)
         (fboundp 'web-mode))
    (web-mode))
   ((and (fboundp 'html-ts-mode) (treesit-language-available-p 'html))
    (html-ts-mode))
   (t (mhtml-mode))))

(defun eminix-web--maybe-enable-djlint ()
  "Set djlint as this buffer's formatter, if its repo declares djlint config.

Sets `apheleia-formatter' buffer-locally.  This is only half the gate:
`eminix-web--apheleia-skip-p' on `apheleia-skip-functions' is what decides
WHETHER a save formats at all (a repo with no matching config skips, no
matter what this function does).  This function only decides WHAT WITH,
once that gate is already open — apheleia's own stock `web-mode' entry in
`apheleia-mode-alist' is plain prettier, which mangles Jinja2's `{% %}',
so the choice of formatter still has to be made explicitly here."
  (let ((dir (and buffer-file-name (file-name-directory buffer-file-name))))
    (when (and dir (eminix-web-djlint-configured-p dir))
      (setq-local apheleia-formatter 'djlint))))

(defun eminix-web--maybe-enable-prettier ()
  "Set prettier as this buffer's formatter, if its repo declares prettier config.
See `eminix-web--maybe-enable-djlint' for the division of labour between
this and `eminix-web--apheleia-skip-p'."
  (let ((dir (and buffer-file-name (file-name-directory buffer-file-name))))
    (when (and dir (eminix-web-prettier-configured-p dir))
      (setq-local apheleia-formatter
                  (if (derived-mode-p 'css-base-mode)
                      'prettier-css
                    'prettier-html)))))

;; --- Format-on-save gate ------------------------------------------------
;;
;; Registered on `apheleia-skip-functions', not expressed through
;; `apheleia-mode-alist'.  Apheleia consults `apheleia-skip-functions'
;; before every format and skips the buffer if any of them return non-nil;
;; that is the only apheleia extension point this file uses, so
;; `apheleia-mode-alist' — and apheleia's own stock defaults in it — is
;; never touched.  This function decides WHETHER to format; the buffer-local
;; `apheleia-formatter' that Task 5's hook bodies set decides WHAT WITH
;; (apheleia's stock `web-mode' entry is plain prettier, which does not
;; understand Jinja2's `{% %}', so the choice of formatter still has to be
;; ours even once the gate is open).

(defun eminix-web--apheleia-skip-p ()
  "Non-nil when apheleia should skip formatting the current buffer.

Skips only when BOTH hold: the buffer is in a mode this file dispatches
to (`web-mode', `html-ts-mode', `mhtml-mode', or a `css-base-mode'
derivative), and the repo has declared no matching formatter config —
djlint for `web-mode' templates, prettier for the rest.  A buffer with no
`buffer-file-name' — nothing on disk to look an ancestor config up from —
answers nil rather than erroring, since `and' short-circuits before
`file-name-directory' ever sees a nil argument."
  (and buffer-file-name
       (derived-mode-p 'web-mode 'html-ts-mode 'mhtml-mode 'css-base-mode)
       (let ((dir (file-name-directory buffer-file-name)))
         (if (derived-mode-p 'web-mode)
             (not (eminix-web-djlint-configured-p dir))
           (not (eminix-web-prettier-configured-p dir))))))

(defun eminix-web-setup ()
  "Install the mode rules and the gated format-on-save hooks.
Idempotent: `add-to-list' and `add-hook' both no-op on a repeat, so this
is safe to re-run after `M-x load-file' on a live daemon."
  ;; web-mode resolves its engine during mode initialisation, so setting
  ;; `web-mode-engine' afterwards is too late. `web-mode-engines-alist' is
  ;; web-mode's own mechanism: the cdr is a regexp matched against the file
  ;; path. django is the engine name for the Jinja2 family.
  (when (boundp 'web-mode-engines-alist)
    (add-to-list 'web-mode-engines-alist '("django" . "/templates/")))
  ;; Prepend, so this beats both the stock `.html' -> mhtml-mode entry and
  ;; the `.html' -> html-ts-mode one that `html-ts-mode.el' installs when it
  ;; loads (which the eager require at the top of this file has already
  ;; forced to happen by now — see the comment there; without it that entry
  ;; would arrive LATER and land in front of this one). Both are
  ;; deliberately left in place: if this file ever fails to load, .html
  ;; still opens in a working mode.
  (add-to-list 'auto-mode-alist '("\\.html?\\'" . eminix-web-html-mode))
  (when (treesit-language-available-p 'css)
    (add-to-list 'major-mode-remap-alist '(css-mode . css-ts-mode)))
  ;; The actual gate — see the comment above `eminix-web--apheleia-skip-p'.
  ;; Soft-required: apheleia is expected everywhere in this distro
  ;; (config.el requires it unconditionally), but a unit test loading only
  ;; this file, or some future Emacs without it, must not error here.
  (when (boundp 'apheleia-skip-functions)
    (add-hook 'apheleia-skip-functions #'eminix-web--apheleia-skip-p))
  ;; One hook covers both CSS modes: `css-mode' and `css-ts-mode' both
  ;; derive from `css-base-mode' (verified 2026-08-20), and a derived mode
  ;; runs its parent's hooks.
  (add-hook 'web-mode-hook #'eminix-web--maybe-enable-djlint)
  (add-hook 'html-ts-mode-hook #'eminix-web--maybe-enable-prettier)
  (add-hook 'mhtml-mode-hook #'eminix-web--maybe-enable-prettier)
  (add-hook 'css-base-mode-hook #'eminix-web--maybe-enable-prettier))

;; djlint is the one formatter apheleia does not ship. prettier-html and
;; prettier-css are built in and need no definition; both route through
;; apheleia's bundled apheleia-npx script, which execs from $PATH when no
;; package.json sits above the file — so the Nix-installed prettier runs and
;; no node_modules is required.
;;
;; Three things here are load-bearing and must not be "tidied":
;;
;;   "-"                     djlint's read-from-stdin argument. apheleia's
;;                           default, absent input/inplace/file, is to write
;;                           the buffer to stdin and splice back stdout --
;;                           the same deal the bare ("nixpkgs-fmt") entry in
;;                           config.el relies on. Both halves must agree.
;;   eminix-web-djlint-profile   A BARE SYMBOL, not a string. apheleia
;;                           evaluates any list element that is not a string
;;                           and not one of its special forms (npx, input,
;;                           output, inplace, file, filepath, scratch), so
;;                           this splices in the defcustom's value at
;;                           invocation. Quoting it would hardcode the
;;                           profile and strip the .dir-locals.el override.
;;   "--quiet"               Suppresses the diff djlint prints by default,
;;                           which would otherwise land on stdout and be
;;                           spliced into the buffer as if it were content.
(with-eval-after-load 'apheleia
  (setf (alist-get 'djlint apheleia-formatters)
        '("djlint" "-" "--reformat"
          "--profile" eminix-web-djlint-profile
          "--quiet")))

(provide 'eminix-web)
;;; eminix-web.el ends here
