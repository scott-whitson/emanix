;;; emanix-prose-test.el --- ERT tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'markdown-mode)
(require 'org)
(require 'emanix-prose)

(ert-deftest emanix-prose-palette-color-known-key ()
  "A key present in the active theme's palette returns a hex colour."
  (let ((c (emanix/theme-palette-color "surface0")))
    (should (or (null c) (string-match-p "\\`#[0-9a-fA-F]\\{6\\}\\'" c)))))

(ert-deftest emanix-prose-palette-color-unknown-key ()
  "An absent key returns nil rather than signalling."
  (should (null (emanix/theme-palette-color "no-such-palette-key"))))

(ert-deftest emanix-prose-remaps-cover-markdown-faces ()
  "Every markdown face the design names is in the remap table."
  (with-temp-buffer
    (markdown-mode)
    (let ((faces (mapcar #'car (emanix-prose--face-remaps))))
      (dolist (f '(markdown-header-face-1 markdown-header-face-2
                   markdown-header-face-3 markdown-header-face-4
                   markdown-header-face-5 markdown-header-face-6
                   markdown-pre-face markdown-code-face
                   markdown-inline-code-face markdown-table-face
                   markdown-language-keyword-face markdown-markup-face))
        (should (memq f faces))))))

(ert-deftest emanix-prose-tables-and-code-stay-monospace ()
  "Table and code faces are remapped to the mono family, not the body font."
  (with-temp-buffer
    (markdown-mode)
    (let ((remaps (emanix-prose--face-remaps)))
      (dolist (f '(markdown-table-face markdown-code-face
                   markdown-pre-face markdown-inline-code-face))
        (should (equal (plist-get (alist-get f remaps) :family)
                       emanix-prose-mono-font))))))

(ert-deftest emanix-prose-headings-use-the-heading-font-and-descend ()
  "Headings use the heading font at strictly decreasing scale."
  (with-temp-buffer
    (markdown-mode)
    (let* ((remaps (emanix-prose--face-remaps))
           (scales (mapcar (lambda (n)
                             (plist-get
                              (alist-get (intern (format "markdown-header-face-%d" n))
                                         remaps)
                              :height))
                           '(1 2 3 4 5 6))))
      (should (equal (plist-get (alist-get 'markdown-header-face-1 remaps) :family)
                     emanix-prose-heading-font))
      (should (equal scales (sort (copy-sequence scales) #'>)))
      (should (> (car scales) 1.0)))))

(ert-deftest emanix-prose-enabling-adds-cookies-disabling-removes-them ()
  "The mode leaves no face-remap state behind when switched off."
  (with-temp-buffer
    (markdown-mode)
    (should (null emanix-prose--cookies))
    (emanix-prose-mode 1)
    (should (> (length emanix-prose--cookies) 0))
    (emanix-prose-mode -1)
    (should (null emanix-prose--cookies))))

(ert-deftest emanix-prose-toggling-is-idempotent ()
  "Enabling twice then disabling twice ends in a clean buffer."
  (with-temp-buffer
    (markdown-mode)
    (emanix-prose-mode 1)
    (let ((n (length emanix-prose--cookies)))
      (emanix-prose-mode 1)
      (should (= n (length emanix-prose--cookies))))
    (emanix-prose-mode -1)
    (emanix-prose-mode -1)
    (should (null emanix-prose--cookies))))

(ert-deftest emanix-prose-restores-line-numbers-on-disable ()
  "Line numbers on before the mode are restored after it."
  (with-temp-buffer
    (markdown-mode)
    (display-line-numbers-mode 1)
    (emanix-prose-mode 1)
    (should (not (bound-and-true-p display-line-numbers-mode)))
    (emanix-prose-mode -1)
    (should (bound-and-true-p display-line-numbers-mode))))

(ert-deftest emanix-prose-leaves-line-numbers-off-if-they-were-off ()
  "A buffer without line numbers does not gain them from a round trip."
  (with-temp-buffer
    (markdown-mode)
    (emanix-prose-mode 1)
    (emanix-prose-mode -1)
    (should (not (bound-and-true-p display-line-numbers-mode)))))

(ert-deftest emanix-prose-double-enable-does-not-forget-line-numbers ()
  "Enabling twice still restores line numbers on disable."
  (with-temp-buffer
    (markdown-mode)
    (display-line-numbers-mode 1)
    (emanix-prose-mode 1)
    (emanix-prose-mode 1)
    (emanix-prose-mode -1)
    (should (bound-and-true-p display-line-numbers-mode))))

(defmacro emanix-prose-test--with-md (text &rest body)
  "Run BODY in a fontified markdown buffer containing TEXT."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (markdown-mode)
     (emanix-prose-mode 1)
     (font-lock-ensure)
     (goto-char (point-min))
     ,@body))

(defun emanix-prose-test--invisible-count ()
  "Number of characters carrying an `invisible' property in this buffer."
  (let ((n 0))
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (when (get-text-property (point) 'invisible) (setq n (1+ n)))
        (forward-char 1)))
    n))

(ert-deftest emanix-prose-hides-markup ()
  "With the mode on, emphasis markers carry an invisible property."
  (emanix-prose-test--with-md "Some **bold** text\n\nMore text\n"
    (should (> (emanix-prose-test--invisible-count) 0))))

(ert-deftest emanix-prose-reveals-the-line-at-point ()
  "Markup on the line at point is revealed; markup elsewhere is not."
  (emanix-prose-test--with-md "Some **bold** text\n\nAnd `code` here\n"
    (goto-char (point-min))
    (emanix-prose--reveal-at-point)
    (should (equal emanix-prose--revealed
                   (cons (line-beginning-position) (line-end-position))))
    ;; nothing on line 1 is hidden any more
    (should (null (get-text-property (+ (point-min) 5) 'invisible)))
    ;; but the backticks on line 3 still are
    (should (save-excursion
              (goto-char (point-max))
              (search-backward "code" nil t)
              (get-text-property (1- (point)) 'invisible)))))

(ert-deftest emanix-prose-rehides-when-point-leaves ()
  "Moving to another line restores the markup that was revealed."
  (emanix-prose-test--with-md "Some **bold** text\n\nAnd `code` here\n"
    (goto-char (point-min))
    (emanix-prose--reveal-at-point)
    (let ((revealed (emanix-prose-test--invisible-count)))
      (goto-char (point-max))
      (emanix-prose--reveal-at-point)
      (should (> (emanix-prose-test--invisible-count) revealed)))))

(ert-deftest emanix-prose-disabling-clears-reveal-state ()
  "Turning the mode off drops the reveal hook and its state."
  (emanix-prose-test--with-md "Some **bold** text\n"
    (emanix-prose--reveal-at-point)
    (should emanix-prose--revealed)
    (emanix-prose-mode -1)
    (should (null emanix-prose--revealed))
    ;; The hook is added buffer-locally, so check the buffer-local value —
    ;; checking the global default would pass vacuously and prove nothing.
    (should (not (memq #'emanix-prose--reveal-at-point post-command-hook)))))

(ert-deftest emanix-prose-detects-image-links ()
  "Image detection is true only for buffers containing an image link."
  (with-temp-buffer
    (insert "A [link](http://x) but no picture\n")
    (markdown-mode)
    (should (null (emanix-prose--buffer-has-images-p))))
  (with-temp-buffer
    (insert "Here: ![alt](assets/diagram.png)\n")
    (markdown-mode)
    (should (emanix-prose--buffer-has-images-p))))

(ert-deftest emanix-prose-sets-up-the-reading-column ()
  "Enabling the mode establishes the centered column and visual wrapping."
  (emanix-prose-test--with-md "Body text\n"
    (should (bound-and-true-p visual-line-mode))
    (should (= visual-fill-column-width emanix-prose-width))
    (should visual-fill-column-center-text)))

(ert-deftest emanix-prose-displays-list-bullets ()
  "An unordered list marker gets a bullet display property."
  (emanix-prose-test--with-md "- first item\n- second item\n"
    (goto-char (point-min))
    (should (equal (get-text-property (point) 'display) "•"))))

(ert-deftest emanix-prose-leaves-ordered-lists-alone ()
  "Numbered list markers are not replaced."
  (emanix-prose-test--with-md "1. first item\n"
    (goto-char (point-min))
    (should (null (get-text-property (point) 'display)))))

(ert-deftest emanix-prose-removes-bullets-on-disable ()
  "Disabling the mode leaves no display property behind on list markers."
  (emanix-prose-test--with-md "- first item\n"
    (goto-char (point-min))
    (should (equal (get-text-property (point) 'display) "•"))
    (emanix-prose-mode -1)
    (font-lock-ensure)
    (goto-char (point-min))
    (should (null (get-text-property (point) 'display)))))

(ert-deftest emanix-prose-leaves-hyphen-thematic-breaks-alone ()
  "A `- - -' horizontal rule does not get a bullet stamped on it.
markdown-mode's own `markdown-hide-markup' feature (on since Task 3)
legitimately puts its own `display' property here — a rendered hr line —
so the assertion is that it is not OUR bullet, not that it is absent."
  (emanix-prose-test--with-md "Text\n\n- - -\n\nMore\n"
    (goto-char (point-min))
    (search-forward "- - -")
    (beginning-of-line)
    (should (not (equal (get-text-property (point) 'display) "•")))))

(ert-deftest emanix-prose-leaves-asterisk-thematic-breaks-alone ()
  "A `* * *' horizontal rule does not get a bullet stamped on it.
markdown-mode's own `markdown-hide-markup' feature (on since Task 3)
legitimately puts its own `display' property here — a rendered hr line —
so the assertion is that it is not OUR bullet, not that it is absent."
  (emanix-prose-test--with-md "Text\n\n* * *\n\nMore\n"
    (goto-char (point-min))
    (search-forward "* * *")
    (beginning-of-line)
    (should (not (equal (get-text-property (point) 'display) "•")))))

(ert-deftest emanix-prose-leaves-major-mode-managed-props-intact ()
  "Teardown retracts only our own `display' addition."
  (with-temp-buffer
    (markdown-mode)
    (setq-local markdown-hide-markup t)
    (font-lock-ensure)
    (let ((before (copy-sequence font-lock-extra-managed-props))
          (by-name (lambda (a b) (string< (symbol-name a) (symbol-name b)))))
      (emanix-prose-mode 1)
      (emanix-prose-mode -1)
      (should (equal (sort (copy-sequence font-lock-extra-managed-props) by-name)
                     (sort (copy-sequence before) by-name))))))

(ert-deftest emanix-prose-remaps-cover-org-faces ()
  "Every org face the design names is in the remap table."
  (with-temp-buffer
    (org-mode)
    (let ((faces (mapcar #'car (emanix-prose--face-remaps))))
      (dolist (f '(org-level-1 org-level-2 org-level-3 org-level-4
                   org-level-5 org-level-6 org-block org-block-begin-line
                   org-block-end-line org-code org-verbatim org-table
                   org-meta-line org-formula org-checkbox))
        (should (memq f faces))))))

(ert-deftest emanix-prose-org-tables-stay-monospace ()
  "org-table is remapped to the mono family."
  (with-temp-buffer
    (org-mode)
    (should (equal (plist-get (alist-get 'org-table (emanix-prose--face-remaps))
                              :family)
                   emanix-prose-mono-font))))

(ert-deftest emanix-prose-org-hides-emphasis-markers ()
  "Enabling the mode in org hides emphasis markers and disabling restores."
  (with-temp-buffer
    (org-mode)
    (emanix-prose-mode 1)
    (should org-hide-emphasis-markers)
    (emanix-prose-mode -1)
    (should (null (local-variable-p 'org-hide-emphasis-markers)))))

(ert-deftest emanix-prose-org-does-not-install-the-markdown-reveal-hook ()
  "Org uses org-appear; the hand-rolled markdown reveal must not attach."
  (with-temp-buffer
    (org-mode)
    (emanix-prose-mode 1)
    (should (not (memq #'emanix-prose--reveal-at-point post-command-hook)))))

(ert-deftest emanix-prose-org-enables-org-modern-and-org-appear ()
  "The org branch actually turns on org-modern and org-appear.
Guarded by `skip-unless': both are soft-required by design, so on a host
without them the mode must still work and this test must not fail."
  (skip-unless (and (require 'org-modern nil :no-error)
                    (require 'org-appear nil :no-error)))
  (with-temp-buffer
    (org-mode)
    (emanix-prose-mode 1)
    (should (bound-and-true-p org-modern-mode))
    (should (bound-and-true-p org-appear-mode))))

(ert-deftest emanix-prose-org-disables-org-modern-and-org-appear ()
  "Disabling the mode turns both back off."
  (skip-unless (and (require 'org-modern nil :no-error)
                    (require 'org-appear nil :no-error)))
  (with-temp-buffer
    (org-mode)
    (emanix-prose-mode 1)
    (emanix-prose-mode -1)
    (should (not (bound-and-true-p org-modern-mode)))
    (should (not (bound-and-true-p org-appear-mode)))))

(provide 'emanix-prose-test)
;;; emanix-prose-test.el ends here
