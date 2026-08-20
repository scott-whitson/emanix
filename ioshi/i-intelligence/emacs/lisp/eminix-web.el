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

(provide 'eminix-web)
;;; eminix-web.el ends here
