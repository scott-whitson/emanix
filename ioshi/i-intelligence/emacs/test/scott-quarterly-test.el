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

(defmacro scott-quarterly-test--with-org-dir (spec &rest body)
  "Run BODY with `org-directory' bound to a temp tree built from SPEC.
SPEC is a list of relative paths; a trailing slash makes a directory,
anything else an empty file."
  (declare (indent 1))
  `(let* ((org-directory (make-temp-file "scott-quarterly-test" t)))
     (unwind-protect
         (progn
           (dolist (entry ,spec)
             (let ((path (expand-file-name entry org-directory)))
               (if (string-suffix-p "/" entry)
                   (make-directory path t)
                 (make-directory (file-name-directory path) t)
                 (write-region "" nil path nil 'silent))))
           ,@body)
       (delete-directory org-directory t))))

(ert-deftest scott-quarterly-work-path-is-always-constructed ()
  "Work notes have exactly one location, whether or not the file exists."
  (scott-quarterly-test--with-org-dir '("work/Quarterly/")
    (should (equal (expand-file-name "work/Quarterly/2026-Q3.org" org-directory)
                   (scott-quarterly--file 'work "2026-Q3")))))

(ert-deftest scott-quarterly-personal-path-prefers-root-then-archive ()
  "Personal resolution is unchanged: root file wins, then Quarterly/, then root."
  (scott-quarterly-test--with-org-dir '("2026-Q3.org" "Quarterly/")
    (should (equal (expand-file-name "2026-Q3.org" org-directory)
                   (scott-quarterly--file 'personal "2026-Q3"))))
  (scott-quarterly-test--with-org-dir '("Quarterly/2026-Q3.org")
    (should (equal (expand-file-name "Quarterly/2026-Q3.org" org-directory)
                   (scott-quarterly--file 'personal "2026-Q3"))))
  ;; Neither exists yet: fall back to the root path, as today.
  (scott-quarterly-test--with-org-dir '("Quarterly/")
    (should (equal (expand-file-name "2026-Q3.org" org-directory)
                   (scott-quarterly--file 'personal "2026-Q3")))))

(ert-deftest scott-quarterly-availability-reads-the-tree-not-the-note ()
  "A scope is available when its tree exists, even with no note for this quarter."
  ;; Work laptop: only the work tree is synced here.
  (scott-quarterly-test--with-org-dir '("work/Quarterly/")
    (should (scott-quarterly--scope-available-p 'work))
    (should-not (scott-quarterly--scope-available-p 'personal))
    (should (eq 'work (scott-quarterly--default-scope))))
  ;; Home machines: both trees present, personal wins by default.
  (scott-quarterly-test--with-org-dir '("Quarterly/" "work/Quarterly/")
    (should (scott-quarterly--scope-available-p 'work))
    (should (scott-quarterly--scope-available-p 'personal))
    (should (eq 'personal (scott-quarterly--default-scope))))
  ;; Personal with no Quarterly/ archive yet — a loose root note counts.
  (scott-quarterly-test--with-org-dir '("2025-Q4.org")
    (should (scott-quarterly--scope-available-p 'personal)))
  ;; Empty tree: work is the fallback so the guard can offer to create it.
  (scott-quarterly-test--with-org-dir '()
    (should (eq 'work (scott-quarterly--default-scope)))))
