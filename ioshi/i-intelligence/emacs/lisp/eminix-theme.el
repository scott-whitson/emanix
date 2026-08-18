;;; eminix-theme.el --- dotfiles theme control -*- lexical-binding: t; -*-

;; The active theme is named in ~/.config/dotfiles/active-theme, and each
;; themes/<name>/ directory carries an `emacs-theme' file naming the Emacs
;; theme to load. bin/dot-theme-set calls (eminix/theme-set "<name>") on switch.
;;
;; This used to take a catppuccin flavor ("mocha"/"latte") and derive it with
;; (string-match-p "latte" name), which silently mapped every other theme name
;; to mocha — so a non-catppuccin theme could not be expressed at all. Both the
;; Catppuccin flavour and the Modus bg-main/fg-main overrides below are now
;; derived from themes/<name>/variant and themes/<name>/colors.toml instead of
;; from substrings or a name-keyed table, so a fifth theme needs no code
;; change here — see eminix-theme--modus-overrides and
;; eminix-theme--catppuccin-flavor.

(require 'catppuccin-theme nil :no-error)

;; Modus ships inside Emacs at <emacs>/share/emacs/<ver>/etc/themes, which is on
;; custom-theme-load-path but NOT on load-path — so `load-theme' finds the
;; themes while `require' cannot find modus-themes.el, where the palette-override
;; variable is defined. Extend load-path so the overrides below actually apply.
(add-to-list 'load-path (expand-file-name "themes/" data-directory))

(defconst eminix-theme--state-file "~/.config/dotfiles/active-theme")
;; Fallback matters only if the daemon starts before EMINIX_THEMES_DIR is in
;; its environment. The distro generates the theme tree itself now (see
;; lib/theme-tree.nix); this ~/dotfiles hardcode is a stale last resort, not
;; the source of truth.
(defconst eminix-theme--themes-dir
  (or (getenv "EMINIX_THEMES_DIR")
      (expand-file-name "themes" "~/dotfiles")))
(defconst eminix-theme--default "catppuccin-mocha")

;; Last-resort bg-main/fg-main pairs, used only when a theme's own
;; colors.toml can't be read (see eminix-theme--modus-overrides below). These
;; happen to match lib/themes.nix's base/text for the same two themes today,
;; but that agreement is no longer load-bearing: the normal path reads
;; base/text straight from colors.toml, so a fifth theme needs no entry here.
(defconst eminix-theme--modus-overrides-fallback
  '(("high-contrast-dark"  . ((bg-main "#0a0a0a") (fg-main "#e8e8e8")))
    ("high-contrast-light" . ((bg-main "#f2f2f2") (fg-main "#111111")))))

(defun eminix-theme--read (path)
  "Return the trimmed contents of PATH, or nil if unreadable."
  (when (file-readable-p path)
    (string-trim (with-temp-buffer (insert-file-contents path) (buffer-string)))))

(defun eminix-theme--read-palette-value (name key)
  "Return the KEY value from themes/NAME/colors.toml's [palette] section.
Returns nil if the directory, the file, the [palette] section, or KEY within
it is missing — this is deliberately defensive rather than signalling, since
it feeds eminix/theme-set, which must never error out to its caller.

This is a narrow regexp over one TOML section, not a general parser: Emacs 30
has no built-in TOML reader, and colors.toml's own header says not to
hand-edit it, so the format here is exactly what lib/themes.nix's colorsToml
emits — one `key = \"value\"` pair per line inside [palette]."
  (let ((path (expand-file-name (format "%s/colors.toml" name)
                                 eminix-theme--themes-dir)))
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

(defun eminix-theme--modus-overrides (name)
  "Return the Modus palette override alist for dotfiles theme NAME.

Every value is read out of themes/NAME/colors.toml, so a new theme needs no
entry anywhere in this file. Two groups:

bg-main/fg-main, because Modus defaults to 19-21:1 (modus-vivendi is
#000/#fff) and the spec deliberately targets ~16:1 to avoid halation. An
unlisted theme must not silently fall through to Modus's native contrast.

The tab-bar and mode-line colours, because Modus's own defaults are a mid
grey drawn from its internal palette, not from ours -- #313131 for the tab
bar, #545454 for inactive tabs and #505050 for the mode line, with a #959595
box on top. Against a #0a0a0a buffer those read as foreign grey slabs, and
the mode line measured 8.06:1 where the rest of the theme is 16:1. The
\"subtle raised\" treatment chosen 2026-08-10 puts them one step off the
buffer (surface0) with a surface1 hairline instead: near-black rather than
grey, and 13.45:1 on dark / 12.99:1 on light.

Falls back to `eminix-theme--modus-overrides-fallback' if colors.toml or a
required key can't be read -- bg-main/fg-main only, since a partial bar
override would look worse than Modus's coherent default."
  (let* ((v (lambda (k) (eminix-theme--read-palette-value name k)))
         (base (funcall v "base"))
         (text (funcall v "text"))
         (surface0 (funcall v "surface0"))
         (surface1 (funcall v "surface1"))
         (subtext0 (funcall v "subtext0")))
    (cond
     ((and base text surface0 surface1 subtext0)
      `((bg-main ,base)
        (fg-main ,text)
        ;; Top bar (the EWM tab-bar). Current tab lifts one further step so it
        ;; is distinguishable without a colour accent.
        (bg-tab-bar ,surface0)
        (bg-tab-current ,surface1)
        (bg-tab-other ,surface0)
        ;; Bottom bar. border-* replaces Modus's #959595 box; using text
        ;; color makes the focused window's border clearly visible.
        (bg-mode-line-active ,surface0)
        (fg-mode-line-active ,text)
        (border-mode-line-active ,text)
        (bg-mode-line-inactive ,surface0)
        (fg-mode-line-inactive ,subtext0)
        (border-mode-line-inactive ,surface0)))
     ((and base text) `((bg-main ,base) (fg-main ,text)))
     (t (cdr (assoc name eminix-theme--modus-overrides-fallback))))))

(defun eminix-theme--catppuccin-flavor (name)
  "Return the catppuccin-theme flavor symbol for dotfiles theme NAME.
Reads themes/NAME/variant (\"dark\" -> mocha, \"light\" -> latte) rather than
matching \"latte\" against NAME, which silently mapped any theme whose name
didn't contain \"latte\" — including a future non-latte Catppuccin flavour —
to mocha. Falls back to that old substring match only if variant can't be
read, so behaviour is unchanged when the directory is missing or broken."
  (let ((variant (eminix-theme--read
                   (expand-file-name (format "%s/variant" name)
                                      eminix-theme--themes-dir))))
    (cond
     ((equal variant "light") 'latte)
     ((equal variant "dark") 'mocha)
     (t (if (string-match-p "latte" name) 'latte 'mocha)))))

(defun eminix-theme--active-name ()
  "Name of the active dotfiles theme."
  (or (eminix-theme--read eminix-theme--state-file) eminix-theme--default))

(defun eminix-theme--emacs-theme (name)
  "Emacs theme symbol for dotfiles theme NAME."
  (intern (or (eminix-theme--read
               (expand-file-name (format "%s/emacs-theme" name)
                                 eminix-theme--themes-dir))
              "catppuccin")))

(defconst eminix-theme--builtin-fallback 'modus-vivendi
  "Last-resort theme when even catppuccin cannot be loaded.
Modus ships inside Emacs itself (see the load-path comment above), so
unlike catppuccin it needs no external package and is available on every
host that runs this file at all.")

(defun eminix-theme--available-p (theme)
  "Non-nil if THEME is one Emacs actually reports it can load."
  (memq theme (custom-available-themes)))

(defun eminix-theme--pick-loadable (theme name)
  "Return a theme Emacs can load for dotfiles theme NAME, or nil.
THEME is the symbol themes/NAME/emacs-theme named. If THEME is not on
`custom-available-themes' — a typo, a hand-edit, a half-written file — warn
and fall back to `catppuccin', and if that too is unavailable (it is
`require'd with :no-error above, so it may be absent) fall back to
`eminix-theme--builtin-fallback'. Checking availability here, before any
theme is disabled, is what lets `eminix/theme-set' avoid leaving the session
themeless."
  (if (eminix-theme--available-p theme)
      theme
    (message "eminix-theme: %S (from %s) is not an available theme; falling back"
             theme (expand-file-name (format "%s/emacs-theme" name)
                                      eminix-theme--themes-dir))
    (cond
     ((eminix-theme--available-p 'catppuccin) 'catppuccin)
     ((eminix-theme--available-p eminix-theme--builtin-fallback)
      eminix-theme--builtin-fallback)
     (t
      (message "eminix-theme: no fallback theme is available either; leaving current theme in place")
      nil))))

(defun eminix/theme-set (name)
  "Switch the running session to dotfiles theme NAME.
Never signals to its caller. This runs early in init.el, ahead of
`eminix/modeline-mode' and the EWM window-management commands — an uncaught
error here would abort the rest of init on the host where Emacs is the
desktop, not just leave colours wrong. So: resolve and confirm the theme is
loadable (falling back per `eminix-theme--pick-loadable') BEFORE disabling
whatever is currently enabled, then wrap `load-theme' itself in
`condition-case' as belt-and-braces, since a theme can be listed as
available and still error while loading. Returns the theme symbol actually
enabled, or nil if nothing could be loaded at all."
  (interactive "sTheme name: ")
  (let* ((wanted (eminix-theme--emacs-theme name))
         (theme (eminix-theme--pick-loadable wanted name)))
    (setq modus-themes-common-palette-overrides
          (eminix-theme--modus-overrides name))
    (when (eq theme 'catppuccin)
      (setq catppuccin-flavor (eminix-theme--catppuccin-flavor name)))
    (when theme
      (condition-case err
          (progn
            (mapc #'disable-theme custom-enabled-themes)
            (load-theme theme :no-confirm)
            (when (eq theme 'catppuccin) (catppuccin-reload))
            theme)
        (error
         (message "eminix-theme: load-theme %S failed: %S" theme err)
         nil)))))

(defun eminix/theme-init ()
  "Load the theme matching the active dotfiles theme."
  (eminix/theme-set (eminix-theme--active-name)))

(defun eminix/theme-palette-color (key)
  "Return the active dotfiles theme's palette colour for KEY, or nil.
KEY is a name from themes/<name>/colors.toml's [palette] section, e.g.
\"base\", \"surface0\", \"text\". This is the public read path into the
palette: other modules (eminix-prose.el) need theme-derived colours and
must not grow a second TOML reader. Returns nil rather than signalling
when the theme directory or the key is missing, matching
`eminix-theme--read-palette-value'."
  (eminix-theme--read-palette-value (eminix-theme--active-name) key))

(provide 'eminix-theme)
;;; eminix-theme.el ends here
