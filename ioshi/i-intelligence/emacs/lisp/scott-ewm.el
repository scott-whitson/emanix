;;; scott-ewm.el --- EWM session glue -*- lexical-binding: t; -*-

;; Loaded from init.el only when emacs IS the compositor ((featurep 'ewm)).
;; Session helpers that must run as emacs subprocesses so they inherit
;; WAYLAND_DISPLAY and end with the session.

(defun scott/lock-screen ()
  "Lock the screen with swaylock."
  (interactive)
  (if (executable-find "swaylock")
      (make-process :name "swaylock"
                    :command '("swaylock" "-f")
                    :noquery t)
    (user-error "swaylock is not installed")))

(defvar scott/ewm--swayidle nil
  "The swayidle process, if running.")

(defun scott/ewm-start-swayidle ()
  "Start swayidle: lock on suspend (lid close) and on loginctl lock-session.
Idempotent; safe to call from init on every start."
  (when (and (executable-find "swayidle")
             (not (process-live-p scott/ewm--swayidle)))
    (setq scott/ewm--swayidle
          (make-process :name "swayidle"
                        :command '("swayidle" "-w"
                                   "before-sleep" "swaylock -f"
                                   "lock" "swaylock -f")
                        :noquery t))))

(scott/ewm-start-swayidle)

;; Input devices — libinput defaults tap-to-click OFF; setopt (not setq) runs
;; the compositor's input refresh. Touchpad only: keyboard xkb options
;; (CapsLock->Control) come from XKB_DEFAULT_OPTIONS in ewm.nix, never here —
;; a (keyboard :xkb-options ...) entry makes the setter error on the live
;; keymap rebuild. See `ewm-input-config' doc for the full option set.
;;
;; CRITICAL — why this is guarded and lives at the END of the file: at
;; compositor start the touchpad has not enumerated yet, and the
;; `ewm-input-config' setter THROWS on the absent device. This file is pulled
;; in with `require', so an unguarded throw aborts the entire load — the retry
;; ladder never gets scheduled and `provide' never runs, leaving
;; (fboundp 'scott/ewm-start-swayidle) => nil and tap silently unconfigured
;; (only a manual re-setopt after login fixed it). So: (1) everything above is
;; defined and the file is safe to `provide' before we touch input; (2) every
;; apply is wrapped in `with-demoted-errors' so a not-yet-ready device is a
;; no-op, not a fatal abort; (3) we build a FRESH list each call so the setter
;; can never eq-skip an unchanged value. An early attempt on the ladder is
;; harmless; a later one lands once the device appears.
(defun scott/ewm-apply-touchpad ()
  "Enable tap-to-click + natural scroll; ignore a not-yet-ready touchpad."
  (with-demoted-errors "eminix touchpad: %S"
    (setopt ewm-input-config (list (list 'touchpad :tap t :natural-scroll t)))))

(scott/ewm-apply-touchpad)
(dolist (secs '("2 sec" "4 sec" "6 sec" "10 sec" "15 sec"))
  (run-at-time secs nil #'scott/ewm-apply-touchpad))

(provide 'scott-ewm)
;;; scott-ewm.el ends here
