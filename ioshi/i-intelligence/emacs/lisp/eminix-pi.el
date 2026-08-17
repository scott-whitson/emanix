;;; eminix-pi.el --- Pi agent integration :: Ghostty launcher -*- lexical-binding: t; -*-
;;
;; The old vterm-based Pi-in-Emacs integration was removed as brittle.
;; This replacement launches Pi in its native TUI in a Ghostty window,
;; avoiding Emacs-terminal emulation issues entirely.
;;
;; Keybinding:
;;   C-c p  — Open Pi agent in a new Ghostty window
;;
;; Pi is searched on PATH and then in `$DOTFILES/bin/pi` (the checkout's
;; wrapper script, not `~/.local/bin` — nothing symlinks there anymore).

(defgroup eminix-pi nil "Pi agent integration (Ghostty launcher)." :group 'tools)

(defcustom eminix/pi-program "pi"
  "Pi CLI executable name or path."
  :type 'string :group 'eminix-pi)

(defcustom eminix/pi-terminal "ghostty"
  "Terminal emulator to launch Pi in."
  :type 'string :group 'eminix-pi)

(defcustom eminix/pi-temp-dir (expand-file-name "pi-region" (or (getenv "TMPDIR") "/tmp"))
  "Directory for temporary files passed to Pi via `@file`."
  :type 'directory :group 'eminix-pi)

;; --- Helpers ---

(defun eminix/pi--ensure-temp-dir ()
  "Create `eminix/pi-temp-dir' if missing."
  (make-directory eminix/pi-temp-dir t))

(defun eminix/pi--executable (name)
  "Return the absolute path to NAME, or nil if missing."
  (or (executable-find name)
      (when (file-name-absolute-p name)
        (and (file-executable-p name) name))))

(defun eminix/pi--find ()
  "Return the pi executable path, or nil.

This checks `eminix/pi-program' first, then falls back to the pi
wrapper script in the consumer's checkout (`$EMINIX_BIN_DIR/pi')
because the Emacs daemon often starts without the interactive
shell's PATH extensions and so never sees that `bin/' on `exec-path'."
  (or (eminix/pi--executable eminix/pi-program)
      (eminix/pi--executable (expand-file-name "pi" (or (getenv "EMINIX_BIN_DIR") "")))))

(defun eminix/pi--terminal ()
  "Return the terminal executable path, or nil."
  (eminix/pi--executable eminix/pi-terminal))

;; --- Commands ---

;;;###autoload
(defun eminix/pi ()
  "Open Pi agent in a new Ghostty terminal window.
This launches Pi's native TUI outside Emacs, bypassing the Emacs
terminal emulation that caused problems with the old vterm approach."
  (interactive)
  (let ((pi-bin (eminix/pi--find))
        (term-bin (eminix/pi--terminal)))
    (unless pi-bin
      (user-error "Pi agent not found (checked `eminix/pi-program' and `$EMINIX_BIN_DIR/pi')"))
    (unless term-bin
      (user-error "Terminal %s not found (check `eminix/pi-terminal')" eminix/pi-terminal))
    (start-process "pi-ghostty" nil term-bin "-e" pi-bin)
    (message "Opened Pi in %s" eminix/pi-terminal)))

;;;###autoload
(defun eminix/pi-send-region (beg end)
  "Send the selected region to Pi.
The region is written to a temp file and Pi is launched with `@file` to
load it as initial context. This starts a new Pi session — to continue
an existing one use `--continue' manually.

If called interactively, the region is taken from the current selection
(or the whole buffer if none is selected)."
  (interactive "r")
  (let ((pi-bin (eminix/pi--find))
        (term-bin (eminix/pi--terminal))
        content temp-file)
    (unless pi-bin
      (user-error "Pi agent not found (checked `eminix/pi-program' and `$EMINIX_BIN_DIR/pi')"))
    (unless term-bin
      (user-error "Terminal %s not found (check `eminix/pi-terminal')" eminix/pi-terminal))
    (eminix/pi--ensure-temp-dir)
    (setq content (buffer-substring-no-properties beg end)
          temp-file (make-temp-file "pi-region-" nil ".txt" content))
    (start-process "pi-ghostty-region" nil term-bin "-e" pi-bin (concat "@" temp-file))
    (message "Sent %d chars to Pi" (length content))))

;; --- Keybindings ---

(global-set-key (kbd "C-c p") #'eminix/pi)
(global-unset-key (kbd "C-c r"))

(provide 'eminix-pi)
;;; eminix-pi.el ends here