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

(provide 'scott-ewm)
;;; scott-ewm.el ends here
