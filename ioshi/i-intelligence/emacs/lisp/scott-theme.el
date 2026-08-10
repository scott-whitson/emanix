;;; scott-theme.el --- dotfiles theme control -*- lexical-binding: t; -*-

;; The active theme is named in ~/.config/dotfiles/active-theme, and each
;; themes/<name>/ directory carries an `emacs-theme' file naming the Emacs
;; theme to load. bin/dot-theme-set calls (scott/theme-set "<name>") on switch.
;;
;; This used to take a catppuccin flavor ("mocha"/"latte") and derive it with
;; (string-match-p "latte" name), which silently mapped every other theme name
;; to mocha — so a non-catppuccin theme could not be expressed at all.

(require 'catppuccin-theme nil :no-error)

;; Modus ships inside Emacs at <emacs>/share/emacs/<ver>/etc/themes, which is on
;; custom-theme-load-path but NOT on load-path — so `load-theme' finds the
;; themes while `require' cannot find modus-themes.el, where the palette-override
;; variable is defined. Extend load-path so the overrides below actually apply.
(add-to-list 'load-path (expand-file-name "themes/" data-directory))

(defconst scott-theme--state-file "~/.config/dotfiles/active-theme")
(defconst scott-theme--themes-dir "~/dotfiles/themes")
(defconst scott-theme--default "catppuccin-mocha")

;; bg-main/fg-main per theme. These MUST match lib/themes.nix's base/text for
;; the same theme: Modus defaults to 19-21:1 (modus-vivendi is #000/#fff), and
;; the spec deliberately targets ~16:1 to avoid halation.
(defconst scott-theme--modus-overrides
  '(("high-contrast-dark"  . ((bg-main "#0a0a0a") (fg-main "#e8e8e8")))
    ("high-contrast-light" . ((bg-main "#f2f2f2") (fg-main "#111111")))))

(defun scott-theme--read (path)
  "Return the trimmed contents of PATH, or nil if unreadable."
  (when (file-readable-p path)
    (string-trim (with-temp-buffer (insert-file-contents path) (buffer-string)))))

(defun scott-theme--active-name ()
  "Name of the active dotfiles theme."
  (or (scott-theme--read scott-theme--state-file) scott-theme--default))

(defun scott-theme--emacs-theme (name)
  "Emacs theme symbol for dotfiles theme NAME."
  (intern (or (scott-theme--read
               (expand-file-name (format "%s/emacs-theme" name)
                                 scott-theme--themes-dir))
              "catppuccin")))

(defun scott/theme-set (name)
  "Switch the running session to dotfiles theme NAME."
  (interactive "sTheme name: ")
  (let ((theme (scott-theme--emacs-theme name)))
    (setq modus-themes-common-palette-overrides
          (cdr (assoc name scott-theme--modus-overrides)))
    (when (eq theme 'catppuccin)
      (setq catppuccin-flavor (if (string-match-p "latte" name) 'latte 'mocha)))
    (mapc #'disable-theme custom-enabled-themes)
    (load-theme theme :no-confirm)
    (when (eq theme 'catppuccin) (catppuccin-reload))
    theme))

(defun scott/theme-init ()
  "Load the theme matching the active dotfiles theme."
  (scott/theme-set (scott-theme--active-name)))

(provide 'scott-theme)
;;; scott-theme.el ends here
