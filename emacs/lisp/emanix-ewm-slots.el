;;; emanix-ewm-slots.el --- EWM slot navigation and the tab-bar slot list -*- lexical-binding: t; -*-

;; Extracted from init.el on 2026-08-10. These commands ARE the window
;; management on rafik, where Emacs is the Wayland compositor, and they used to
;; sit below every package `require' in init.el — so any package that failed to
;; load took them with it. They live here so both the normal path (config.el)
;; and the fallback (fallback.el) can require them instead of one duplicating
;; the other.
;;
;; DELIBERATELY NO (require 'ewm). Emacs is started
;;   --fg-daemon --eval (require 'ewm) --eval (ewm-start-module)
;; and Emacs processes --eval arguments AFTER loading init, so `ewm' does not
;; exist while this file loads. The ewm--focused-frame / ewm-frame-new /
;; ewm--strip-frames / ewm-workspace-rename references below are resolved at
;; CALL time, guarded by fboundp / bound-and-true-p. Adding a require here
;; would break startup on every host.

(defun emanix/ewm-launch-firefox ()
  "Launch Firefox in the current EWM session."
  (interactive)
  (start-process-shell-command
   "firefox" nil
   (or (executable-find "firefox")
       (executable-find "firefox-esr")
       (expand-file-name "firefox" (or (getenv "EMANIX_BIN_DIR") "")))))

;; Keyed slots: each frame carries its slot NUMBER in the `emanix/ewm-slot'
;; frame parameter, so `s-3' owns one specific frame rather than "the 3rd
;; frame in the strip". Selecting slot 3 never conjures 1 and 2.
;;
;; No auto-close: under EWM a new frame inherits the current buffer (a
;; terminal surface, not *scratch*), and focus is async/compositor-owned, so
;; "reap the blank slot I just left" has no reliable trigger. Slots close
;; explicitly via `emanix/ewm-close-slot' (s-w); apps that exit are cleaned up
;; by EWM's own close handler.

(defun emanix/ewm--slot-frame (slot output)
  "Return the frame keyed to SLOT on OUTPUT, or nil."
  (seq-find (lambda (f) (eql slot (frame-parameter f 'emanix/ewm-slot)))
            (ewm--strip-frames output)))

(defun emanix/ewm--goto (target)
  "Focus TARGET and refresh the bar.
The force-update defeats tab-bar's per-frame cache so the highlight
tracks the switch."
  (select-frame-set-input-focus target)
  (force-mode-line-update t))

(defun emanix/ewm-close-slot ()
  "Close the current EWM slot/frame.
EWM's delete-frame handling refocuses a same-output neighbour and drops
the frame from the strip; its advice refuses to close the last frame."
  (interactive)
  (unless (bound-and-true-p ewm--module-mode)
    (user-error "EWM is not active"))
  (delete-frame (if (fboundp 'ewm--focused-frame)
                    (ewm--focused-frame)
                  (selected-frame)))
  (force-mode-line-update t))

(defun emanix/ewm-select-slot (slot)
  "Focus the frame keyed to SLOT on the current output, creating it once.
Slots are identified by number, not strip position, so selecting slot 3
never creates 1 and 2."
  (interactive "nSlot: ")
  (unless (and (integerp slot) (>= slot 1))
    (user-error "Slot must be a positive integer"))
  (unless (bound-and-true-p ewm--module-mode)
    (user-error "EWM is not active"))
  (let* ((frame (if (fboundp 'ewm--focused-frame)
                    (ewm--focused-frame)
                  (selected-frame)))
         (output (frame-parameter frame 'ewm-output)))
    (unless output
      (user-error "Current frame has no EWM output"))
    ;; Adopt the leftmost frame as slot 1 (home) the first time, so it shows
    ;; in the bar as a numbered slot.
    (unless (emanix/ewm--slot-frame 1 output)
      (when-let* ((home (car (ewm--strip-frames output))))
        (set-frame-parameter home 'emanix/ewm-slot 1)))
    (if-let* ((existing (emanix/ewm--slot-frame slot output)))
        (emanix/ewm--goto existing)
      (let ((before (ewm--strip-frames output)))
        (ewm-frame-new)
        (let ((new (car (seq-difference (ewm--strip-frames output) before))))
          (unless new
            (user-error "Slot %d creation failed" slot))
          (set-frame-parameter new 'emanix/ewm-slot slot)
          (emanix/ewm--goto new))))))

(defun emanix/ewm-rename-workspace (name)
  "Rename the current EWM workspace/slot to NAME (shown in the tab bar).
An empty NAME clears the custom label, falling back to the frame name."
  (interactive "sWorkspace name: ")
  (unless (bound-and-true-p ewm--module-mode)
    (user-error "EWM is not active"))
  (let ((frame (if (fboundp 'ewm--focused-frame)
                   (ewm--focused-frame)
                 (selected-frame))))
    (ewm-workspace-rename name frame)
    (set-frame-parameter frame 'ewm-workspace-name
                         (unless (string-empty-p name) name))
    (force-mode-line-update t)))

(defun emanix/ewm--slot-label (frame)
  "Short display label for FRAME's slot.
Prefers the tracked workspace name, else the frame name, decorations
stripped and truncated for the bar."
  (let ((n (or (frame-parameter frame 'ewm-workspace-name)
               (frame-parameter frame 'name)
               "")))
    (setq n (replace-regexp-in-string "\\`\\*ewm:[ \t]*" "" n))
    (setq n (replace-regexp-in-string "\\*\\'" "" n))
    (setq n (string-trim n))
    (if (string-empty-p n) "?"
      (truncate-string-to-width n 10 nil nil "…"))))

(defun emanix/ewm-tab-bar-slots ()
  "Tab-bar segment listing EWM slots on the focused output, sorted by slot
number, current one highlighted, each clickable to focus it.
Returns nil off EWM, so it is a no-op in a plain Emacs frame."
  (when (fboundp 'ewm--focused-frame)
    (let* ((focused (ewm--focused-frame))
           (output (frame-parameter focused 'ewm-output))
           (frames (and output (ewm--strip-frames output)))
           (pos 0)
           pairs)
      ;; Pair each frame with its slot number (its `emanix/ewm-slot' tag, or
      ;; its strip position for any not-yet-adopted frame), then sort so the
      ;; bar reads 1, 2, 3 … regardless of physical strip order.
      (dolist (f frames)
        (setq pos (1+ pos))
        (push (cons (or (frame-parameter f 'emanix/ewm-slot) pos) f) pairs))
      (setq pairs (sort (nreverse pairs) (lambda (a b) (< (car a) (car b)))))
      (mapcar
       (lambda (pair)
         (let* ((num (car pair))
                (f (cdr pair))
                (cur (eq f focused))
                (label (format " %d:%s " num (emanix/ewm--slot-label f)))
                (face (if cur 'tab-bar-tab 'tab-bar-tab-inactive)))
           (list (intern (format "ewm-slot-%d" num))
                 'menu-item
                 (propertize label 'face face)
                 (lambda () (interactive) (emanix/ewm--goto f)))))
       pairs))))

(provide 'emanix-ewm-slots)
;;; emanix-ewm-slots.el ends here
