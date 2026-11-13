;;; emanix-ewm-test.el --- ERT tests -*- lexical-binding: t; -*-

;; The PrintScreen command, without EWM, grim, slurp or a Wayland session: the
;; three subprocesses are stubbed and the choice is injected, so what is under
;; test is the orchestration -- when slurp runs, what grim is told, what happens
;; to the temp file, and what reaches the kill ring.

(require 'ert)
(require 'cl-lib)
(require 'emanix-ewm-screenshot)

(defvar emanix-ewm-test--calls nil
  "Recorded subprocess calls, newest first, as (PROGRAM INFILE . ARGS).")
(defvar emanix-ewm-test--geometry "10,20 300x400"
  "What the slurp stub writes to stdout; nil means the user cancelled.")
(defvar emanix-ewm-test--slurp-status 0
  "Exit status the slurp stub returns. Non-zero is how slurp reports a cancel.")
(defvar emanix-ewm-test--grim-status 0
  "Exit status the grim stub returns.")
(defvar emanix-ewm-test--action 'save
  "What the choice stub returns.")

(defun emanix-ewm-test--call-process (program &optional infile _dest _display &rest args)
  "A `call-process' that obeys the three stubs and records every call."
  (push (cons program (cons infile args)) emanix-ewm-test--calls)
  (pcase program
    ("slurp" (when (eq _dest t) (insert (or emanix-ewm-test--geometry "")))
             emanix-ewm-test--slurp-status)
    ;; grim writes its last argument's file; a PNG payload is not needed.
    ("grim" (with-temp-file (car (last args)) (insert "PNG")) emanix-ewm-test--grim-status)
    (_ 0)))

(defmacro emanix-ewm-test--stub (&rest body)
  "Run BODY with subprocesses and the capture choice stubbed."
  (declare (indent 0))
  `(let ((emanix-ewm-test--calls nil)
         (emanix-ewm-test--geometry "10,20 300x400")
         (emanix-ewm-test--slurp-status 0)
         (emanix-ewm-test--grim-status 0)
         (emanix-ewm-test--action 'save))
     (cl-letf (((symbol-function 'call-process) #'emanix-ewm-test--call-process)
               ((symbol-function 'emanix/ewm--choose-action)
                (lambda () emanix-ewm-test--action)))
       ,@body)))

(defun emanix-ewm-test--call (program)
  "The most recent recorded call of PROGRAM, or nil."
  (assoc program emanix-ewm-test--calls))

(defun emanix-ewm-test--infile (program)
  "The INFILE of PROGRAM's most recent call."
  (nth 1 (emanix-ewm-test--call program)))

(defun emanix-ewm-test--args (program)
  "The ARGS of PROGRAM's most recent call."
  (nthcdr 2 (emanix-ewm-test--call program)))

(defun emanix-ewm-test--pngs (dir)
  "The PNG names sitting in DIR."
  (directory-files dir nil "\\.png\\'"))

(ert-deftest emanix-ewm-screenshot-region-is-slurped-and-saved ()
  "A region capture runs slurp then grim -g, and save lands it in the directory."
  (emanix-ewm-test--stub
    (let* ((dir (make-temp-file "emanix-shots-" t))
           (emanix/screenshot-directory dir))
      (emanix/ewm-screenshot)
      (should (emanix-ewm-test--call "slurp"))
      (should (equal (seq-take (emanix-ewm-test--args "grim") 2)
                     '("-g" "10,20 300x400")))
      (should (= 1 (length (emanix-ewm-test--pngs dir))))
      (should (string-prefix-p (file-name-as-directory dir) (car kill-ring))))))

(ert-deftest emanix-ewm-screenshot-copy-leaves-no-file-and-clears-the-temp ()
  "Copy hands the temp file to wl-copy as PNG, then deletes the temp."
  (emanix-ewm-test--stub
    (let* ((dir (make-temp-file "emanix-shots-" t))
           (emanix/screenshot-directory dir)
           (emanix-ewm-test--action 'copy))
      (emanix/ewm-screenshot)
      (let ((temp (emanix-ewm-test--infile "wl-copy")))
        (should temp)
        (should (equal (emanix-ewm-test--args "wl-copy") '("--type" "image/png")))
        (should (string-suffix-p ".png" temp))
        (should-not (file-exists-p temp)))
      (should-not (emanix-ewm-test--pngs dir)))))

(ert-deftest emanix-ewm-screenshot-both-saves-the-copied-file ()
  "Both saves first; the clipboard holds the saved path, not the temp."
  (emanix-ewm-test--stub
    (let* ((dir (make-temp-file "emanix-shots-" t))
           (emanix/screenshot-directory dir)
           (emanix-ewm-test--action 'both))
      (emanix/ewm-screenshot)
      (should (= 1 (length (emanix-ewm-test--pngs dir))))
      (should (string-prefix-p (file-name-as-directory dir)
                               (emanix-ewm-test--infile "wl-copy")))
      (should (equal (car kill-ring) (emanix-ewm-test--infile "wl-copy"))))))

(ert-deftest emanix-ewm-screenshot-full-skips-slurp-and-region ()
  "Whole-output capture never calls slurp and passes grim no geometry."
  (emanix-ewm-test--stub
    (let* ((dir (make-temp-file "emanix-shots-" t))
           (emanix/screenshot-directory dir))
      (emanix/ewm-screenshot t)
      (should-not (emanix-ewm-test--call "slurp"))
      (should (= 1 (length (emanix-ewm-test--args "grim")))))))

(ert-deftest emanix-ewm-screenshot-cancelled-selection-does-nothing ()
  "A cancelled slurp is not an error, and grim never runs.
slurp reports a cancel as a non-zero exit; empty output at exit 0 is the other
shape that reaches the same nil, and both are asserted because the stub used to
return 0 unconditionally -- so only the second one was ever exercised."
  (emanix-ewm-test--stub
    (let ((emanix-ewm-test--slurp-status 1))
      (emanix/ewm-screenshot)
      (should (emanix-ewm-test--call "slurp"))
      (should-not (emanix-ewm-test--call "grim"))))
  (emanix-ewm-test--stub
    (let ((emanix-ewm-test--geometry nil))
      (emanix/ewm-screenshot)
      (should (emanix-ewm-test--call "slurp"))
      (should-not (emanix-ewm-test--call "grim")))))

(ert-deftest emanix-ewm-screenshot-quit-at-the-prompt-clears-the-temp ()
  "C-g at the prompt is not a choice, and the temp PNG still goes.
The prompt's cancel key is handled as a nil choice; quit is the path that leaves
`emanix/ewm-screenshot' early, which is why the cleanup is an unwind-protect
rather than one delete per branch.

Caught with `condition-case', NOT `should-error': the `error' condition class
does not include `quit', so should-error lets the quit escape to ERT, which
records QUIT for the whole test and never reaches the assertion below it. That
version built green and asserted nothing."
  (emanix-ewm-test--stub
    (let ((temp (make-temp-file "emanix-ewm-test-" nil ".png")))
      (cl-letf (((symbol-function 'make-temp-file) (lambda (&rest _) temp))
                ((symbol-function 'emanix/ewm--choose-action)
                 (lambda () (signal 'quit nil))))
        (should (eq 'quit (condition-case nil
                              (progn (emanix/ewm-screenshot) 'no-quit)
                            (quit 'quit)))))
      (should-not (file-exists-p temp)))))

(ert-deftest emanix-ewm-screenshot-grim-failure-signals-and-clears-the-temp ()
  "A failed grim raises a user-error and does not leave the temp behind."
  (emanix-ewm-test--stub
    (let* ((dir (make-temp-file "emanix-shots-" t))
           (emanix/screenshot-directory dir)
           (emanix-ewm-test--grim-status 1))
      (let ((temp (make-temp-file "emanix-ewm-test-" nil ".png")))
        (cl-letf (((symbol-function 'make-temp-file) (lambda (&rest _) temp)))
          (should-error (emanix/ewm-screenshot) :type 'user-error))
        (should-not (file-exists-p temp))))))

(ert-deftest emanix-ewm-choose-action-maps-keys-to-symbols ()
  "Each prompt key maps to its action; cancel (and anything else) is nil."
  (dolist (case '((?s . save) (?c . copy) (?b . both) (?q . nil)))
    (cl-letf (((symbol-function 'read-multiple-choice)
               (lambda (&rest _) (list (car case) "name"))))
      (should (eq (emanix/ewm--choose-action) (cdr case))))))

(provide 'emanix-ewm-test)
;;; emanix-ewm-test.el ends here
