;;; scott-ewm.el --- EWM session glue -*- lexical-binding: t; -*-

;; Loaded from init.el only when emacs IS the compositor ((featurep 'ewm)).
;; Session helpers that must run as emacs subprocesses so they inherit
;; WAYLAND_DISPLAY and end with the session.

;; Input devices — libinput defaults to tap-to-click OFF; setopt (not
;; setq) so the compositor refresh runs. See `ewm-input-config' doc for
;; the full option set (natural-scroll, accel, xkb, per-device overrides).
;; Touchpad only. Keyboard xkb options (CapsLock->Control) are set via
;; XKB_DEFAULT_OPTIONS in ewm.nix, NOT here: putting :xkb-options in
;; ewm-input-config makes the setter error on the live keymap rebuild and
;; abort before the touchpad settings apply — which silently breaks
;; tap-to-click. Do not re-add a (keyboard ...) entry with :xkb-options.
(setopt ewm-input-config '((touchpad :tap t :natural-scroll t)))

;; On a cold boot the touchpad enumerates several seconds after the compositor
;; is up — later than a single deferral catches — so the load-time setopt above
;; no-ops and tap/natural-scroll don't take (confirmed on the T14: a manual
;; re-`setopt` well after login fixes it). Re-apply on a short ladder so one
;; attempt lands after the device appears; setopt re-runs the setter each time.
(dolist (secs '("2 sec" "4 sec" "6 sec" "10 sec" "15 sec"))
  (run-at-time secs nil (lambda () (setopt ewm-input-config ewm-input-config))))

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

(provide 'scott-ewm)
;;; scott-ewm.el ends here
