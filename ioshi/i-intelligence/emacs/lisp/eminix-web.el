;;; eminix-web.el --- Jinja2/HTML/CSS modes and gated formatting -*- lexical-binding: t; -*-

;; Jinja2 in this world is 134 plain `.html' files under `templates'
;; directories (FastAPI `Jinja2Templates' in pearl-platform, cd-audit and
;; distrosim).  There is not one `.j2' in the tree, so the file extension
;; cannot pick the major mode.  This file supplies the rule that can.
;;
;; It also gates format-on-save behind the repo's own declared config, and
;; the gate is the point: none of those repos declares any formatter config,
;; and `apheleia-global-mode' is already on, so an ungated hook would rewrite
;; all 134 files on their first save.  The repo owns its formatting — exactly
;; as ruff + pyproject.toml already decides Python line length per repo
;; (pearl 88, distrosim 120) without this config knowing either number.
;;
;; web-mode is soft-required.  A missing package must cost template-aware
;; editing and nothing else; on rafik this Emacs is the compositor.

(require 'treesit)
(require 'seq)
(require 'web-mode nil :no-error)

(defgroup eminix-web nil
  "Major modes and gated format-on-save for Jinja2, HTML and CSS."
  :group 'tools)

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
  "Placeholder; implemented in Task 5."
  nil)

(defun eminix-web--maybe-enable-prettier ()
  "Placeholder; implemented in Task 5."
  nil)

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
  ;; Prepend, so this beats the stock `.html' -> mhtml-mode entry. That entry
  ;; is deliberately left in place: if this file ever fails to load, .html
  ;; still opens in a working mode.
  (add-to-list 'auto-mode-alist '("\\.html?\\'" . eminix-web-html-mode))
  (when (treesit-language-available-p 'css)
    (add-to-list 'major-mode-remap-alist '(css-mode . css-ts-mode)))
  ;; Format-on-save gate. One hook covers both CSS modes: `css-mode' and
  ;; `css-ts-mode' both derive from `css-base-mode' (verified 2026-08-20),
  ;; and a derived mode runs its parent's hooks.
  (add-hook 'web-mode-hook #'eminix-web--maybe-enable-djlint)
  (add-hook 'html-ts-mode-hook #'eminix-web--maybe-enable-prettier)
  (add-hook 'mhtml-mode-hook #'eminix-web--maybe-enable-prettier)
  (add-hook 'css-base-mode-hook #'eminix-web--maybe-enable-prettier))

(provide 'eminix-web)
;;; eminix-web.el ends here
