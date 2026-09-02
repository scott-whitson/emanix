;;; emanix-welcome-test.el --- ERT tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'emanix-welcome)

(ert-deftest emanix-welcome-dismissed-file-honours-xdg ()
  "The dismissal marker follows XDG_STATE_HOME when it is set."
  (let ((process-environment (cons "XDG_STATE_HOME=/tmp/xdgstate" process-environment)))
    (should (equal "/tmp/xdgstate/emanix/welcome-dismissed"
                   (emanix-welcome--dismissed-file)))))

(ert-deftest emanix-welcome-dismissed-file-falls-back-under-home ()
  "Without XDG_STATE_HOME it falls back to ~/.local/state, never an absolute
/home/<user> literal."
  (let ((process-environment
         (cons "XDG_STATE_HOME=" (cons "HOME=/tmp/fakehome" process-environment))))
    (should (equal "/tmp/fakehome/.local/state/emanix/welcome-dismissed"
                   (emanix-welcome--dismissed-file)))))

(ert-deftest emanix-welcome-config-repo-detects-a-flake ()
  "A directory holding flake.nix counts as a config repo; one without does not."
  (let* ((dir (make-temp-file "emanix-welcome-test" t)))
    (unwind-protect
        (progn
          (should-not (emanix-welcome--config-repo (list dir)))
          (write-region "" nil (expand-file-name "flake.nix" dir))
          (should (equal dir (emanix-welcome--config-repo (list dir)))))
      (delete-directory dir t))))

(ert-deftest emanix-welcome-config-repo-returns-the-first-hit ()
  "Candidates are tried in order, so a consumer's path wins over the generated one."
  (let* ((a (make-temp-file "emanix-welcome-a" t))
         (b (make-temp-file "emanix-welcome-b" t)))
    (unwind-protect
        (progn
          (write-region "" nil (expand-file-name "flake.nix" a))
          (write-region "" nil (expand-file-name "flake.nix" b))
          (should (equal a (emanix-welcome--config-repo (list a b)))))
      (delete-directory a t)
      (delete-directory b t))))

(ert-deftest emanix-welcome-renders-without-a-repo ()
  "With no config repo the buffer offers to create one."
  (let ((emanix-welcome-repo-candidates (list "/nonexistent-emanix-path")))
    (emanix-welcome)
    (with-current-buffer "*emanix-welcome*"
      (should (string-match-p "no config repo" (buffer-string)))
      (should (string-match-p "emanix.net" (buffer-string)))
      ;; Pins the fix for a brief bug where this hint was built as a bare
      ;; (if repo "" "...") statement whose string result was discarded
      ;; instead of being passed to `insert', so it never appeared.
      (should (string-match-p "\\[i\\] create a config repo" (buffer-string))))
    (kill-buffer "*emanix-welcome*")))

(ert-deftest emanix-welcome-renders-with-a-repo ()
  "With a config repo present, the [i] hint is not offered."
  (let* ((dir (make-temp-file "emanix-welcome-repo-test" t)))
    (unwind-protect
        (progn
          (write-region "" nil (expand-file-name "flake.nix" dir))
          (let ((emanix-welcome-repo-candidates (list dir)))
            (emanix-welcome)
            (with-current-buffer "*emanix-welcome*"
              (should (string-match-p (regexp-quote dir) (buffer-string)))
              (should-not (string-match-p "\\[i\\] create a config repo" (buffer-string))))
            (kill-buffer "*emanix-welcome*")))
      (delete-directory dir t))))

;;; emanix-welcome-test.el ends here
