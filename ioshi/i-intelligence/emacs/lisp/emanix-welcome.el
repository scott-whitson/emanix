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
  "i" #'emanix-welcome-init
  "g" #'emanix-guides)

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
        (insert "  [g] where to learn — Emacs, Elisp, EWM, NixOS\n\n")
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


;;; --- Guides -----------------------------------------------------------------

;; Where to learn, in one place, so the answer is never "search the web and
;; hope". Every info entry here was verified present in this Emacs build before
;; being listed (2026-09-05): emacs, eintr, elisp, org, efaq, cl and transient
;; all resolve. `magit' is deliberately absent — its manual is NOT installed,
;; and a dead node in a guide is worse than an omission.
;;
;; Buttons rather than a keymap of letters: `insert-text-button' is built in,
;; needs no package, and gives RET and mouse for free without inventing a
;; binding that could collide with something the operator already uses.

(defconst emanix-guides--entries
  '(("Emacs manual"         info "(emacs)"
     "The editor itself, exhaustively")
    ("Emacs Lisp Intro"     info "(eintr)"
     "Start here to write your first Elisp")
    ("Elisp Reference"      info "(elisp)"
     "The language, for when the intro runs out")
    ("Org manual"           info "(org)"
     "Outlines, agenda, literate config")
    ("Emacs FAQ"            info "(efaq)"
     "Short answers to the common confusions")
    ("All info manuals"     info "(dir)"
     "The whole directory — the same as C-h i")
    ("Emanix"               url  "https://emanix.net"
     "This distribution: philosophy, options, keybindings, theming")
    ("EWM"                  url  "https://codeberg.org/ezemtsov/ewm"
     "The Wayland compositor Emacs runs as, upstream")
    ("NixOS manual"         url  "https://nixos.org/manual/nixos/stable/"
     "Configuring the system")
    ("Nixpkgs manual"       url  "https://nixos.org/manual/nixpkgs/stable/"
     "Packages, overlays, and how derivations are written")
    ("nix.dev"              url  "https://nix.dev/"
     "Learning Nix the language, from the beginning")
    ("Home Manager options" url  "https://nix-community.github.io/home-manager/options.xhtml"
     "Every option the per-user layer accepts"))
  "Learning resources: (LABEL KIND TARGET BLURB).
KIND is `info' for a manual in this Emacs, or `url' for the browser.")

(defun emanix-guides--open (entry)
  "Open ENTRY, an element of `emanix-guides--entries'."
  (pcase-let ((`(,_label ,kind ,target ,_blurb) entry))
    (pcase kind
      ('info (info target))
      ('url  (browse-url target))
      (_     (message "emanix: unknown guide kind %s" kind)))))

(define-derived-mode emanix-guides-mode special-mode "Emanix-Guides"
  "Major mode for the emanix guide index.")

;;;###autoload
(defun emanix-guides ()
  "Show every guide worth knowing about, each openable with RET."
  (interactive)
  (let ((buf (get-buffer-create "*emanix-guides*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Where to learn\n\n")
        (insert "  RET or click opens.  TAB moves between entries.  q closes.\n\n")
        (dolist (e emanix-guides--entries)
          (pcase-let ((`(,label ,kind ,_target ,blurb) e))
            (insert "  ")
            (insert-text-button
             (format "%-22s" label)
             'action (lambda (_b) (emanix-guides--open e))
             'follow-link t
             'help-echo (format "Open %s" label))
            (insert (format " %s%s\n" (if (eq kind 'url) "↗ " "  ") blurb))))
        (insert "\n  C-h i reaches the info directory from anywhere.\n"))
      (emanix-guides-mode)
      (goto-char (point-min)))
    (pop-to-buffer buf)))

(provide 'emanix-welcome)
;;; emanix-welcome.el ends here
