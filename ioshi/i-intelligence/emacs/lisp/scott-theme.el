;;; scott-theme.el --- dotfiles theme control -*- lexical-binding: t; -*-

;; The active theme is named in ~/.config/dotfiles/active-theme, and each
;; themes/<name>/ directory carries an `emacs-theme' file naming the Emacs
;; theme to load. bin/dot-theme-set calls (scott/theme-set "<name>") on switch.
;;
;; This used to take a catppuccin flavor ("mocha"/"latte") and derive it with
;; (string-match-p "latte" name), which silently mapped every other theme name
;; to mocha — so a non-catppuccin theme could not be expressed at all. Both the
;; Catppuccin flavour and the Modus bg-main/fg-main overrides below are now
;; derived from themes/<name>/variant and themes/<name>/colors.toml instead of
;; from substrings or a name-keyed table, so a fifth theme needs no code
;; change here — see scott-theme--modus-overrides and
;; scott-theme--catppuccin-flavor.

(require 'catppuccin-theme nil :no-error)

;; Modus ships inside Emacs at <emacs>/share/emacs/<ver>/etc/themes, which is on
;; custom-theme-load-path but NOT on load-path — so `load-theme' finds the
;; themes while `require' cannot find modus-themes.el, where the palette-override
;; variable is defined. Extend load-path so the overrides below actually apply.
(add-to-list 'load-path (expand-file-name "themes/" data-directory))

(defconst scott-theme--state-file "~/.config/dotfiles/active-theme")
(defconst scott-theme--themes-dir "~/dotfiles/themes")
(defconst scott-theme--default "catppuccin-mocha")

;; Last-resort bg-main/fg-main pairs, used only when a theme's own
;; colors.toml can't be read (see scott-theme--modus-overrides below). These
;; happen to match lib/themes.nix's base/text for the same two themes today,
;; but that agreement is no longer load-bearing: the normal path reads
;; base/text straight from colors.toml, so a fifth theme needs no entry here.
(defconst scott-theme--modus-overrides-fallback
  '(("high-contrast-dark"  . ((bg-main "#0a0a0a") (fg-main "#e8e8e8")))
    ("high-contrast-light" . ((bg-main "#f2f2f2") (fg-main "#111111")))))

(defun scott-theme--read (path)
  "Return the trimmed contents of PATH, or nil if unreadable."
  (when (file-readable-p path)
    (string-trim (with-temp-buffer (insert-file-contents path) (buffer-string)))))

(defun scott-theme--read-palette-value (name key)
  "Return the KEY value from themes/NAME/colors.toml's [palette] section.
Returns nil if the directory, the file, the [palette] section, or KEY within
it is missing — this is deliberately defensive rather than signalling, since
it feeds scott/theme-set, which must never error out to its caller.

This is a narrow regexp over one TOML section, not a general parser: Emacs 30
has no built-in TOML reader, and colors.toml's own header says not to
hand-edit it, so the format here is exactly what bin/gen-theme-dir.py emits —
one `key = \"value\"` pair per line inside [palette]."
  (let ((path (expand-file-name (format "%s/colors.toml" name)
                                 scott-theme--themes-dir)))
    (when (file-readable-p path)
      (with-temp-buffer
        (insert-file-contents path)
        (goto-char (point-min))
        (when (re-search-forward "^\\[palette\\]" nil t)
          (let ((section-start (point))
                (section-end (save-excursion
                               (if (re-search-forward "^\\[" nil t)
                                   (match-beginning 0)
                                 (point-max)))))
            (goto-char section-start)
            (when (re-search-forward
                   (format "^%s[ \t]*=[ \t]*\"\\([^\"]*\\)\""
                           (regexp-quote key))
                   section-end t)
              (match-string 1))))))))

(defun scott-theme--modus-overrides (name)
  "Return the Modus bg-main/fg-main override alist for dotfiles theme NAME.
Reads base/text straight out of themes/NAME/colors.toml so a fifth theme
needs no entry anywhere in this file — Modus defaults to 19-21:1
(modus-vivendi is #000/#fff), and the spec deliberately targets ~16:1 to
avoid halation, so an unlisted theme must not silently fall through to
Modus's native contrast. Falls back to `scott-theme--modus-overrides-fallback'
only if colors.toml or one of the two keys can't be read."
  (let ((base (scott-theme--read-palette-value name "base"))
        (text (scott-theme--read-palette-value name "text")))
    (if (and base text)
        `((bg-main ,base) (fg-main ,text))
      (cdr (assoc name scott-theme--modus-overrides-fallback)))))

(defun scott-theme--catppuccin-flavor (name)
  "Return the catppuccin-theme flavor symbol for dotfiles theme NAME.
Reads themes/NAME/variant (\"dark\" -> mocha, \"light\" -> latte) rather than
matching \"latte\" against NAME, which silently mapped any theme whose name
didn't contain \"latte\" — including a future non-latte Catppuccin flavour —
to mocha. Falls back to that old substring match only if variant can't be
read, so behaviour is unchanged when the directory is missing or broken."
  (let ((variant (scott-theme--read
                   (expand-file-name (format "%s/variant" name)
                                      scott-theme--themes-dir))))
    (cond
     ((equal variant "light") 'latte)
     ((equal variant "dark") 'mocha)
     (t (if (string-match-p "latte" name) 'latte 'mocha)))))

(defun scott-theme--active-name ()
  "Name of the active dotfiles theme."
  (or (scott-theme--read scott-theme--state-file) scott-theme--default))

(defun scott-theme--emacs-theme (name)
  "Emacs theme symbol for dotfiles theme NAME."
  (intern (or (scott-theme--read
               (expand-file-name (format "%s/emacs-theme" name)
                                 scott-theme--themes-dir))
              "catppuccin")))

(defconst scott-theme--builtin-fallback 'modus-vivendi
  "Last-resort theme when even catppuccin cannot be loaded.
Modus ships inside Emacs itself (see the load-path comment above), so
unlike catppuccin it needs no external package and is available on every
host that runs this file at all.")

(defun scott-theme--available-p (theme)
  "Non-nil if THEME is one Emacs actually reports it can load."
  (memq theme (custom-available-themes)))

(defun scott-theme--pick-loadable (theme name)
  "Return a theme Emacs can load for dotfiles theme NAME, or nil.
THEME is the symbol themes/NAME/emacs-theme named. If THEME is not on
`custom-available-themes' — a typo, a hand-edit, a half-written file — warn
and fall back to `catppuccin', and if that too is unavailable (it is
`require'd with :no-error above, so it may be absent) fall back to
`scott-theme--builtin-fallback'. Checking availability here, before any
theme is disabled, is what lets `scott/theme-set' avoid leaving the session
themeless."
  (if (scott-theme--available-p theme)
      theme
    (message "scott-theme: %S (from %s) is not an available theme; falling back"
             theme (expand-file-name (format "%s/emacs-theme" name)
                                      scott-theme--themes-dir))
    (cond
     ((scott-theme--available-p 'catppuccin) 'catppuccin)
     ((scott-theme--available-p scott-theme--builtin-fallback)
      scott-theme--builtin-fallback)
     (t
      (message "scott-theme: no fallback theme is available either; leaving current theme in place")
      nil))))

(defun scott/theme-set (name)
  "Switch the running session to dotfiles theme NAME.
Never signals to its caller. This runs early in init.el, ahead of
`scott/modeline-mode' and the EWM window-management commands — an uncaught
error here would abort the rest of init on the host where Emacs is the
desktop, not just leave colours wrong. So: resolve and confirm the theme is
loadable (falling back per `scott-theme--pick-loadable') BEFORE disabling
whatever is currently enabled, then wrap `load-theme' itself in
`condition-case' as belt-and-braces, since a theme can be listed as
available and still error while loading. Returns the theme symbol actually
enabled, or nil if nothing could be loaded at all."
  (interactive "sTheme name: ")
  (let* ((wanted (scott-theme--emacs-theme name))
         (theme (scott-theme--pick-loadable wanted name)))
    (setq modus-themes-common-palette-overrides
          (scott-theme--modus-overrides name))
    (when (eq theme 'catppuccin)
      (setq catppuccin-flavor (scott-theme--catppuccin-flavor name)))
    (when theme
      (condition-case err
          (progn
            (mapc #'disable-theme custom-enabled-themes)
            (load-theme theme :no-confirm)
            (when (eq theme 'catppuccin) (catppuccin-reload))
            theme)
        (error
         (message "scott-theme: load-theme %S failed: %S" theme err)
         nil)))))

(defun scott/theme-init ()
  "Load the theme matching the active dotfiles theme."
  (scott/theme-set (scott-theme--active-name)))

(provide 'scott-theme)
;;; scott-theme.el ends here
