;;; emanix-agent-shell-tests.el --- Tests for the buffer-sync patch -*- lexical-binding: t; -*-
;;
;; These cover the half of emanix-agent-shell.el that has no agent-shell
;; dependency, which is deliberately the half where every measured failure
;; lived. Run by checks/agent-shell-sync.nix on every `nix flake check'.

(require 'ert)
;; `cl-letf' (the stubbing in the emanix/agent-shell-claude tests) is cl-lib's,
;; not a subr. ert happens to pull cl-lib in today; requiring it explicitly
;; keeps these tests from depending on that.
(require 'cl-lib)
(require 'emanix-agent-shell)

(defmacro emanix/agent-shell-test--with-file (var contents &rest body)
  "Bind VAR to a temp file containing CONTENTS and run BODY."
  (declare (indent 2))
  `(let ((,var (make-temp-file "emanix-agent-shell-test-" nil ".txt" ,contents)))
     (unwind-protect (progn ,@body)
       (dolist (b (buffer-list))
         (when (equal (buffer-file-name b) ,var)
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-file ,var))))

;; The payload mixes key styles: keywords at the top level of the tool call,
;; plain symbols inside the JSON-derived vectors. Getting this wrong fails
;; SILENTLY -- the handler runs, matches nothing, logs nothing -- which is
;; exactly how it failed during the probe.
(ert-deftest emanix/agent-shell-tool-call-paths-handles-both-key-styles ()
  (let ((tool-call
         '((:title . "Edit x.py")
           (:status . "completed")
           (:content . [((type . "diff") (path . "/tmp/from-content"))])
           (:raw-input (file_path . "/tmp/from-raw-input"))
           (:locations . [((path . "/tmp/from-locations") (line . 3))])
           (:diffs ((:file . "/tmp/from-diffs") (:line . 3))))))
    (let ((paths (emanix/agent-shell--tool-call-paths tool-call)))
      (dolist (expected '("/tmp/from-content" "/tmp/from-raw-input"
                          "/tmp/from-locations" "/tmp/from-diffs"))
        (should (member expected paths))))))

(ert-deftest emanix/agent-shell-tool-call-paths-deduplicates ()
  (let ((tool-call
         '((:raw-input (file_path . "/tmp/same"))
           (:locations . [((path . "/tmp/same"))])
           (:diffs ((:file . "/tmp/same"))))))
    (should (equal (emanix/agent-shell--tool-call-paths tool-call) '("/tmp/same")))))

(ert-deftest emanix/agent-shell-sync-updates-clean-buffer ()
  (emanix/agent-shell-test--with-file f "line1\nline2\n"
    (let ((buf (find-file-noselect f)))
      (write-region "line1\nline2\nline3\n" nil f nil 0)
      (should (eq (emanix/agent-shell--sync-from-disk f) 'synced))
      (with-current-buffer buf
        (should (equal (buffer-string) "line1\nline2\nline3\n"))
        (should-not (buffer-modified-p))))))

(ert-deftest emanix/agent-shell-sync-preserves-point ()
  (emanix/agent-shell-test--with-file f "line1\nline2\n"
    (let ((buf (find-file-noselect f)))
      (with-current-buffer buf (goto-char 4))
      (write-region "line1\nline2\nline3\n" nil f nil 0)
      (emanix/agent-shell--sync-from-disk f)
      (with-current-buffer buf (should (= (point) 4))))))

;; The reason this uses `replace-buffer-contents' and not `revert-buffer':
;; an agent's edit must be undoable like any other edit.
(ert-deftest emanix/agent-shell-sync-preserves-undo ()
  (emanix/agent-shell-test--with-file f "line1\nline2\n"
    (let ((buf (find-file-noselect f)))
      (write-region "line1\nline2\nline3\n" nil f nil 0)
      (emanix/agent-shell--sync-from-disk f)
      (with-current-buffer buf
        (undo-start)
        (undo-more 1)
        (should (equal (buffer-string) "line1\nline2\n"))))))

(ert-deftest emanix/agent-shell-sync-refuses-dirty-buffer ()
  (emanix/agent-shell-test--with-file f "line1\nline2\n"
    (let ((buf (find-file-noselect f)))
      (with-current-buffer buf
        (goto-char (point-max))
        (insert "MY-UNSAVED\n"))
      (write-region "line1\nline2\nline3\n" nil f nil 0)
      (should (eq (emanix/agent-shell--sync-from-disk f) 'skipped-dirty))
      (with-current-buffer buf
        (should (string-match-p "MY-UNSAVED" (buffer-string)))))))

;; Read and Grep complete as tool calls too, so most updates name a file
;; nothing wrote. Doing the temp-buffer/diff dance for those is waste, and for
;; a DIRTY buffer it produced a "changed on disk" warning that was simply false.
(ert-deftest emanix/agent-shell-sync-skips-buffer-already-current ()
  (emanix/agent-shell-test--with-file f "line1\n"
    (find-file-noselect f)
    (should (eq (emanix/agent-shell--sync-from-disk f) 'unchanged))))

(ert-deftest emanix/agent-shell-sync-skips-dirty-buffer-nothing-wrote ()
  (emanix/agent-shell-test--with-file f "line1\n"
    (with-current-buffer (find-file-noselect f)
      (goto-char (point-max))
      (insert "MY-UNSAVED\n"))
    (should (eq (emanix/agent-shell--sync-from-disk f) 'unchanged))))

;; The modtime is stamped BEFORE the replacement, so a replacement that
;; signals would leave the buffer claiming to be in sync with content it never
;; received -- and would silence the supersession warning too. A read-only
;; buffer is the reachable case: `view-mode', \[read-only-mode], or an
;; unwritable file.
(ert-deftest emanix/agent-shell-sync-updates-read-only-buffer ()
  (emanix/agent-shell-test--with-file f "line1\nline2\n"
    (let ((buf (find-file-noselect f)))
      (with-current-buffer buf (setq buffer-read-only t))
      (write-region "line1\nline2\nline3\n" nil f nil 0)
      (should (eq (emanix/agent-shell--sync-from-disk f) 'synced))
      (with-current-buffer buf
        (should (equal (buffer-string) "line1\nline2\nline3\n"))
        (should buffer-read-only)))))

;; The advice hands over the shell buffer's `default-directory', which
;; upstream's `agent-shell-cwd' falls back to when there is no project. A
;; shell started from *scratch* would therefore force-save every modified
;; buffer under $HOME on every RET.
(ert-deftest emanix/agent-shell-save-project-buffers-refuses-broad-roots ()
  (emanix/agent-shell-test--with-file f "a\n"
    (with-current-buffer (find-file-noselect f)
      (goto-char (point-max))
      (insert "edited\n"))
    (should-not (emanix/agent-shell--save-project-buffers "/"))
    (should (emanix/agent-shell--save-root-too-broad-p
             (file-name-as-directory (expand-file-name "~"))))
    (with-current-buffer (find-buffer-visiting f)
      (should (buffer-modified-p)))))

;; Scoping matters: an agent shell's `default-directory' is one project, and
;; saving every modified buffer in the session would commit unrelated work.
;; The two files must therefore live in genuinely different directories --
;; sharing $TMPDIR would let a broken implementation pass.
(ert-deftest emanix/agent-shell-save-project-buffers-saves-only-under-root ()
  (let* ((root (make-temp-file "emanix-agent-shell-root-" t))
         (inside (expand-file-name "inside.txt" root))
         (outside (make-temp-file "emanix-agent-shell-outside-" nil ".txt" "b\n")))
    (unwind-protect
        (progn
          (write-region "a\n" nil inside)
          (dolist (f (list inside outside))
            (with-current-buffer (find-file-noselect f)
              (goto-char (point-max))
              (insert "edited\n")))
          (let ((saved (emanix/agent-shell--save-project-buffers root)))
            (should (member inside saved))
            (should-not (member outside saved)))
          (with-current-buffer (find-file-noselect inside)
            (should-not (buffer-modified-p)))
          ;; The buffer outside the root must still be dirty and unwritten.
          (with-current-buffer (find-file-noselect outside)
            (should (buffer-modified-p))))
      (dolist (f (list inside outside))
        (when-let* ((b (find-buffer-visiting f)))
          (with-current-buffer b (set-buffer-modified-p nil))
          (kill-buffer b)))
      (delete-directory root t)
      (delete-file outside))))

;; emanix/agent-shell-claude starts an agent elsewhere by binding
;; `default-directory' around the upstream command, so what these assert is
;; the value the upstream command SEES. Nothing else about it is observable
;; from batch: agent-shell is not loadable here (that independence is the
;; point of this test file), so the command itself is stubbed and the captured
;; directory is the whole result. `cl-letf' on `symbol-function' is what makes
;; that work against the top-level `autoload' -- it rebinds the autoload stub
;; without ever letting it fire, so no ACP process and no package load happen.
(ert-deftest emanix/agent-shell-claude-uses-current-directory-without-prefix ()
  (let ((seen nil)
        (default-directory (file-name-as-directory (make-temp-file "emanix-cwd-" t))))
    (unwind-protect
        (cl-letf (((symbol-function 'agent-shell-anthropic-start-claude-code)
                   (lambda () (setq seen default-directory)))
                  ;; A bare press must not prompt. Signalling here rather than
                  ;; returning a value is deliberate: a stub that quietly
                  ;; answered the prompt would let the regression pass.
                  ((symbol-function 'read-directory-name)
                   (lambda (&rest _) (error "prompted without a prefix argument"))))
          (emanix/agent-shell-claude nil))
      (delete-directory default-directory t))
    (should (equal seen default-directory))))

(ert-deftest emanix/agent-shell-claude-uses-prompted-directory-with-prefix ()
  (let* ((elsewhere (make-temp-file "emanix-elsewhere-" t))
         (seen nil))
    (unwind-protect
        (let ((default-directory (file-name-as-directory (make-temp-file "emanix-cwd-" t))))
          (unwind-protect
              (cl-letf (((symbol-function 'agent-shell-anthropic-start-claude-code)
                         (lambda () (setq seen default-directory)))
                        ;; Returned WITHOUT a trailing slash, as completion may:
                        ;; `default-directory' must end in one, so the wrapper
                        ;; owns that normalisation and this is where it shows.
                        ((symbol-function 'read-directory-name)
                         (lambda (&rest _) elsewhere)))
                (emanix/agent-shell-claude '(4)))
            (delete-directory default-directory t)))
      (delete-directory elsewhere t))
    (should (equal seen (file-name-as-directory elsewhere)))))

(provide 'emanix-agent-shell-tests)
;;; emanix-agent-shell-tests.el ends here
