;;; emanix-ewm.el --- EWM session glue -*- lexical-binding: t; -*-

;; Loaded from init.el only when emacs IS the compositor ((featurep 'ewm)).
;; Session helpers that must run as emacs subprocesses so they inherit
;; WAYLAND_DISPLAY and end with the session.

(defun emanix/lock-screen ()
  "Lock the screen with swaylock."
  (interactive)
  (if (executable-find "swaylock")
      (make-process :name "swaylock"
                    :command '("swaylock" "-f")
                    :noquery t)
    (user-error "swaylock is not installed")))

(defvar emanix/ewm--swayidle nil
  "The swayidle process, if running.")

(defun emanix/ewm-start-swayidle ()
  "Start swayidle: lock on suspend (lid close) and on loginctl lock-session.
Idempotent; safe to call from init on every start."
  (when (and (executable-find "swayidle")
             (not (process-live-p emanix/ewm--swayidle)))
    (with-demoted-errors "emanix swayidle: %S"
      (setq emanix/ewm--swayidle
            (make-process :name "swayidle"
                          :command '("swayidle" "-w"
                                     "before-sleep" "swaylock -f"
                                     "lock" "swaylock -f")
                          :noquery t)))))

;; Retry ladder, exactly as the touchpad and output appliers below use, and for
;; the same reason: at load time the compositor is not up yet. `swayidle -w'
;; connects to WAYLAND_DISPLAY and EXITS when it cannot — "Unable to connect to
;; the compositor" — so the single load-time call started a process that died
;; at once, leaving NO lock on lid-close and none on `loginctl lock-session'.
;;
;; Measured on rafik 2026-09-02, after a rebuild and reboot: swayidle absent
;; from the process table entirely, while starting it by hand against the live
;; compositor worked first time (status=run). The `process-live-p' guard makes
;; every later rung a no-op once one has taken, and a rung that fires before
;; the compositor is simply another no-op.
(emanix/ewm-start-swayidle)
(dolist (secs '("2 sec" "4 sec" "6 sec" "10 sec" "15 sec"))
  (run-at-time secs nil #'emanix/ewm-start-swayidle))

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
;; (fboundp 'emanix/ewm-start-swayidle) => nil and tap silently unconfigured
;; (only a manual re-setopt after login fixed it). So: (1) everything above is
;; defined and the file is safe to `provide' before we touch input; (2) every
;; apply is wrapped in `with-demoted-errors' so a not-yet-ready device is a
;; no-op, not a fatal abort; (3) we build a FRESH list each call so the setter
;; can never eq-skip an unchanged value. An early attempt on the ladder is
;; harmless; a later one lands once the device appears.
(defun emanix/ewm-apply-touchpad ()
  "Enable tap-to-click + natural scroll; ignore a not-yet-ready touchpad."
  (with-demoted-errors "emanix touchpad: %S"
    (setopt ewm-input-config (list (list 'touchpad :tap t :natural-scroll t)))))

(emanix/ewm-apply-touchpad)
(dolist (secs '("2 sec" "4 sec" "6 sec" "10 sec" "15 sec"))
  (run-at-time secs nil #'emanix/ewm-apply-touchpad))

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
(defconst emanix/ewm-laptop-output "Lenovo Group Limited 0x403D Unknown"
  "Make-Model-Serial name of the built-in laptop panel (eDP-1).")
(defconst emanix/ewm-external-output "Philips Consumer Electronics Company PHL 271E1 0x0000098C"
  "Make-Model-Serial name of the external HDMI monitor (HDMI-A-1).")

(setopt ewm-output-config
        (list (list emanix/ewm-laptop-output
                    :width 1920 :height 1200 :scale 1 :x 0 :y 0)
              (list emanix/ewm-external-output
                    :width 1920 :height 1080 :scale 1 :x 0 :y -1080)))

(defun emanix/ewm-apply-output-layout ()
  "Position any currently-connected output per the stacked layout.
No-op (demoted) for an output that is not connected right now."
  (with-demoted-errors "emanix output layout: %S"
    (ewm-configure-output emanix/ewm-laptop-output :x 0 :y 0))
  (with-demoted-errors "emanix output layout: %S"
    (ewm-configure-output emanix/ewm-external-output :x 0 :y -1080)))

(emanix/ewm-apply-output-layout)

(provide 'emanix-ewm)

;;; --- XWayland helper ---

(defun emanix/kill-xwayland ()
  "Kill all Xwayland processes and remove the X11 socket.
Useful when the black Xwayland buffer lingers after closing Steam."
  (interactive)
  (let ((procs (process-list)))
    (dolist (p procs)
      (when (string= (process-name p) "Xwayland")
        (delete-process p))))
  ;; Also kill via shell in case it's not an Emacs subprocess
  (call-process "pkill" nil nil nil "Xwayland")
  (delete-file "/tmp/.X11-unix/X0" nil)
  (message "Xwayland killed"))

(defun emanix/ewm-restart ()
  "Save every file buffer, then exit so the tty1 login loop relaunches EWM.

No reboot is needed: ewm.nix launches EWM from the tty1 login shell, which
then waits on this daemon and lets getty's autologin log straight back in
when it exits.  Killing this daemon IS the restart.

Why not `save-buffers-kill-emacs': that prompts once per modified buffer and
again per buffer with a live process, which on a daemon that has been up for
days is a long interactive walk.  This saves file buffers unattended and then
calls `kill-emacs', which runs `kill-emacs-hook' but asks nothing.

The trade-off, stated plainly: live processes (vterm shells, running agents)
are terminated without a prompt.  Anything unsaved that is NOT a file buffer
is lost.  That is the intended bargain for a deliberate restart.

Recovery: the login hook writes a marker to
$XDG_RUNTIME_DIR/ewm-flap (falling back to /run/user/$(id -u)) when either
the daemon never starts within its poll window, or it starts but dies
within 15s.  Either way the next login drops to a plain shell instead of
looping.  The marker's contents say which of the two happened — read it
with `cat', then remove the file and log out to re-arm."
  (interactive)
  (when (yes-or-no-p "Restart EWM — save file buffers and end the session? ")
    (save-some-buffers t)
    (kill-emacs)))

;;; emanix-ewm.el ends here
