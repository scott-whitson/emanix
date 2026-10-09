;;; emanix-prose.el --- render org as prose -*- lexical-binding: t; -*-

;; Opening a documentation file should look like reading a document, not like
;; editing source.  This mode gives org-mode buffers a proportional body font,
;; scaled headings, a centered reading column, org-modern boxes and org-appear
;; reveal.
;;
;; Markdown rendering is handled by markdown-modern (a separate major mode),
;; not by this file.
;;
;; Everything is applied with `face-remap-add-relative' and `setq-local', so it
;; is confined to the buffer and removed exactly on disable.  Nothing here may
;; use `set-face-attribute': that is global, would leak into every other
;; buffer, and would fight emanix-theme.el.
;;
;; Every optional dependency is soft-required.  On rafik this Emacs is the
;; compositor; a missing package must cost the prose look and nothing else.

(require 'face-remap)
(require 'emanix-theme nil :no-error)
(require 'org nil :no-error)

(eval-when-compile (require 'subr-x))

(declare-function emanix/theme-palette-color "emanix-theme" (key))
(declare-function visual-fill-column-mode "visual-fill-column" (&optional arg))
(declare-function org-modern-mode "org-modern" (&optional arg))
(declare-function org-appear-mode "org-appear" (&optional arg))

(defgroup emanix-prose nil
  "Render org buffers as prose."
  :group 'text)

(defcustom emanix-prose-body-font "IBM Plex Sans"
  "Proportional family used for body text."
  :type 'string :group 'emanix-prose)

(defcustom emanix-prose-heading-font "IBM Plex Serif"
  "Family used for headings."
  :type 'string :group 'emanix-prose)

(defcustom emanix-prose-mono-font "JetBrains Mono"
  "Monospace family for code, tables and blocks."
  :type 'string :group 'emanix-prose)

(defcustom emanix-prose-width 90
  "Width in characters of the centered reading column."
  :type 'integer :group 'emanix-prose)

(defcustom emanix-prose-left-margin 4
  "Left margin width in characters.
Creates whitespace on the left side of the buffer for better readability."
  :type 'integer :group 'emanix-prose)

(defcustom emanix-prose-heading-scales '(1.6 1.4 1.25 1.15 1.05 1.0)
  "Height multipliers for heading levels 1-6."
  :type '(repeat number) :group 'emanix-prose)

(defvar-local emanix-prose--cookies nil
  "Face-remap cookies added by `emanix-prose-mode' in this buffer.")

(defvar-local emanix-prose--line-numbers-prior nil
  "Whether `display-line-numbers-mode' was on before this mode turned it off.
`on', `off', or nil when nothing has been recorded yet.  Recorded only on
the first enable: the body of a minor mode re-runs on every
\(emanix-prose-mode 1) call, and by the second call line numbers are already
off — re-recording there would forget they had ever been on.")

(defun emanix-prose--heading-remaps ()
  "Return heading remaps for org-level-{1..6}."
  (let ((n 0))
    (mapcar (lambda (scale)
              (setq n (1+ n))
              (cons (intern (format "org-level-%d" n))
                    (list :family emanix-prose-heading-font
                          :weight 'semibold
                          :height scale)))
            emanix-prose-heading-scales)))

(defun emanix-prose--mono (faces)
  "Return remaps forcing FACES to `emanix-prose-mono-font'."
  (mapcar (lambda (f) (cons f (list :family emanix-prose-mono-font))) faces))

(defun emanix-prose--code-background ()
  "Plist adding the theme's code-block background, or nil if unavailable."
  (when-let* ((bg (and (fboundp 'emanix/theme-palette-color)
                       (emanix/theme-palette-color "surface0"))))
    (list :background bg :extend t)))

(defun emanix-prose--face-remaps ()
  "Return the alist of (FACE . PLIST) remaps for the current buffer."
  (let ((bg (emanix-prose--code-background)))
    (append
     (emanix-prose--heading-remaps)
     (emanix-prose--mono '(org-code org-verbatim org-table org-meta-line
                          org-formula org-checkbox org-block-begin-line
                          org-block-end-line))
     (list (cons 'org-block
                 (append (list :family emanix-prose-mono-font) bg))))))

(defun emanix-prose--apply-faces ()
  "Apply the remap table for this buffer, recording the cookies."
  (setq emanix-prose--cookies
        (append
         (list (face-remap-add-relative 'variable-pitch
                                        :family emanix-prose-body-font))
         (mapcar (lambda (entry)
                   (apply #'face-remap-add-relative (car entry) (cdr entry)))
                 (emanix-prose--face-remaps))))
  (variable-pitch-mode 1))

(defun emanix-prose--unapply-faces ()
  "Remove every face remap this mode added."
  (variable-pitch-mode -1)
  (mapc #'face-remap-remove-relative emanix-prose--cookies)
  (setq emanix-prose--cookies nil))

;; --- Reading column, left margin ------------------------------------------

(defun emanix-prose--setup-column ()
  "Turn on visual wrapping in a centered reading column with a left margin."
  (let ((indent-str (propertize (make-string emanix-prose-left-margin ?\s)
                                'face 'default)))
    (setq-local line-prefix indent-str)
    (setq-local wrap-prefix indent-str))
  (visual-line-mode 1)
  (when (require 'visual-fill-column nil :no-error)
    (setq-local visual-fill-column-width emanix-prose-width)
    (setq-local visual-fill-column-center-text t)
    (visual-fill-column-mode 1)))

(defun emanix-prose--teardown-column ()
  "Undo `emanix-prose--setup-column'."
  (kill-local-variable 'line-prefix)
  (kill-local-variable 'wrap-prefix)
  (when (fboundp 'visual-fill-column-mode)
    (visual-fill-column-mode -1))
  (kill-local-variable 'visual-fill-column-width)
  (kill-local-variable 'visual-fill-column-center-text)
  (visual-line-mode -1))

;;;###autoload
(define-minor-mode emanix-prose-mode
  "Render the current org buffer as prose."
  :lighter " Prose"
  :group 'emanix-prose
  (if emanix-prose-mode
      (progn
        (emanix-prose--unapply-faces)   ; idempotent: re-enabling must not stack
        (emanix-prose--apply-faces)
        (setq-local line-spacing 0.25)
        (unless emanix-prose--line-numbers-prior
          (setq emanix-prose--line-numbers-prior
                (if (bound-and-true-p display-line-numbers-mode) 'on 'off)))
        (when (eq emanix-prose--line-numbers-prior 'on)
          (display-line-numbers-mode -1))
        (when (derived-mode-p 'org-mode)
          (setq-local org-hide-emphasis-markers t)
          (when (require 'org-modern nil :no-error) (org-modern-mode 1))
          (when (require 'org-appear nil :no-error) (org-appear-mode 1)))
        (emanix-prose--setup-column)
        (font-lock-flush)
        (font-lock-ensure))
    (emanix-prose--unapply-faces)
    (kill-local-variable 'line-spacing)
    (when (eq emanix-prose--line-numbers-prior 'on)
      (display-line-numbers-mode 1))
    (setq emanix-prose--line-numbers-prior nil)
    (when (derived-mode-p 'org-mode)
      (kill-local-variable 'org-hide-emphasis-markers)
      (when (fboundp 'org-modern-mode) (org-modern-mode -1))
      (when (fboundp 'org-appear-mode) (org-appear-mode -1)))
    (emanix-prose--teardown-column)
    (font-lock-flush)
    (font-lock-ensure))))

;;;###autoload
(defun emanix-prose-toggle ()
  "Toggle `emanix-prose-mode' in the current buffer."
  (interactive)
  (emanix-prose-mode (if emanix-prose-mode -1 1)))

;; --- Magnification ---------------------------------------------------------
;;
;; The reading column is fixed and the heading scales are fixed, so a reader
;; who needs larger type had no way to enlarge the document.  These wrap
;; Emacs's own text scaling, which remaps the default face in the buffer:
;; every face built on it (body, headings, code, drawn tables) grows together,
;; and the setting is per buffer, so no other document changes.

;;;###autoload
(defun emanix-prose-increase-magnification (&optional n)
  "Enlarge the current document N steps (default 1, or the prefix argument)."
  (interactive "p")
  (text-scale-increase (or n 1)))

;;;###autoload
(defun emanix-prose-decrease-magnification (&optional n)
  "Shrink the current document N steps (default 1, or the prefix argument)."
  (interactive "p")
  (text-scale-decrease (or n 1)))

;;;###autoload
(defun emanix-prose-reset-magnification ()
  "Return the current document to its default size."
  (interactive)
  (text-scale-set 0))

(provide 'emanix-prose)
;;; emanix-prose.el ends here