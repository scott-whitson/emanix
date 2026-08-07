;;; scott-quarterly-test.el --- ERT tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
;; `org' must be loaded before the tests bind `org-directory'. Under
;; lexical-binding, `let' over a symbol that is not globally special creates a
;; lexical binding the module cannot see — the filesystem tests would then
;; silently exercise the real ~/docs/org instead of the temp tree. Requiring
;; org defvars `org-directory' with a value, making it truly special.
(require 'org)
(require 'scott-quarterly)

(ert-deftest scott-quarterly-name-maps-months-to-quarters ()
  "Each month maps to its calendar quarter."
  ;; encode-time: (SEC MIN HOUR DAY MONTH YEAR)
  (should (equal "2026-Q1" (scott-quarterly-name (encode-time 0 0 12 15 1 2026))))
  (should (equal "2026-Q1" (scott-quarterly-name (encode-time 0 0 12 31 3 2026))))
  (should (equal "2026-Q2" (scott-quarterly-name (encode-time 0 0 12 1 4 2026))))
  (should (equal "2026-Q3" (scott-quarterly-name (encode-time 0 0 12 6 8 2026))))
  (should (equal "2026-Q4" (scott-quarterly-name (encode-time 0 0 12 31 12 2026)))))

(ert-deftest scott-quarterly-prev-name-wraps-the-year ()
  "The quarter before Q1 is Q4 of the previous year."
  (should (equal "2026-Q2" (scott-quarterly--prev-name "2026-Q3")))
  (should (equal "2025-Q4" (scott-quarterly--prev-name "2026-Q1"))))
