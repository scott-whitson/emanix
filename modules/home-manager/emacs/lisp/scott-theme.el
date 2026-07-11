;;; scott-theme.el --- catppuccin flavor control -*- lexical-binding: t; -*-
;; Flavor tracks the dotfiles theme system: dot-theme-set calls
;; (scott/theme-set "mocha"|"latte") on switch; on startup we derive the
;; flavor from the active-theme state marker.
(require 'catppuccin-theme)

(defconst scott-theme--state-file "~/.config/dotfiles/active-theme")

(defun scott-theme--flavor-from-state ()
  "Return the catppuccin flavor symbol for the active dotfiles theme."
  (let ((name (when (file-readable-p scott-theme--state-file)
                (string-trim (with-temp-buffer
                               (insert-file-contents scott-theme--state-file)
                               (buffer-string))))))
    (if (and name (string-match-p "latte" name)) 'latte 'mocha)))

(defun scott/theme-set (flavor)
  "Switch the catppuccin FLAVOR (\"mocha\" or \"latte\") in the running session."
  (setq catppuccin-flavor (intern flavor))
  (catppuccin-reload))

(defun scott/theme-init ()
  "Load catppuccin with the flavor matching the dotfiles active theme."
  (setq catppuccin-flavor (scott-theme--flavor-from-state))
  (load-theme 'catppuccin t))

(provide 'scott-theme)
;;; scott-theme.el ends here
