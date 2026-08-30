;;; emanix-pi.el --- Pi agent integration :: Ghostty launcher -*- lexical-binding: t; -*-
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

(defgroup emanix-pi nil "Pi agent integration (Ghostty launcher)." :group 'tools)

(defcustom emanix/pi-program "pi"
  "Pi CLI executable name or path."
  :type 'string :group 'emanix-pi)

(defcustom emanix/pi-terminal "ghostty"
  "Terminal emulator to launch Pi in."
  :type 'string :group 'emanix-pi)

(defcustom emanix/pi-temp-dir (expand-file-name "pi-region" (or (getenv "TMPDIR") "/tmp"))
  "Directory for temporary files passed to Pi via `@file`."
  :type 'directory :group 'emanix-pi)

;; --- Helpers ---

(defun emanix/pi--ensure-temp-dir ()
  "Create `emanix/pi-temp-dir' if missing."
  (make-directory emanix/pi-temp-dir t))

(defun emanix/pi--executable (name)
  "Return the absolute path to NAME, or nil if missing."
  (or (executable-find name)
      (when (file-name-absolute-p name)
        (and (file-executable-p name) name))))

(defun emanix/pi--find ()
  "Return the pi executable path, or nil.

This checks `emanix/pi-program' first, then falls back to the pi
wrapper script in the consumer's checkout (`$EMANIX_BIN_DIR/pi')
because the Emacs daemon often starts without the interactive
shell's PATH extensions and so never sees that `bin/' on `exec-path'."
  (or (emanix/pi--executable emanix/pi-program)
      (emanix/pi--executable (expand-file-name "pi" (or (getenv "EMANIX_BIN_DIR") "")))))

(defun emanix/pi--terminal ()
  "Return the terminal executable path, or nil."
  (emanix/pi--executable emanix/pi-terminal))

;; --- Commands ---

;;;###autoload
(defun emanix/pi ()
  "Open Pi agent in a new Ghostty terminal window.
This launches Pi's native TUI outside Emacs, bypassing the Emacs
terminal emulation that caused problems with the old vterm approach."
  (interactive)
  (let ((pi-bin (emanix/pi--find))
        (term-bin (emanix/pi--terminal)))
    (unless pi-bin
      (user-error "Pi agent not found (checked `emanix/pi-program' and `$EMANIX_BIN_DIR/pi')"))
    (unless term-bin
      (user-error "Terminal %s not found (check `emanix/pi-terminal')" emanix/pi-terminal))
    (start-process "pi-ghostty" nil term-bin "-e" pi-bin)
    (message "Opened Pi in %s" emanix/pi-terminal)))

;;;###autoload
(defun emanix/pi-send-region (beg end)
  "Send the selected region to Pi.
The region is written to a temp file and Pi is launched with `@file` to
load it as initial context. This starts a new Pi session — to continue
an existing one use `--continue' manually.

If called interactively, the region is taken from the current selection
(or the whole buffer if none is selected)."
  (interactive "r")
  (let ((pi-bin (emanix/pi--find))
        (term-bin (emanix/pi--terminal))
        content temp-file)
    (unless pi-bin
      (user-error "Pi agent not found (checked `emanix/pi-program' and `$EMANIX_BIN_DIR/pi')"))
    (unless term-bin
      (user-error "Terminal %s not found (check `emanix/pi-terminal')" emanix/pi-terminal))
    (emanix/pi--ensure-temp-dir)
    (setq content (buffer-substring-no-properties beg end)
          temp-file (make-temp-file "pi-region-" nil ".txt" content))
    (start-process "pi-ghostty-region" nil term-bin "-e" pi-bin (concat "@" temp-file))
    (message "Sent %d chars to Pi" (length content))))

;; --- Keybindings ---

(global-set-key (kbd "C-c p") #'emanix/pi)
(global-unset-key (kbd "C-c r"))

(provide 'emanix-pi)
;;; emanix-pi.el ends here