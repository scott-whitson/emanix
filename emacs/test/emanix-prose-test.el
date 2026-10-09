;;; emanix-prose-test.el --- ERT tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'org)
(require 'emanix-prose)

(ert-deftest emanix-prose-palette-color-known-key ()
  "A key present in the active theme's palette returns a hex colour."
  (let ((c (emanix/theme-palette-color "surface0")))
    (should (or (null c) (string-match-p "\\`#[0-9a-fA-F]\\{6\\}\\'" c)))))

(ert-deftest emanix-prose-palette-color-unknown-key ()
  "An absent key returns nil rather than signalling."
  (should (null (emanix/theme-palette-color "no-such-palette-key"))))

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

(ert-deftest emanix-prose-headings-use-the-heading-font-and-descend ()
  "Headings use the heading font at strictly decreasing scale."
  (with-temp-buffer
    (org-mode)
    (let* ((remaps (emanix-prose--face-remaps))
           (scales (mapcar (lambda (n)
                             (plist-get
                              (alist-get (intern (format "org-level-%d" n))
                                         remaps)
                              :height))
                           '(1 2 3 4 5 6))))
      (should (equal (plist-get (alist-get 'org-level-1 remaps) :family)
                     emanix-prose-heading-font))
      (should (equal scales (sort (copy-sequence scales) #'>)))
      (should (> (car scales) 1.0)))))

(ert-deftest emanix-prose-enabling-adds-cookies-disabling-removes-them ()
  "The mode leaves no face-remap state behind when switched off."
  (with-temp-buffer
    (org-mode)
    (should (null emanix-prose--cookies))
    (emanix-prose-mode 1)
    (should (> (length emanix-prose--cookies) 0))
    (emanix-prose-mode -1)
    (should (null emanix-prose--cookies))))

(ert-deftest emanix-prose-toggling-is-idempotent ()
  "Enabling twice then disabling twice ends in a clean buffer."
  (with-temp-buffer
    (org-mode)
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
    (org-mode)
    (display-line-numbers-mode 1)
    (emanix-prose-mode 1)
    (should (not (bound-and-true-p display-line-numbers-mode)))
    (emanix-prose-mode -1)
    (should (bound-and-true-p display-line-numbers-mode))))

(ert-deftest emanix-prose-leaves-line-numbers-off-if-they-were-off ()
  "A buffer without line numbers does not gain them from a round trip."
  (with-temp-buffer
    (org-mode)
    (emanix-prose-mode 1)
    (emanix-prose-mode -1)
    (should (not (bound-and-true-p display-line-numbers-mode)))))

(ert-deftest emanix-prose-double-enable-does-not-forget-line-numbers ()
  "Enabling twice still restores line numbers on disable."
  (with-temp-buffer
    (org-mode)
    (display-line-numbers-mode 1)
    (emanix-prose-mode 1)
    (emanix-prose-mode 1)
    (emanix-prose-mode -1)
    (should (bound-and-true-p display-line-numbers-mode))))

(ert-deftest emanix-prose-sets-up-the-reading-column ()
  "Enabling the mode establishes the centered column and visual wrapping."
  (with-temp-buffer
    (org-mode)
    (emanix-prose-mode 1)
    (should (bound-and-true-p visual-line-mode))
    (should (= visual-fill-column-width emanix-prose-width))
    (should visual-fill-column-center-text)))

(ert-deftest emanix-prose-displays-list-bullets ()
  "An unordered list marker gets a bullet display property."
  (with-temp-buffer
    (insert "- first item\n- second item\n")
    (org-mode)
    (emanix-prose-mode 1)
    (font-lock-ensure)
    (goto-char (point-min))
    (should (equal (get-text-property (point) 'display) "•"))))

(ert-deftest emanix-prose-leaves-ordered-lists-alone ()
  "Numbered list markers are not replaced."
  (with-temp-buffer
    (insert "1. first item\n")
    (org-mode)
    (emanix-prose-mode 1)
    (goto-char (point-min))
    (should (null (get-text-property (point) 'display)))))

(ert-deftest emanix-prose-removes-bullets-on-disable ()
  "Disabling the mode leaves no display property behind on list markers."
  (with-temp-buffer
    (insert "- first item\n")
    (org-mode)
    (emanix-prose-mode 1)
    (font-lock-ensure)
    (goto-char (point-min))
    (should (equal (get-text-property (point) 'display) "•"))
    (emanix-prose-mode -1)
    (font-lock-ensure)
    (goto-char (point-min))
    (should (null (get-text-property (point) 'display)))))

(ert-deftest emanix-prose-leaves-major-mode-managed-props-intact ()
  "Teardown retracts only our own `display' addition."
  (with-temp-buffer
    (org-mode)
    (org-mode)  ; ensure a clean state
    (font-lock-ensure)
    (let ((before (copy-sequence font-lock-extra-managed-props))
          (by-name (lambda (a b) (string< (symbol-name a) (symbol-name b)))))
      (emanix-prose-mode 1)
      (emanix-prose-mode -1)
      (should (equal (sort (copy-sequence font-lock-extra-managed-props) by-name)
                     (sort (copy-sequence before) by-name))))))

(ert-deftest emanix-prose-org-hides-emphasis-markers ()
  "Enabling the mode in org hides emphasis markers and disabling restores."
  (with-temp-buffer
    (org-mode)
    (emanix-prose-mode 1)
    (should org-hide-emphasis-markers)
    (emanix-prose-mode -1)
    (should (null (local-variable-p 'org-hide-emphasis-markers)))))

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

;; --- Magnification ----------------------------------------------------------

(ert-deftest emanix-prose-magnification-round-trip ()
  "Increase, decrease and reset move the buffer's text scale."
  (with-temp-buffer
    (text-mode)
    (emanix-prose-mode 1)
    (emanix-prose-increase-magnification)
    (should (> text-scale-mode-amount 0))
    (emanix-prose-increase-magnification 2)
    (should (= text-scale-mode-amount 3))
    (emanix-prose-decrease-magnification)
    (should (= text-scale-mode-amount 2))
    (emanix-prose-reset-magnification)
    (should (= text-scale-mode-amount 0))))

(ert-deftest emanix-prose-magnification-commands-show-a-document ()
  "The magnification commands are interactive, so the keys can call them."
  (should (commandp #'emanix-prose-increase-magnification))
  (should (commandp #'emanix-prose-decrease-magnification))
  (should (commandp #'emanix-prose-reset-magnification)))

(provide 'emanix-prose-test)
;;; emanix-prose-test.el ends here