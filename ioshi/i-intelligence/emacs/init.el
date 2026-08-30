;;; init.el --- loader -*- lexical-binding: t; -*-

;; This file must never break, so it is deliberately tiny and rarely edited.
;; The real configuration is config.el; a failure there is caught here.
;;
;; Why a separate file rather than a condition-case inside the config: a signal
;; raised inside a `load'ed file propagates to its CALLER, so this catches both
;; failure modes seen on 2026-08-10 —
;;
;;   read-time  an unbalanced paren, "End of file during parsing". Nothing
;;              inside config.el could ever catch this, because none of it runs.
;;   load-time  a bare (require 'gdocs) that signalled because
;;              ~/.config/emacs/elpa is not on load-path.
;;
;; Both aborted every remaining form, and on rafik — where Emacs is the Wayland
;; compositor — that meant no top bar, no s-d and no window navigation. EWM
;; itself survived both times, because it is started from --eval on the command
;; line, which Emacs processes after init.
;;
;; This file is small by design, not by a specific line count — every line
;; here is unguarded, so keep it to what a loader strictly needs. It is
;; unguarded by construction: there is no outer file to catch a mistake
;; made here.

(defvar emanix/init-error nil
  "The error that aborted `config.el', or nil on a healthy boot.
Check it with: emacsclient -e \\='emanix/init-error\\='.
When non-nil, `fallback.el' ran and the tab bar says so.")

(defvar emanix/init-backtrace nil
  "Backtrace captured at the moment `config.el' signalled, or nil.
`condition-case' unwinds the stack before its handler runs, so
`--debug-init' shows nothing once a handler exists to catch the error —
`signal-hook-function' below runs earlier, in the original dynamic
context, before that unwind, so this still captures something useful.
Populated only when debugging was requested (`debug-on-error', or
`init-file-debug' — what `--debug-init' actually sets in this Emacs;
see `startup.el''s `load-user-init-file'): the hook below fires on
EVERY signal, even the many harmless ones org-roam's db sync raises and
catches internally on a healthy boot, so it must stay off otherwise.
Check it with: emacsclient -e \\='(insert emanix/init-backtrace)\\='.")

;; Resolve config.el/fallback.el next to init.el's OWN true location, not
;; `user-emacs-directory'. liveElisp makes init.el an out-of-store symlink
;; into the checkout, deployed the moment a host runs `git pull' — but
;; config.el and fallback.el reach `user-emacs-directory' only via
;; `xdg.configFile', which needs a rebuild. A pulled-not-yet-rebuilt host
;; would otherwise have the new loader and neither file it loads. Resolving
;; against init.el's truename finds both, because they always ship together
;; in the checkout. `load-file-name' is nil when this is evaluated rather
;; than loaded (e.g. from a REPL), hence the fallback to
;; `user-emacs-directory'.
;;
;; `ignore-errors' matters as much as the fallback value it guards: this
;; form runs BEFORE the `condition-case' below exists, so — together with
;; the `let' binding right after it — it is the one place in this file an
;; uncaught signal is fatal by construction. `file-truename' is not
;; guaranteed not to signal (a symlink cycle does it, verified); letting
;; that propagate here would abort init.el fifteen lines before its own
;; guard, loading neither config.el nor fallback.el — the exact
;; total-desktop-loss this split exists to prevent, reintroduced one form
;; earlier than the fix for it.
(defvar emanix/init-dir
  (or (and load-file-name
           (ignore-errors
             (file-name-directory (file-truename load-file-name))))
      user-emacs-directory)
  "Directory to load `config.el' and `fallback.el' from.
Init.el's own truename when loaded normally; `user-emacs-directory' when
`load-file-name' is nil (evaluated rather than loaded) or when resolving
the truename itself signals (e.g. a symlink cycle).")

(let ((signal-hook-function
       ;; Gated on debugging having been requested: this fires on EVERY
       ;; signal, not just the one that eventually escapes to the handler
       ;; below, so leave it unbound (nil, same as the default) otherwise.
       ;; Rebinds itself to nil first: a fault in `backtrace' itself must
       ;; not recurse back into this hook.
       (and (or debug-on-error init-file-debug)
            (lambda (&rest _)
              (let ((signal-hook-function nil))
                (setq emanix/init-backtrace (with-output-to-string (backtrace))))))))
  (condition-case err
      ;; NOERROR nil on purpose: config.el MUST signal so the handler runs.
      (load (expand-file-name "config.el" emanix/init-dir) nil :nomessage)
    (error
     (setq emanix/init-error err)
     (message "emanix/init: config.el FAILED (%S) — loading fallback.el" err)
     ;; NOERROR t here: if fallback.el is missing too, do not cascade.
     (load (expand-file-name "fallback.el" emanix/init-dir)
           :noerror :nomessage))))

;;; init.el ends here
