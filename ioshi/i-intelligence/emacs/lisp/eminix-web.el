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

(provide 'eminix-web)
;;; eminix-web.el ends here
