;;; eminix-prose.el --- render markdown/org as prose -*- lexical-binding: t; -*-

;; Opening a documentation file should look like reading a document, not like
;; editing source.  This mode gives markdown-mode and org-mode buffers a
;; proportional body font, scaled headings, a centered reading column, and
;; hidden markup.
;;
;; Everything is applied with `face-remap-add-relative' and `setq-local', so it
;; is confined to the buffer and removed exactly on disable.  Nothing here may
;; use `set-face-attribute': that is global, would leak into every other
;; buffer, and would fight eminix-theme.el.
;;
;; Every optional dependency is soft-required.  On rafik this Emacs is the
;; compositor; a missing package must cost the prose look and nothing else.

(require 'face-remap)
(require 'eminix-theme nil :no-error)
(require 'markdown-mode nil :no-error)
(require 'org nil :no-error)

(eval-when-compile (require 'subr-x))

(declare-function eminix/theme-palette-color "eminix-theme" (key))
(declare-function markdown-toggle-markup-hiding "markdown-mode" (&optional arg))
(declare-function markdown-display-inline-images "markdown-mode" ())
(declare-function visual-fill-column-mode "visual-fill-column" (&optional arg))
(declare-function org-modern-mode "org-modern" (&optional arg))
(declare-function org-appear-mode "org-appear" (&optional arg))

(defgroup eminix-prose nil
  "Render markdown and org buffers as prose."
  :group 'text)

(defcustom eminix-prose-body-font "IBM Plex Sans"
  "Proportional family used for body text."
  :type 'string :group 'eminix-prose)

(defcustom eminix-prose-heading-font "IBM Plex Serif"
  "Family used for headings."
  :type 'string :group 'eminix-prose)

(defcustom eminix-prose-mono-font "JetBrainsMono Nerd Font"
  "Monospace family for code, fences and tables.
Tables align by character count; under a proportional font they break."
  :type 'string :group 'eminix-prose)

(defcustom eminix-prose-width 90
  "Width in characters of the centered reading column."
  :type 'integer :group 'eminix-prose)

(defcustom eminix-prose-heading-scales '(1.6 1.4 1.25 1.15 1.05 1.0)
  "Height multipliers for heading levels 1-6."
  :type '(repeat number) :group 'eminix-prose)

(defvar-local eminix-prose--cookies nil
  "Face-remap cookies added by `eminix-prose-mode' in this buffer.")

(defvar-local eminix-prose--line-numbers-prior nil
  "Whether `display-line-numbers-mode' was on before this mode turned it off.
`on', `off', or nil when nothing has been recorded yet.  Recorded only on
the first enable: the body of a minor mode re-runs on every
\(eminix-prose-mode 1) call, and by the second call line numbers are already
off — re-recording there would forget they had ever been on.")

(defun eminix-prose--heading-remaps (face-prefix)
  "Return heading remaps for FACE-PREFIX (\"markdown-header-face-\" or \"org-level-\")."
  (let ((n 0))
    (mapcar (lambda (scale)
              (setq n (1+ n))
              (cons (intern (format "%s%d" face-prefix n))
                    (list :family eminix-prose-heading-font
                          :weight 'semibold
                          :height scale)))
            eminix-prose-heading-scales)))

(defun eminix-prose--mono (faces)
  "Return remaps forcing FACES back to `eminix-prose-mono-font'."
  (mapcar (lambda (f) (cons f (list :family eminix-prose-mono-font))) faces))

(defun eminix-prose--code-background ()
  "Plist adding the theme's code-block background, or nil if unavailable."
  (when-let* ((bg (and (fboundp 'eminix/theme-palette-color)
                       (eminix/theme-palette-color "surface0"))))
    (list :background bg :extend t)))

(defun eminix-prose--face-remaps ()
  "Return the alist of (FACE . PLIST) remaps for the current major mode."
  (let ((bg (eminix-prose--code-background)))
    (cond
     ((derived-mode-p 'markdown-mode)
      (append
       (eminix-prose--heading-remaps "markdown-header-face-")
       (eminix-prose--mono '(markdown-pre-face
                            markdown-inline-code-face
                            markdown-table-face
                            markdown-language-keyword-face
                            markdown-markup-face
                            markdown-gfm-checkbox-face))
       (list (cons 'markdown-code-face
                   (append (list :family eminix-prose-mono-font) bg))
             (cons 'markdown-list-face
                   (list :family eminix-prose-mono-font)))))
     ((derived-mode-p 'org-mode)
      (append
       (eminix-prose--heading-remaps "org-level-")
       (eminix-prose--mono '(org-code org-verbatim org-table org-meta-line
                            org-formula org-checkbox org-block-begin-line
                            org-block-end-line))
       (list (cons 'org-block
                   (append (list :family eminix-prose-mono-font) bg)))))
     (t nil))))

(defun eminix-prose--apply-faces ()
  "Apply the remap table for this buffer, recording the cookies."
  (setq eminix-prose--cookies
        (append
         (list (face-remap-add-relative 'variable-pitch
                                        :family eminix-prose-body-font))
         (mapcar (lambda (entry)
                   (apply #'face-remap-add-relative (car entry) (cdr entry)))
                 (eminix-prose--face-remaps))))
  (variable-pitch-mode 1))

(defun eminix-prose--unapply-faces ()
  "Remove every face remap this mode added."
  (variable-pitch-mode -1)
  (mapc #'face-remap-remove-relative eminix-prose--cookies)
  (setq eminix-prose--cookies nil))

;; --- Markup hiding, revealed at point -------------------------------------
;;
;; markdown-mode hides markup by putting an `invisible' text property on it
;; during fontification, but has no reveal-at-point of its own (org gets that
;; from org-appear).  So: remove the property over the line point is on, and
;; restore it by refontifying that line once point leaves.
;;
;; Reveal is line-granular on purpose.  Point inside **bold** sits BETWEEN the
;; two invisible runs, so an element-precise version would have to re-parse
;; markdown at point.  A line is where editing happens and is cheap to restore.

(defvar-local eminix-prose--revealed nil
  "Cons (BEG . END) of the region whose markup is currently revealed.")

(defvar-local eminix-prose--added-display-prop nil
  "Non-nil if this mode added `display' to `font-lock-extra-managed-props'.
The major mode may already manage `display' itself — markdown-mode does,
once `markdown-hide-markup' is set — so teardown must retract only our own
addition rather than killing the variable and taking the major mode's
bookkeeping with it.")

(defun eminix-prose--rehide ()
  "Restore markup hidden before the last reveal."
  (when eminix-prose--revealed
    (let ((beg (car eminix-prose--revealed))
          (end (cdr eminix-prose--revealed)))
      (setq eminix-prose--revealed nil)
      (when (and (<= (point-min) beg) (<= end (point-max)))
        (font-lock-flush beg end)
        (font-lock-ensure beg end)))))

(defun eminix-prose--reveal-at-point ()
  "Reveal hidden markup on the line at point, rehiding the previous line."
  (let ((beg (line-beginning-position))
        (end (line-end-position)))
    (unless (equal eminix-prose--revealed (cons beg end))
      (eminix-prose--rehide)
      (with-silent-modifications
        (remove-text-properties beg end '(invisible nil)))
      (setq eminix-prose--revealed (cons beg end)))))

;; --- Reading column, bullets, images --------------------------------------

(defun eminix-prose--match-list-bullet (limit)
  "Font-lock matcher for an unordered list marker, searching to LIMIT.
Skips thematic breaks (`* * *', `- - -'), which share the marker-space
prefix with a list item but are horizontal rules.  Sets the match data
so group 1 is the marker character."
  (let (found)
    (while (and (not found)
                (re-search-forward "^[ \t]*\\([-*+]\\)[ \t]+" limit t))
      (unless (save-excursion
                (goto-char (line-beginning-position))
                (looking-at-p
                 "[ \t]*\\([-*+]\\)[ \t]*\\(?:\\1[ \t]*\\)\\{2,\\}$"))
        (setq found t)))
    found))

(defconst eminix-prose--bullet-keywords
  '((eminix-prose--match-list-bullet 1 '(face nil display "•")))
  "Font-lock keywords displaying unordered list markers as a bullet.
Ordered lists are untouched — a numbered list carries information a
bullet would throw away — and so are thematic breaks, see the matcher.")

(defun eminix-prose--buffer-has-images-p ()
  "Non-nil if the buffer contains a markdown image link."
  (save-excursion
    (goto-char (point-min))
    (and (re-search-forward "!\\[[^]]*\\]([^)]+)" nil t) t)))

(defun eminix-prose--setup-column ()
  "Turn on visual wrapping in a centered reading column."
  (visual-line-mode 1)
  (when (require 'visual-fill-column nil :no-error)
    (setq-local visual-fill-column-width eminix-prose-width)
    (setq-local visual-fill-column-center-text t)
    (visual-fill-column-mode 1)))

(defun eminix-prose--teardown-column ()
  "Undo `eminix-prose--setup-column'."
  (when (fboundp 'visual-fill-column-mode)
    (visual-fill-column-mode -1))
  (kill-local-variable 'visual-fill-column-width)
  (kill-local-variable 'visual-fill-column-center-text)
  (visual-line-mode -1))

;;;###autoload
(define-minor-mode eminix-prose-mode
  "Render the current markdown or org buffer as prose."
  :lighter " Prose"
  :group 'eminix-prose
  (if eminix-prose-mode
      (progn
        (eminix-prose--unapply-faces)   ; idempotent: re-enabling must not stack
        (eminix-prose--apply-faces)
        (setq-local line-spacing 0.25)
        (unless eminix-prose--line-numbers-prior
          (setq eminix-prose--line-numbers-prior
                (if (bound-and-true-p display-line-numbers-mode) 'on 'off)))
        (when (eq eminix-prose--line-numbers-prior 'on)
          (display-line-numbers-mode -1))
        (when (derived-mode-p 'markdown-mode)
          (setq-local markdown-hide-markup t)
          (add-hook 'post-command-hook #'eminix-prose--reveal-at-point nil t))
        (when (derived-mode-p 'org-mode)
          ;; Reveal-at-point comes from org-appear here; the hand-rolled
          ;; markdown hook must not also attach, or the two fight over the
          ;; same invisible properties.
          (setq-local org-hide-emphasis-markers t)
          (when (require 'org-modern nil :no-error) (org-modern-mode 1))
          (when (require 'org-appear nil :no-error) (org-appear-mode 1)))
        (eminix-prose--setup-column)
        ;; font-lock only removes properties it is told it manages. Without
        ;; `display' here the bullets would be applied but never cleaned up,
        ;; so disabling the mode would leave • behind on every list marker.
        (unless (memq 'display font-lock-extra-managed-props)
          (setq-local font-lock-extra-managed-props
                      (cons 'display font-lock-extra-managed-props))
          (setq eminix-prose--added-display-prop t))
        (font-lock-add-keywords nil eminix-prose--bullet-keywords t)
        (when (and (derived-mode-p 'markdown-mode)
                   (eminix-prose--buffer-has-images-p)
                   (fboundp 'markdown-display-inline-images))
          (setq-local markdown-max-image-size
                      (cons (* eminix-prose-width (default-font-width)) nil))
          (ignore-errors (markdown-display-inline-images)))
        (font-lock-flush)
        (font-lock-ensure))
    (eminix-prose--unapply-faces)
    (kill-local-variable 'line-spacing)
    (when (eq eminix-prose--line-numbers-prior 'on)
      (display-line-numbers-mode 1))
    (setq eminix-prose--line-numbers-prior nil)
    (remove-hook 'post-command-hook #'eminix-prose--reveal-at-point t)
    (setq eminix-prose--revealed nil)
    (when (derived-mode-p 'markdown-mode)
      (kill-local-variable 'markdown-hide-markup))
    (when (derived-mode-p 'org-mode)
      (kill-local-variable 'org-hide-emphasis-markers)
      (when (fboundp 'org-modern-mode) (org-modern-mode -1))
      (when (fboundp 'org-appear-mode) (org-appear-mode -1)))
    (font-lock-remove-keywords nil eminix-prose--bullet-keywords)
    (eminix-prose--teardown-column)
    (kill-local-variable 'markdown-max-image-size)
    (font-lock-flush)
    (font-lock-ensure)
    ;; Done only after the flush/ensure above: font-lock strips a managed
    ;; prop from stale text during that refontification by consulting this
    ;; variable's CURRENT value, so retracting it first would drop `display'
    ;; before the • display properties get a chance to be cleaned up.
    (when eminix-prose--added-display-prop
      (setq-local font-lock-extra-managed-props
                  (remq 'display font-lock-extra-managed-props))
      (setq eminix-prose--added-display-prop nil))))

;;;###autoload
(defun eminix-prose-toggle ()
  "Toggle `eminix-prose-mode' in the current buffer."
  (interactive)
  (eminix-prose-mode (if eminix-prose-mode -1 1)))

(provide 'eminix-prose)
;;; eminix-prose.el ends here
