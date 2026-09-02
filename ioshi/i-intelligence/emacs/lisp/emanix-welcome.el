;;; emanix-welcome.el --- First-run orientation buffer -*- lexical-binding: t; -*-

;;; Commentary:
;; Shown once after an install.  Orientation, not documentation: the manual
;; lives at emanix.net and this buffer points there.
;;
;; Written under fallback.el's rule -- no package requires, no network -- because
;; it runs at startup and must never be the thing that breaks a first boot.
;;
;; Two facts are computed at RUNTIME, never baked in: whether this machine has
;; a config repo (false at first boot on a fresh install, true after
;; emanix-init) and where it is.  A hardcoded ~/dotfiles here would be the
;; emanix-elisa.el defect again -- shipped elisp naming a path that exists on
;; no machine.

;;; Code:

(defgroup emanix-welcome nil
  "First-run orientation buffer."
  :group 'emanix)

(defcustom emanix-welcome-repo-candidates
  (list (getenv "EMANIX_DOTFILES")
        (expand-file-name "flake" (or (getenv "HOME") "~"))
        "/etc/nixos")
  "Directories to search, in order, for this machine's config repo.
The first one holding both a `flake.nix' and a `.git' wins -- \"config repo\"
means what \"repo\" means.  /etc/nixos is in this list unconditionally because
`emanix-init's whole job is to turn it into a git repo elsewhere; while it is
still un-git-inited (always true on a fresh interactive install, which always
populates /etc/nixos/flake.nix) it correctly reads as not-yours-yet, and a
hand-`git init'ed /etc/nixos is still detected.  Nil entries are ignored, so
an unset environment variable costs nothing."
  :type '(repeat (choice string (const nil))))

(defun emanix-welcome--dismissed-file ()
  "Return the path of the dismissal marker."
  (let* ((xdg (getenv "XDG_STATE_HOME"))
         (base (if (and xdg (not (string-empty-p xdg)))
                   xdg
                 (expand-file-name ".local/state" (or (getenv "HOME") "~")))))
    (expand-file-name "emanix/welcome-dismissed" base)))

(defun emanix-welcome--config-repo (&optional candidates)
  "Return the first directory in CANDIDATES that is a config repo, or nil.
A candidate counts only when it holds BOTH a `flake.nix' and a `.git' --
requiring only `flake.nix' let /etc/nixos (which an interactive install
always populates with one) read as a config repo before `emanix-init' ever
ran, hiding the buffer's own \"create a config repo\" hint on exactly the
machines it exists for.  CANDIDATES defaults to
`emanix-welcome-repo-candidates'."
  (seq-find (lambda (dir)
              (and dir
                   (file-directory-p dir)
                   (file-exists-p (expand-file-name "flake.nix" dir))
                   (file-directory-p (expand-file-name ".git" dir))))
            (delq nil (or candidates emanix-welcome-repo-candidates))))

(defvar-keymap emanix-welcome-mode-map
  :doc "Keymap for `emanix-welcome-mode'."
  "q" #'quit-window
  "n" #'emanix-welcome-never-again
  "i" #'emanix-welcome-init)

(define-derived-mode emanix-welcome-mode special-mode "Emanix-Welcome"
  "Major mode for the emanix orientation buffer.")

(defun emanix-welcome-never-again ()
  "Dismiss the welcome buffer permanently."
  (interactive)
  (let ((f (emanix-welcome--dismissed-file)))
    (make-directory (file-name-directory f) t)
    (write-region "" nil f nil 'quiet))
  (message "emanix: welcome dismissed. Reopen it any time with M-x emanix-welcome")
  (quit-window))

(defun emanix-welcome-init ()
  "Run `emanix-init' in a terminal-ish buffer to create a config repo."
  (interactive)
  (if (emanix-welcome--config-repo)
      (message "emanix: this machine already has a config repo")
    (if (executable-find "emanix-init")
        (async-shell-command "emanix-init" "*emanix-init*")
      (message "emanix: emanix-init is not on PATH"))))

;;;###autoload
(defun emanix-welcome ()
  "Show the emanix orientation buffer."
  (interactive)
  (let ((repo (emanix-welcome--config-repo))
        (buf (get-buffer-create "*emanix-welcome*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Emanix — Emacs is the desktop.\n\n")
        (insert "  s-<return>   terminal          C-c i   ask arc\n")
        (insert "  s-1 … s-9    frame slots       C-c t   ghostel\n")
        (insert "  s-d          app launcher      C-x g   magit\n")
        (insert "  s-arrows     move focus        C-c z   prose mode\n\n")
        (if repo
            (insert (format "  Your config    %s\n" repo))
          (insert "  ⚠ This machine has no config repo yet.\n")
          (insert "    Press [i] to create one you can edit and keep.\n"))
        (insert "  Manual         https://emanix.net\n\n")
        (insert "  [q] close   [n] never show again")
        (insert (if repo "" "   [i] create a config repo"))
        (insert "\n"))
      (emanix-welcome-mode)
      (goto-char (point-min)))
    (pop-to-buffer buf)))

;;;###autoload
(defun emanix-welcome-maybe-show ()
  "Show the welcome buffer unless it has been dismissed."
  (interactive)
  (unless (file-exists-p (emanix-welcome--dismissed-file))
    (emanix-welcome)))

(provide 'emanix-welcome)
;;; emanix-welcome.el ends here
