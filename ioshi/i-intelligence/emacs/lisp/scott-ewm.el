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

;; Output layout — the external HDMI monitor sits ABOVE the laptop panel, so
;; the cursor crosses from the top edge of eDP-1 to the bottom edge of the
;; external. Both panels are 1920 wide and share x=0, so their full width is a
;; single seam (laptop 1920x1200 at y=0; external 1920x1080 stacked at
;; y=-1080). Names are Make-Model-Serial strings (per `ewm-list-outputs'), not
;; eDP-1/HDMI-A-1, so the mapping survives connector renumbering across replugs.
;;
;; Two mechanisms, for the same enumeration reason as the touchpad above:
;;   (1) `ewm-output-config' is stored in the compositor and re-applied every
;;       time an output connects (boot AND hotplug) — this is what makes
;;       plugging the monitor in later Just Work.
;;   (2) an imperative `ewm-configure-output' pass positions any output already
;;       connected at load time. Guarded, so an unplugged monitor is a no-op.
(defconst scott/ewm-laptop-output "Lenovo Group Limited 0x403D Unknown"
  "Make-Model-Serial name of the built-in laptop panel (eDP-1).")
(defconst scott/ewm-external-output "Philips Consumer Electronics Company PHL 271E1 0x0000098C"
  "Make-Model-Serial name of the external HDMI monitor (HDMI-A-1).")

(setopt ewm-output-config
        (list (list scott/ewm-laptop-output
                    :width 1920 :height 1200 :scale 1 :x 0 :y 0)
              (list scott/ewm-external-output
                    :width 1920 :height 1080 :scale 1 :x 0 :y -1080)))

(defun scott/ewm-apply-output-layout ()
  "Position any currently-connected output per the stacked layout.
No-op (demoted) for an output that is not connected right now."
  (with-demoted-errors "eminix output layout: %S"
    (ewm-configure-output scott/ewm-laptop-output :x 0 :y 0))
  (with-demoted-errors "eminix output layout: %S"
    (ewm-configure-output scott/ewm-external-output :x 0 :y -1080)))

(scott/ewm-apply-output-layout)

(provide 'scott-ewm)
;;; scott-ewm.el ends here
