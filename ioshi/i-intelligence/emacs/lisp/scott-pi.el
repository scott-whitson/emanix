;;; scott-pi.el --- Pi agent integration :: Ghostty launcher -*- lexical-binding: t; -*-
;;
;; The old vterm-based Pi-in-Emacs integration was removed as brittle.
;; This replacement launches Pi in its native TUI in a Ghostty window,
;; avoiding Emacs-terminal emulation issues entirely.
;;
;; Keybinding:
;;   C-c p  — Open Pi agent in a new Ghostty window
;;
;; Pi is searched on PATH and then in `~/.local/bin/pi`.

(defgroup scott-pi nil "Pi agent integration (Ghostty launcher)." :group 'tools)

(defcustom scott/pi-program "pi"
  "Pi CLI executable name or path."
  :type 'string :group 'scott-pi)

(defcustom scott/pi-terminal "ghostty"
  "Terminal emulator to launch Pi in."
  :type 'string :group 'scott-pi)

(defcustom scott/pi-temp-dir (expand-file-name "pi-region" (or (getenv "TMPDIR") "/tmp"))
  "Directory for temporary files passed to Pi via `@file`."
  :type 'directory :group 'scott-pi)

;; --- Helpers ---

(defun scott/pi--ensure-temp-dir ()
  "Create `scott/pi-temp-dir' if missing."
  (make-directory scott/pi-temp-dir t))

(defun scott/pi--executable (name)
  "Return the absolute path to NAME, or nil if missing."
  (or (executable-find name)
      (when (file-name-absolute-p name)
        (and (file-executable-p name) name))))

(defun scott/pi--find ()
  "Return the pi executable path, or nil.

This checks `scott/pi-program' first, then falls back to
`~/.local/bin/pi' because the Emacs daemon often starts without the
interactive shell's PATH extensions."
  (or (scott/pi--executable scott/pi-program)
      (scott/pi--executable (expand-file-name "~/.local/bin/pi"))))

(defun scott/pi--terminal ()
  "Return the terminal executable path, or nil."
  (scott/pi--executable scott/pi-terminal))

;; --- Commands ---

;;;###autoload
(defun scott/pi ()
  "Open Pi agent in a new Ghostty terminal window.
This launches Pi's native TUI outside Emacs, bypassing the Emacs
terminal emulation that caused problems with the old vterm approach."
  (interactive)
  (let ((pi-bin (scott/pi--find))
        (term-bin (scott/pi--terminal)))
    (unless pi-bin
      (user-error "Pi agent not found (checked `scott/pi-program' and `~/.local/bin/pi')"))
    (unless term-bin
      (user-error "Terminal %s not found (check `scott/pi-terminal')" scott/pi-terminal))
    (start-process "pi-ghostty" nil term-bin "-e" pi-bin)
    (message "Opened Pi in %s" scott/pi-terminal)))

;;;###autoload
(defun scott/pi-send-region (beg end)
  "Send the selected region to Pi.
The region is written to a temp file and Pi is launched with `@file` to
load it as initial context. This starts a new Pi session — to continue
an existing one use `--continue' manually.

If called interactively, the region is taken from the current selection
(or the whole buffer if none is selected)."
  (interactive "r")
  (let ((pi-bin (scott/pi--find))
        (term-bin (scott/pi--terminal))
        content temp-file)
    (unless pi-bin
      (user-error "Pi agent not found (checked `scott/pi-program' and `~/.local/bin/pi')"))
    (unless term-bin
      (user-error "Terminal %s not found (check `scott/pi-terminal')" scott/pi-terminal))
    (scott/pi--ensure-temp-dir)
    (setq content (buffer-substring-no-properties beg end)
          temp-file (make-temp-file "pi-region-" nil ".txt" content))
    (start-process "pi-ghostty-region" nil term-bin "-e" pi-bin (concat "@" temp-file))
    (message "Sent %d chars to Pi" (length content))))

;; --- Keybindings ---

(global-set-key (kbd "C-c p") #'scott/pi)
(global-unset-key (kbd "C-c r"))

(provide 'scott-pi)
;;; scott-pi.el ends here