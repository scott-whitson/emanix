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
  (should (equal "2026-Q1" (scott-quarterly--name (encode-time 0 0 12 15 1 2026))))
  (should (equal "2026-Q1" (scott-quarterly--name (encode-time 0 0 12 31 3 2026))))
  (should (equal "2026-Q2" (scott-quarterly--name (encode-time 0 0 12 1 4 2026))))
  (should (equal "2026-Q3" (scott-quarterly--name (encode-time 0 0 12 6 8 2026))))
  (should (equal "2026-Q4" (scott-quarterly--name (encode-time 0 0 12 31 12 2026)))))

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

(ert-deftest scott-quarterly-file-id-reads-the-top-level-id ()
  "The :ID: property is read out of an existing note."
  (let ((file (make-temp-file "quarter" nil ".org"
                              ":PROPERTIES:\n:ID:       abc-123\n:END:\n#+title: 2026-Q2 (Work)\n")))
    (unwind-protect
        (should (equal "abc-123" (scott-quarterly--file-id file)))
      (delete-file file)))
  ;; A note with no ID yields nil rather than erroring.
  (let ((file (make-temp-file "quarter" nil ".org" "#+title: 2026-Q2 (Work)\n")))
    (unwind-protect
        (should-not (scott-quarterly--file-id file))
      (delete-file file)))
  ;; A heading's ID is not the file's ID. With `org-adapt-indentation' nil a
  ;; subheading drawer also sits at column 0, so the search must stop at the
  ;; first heading rather than return an ID that links mid-file.
  (let ((file (make-temp-file "quarter" nil ".org"
                              "#+title: 2026-Q2 (Work)\n* Rock\n:PROPERTIES:\n:ID:       heading-id\n:END:\n")))
    (unwind-protect
        (should-not (scott-quarterly--file-id file))
      (delete-file file))))

(ert-deftest scott-quarterly-template-work-title-is-suffixed ()
  "Work notes are titled `NAME (Work)'; personal notes are not."
  (let ((work (scott-quarterly--template 'work "2026-Q4"))
        (personal (scott-quarterly--template 'personal "2026-Q4")))
    (should (string-match-p "^#\\+title: 2026-Q4 (Work)$" work))
    (should (string-match-p "^#\\+title: 2026-Q4$" personal))))

(ert-deftest scott-quarterly-template-has-the-agreed-sections ()
  "Rock / Top of Mind / New This Quarter / Workspace, and no Review."
  (let ((out (scott-quarterly--template 'work "2026-Q4")))
    (should (string-match-p "^\\* Rock$" out))
    (should (string-match-p "^\\* Top of Mind$" out))
    (should (string-match-p "^\\* New This Quarter$" out))
    (should (string-match-p "^\\* Workspace$" out))
    (should-not (string-match-p "^\\* Review$" out))
    ;; Exactly four top-level headings.
    (should (= 4 (length (seq-filter (lambda (l) (string-prefix-p "* " l))
                                     (split-string out "\n")))))))

(ert-deftest scott-quarterly-template-carries-a-fresh-id ()
  "Every new note gets its own org-id."
  (let ((a (scott-quarterly--template 'work "2026-Q4"))
        (b (scott-quarterly--template 'work "2026-Q4")))
    (should (string-match-p "^:ID:       [0-9a-zA-Z-]+$" a))
    (should-not (equal a b))))

(ert-deftest scott-quarterly-template-back-links-to-the-prior-quarter ()
  "The prior quarter is linked by id when known, and omitted when not."
  (let ((with-prev (scott-quarterly--template 'work "2026-Q4" "prev-id-9" "2026-Q3"))
        (without (scott-quarterly--template 'work "2026-Q4")))
    (should (string-match-p "\\[\\[id:prev-id-9\\]\\[2026-Q3\\]\\]" with-prev))
    (should-not (string-match-p "\\[\\[id:" without))))

(ert-deftest scott-quarterly-open-declining-creates-nothing ()
  "Answering no to the create prompt must leave the tree untouched.
An empty note saved here can win a Syncthing conflict against the real
one still in flight (2026-07-16, 2026-Q3)."
  (scott-quarterly-test--with-org-dir '("work/Quarterly/")
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil))
              ((symbol-function 'find-file) (lambda (&rest _) (error "must not visit"))))
      (scott-quarterly-open)
      (should-not (directory-files (expand-file-name "work/Quarterly" org-directory)
                                   nil "\\.org\\'")))))

(ert-deftest scott-quarterly-open-accepting-writes-the-template ()
  "Answering yes creates the note for the current quarter with template text."
  (scott-quarterly-test--with-org-dir '("work/Quarterly/")
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
      (let ((name (scott-quarterly--name)))
        (unwind-protect
            (progn
              (scott-quarterly-open)
              (let ((file (expand-file-name (concat "work/Quarterly/" name ".org")
                                            org-directory)))
                (should (file-exists-p file))
                (with-temp-buffer
                  (insert-file-contents file)
                  (let ((text (buffer-string)))
                    (should (string-match-p (concat "#\\+title: " name " (Work)") text))
                    (should (string-match-p "^\\* Rock$" text))))))
          ;; `buffer-file-name' is a truename, so compare truenames: if TMPDIR
          ;; is a symlink a raw prefix test never matches and the buffers leak
          ;; into later tests.
          (dolist (buf (buffer-list))
            (when (and (buffer-file-name buf)
                       (string-prefix-p (file-truename org-directory)
                                        (file-truename (buffer-file-name buf))))
              (kill-buffer buf))))))))

(ert-deftest scott-quarterly-open-links-back-when-prior-quarter-exists ()
  "A prior-quarter note in the same scope is linked from the new note."
  (scott-quarterly-test--with-org-dir '("work/Quarterly/")
    (let* ((name (scott-quarterly--name))
           (prev (scott-quarterly--prev-name name))
           (prev-file (expand-file-name (concat "work/Quarterly/" prev ".org")
                                        org-directory)))
      (write-region (concat ":PROPERTIES:\n:ID:       older-id-7\n:END:\n#+title: "
                            prev " (Work)\n")
                    nil prev-file nil 'silent)
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
        (unwind-protect
            (progn
              (scott-quarterly-open)
              (with-temp-buffer
                (insert-file-contents
                 (expand-file-name (concat "work/Quarterly/" name ".org") org-directory))
                (should (string-match-p
                         (concat "\\[\\[id:older-id-7\\]\\[" prev "\\]\\]")
                         (buffer-string)))))
          ;; `buffer-file-name' is a truename, so compare truenames: if TMPDIR
          ;; is a symlink a raw prefix test never matches and the buffers leak
          ;; into later tests.
          (dolist (buf (buffer-list))
            (when (and (buffer-file-name buf)
                       (string-prefix-p (file-truename org-directory)
                                        (file-truename (buffer-file-name buf))))
              (kill-buffer buf))))))))

(ert-deftest scott-quarterly-open-prefix-arg-forces-work-scope ()
  "C-u opens work even when personal is available and would be the default."
  (scott-quarterly-test--with-org-dir '("Quarterly/" "work/Quarterly/")
    (let (visited)
      (cl-letf (((symbol-function 'find-file) (lambda (f) (setq visited f)))
                ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
        (let ((name (scott-quarterly--name)))
          ;; Both notes exist, so no create prompt is involved.
          (write-region "" nil (expand-file-name (concat name ".org") org-directory)
                        nil 'silent)
          (write-region "" nil (expand-file-name (concat "work/Quarterly/" name ".org")
                                                 org-directory)
                        nil 'silent)
          (scott-quarterly-open)
          (should (equal visited (expand-file-name (concat name ".org") org-directory)))
          (scott-quarterly-open '(4))
          (should (equal visited (expand-file-name (concat "work/Quarterly/" name ".org")
                                                   org-directory))))))))
