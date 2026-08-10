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
;; Keep this under ~30 lines. It is unguarded by construction: there is no
;; outer file to catch a mistake made here.

(defvar scott/init-error nil
  "The error that aborted `config.el', or nil on a healthy boot.
Check it with: emacsclient -e \\='scott/init-error\\='.
When non-nil, `fallback.el' ran and the tab bar says so.")

(condition-case err
    ;; NOERROR nil on purpose: config.el MUST signal so the handler runs.
    (load (expand-file-name "config.el" user-emacs-directory) nil :nomessage)
  (error
   (setq scott/init-error err)
   (message "scott/init: config.el FAILED (%S) — loading fallback.el" err)
   ;; NOERROR t here: if fallback.el is missing too, do not cascade.
   (load (expand-file-name "fallback.el" user-emacs-directory)
         :noerror :nomessage)))

;;; init.el ends here
