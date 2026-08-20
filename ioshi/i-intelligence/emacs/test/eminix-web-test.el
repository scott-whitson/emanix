;;; eminix-web-test.el --- ERT tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'eminix-web)

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

(provide 'eminix-web-test)
;;; eminix-web-test.el ends here
