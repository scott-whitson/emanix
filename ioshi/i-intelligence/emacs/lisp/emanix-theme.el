;;; emanix-theme.el --- dotfiles theme control -*- lexical-binding: t; -*-

;; The active theme is named in ~/.config/dotfiles/active-theme, and each
;; themes/<name>/ directory carries an `emacs-theme' file naming the Emacs
;; theme to load. bin/dot-theme-set calls (emanix/theme-set "<name>") on switch.
;;
;; This used to take a catppuccin flavor ("mocha"/"latte") and derive it with
;; (string-match-p "latte" name), which silently mapped every other theme name
;; to mocha — so a non-catppuccin theme could not be expressed at all. Both the
;; Catppuccin flavour and the Modus bg-main/fg-main overrides below are now
;; derived from themes/<name>/variant and themes/<name>/colors.toml instead of
;; from substrings or a name-keyed table, so a fifth theme needs no code
;; change here — see emanix-theme--modus-overrides and
;; emanix-theme--catppuccin-flavor.

(require 'catppuccin-theme nil :no-error)

;; Modus ships inside Emacs at <emacs>/share/emacs/<ver>/etc/themes, which is on
;; custom-theme-load-path but NOT on load-path — so `load-theme' finds the
;; themes while `require' cannot find modus-themes.el, where the palette-override
;; variable is defined. Extend load-path so the overrides below actually apply.
(add-to-list 'load-path (expand-file-name "themes/" data-directory))

(defgroup emanix nil
  "The emanix distribution."
  :group 'environment)

(defcustom emanix/theme-state-dir "~/.config/dotfiles"
  "Directory holding the runtime theme state markers.
Contains `active-theme' and one `last-<variant>' per variant. A
defcustom rather than a constant because Emacs now WRITES here: the
tests bind it to a temp directory, which a hardcoded path made
impossible without writing into the real state.

The name is stow-era and predates Emacs owning what is inside it.
Renaming it is worth doing and is deliberately not folded into this
change -- see the 2026-09-11 theme-authority-inversion spec."
  :type 'directory
  :group 'emanix)

(defun emanix-theme--state-file ()
  "Path of the active-theme marker."
  (expand-file-name "active-theme" emanix/theme-state-dir))

(defun emanix-theme--last-file (variant)
  "Path of the last-VARIANT marker."
  (expand-file-name (concat "last-" variant) emanix/theme-state-dir))
;; Fallback matters only if the daemon starts before EMANIX_THEMES_DIR is in
;; its environment. The distro generates the theme tree itself now (see
;; lib/theme-tree.nix); this ~/dotfiles hardcode is a stale last resort, not
;; the source of truth.
(defconst emanix-theme--themes-dir
  (or (getenv "EMANIX_THEMES_DIR")
      (expand-file-name "themes" "~/dotfiles")))
(defconst emanix-theme--default "catppuccin-mocha")

;; Last-resort bg-main/fg-main pairs, used only when a theme's own
;; colors.toml can't be read (see emanix-theme--modus-overrides below). These
;; happen to match lib/themes.nix's base/text for the same two themes today,
;; but that agreement is no longer load-bearing: the normal path reads
;; base/text straight from colors.toml, so a fifth theme needs no entry here.
(defconst emanix-theme--modus-overrides-fallback
  '(("high-contrast-dark"  . ((bg-main "#0a0a0a") (fg-main "#e8e8e8")))
    ("high-contrast-light" . ((bg-main "#f2f2f2") (fg-main "#111111")))))

(defun emanix-theme--read (path)
  "Return the trimmed contents of PATH, or nil if unreadable.
`file-readable-p' is necessary but NOT sufficient: it returns t for a
DIRECTORY, and it describes the filesystem as of a moment that has
passed by the time `insert-file-contents' runs. Both cases signal
`file-error', and every caller here already treats nil as \"unreadable\",
so unreadable is what they get."
  (when (file-readable-p path)
    (condition-case nil
        (string-trim (with-temp-buffer (insert-file-contents path) (buffer-string)))
      (error nil))))

(defun emanix-theme--read-palette-value (name key)
  "Return the KEY value from themes/NAME/colors.toml's [palette] section.
Returns nil if the directory, the file, the [palette] section, or KEY within
it is missing — this is deliberately defensive rather than signalling, since
it feeds emanix/theme-set, which must never error out to its caller.

This is a narrow regexp over one TOML section, not a general parser: Emacs 30
has no built-in TOML reader, and colors.toml's own header says not to
hand-edit it, so the format here is exactly what lib/themes.nix's colorsToml
emits — one `key = \"value\"` pair per line inside [palette]."
  (let ((path (expand-file-name (format "%s/colors.toml" name)
                                 emanix-theme--themes-dir)))
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

(defun emanix-theme--modus-overrides (name)
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

Falls back to `emanix-theme--modus-overrides-fallback' if colors.toml or a
required key can't be read -- bg-main/fg-main only, since a partial bar
override would look worse than Modus's coherent default."
  (let* ((v (lambda (k) (emanix-theme--read-palette-value name k)))
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
     (t (cdr (assoc name emanix-theme--modus-overrides-fallback))))))

(defun emanix-theme--catppuccin-flavor (name)
  "Return the catppuccin-theme flavor symbol for dotfiles theme NAME.
Reads themes/NAME/variant (\"dark\" -> mocha, \"light\" -> latte) rather than
matching \"latte\" against NAME, which silently mapped any theme whose name
didn't contain \"latte\" — including a future non-latte Catppuccin flavour —
to mocha. Falls back to that old substring match only if variant can't be
read, so behaviour is unchanged when the directory is missing or broken."
  (let ((variant (emanix-theme--read
                   (expand-file-name (format "%s/variant" name)
                                      emanix-theme--themes-dir))))
    (cond
     ((equal variant "light") 'latte)
     ((equal variant "dark") 'mocha)
     (t (if (string-match-p "latte" name) 'latte 'mocha)))))

(defun emanix-theme--active-name ()
  "Name of the active dotfiles theme."
  (or (emanix-theme--read (emanix-theme--state-file)) emanix-theme--default))

(defun emanix-theme--emacs-theme (name)
  "Emacs theme symbol for dotfiles theme NAME."
  (intern (or (emanix-theme--read
               (expand-file-name (format "%s/emacs-theme" name)
                                 emanix-theme--themes-dir))
              "catppuccin")))

(defconst emanix-theme--zellij-themes-dir
  "~/.local/share/emanix/zellij-themes"
  "Where zellij.nix writes its two ANSI-index theme definitions.
Both are named `emanix' inside the KDL -- zellij selects a theme by
NAME, so switching swaps which definition is visible in theme_dir
rather than editing config.kdl, which lives in the checkout and must
stay clean.")

(defun emanix-theme--parse-gtk-conf (path)
  "Parse PATH, a KEY=VALUE file, into an alist of strings.
The bash this replaces `source'd the file; reading it as data instead
means a theme tree cannot execute anything in this Emacs."
  (when (file-readable-p path)
    (with-temp-buffer
      (insert-file-contents path)
      (let (out)
        (goto-char (point-min))
        (while (re-search-forward "^\\([A-Z_]+\\)=\\(.*\\)$" nil t)
          (push (cons (match-string 1) (string-trim (match-string 2))) out))
        (nreverse out)))))

(defun emanix-theme--link-plan (name dir variant)
  "Return the (SOURCE . TARGET) symlinks for theme NAME in DIR at VARIANT.
Sources that do not exist are dropped, which is `link_if_present' from
the bash this replaces: ghostty renders its palettes only on hosts with
`emanix.ghostty.enable', and zellij's tree exists only where
`emanix.zellij.enable' is set."
  (seq-filter
   (lambda (pair) (file-exists-p (car pair)))
   (list
    (cons (expand-file-name (format "~/.config/ghostty/themes/%s.conf" name))
          (expand-file-name "~/.config/ghostty/theme.conf"))
    (cons (expand-file-name "btop.theme" dir)
          (expand-file-name "~/.config/btop/themes/active.theme"))
    (cons (expand-file-name "swaylock.conf" dir)
          (expand-file-name "~/.config/swaylock/config"))
    (cons (expand-file-name (format "available/emanix-%s.kdl" variant)
                            emanix-theme--zellij-themes-dir)
          (expand-file-name "active/theme.kdl"
                            emanix-theme--zellij-themes-dir)))))

(defun emanix-theme--plan (name)
  "Describe the switch to theme NAME as data, or nil if NAME is unusable.
Writes nothing and touches no application state, so it is safe to call
on a name that came from a shell argument. Returning nil here is what
lets `emanix/theme-set' reject a bad name before disabling the theme
that is currently working.

CANNOT SIGNAL. This is the one step `emanix/theme-set' and
`emanix/theme-init' run OUTSIDE their per-step `condition-case'
wrappers -- it is what produces the plan those wrappers consume -- so a
signal escaping here escapes all the way into init on the host where
Emacs is the compositor. `emanix-theme--parse-gtk-conf' tests
`file-readable-p' and then calls `insert-file-contents', and
`file-readable-p' returns t for a DIRECTORY: a `gtk.conf' that is a
directory signals `file-error', as does a permission change landing
between the two calls. `emanix-theme--read' guards itself the same way,
so this wrapper is the outer one rather than the only one. An unusable
tree must read as an unusable theme NAME, which is exactly nil."
  (condition-case err
      (let* ((dir (expand-file-name name emanix-theme--themes-dir))
             (variant (emanix-theme--read (expand-file-name "variant" dir))))
        (when (and (file-directory-p dir) (member variant '("dark" "light")))
          (list :name name
                :dir dir
                :variant variant
                :emacs-theme (emanix-theme--emacs-theme name)
                :links (emanix-theme--link-plan name dir variant)
                :gtk (emanix-theme--parse-gtk-conf
                      (expand-file-name "gtk.conf" dir)))))
    (error
     (message "emanix-theme: cannot plan %S in %s: %S"
              name emanix-theme--themes-dir err)
     nil)))

(defconst emanix-theme--builtin-fallback 'modus-vivendi
  "Last-resort theme when even catppuccin cannot be loaded.
Modus ships inside Emacs itself (see the load-path comment above), so
unlike catppuccin it needs no external package and is available on every
host that runs this file at all.")

(defun emanix-theme--available-p (theme)
  "Non-nil if THEME is one Emacs actually reports it can load."
  (memq theme (custom-available-themes)))

(defun emanix-theme--pick-loadable (theme name)
  "Return a theme Emacs can load for dotfiles theme NAME, or nil.
THEME is the symbol themes/NAME/emacs-theme named. If THEME is not on
`custom-available-themes' — a typo, a hand-edit, a half-written file — warn
and fall back to `catppuccin', and if that too is unavailable (it is
`require'd with :no-error above, so it may be absent) fall back to
`emanix-theme--builtin-fallback'. Checking availability here, before any
theme is disabled, is what lets `emanix/theme-set' avoid leaving the session
themeless."
  (if (emanix-theme--available-p theme)
      theme
    (message "emanix-theme: %S (from %s) is not an available theme; falling back"
             theme (expand-file-name (format "%s/emacs-theme" name)
                                      emanix-theme--themes-dir))
    (cond
     ((emanix-theme--available-p 'catppuccin) 'catppuccin)
     ((emanix-theme--available-p emanix-theme--builtin-fallback)
      emanix-theme--builtin-fallback)
     (t
      (message "emanix-theme: no fallback theme is available either; leaving current theme in place")
      nil))))

(defun emanix-theme--apply-emacs (plan)
  "Load PLAN's Emacs theme. Return the theme symbol enabled, or nil.
Resolve and confirm the theme is loadable BEFORE disabling whatever is
currently enabled, then wrap `load-theme' itself in `condition-case' as
belt-and-braces, since a theme can be listed as available and still
error while loading. That ordering is what stops a failed switch from
leaving the session themeless.

The whole prelude -- `emanix-theme--pick-loadable' and the
`colors.toml' read behind `emanix-theme--modus-overrides' -- runs
inside the same `condition-case': a `colors.toml' that is a directory,
or a permissions race, would otherwise signal `file-error' straight
out of this function and, on the host where Emacs is the compositor,
cost the rest of init. Every step this function drives must fail into
`nil', never out."
  (condition-case err
      (let* ((name (plist-get plan :name))
             (wanted (plist-get plan :emacs-theme))
             (theme (emanix-theme--pick-loadable wanted name)))
        (setq modus-themes-common-palette-overrides
              (emanix-theme--modus-overrides name))
        (when (eq theme 'catppuccin)
          (setq catppuccin-flavor (emanix-theme--catppuccin-flavor name)))
        (when theme
          (mapc #'disable-theme custom-enabled-themes)
          (load-theme theme :no-confirm)
          (when (eq theme 'catppuccin) (catppuccin-reload))
          theme))
    (error
     (message "emanix-theme: apply-emacs for %S failed: %S" (plist-get plan :name) err)
     nil)))

(defcustom emanix/theme-apply-functions nil
  "Functions run after a theme switch, each called with the plan plist.
The plist carries :name, :dir, :variant, :emacs-theme, :links and :gtk.

This is the CONSUMER extension point, and the distribution registers
none of its own. Side effects for programs emanix does not install --
the author's pi agent and Claude Code settings, for instance -- belong
here rather than in `emanix/theme-set', which must stay ignorant of
anything `scott.*' declares.

A function that signals is reported and skipped; the switch continues."
  :type '(repeat function)
  :group 'emanix)

(defun emanix-theme--run-hook (plan)
  "Run `emanix/theme-apply-functions' on PLAN. Return failure descriptions."
  (let (failures)
    (dolist (f emanix/theme-apply-functions)
      (condition-case err
          (funcall f plan)
        (error (push (format "%s: %S" f err) failures))))
    (nreverse failures)))

(defun emanix/theme-set (name)
  "Switch the running session to theme NAME, everywhere.
Never signals to its caller. This runs from init on the host where
Emacs is the desktop, so an uncaught error here would abort the rest of
init rather than merely leave colours wrong -- and it now drives six
side-effects rather than one, so each is wrapped individually and
reports instead of raising.

Returns the Emacs theme symbol actually enabled, or nil if the name is
unknown or nothing could be loaded. Side-effect failures do NOT change
the return value: the colours are the part you can see, and a
read-only btop directory must not look like a failed theme switch."
  (interactive
   (list (completing-read
          "Theme: "
          (and (file-directory-p emanix-theme--themes-dir)
               (directory-files emanix-theme--themes-dir nil "\\`[^.]"))
          nil t)))
  (if-let* ((plan (emanix-theme--plan name)))
      (let* ((theme (emanix-theme--apply-emacs plan))
             (failures (append (emanix-theme--write-state plan)
                               (emanix-theme--apply-links plan)
                               (emanix-theme--apply-gtk plan)
                               (emanix-theme--run-hook plan)
                               (emanix-theme--reload-apps))))
        (when failures
          (message "emanix-theme: %s applied with %d failure(s): %s"
                   name (length failures) (string-join failures "; ")))
        theme)
    (message "emanix-theme: no such theme %S in %s"
             name emanix-theme--themes-dir)
    nil))

(defun emanix-theme--seed-name ()
  "The theme name a machine with no usable state converges on.

The host's build-time `emanix.theme', delivered as $EMANIX_THEME, and
`emanix-theme--default' only when that is unset or empty.

The Nix value IS reachable here, contrary to what this function's
predecessor asserted. The spec's rejection of `EMANIX_GUI' was about
the EWM Emacs not inheriting a SHELL variable, because it is started
outside the login shell -- but ewm.nix launches it FROM
`environment.loginShellInit' and now exports both $EMANIX_THEME and
$EMANIX_THEMES_DIR through `environment.sessionVariables', which NixOS
writes to /etc/set-environment and /etc/zshenv sources before
/etc/zprofile runs the launch snippet. The non-EWM daemon gets the same
pair from zsh.nix's `systemd.user.sessionVariables'.

Falling back to `emanix-theme--default' rather than requiring the
variable keeps a host that has not rebuilt since this landed working
exactly as it did before."
  (let ((configured (getenv "EMANIX_THEME")))
    (if (and configured (not (equal configured ""))) configured
      emanix-theme--default)))

(defun emanix-theme--colours-only-plan (name)
  "A plan carrying just what `emanix-theme--apply-emacs' reads: NAME and a theme.

Not a real plan -- no :dir, :links or :gtk, so it must never be handed
to the side-effect steps. It exists for the one case `emanix/theme-init'
must survive and `emanix-theme--plan' cannot describe: no theme tree at
all. `emanix-theme--apply-emacs' then resolves the symbol through
`emanix-theme--pick-loadable', which falls back catppuccin ->
`emanix-theme--builtin-fallback', so a session with an unreadable tree
still gets colours."
  (list :name name
        :emacs-theme (condition-case nil
                         (emanix-theme--emacs-theme name)
                       (error 'catppuccin))))

(defun emanix/theme-init ()
  "Apply the active theme at startup. Never signals, and never no-ops.

Converges the whole machine when `active-theme' is missing or names a
theme that is no longer in the tree, seeding from
`emanix-theme--seed-name'. That is the fresh-install case, and it is why
ghostty's `seedGhosttyTheme' activation hook could be deleted: seeding
one application was a narrower version of this.

Otherwise loads only the Emacs theme. Re-running the full switch on
every start would be an idempotent re-base in the spirit of
`nixos-rebuild switch', but it rewrites ~/.claude/settings.json at each
login, and Claude Code rewrites that file at runtime -- repeating the
write when nothing changed only widens that race.

ALWAYS ends with a theme enabled if Emacs can load one at all. The
tree is reached through $EMANIX_THEMES_DIR, and an environment
regression that empties or misdirects that variable makes every plan
nil -- which would otherwise leave the session with NO theme loaded,
the failure mode measured on the EWM host on 2026-09-11 when the
variable never reached the login shell. A themeless desktop is a worse
outcome than the wrong colours, so the last resort is a plan that
describes colours and nothing else."
  (let* ((recorded (emanix-theme--read (emanix-theme--state-file)))
         (plan (and recorded (emanix-theme--plan recorded))))
    (if plan
        (emanix-theme--apply-emacs plan)
      ;; No marker, or one naming a theme no longer in the tree. Converge on
      ;; the seed -- NOT on the recorded name, which is the dead one.
      (let ((seed (emanix-theme--seed-name)))
        (or (emanix/theme-set seed)
            ;; The tree could not describe the seed either, so there is
            ;; nothing to converge. Load colours and stop; writing state for
            ;; a theme whose directory we cannot read would only record a
            ;; second dead marker.
            (emanix-theme--apply-emacs
             (emanix-theme--colours-only-plan seed)))))))

(defun emanix-theme--themes-of-variant (variant)
  "Names of every theme in the tree whose variant is VARIANT."
  (when (file-directory-p emanix-theme--themes-dir)
    (seq-filter
     (lambda (name)
       (equal variant (emanix-theme--read
                       (expand-file-name (format "%s/variant" name)
                                         emanix-theme--themes-dir))))
     (directory-files emanix-theme--themes-dir nil "\\`[^.]"))))

;;;###autoload
(defun emanix/theme-toggle ()
  "Flip between the last-used dark theme and the last-used light one.
Prefers the `last-<variant>' marker, then any theme of the opposite
variant. A marker naming a theme that no longer exists is ignored
rather than trusted -- deleting a theme directory is how themes are
retired here, so a stale marker is expected, not exceptional."
  (interactive)
  (let* ((active (emanix-theme--active-name))
         (plan (emanix-theme--plan active))
         (variant (or (plist-get plan :variant) "dark"))
         (other (if (equal variant "dark") "light" "dark"))
         (marked (emanix-theme--read (emanix-theme--last-file other)))
         (target (if (and marked (emanix-theme--plan marked))
                     marked
                   (car (emanix-theme--themes-of-variant other)))))
    (if target
        (emanix/theme-set target)
      (message "emanix-theme: no %s theme in %s"
               other emanix-theme--themes-dir)
      nil)))

(defun emanix/theme-palette-color (key)
  "Return the active dotfiles theme's palette colour for KEY, or nil.
KEY is a name from themes/<name>/colors.toml's [palette] section, e.g.
\"base\", \"surface0\", \"text\". This is the public read path into the
palette: other modules (emanix-prose.el) need theme-derived colours and
must not grow a second TOML reader. Returns nil rather than signalling
when the theme directory or the key is missing, matching
`emanix-theme--read-palette-value'."
  (emanix-theme--read-palette-value (emanix-theme--active-name) key))

(defmacro emanix-theme--collecting (failures &rest body)
  "Run BODY, pushing a description of any error onto FAILURES.
Every apply step reports rather than signals: `emanix/theme-set' runs
during init on the host where Emacs is the compositor, so an error
escaping one side-effect must not cost the rest of the switch."
  (declare (indent 1))
  `(condition-case err
       (progn ,@body)
     (error (push (format "%S" err) ,failures))))

(defun emanix-theme--apply-links (plan)
  "Create every symlink in PLAN. Return a list of failure descriptions."
  (let (failures)
    (pcase-dolist (`(,source . ,target) (plist-get plan :links))
      (emanix-theme--collecting failures
        (make-directory (file-name-directory target) t)
        (make-symbolic-link source target :ok-if-already-exists)))
    (nreverse failures)))

(defun emanix-theme--apply-gtk (plan)
  "Apply PLAN's gtk.conf values through gsettings.
Runs unconditionally: Emacs cannot see `emanix.gui', a session variable
would not reach the EWM Emacs (started by a system unit, so it does not
inherit the shell environment), and `display-graphic-p' is nil on a
frameless daemon. A headless host simply fails here and has no GTK to
theme anyway."
  (let ((keys '(("COLOR_SCHEME" . "color-scheme")
                ("GTK_THEME"    . "gtk-theme")))
        failures)
    (pcase-dolist (`(,var . ,key) keys)
      (when-let* ((value (alist-get var (plist-get plan :gtk) nil nil #'equal)))
        (emanix-theme--collecting failures
          (call-process "gsettings" nil nil nil
                        "set" "org.gnome.desktop.interface" key value))))
    (nreverse failures)))

(defun emanix-theme--write-state (plan)
  "Record PLAN as the active theme. Return a list of failure descriptions."
  (let (failures)
    (emanix-theme--collecting failures
      (make-directory emanix/theme-state-dir t)
      (let ((name (plist-get plan :name)))
        (write-region (concat name "\n") nil (emanix-theme--state-file))
        (write-region (concat name "\n") nil
                      (emanix-theme--last-file (plist-get plan :variant)))))
    (nreverse failures)))

(defun emanix-theme--reload-apps ()
  "Tell running apps to re-read their config. Return failure descriptions.
Only ghostty needs this: btop, zellij and swaylock read their theme
when they next start, and GTK apps follow gsettings live."
  (let (failures)
    (emanix-theme--collecting failures
      (call-process "pkill" nil nil nil "-SIGUSR2" "ghostty"))
    (nreverse failures)))

(provide 'emanix-theme)
;;; emanix-theme.el ends here
