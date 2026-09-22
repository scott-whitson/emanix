;;; emanix-prose.el --- render markdown/org as prose -*- lexical-binding: t; -*-

;; Opening a documentation file should look like reading a document, not like
;; editing source.  This mode gives markdown-mode and org-mode buffers a
;; proportional body font, scaled headings, a centered reading column, and
;; hidden markup.
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
(require 'markdown-mode nil :no-error)
(require 'org nil :no-error)

(eval-when-compile (require 'subr-x))

(declare-function emanix/theme-palette-color "emanix-theme" (key))
(declare-function markdown-toggle-markup-hiding "markdown-mode" (&optional arg))
(declare-function markdown-display-inline-images "markdown-mode" ())
(declare-function markdown-table-at-point-p "markdown-mode" ())
(declare-function markdown-table-begin "markdown-mode" ())
(declare-function markdown-table-end "markdown-mode" ())
(declare-function markdown-table-colfmt "markdown-mode" (fmtspec))
(declare-function markdown--remove-invisible-markup "markdown-mode" (s))
(declare-function visual-fill-column-mode "visual-fill-column" (&optional arg))
(declare-function org-modern-mode "org-modern" (&optional arg))
(declare-function org-appear-mode "org-appear" (&optional arg))

(defgroup emanix-prose nil
  "Render markdown and org buffers as prose."
  :group 'text)

(defcustom emanix-prose-body-font "IBM Plex Sans"
  "Proportional family used for body text."
  :type 'string :group 'emanix-prose)

(defcustom emanix-prose-heading-font "IBM Plex Serif"
  "Family used for headings."
  :type 'string :group 'emanix-prose)

(defcustom emanix-prose-mono-font "JetBrains Mono"
  "Monospace family for code, fences and tables.
Tables align by character count; under a proportional font they break."
  :type 'string :group 'emanix-prose)

(defcustom emanix-prose-width 90
  "Width in characters of the centered reading column."
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

(defun emanix-prose--heading-remaps (face-prefix)
  "Return heading remaps for FACE-PREFIX (\"markdown-header-face-\" or \"org-level-\")."
  (let ((n 0))
    (mapcar (lambda (scale)
              (setq n (1+ n))
              (cons (intern (format "%s%d" face-prefix n))
                    (list :family emanix-prose-heading-font
                          :weight 'semibold
                          :height scale)))
            emanix-prose-heading-scales)))

(defun emanix-prose--mono (faces)
  "Return remaps forcing FACES back to `emanix-prose-mono-font'."
  (mapcar (lambda (f) (cons f (list :family emanix-prose-mono-font))) faces))

(defun emanix-prose--code-background ()
  "Plist adding the theme's code-block background, or nil if unavailable."
  (when-let* ((bg (and (fboundp 'emanix/theme-palette-color)
                       (emanix/theme-palette-color "surface0"))))
    (list :background bg :extend t)))

(defun emanix-prose--face-remaps ()
  "Return the alist of (FACE . PLIST) remaps for the current major mode."
  (let ((bg (emanix-prose--code-background)))
    (cond
     ((derived-mode-p 'markdown-mode)
      (append
       (emanix-prose--heading-remaps "markdown-header-face-")
       (emanix-prose--mono '(markdown-pre-face
                            markdown-inline-code-face
                            markdown-table-face
                            markdown-language-keyword-face
                            markdown-markup-face
                            markdown-gfm-checkbox-face))
       (list (cons 'markdown-code-face
                   (append (list :family emanix-prose-mono-font) bg))
             (cons 'markdown-list-face
                   (list :family emanix-prose-mono-font)))))
     ((derived-mode-p 'org-mode)
      (append
       (emanix-prose--heading-remaps "org-level-")
       (emanix-prose--mono '(org-code org-verbatim org-table org-meta-line
                            org-formula org-checkbox org-block-begin-line
                            org-block-end-line))
       (list (cons 'org-block
                   (append (list :family emanix-prose-mono-font) bg)))))
     (t nil))))

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

(defvar-local emanix-prose--revealed nil
  "Cons (BEG . END) of the region whose markup is currently revealed.")

(defvar-local emanix-prose--added-display-prop nil
  "Non-nil if this mode added `display' to `font-lock-extra-managed-props'.
The major mode may already manage `display' itself — markdown-mode does,
once `markdown-hide-markup' is set — so teardown must retract only our own
addition rather than killing the variable and taking the major mode's
bookkeeping with it.")

(defun emanix-prose--rehide ()
  "Restore markup hidden before the last reveal."
  (when emanix-prose--revealed
    (let ((beg (car emanix-prose--revealed))
          (end (cdr emanix-prose--revealed)))
      (setq emanix-prose--revealed nil)
      (when (and (<= (point-min) beg) (<= end (point-max)))
        (font-lock-flush beg end)
        (font-lock-ensure beg end)))))

(defun emanix-prose--reveal-at-point ()
  "Reveal hidden markup on the line at point, rehiding the previous line."
  (let ((beg (line-beginning-position))
        (end (line-end-position)))
    (unless (equal emanix-prose--revealed (cons beg end))
      (emanix-prose--rehide)
      (with-silent-modifications
        (remove-text-properties beg end '(invisible nil))
        ;; A drawn table line is display-replaced whole.  Reveal it with the
        ;; rest of the markup so the source under point stays readable and
        ;; editable; `emanix-prose--rehide' refontifies the box back.
        (when (and (derived-mode-p 'markdown-mode)
                   (markdown-table-at-point-p))
          (remove-text-properties beg end '(display nil))))
      (setq emanix-prose--revealed (cons beg end)))))

;; --- Reading column, bullets, images --------------------------------------

(defun emanix-prose--match-list-bullet (limit)
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

(defconst emanix-prose--bullet-keywords
  '((emanix-prose--match-list-bullet 1 '(face nil display "•")))
  "Font-lock keywords displaying unordered list markers as a bullet.
Ordered lists are untouched — a numbered list carries information a
bullet would throw away — and so are thematic breaks, see the matcher.")

;; --- Markdown tables drawn as boxes ---------------------------------------
;;
;; markdown-mode fontifies a table but never renders one: the reader sees the
;; `|' source, and a hand-written table need not even be aligned (the tables
;; in this repository's WALKTHROUGH.md are not).  Org gets boxes from
;; org-modern; markdown must get them from us, or the two prose branches read
;; differently.  A table line's display is replaced by the same grid the
;; source encodes: cells padded to one width per column, box sides, a rule
;; under the header, and drawn corners.
;;
;; Geometry is per table, not per line, because the source cannot be trusted to
;; be aligned.  Rendered strings are cached and keyed on the buffer's
;; modification tick, so a font-lock pass over a table computes the widths
;; once.  Cells are split on an unescaped `|'; a table that needs a literal
;; pipe inside a code span must escape it, which is the GFM rule anyway.

(defvar-local emanix-prose--table-cache-tick nil
  "`buffer-chars-modified-tick' the table cache was built at.")

(defvar-local emanix-prose--table-cache nil
  "Alist of (TABLE-BEGIN (LINE-BEGIN . DISPLAY-STRING) ...) ...")

(defun emanix-prose--table-line-cells ()
  "Return the cell strings of the table line at point.
Each cell has its hidden markup removed and its surrounding whitespace
trimmed.  An escaped pipe (`\\|') stays inside its cell."
  (let ((bol (line-beginning-position))
        (eol (line-end-position))
        (start nil)
        cells)
    (save-excursion
      (goto-char bol)
      (skip-chars-forward " \t")
      (when (looking-at-p "|")
        (forward-char 1))
      (setq start (point))
      (while (re-search-forward "|" eol t)
        (unless (eq (char-before (1- (point))) ?\\)
          (push (buffer-substring start (1- (point))) cells)
          (setq start (point))))
      (push (buffer-substring start eol) cells))
    (setq cells (nreverse cells))
    ;; An optional trailing pipe contributes one empty cell; drop it.
    (when (and cells (string-empty-p (string-trim (car (last cells)))))
      (setq cells (butlast cells)))
    (mapcar (lambda (cell)
              (let ((s (markdown--remove-invisible-markup
                        (string-trim (replace-regexp-in-string "\\\\|" "|" cell)))))
                ;; Keep the cell's face, drop anything that would render (or
                ;; hide) inside the drawn row: markdown's alignment spaces and
                ;; our own display property from an earlier font-lock pass.
                (remove-text-properties 0 (length s) '(display nil invisible nil) s)
                s))
            cells)))

(defun emanix-prose--table-metrics (begin end)
  "Return (WIDTHS ALIGNS ROWS) for the table in [BEGIN,END].
WIDTHS is one width per column; ALIGNS the delimiter row's specifiers
\(`l', `r', `c' or `d'); ROWS the cell lists of every non-delimiter line,
in order.  ALIGNS is nil when the table has no delimiter row."
  (let (rows aligns)
    (save-excursion
      (goto-char begin)
      (while (< (point) end)
        (let ((line (buffer-substring (line-beginning-position)
                                      (line-end-position))))
          (if (markdown--is-delimiter-row line)
              (unless aligns (setq aligns (markdown-table-colfmt line)))
            (push (emanix-prose--table-line-cells) rows)))
        (forward-line 1)))
    (setq rows (nreverse rows))
    (let* ((ncols (apply #'max 1 (mapcar #'length rows)))
           (widths (make-list ncols 1)))
      (dolist (row rows)
        (dotimes (i ncols)
          (let ((w (string-width (or (nth i row) ""))))
            (when (> w (nth i widths))
              (setcar (nthcdr i widths) w)))))
      (list widths aligns rows))))

(defun emanix-prose--table-pad (string width align)
  "Return STRING padded to WIDTH according to ALIGN."
  (let ((pad (- width (string-width string))))
    (cond
     ((<= pad 0) string)
     ((eq align 'r) (concat (make-string pad ?\s) string))
     ((eq align 'c) (concat (make-string (/ pad 2) ?\s) string
                            (make-string (- pad (/ pad 2)) ?\s)))
     (t (concat string (make-string pad ?\s))))))

(defun emanix-prose--table-draw (string)
  "Give STRING the table's monospace face and return it."
  (add-face-text-property 0 (length string) 'markdown-table-face nil string)
  string)

(defun emanix-prose--table-row-string (cells widths aligns)
  "Render one body row of a table as a line of box drawing."
  (emanix-prose--table-draw
   (concat
    "│"
    (mapconcat
     (lambda (i)
       (concat " "
               (emanix-prose--table-pad (or (nth i cells) "")
                                        (nth i widths)
                                        (or (nth i aligns) 'l))
               " "))
     (number-sequence 0 (1- (length widths)))
     "│")
    "│")))

(defun emanix-prose--table-rule (widths left middle right)
  "Render a horizontal rule spanning WIDTHS with the given corners."
  (emanix-prose--table-draw
   (concat left
           (mapconcat (lambda (w) (make-string (+ w 2) ?─)) widths middle)
           right)))

(defun emanix-prose--table-render (begin end)
  "Return an alist (LINE-BEGIN . DISPLAY-STRING) for the table in [BEGIN,END].
Nil when the block has no delimiter row and is therefore not a table."
  (let* ((metrics (emanix-prose--table-metrics begin end))
         (widths (nth 0 metrics))
         (aligns (nth 1 metrics))
         (top (emanix-prose--table-rule widths "┌" "┬" "┐"))
         (rule (emanix-prose--table-rule widths "├" "┼" "┤"))
         (bottom (emanix-prose--table-rule widths "└" "┴" "┘")))
    (when aligns
      (let (entries)
        (save-excursion
          (goto-char begin)
          (while (< (point) end)
            (let* ((b (line-beginning-position))
                   (line (buffer-substring b (line-end-position)))
                   (delim (markdown--is-delimiter-row line)))
              (push (cons b (if delim 'delim 'data)) entries))
            (forward-line 1)))
        (setq entries (nreverse entries))
        (let ((result nil)
              (last-line (car (car (last entries))))
              (header-p t))
          (dolist (entry entries)
            (let ((b (car entry)))
              (if (eq (cdr entry) 'delim)
                  (push (cons b (if (equal b last-line)
                                    (concat rule "\n" bottom)
                                  rule))
                        result)
                (let* ((cells (save-excursion
                                (goto-char b)
                                (emanix-prose--table-line-cells)))
                       (row (emanix-prose--table-row-string cells widths aligns))
                       (text (cond (header-p (concat top "\n" row))
                                   ((equal b last-line) (concat row "\n" bottom))
                                   (t row))))
                  (push (cons b text) result)
                  (setq header-p nil)))))
          (nreverse result))))))

(defun emanix-prose--table-lines (begin)
  "Return the rendered lines for the table at BEGIN, from the cache."
  (let ((tick (buffer-chars-modified-tick)))
    (unless (eq tick emanix-prose--table-cache-tick)
      (setq emanix-prose--table-cache-tick tick
            emanix-prose--table-cache nil))
    (or (cdr (assq begin emanix-prose--table-cache))
        (let* ((end (save-excursion (goto-char begin) (markdown-table-end)))
               (rendered (emanix-prose--table-render begin end)))
          (push (cons begin rendered) emanix-prose--table-cache)
          rendered))))

(defun emanix-prose--table-display ()
  "Replace the table line under the current match with a drawn row.
A font-lock function: it sets the `display' property itself, like
org-modern's table renderer, and returns nil."
  (when (derived-mode-p 'markdown-mode)
    (let* ((bol (save-excursion (goto-char (match-beginning 0))
                                (line-beginning-position)))
           (begin (save-excursion (goto-char bol) (markdown-table-begin)))
           (entry (assq bol (emanix-prose--table-lines begin))))
      (when entry
        (put-text-property bol (line-end-position) 'display (cdr entry))))))

(defun emanix-prose--match-table-line (limit)
  "Font-lock matcher for a line inside a markdown table, searching to LIMIT."
  (when (re-search-forward "^[ \t]*|" limit t)
    (when (save-excursion
            (goto-char (match-beginning 0))
            (markdown-table-at-point-p))
      t)))

(defconst emanix-prose--table-keywords
  '((emanix-prose--match-table-line (0 (emanix-prose--table-display))))
  "Font-lock keywords drawing a markdown table as a box.")

(defun emanix-prose--buffer-has-images-p ()
  "Non-nil if the buffer contains a markdown image link."
  (save-excursion
    (goto-char (point-min))
    (and (re-search-forward "!\\[[^]]*\\]([^)]+)" nil t) t)))

(defun emanix-prose--setup-column ()
  "Turn on visual wrapping in a centered reading column."
  (visual-line-mode 1)
  (when (require 'visual-fill-column nil :no-error)
    (setq-local visual-fill-column-width emanix-prose-width)
    (setq-local visual-fill-column-center-text t)
    (visual-fill-column-mode 1)))

(defun emanix-prose--teardown-column ()
  "Undo `emanix-prose--setup-column'."
  (when (fboundp 'visual-fill-column-mode)
    (visual-fill-column-mode -1))
  (kill-local-variable 'visual-fill-column-width)
  (kill-local-variable 'visual-fill-column-center-text)
  (visual-line-mode -1))

;;;###autoload
(define-minor-mode emanix-prose-mode
  "Render the current markdown or org buffer as prose."
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
        (when (derived-mode-p 'markdown-mode)
          (setq-local markdown-hide-markup t)
          (add-hook 'post-command-hook #'emanix-prose--reveal-at-point nil t))
        (when (derived-mode-p 'org-mode)
          ;; Reveal-at-point comes from org-appear here; the hand-rolled
          ;; markdown hook must not also attach, or the two fight over the
          ;; same invisible properties.
          (setq-local org-hide-emphasis-markers t)
          (when (require 'org-modern nil :no-error) (org-modern-mode 1))
          (when (require 'org-appear nil :no-error) (org-appear-mode 1)))
        (emanix-prose--setup-column)
        ;; font-lock only removes properties it is told it manages. Without
        ;; `display' here the bullets would be applied but never cleaned up,
        ;; so disabling the mode would leave • behind on every list marker.
        (unless (memq 'display font-lock-extra-managed-props)
          (setq-local font-lock-extra-managed-props
                      (cons 'display font-lock-extra-managed-props))
          (setq emanix-prose--added-display-prop t))
        (font-lock-add-keywords nil emanix-prose--bullet-keywords t)
        (when (derived-mode-p 'markdown-mode)
          (font-lock-add-keywords nil emanix-prose--table-keywords t))
        (when (and (derived-mode-p 'markdown-mode)
                   (emanix-prose--buffer-has-images-p)
                   (fboundp 'markdown-display-inline-images))
          (setq-local markdown-max-image-size
                      (cons (* emanix-prose-width (default-font-width)) nil))
          (ignore-errors (markdown-display-inline-images)))
        (font-lock-flush)
        (font-lock-ensure))
    (emanix-prose--unapply-faces)
    (kill-local-variable 'line-spacing)
    (when (eq emanix-prose--line-numbers-prior 'on)
      (display-line-numbers-mode 1))
    (setq emanix-prose--line-numbers-prior nil)
    (remove-hook 'post-command-hook #'emanix-prose--reveal-at-point t)
    (setq emanix-prose--revealed nil)
    (when (derived-mode-p 'markdown-mode)
      (kill-local-variable 'markdown-hide-markup))
    (when (derived-mode-p 'org-mode)
      (kill-local-variable 'org-hide-emphasis-markers)
      (when (fboundp 'org-modern-mode) (org-modern-mode -1))
      (when (fboundp 'org-appear-mode) (org-appear-mode -1)))
    (font-lock-remove-keywords nil emanix-prose--bullet-keywords)
    (when (derived-mode-p 'markdown-mode)
      (font-lock-remove-keywords nil emanix-prose--table-keywords))
    (setq emanix-prose--table-cache nil)
    (emanix-prose--teardown-column)
    (kill-local-variable 'markdown-max-image-size)
    (font-lock-flush)
    (font-lock-ensure)
    ;; Done only after the flush/ensure above: font-lock strips a managed
    ;; prop from stale text during that refontification by consulting this
    ;; variable's CURRENT value, so retracting it first would drop `display'
    ;; before the • display properties get a chance to be cleaned up.
    (when emanix-prose--added-display-prop
      (setq-local font-lock-extra-managed-props
                  (remq 'display font-lock-extra-managed-props))
      (setq emanix-prose--added-display-prop nil))))

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
