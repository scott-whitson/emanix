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
;; CALL time, guarded by `ewm--module-mode' (or fboundp, in the tab-bar
;; segment). Adding a require here would break startup on every host.

(declare-function ewm--focused-frame "ewm")
(declare-function ewm--strip-frames "ewm")
(declare-function ewm-frame-new "ewm")
(declare-function ewm-workspace-rename "ewm")
(defvar ewm--module-mode)

(defun emanix/ewm-launch-firefox ()
  "Launch Firefox in the current EWM session."
  (interactive)
  ;; The old third `or' branch, $EMANIX_BIN_DIR/firefox, could never help:
  ;; that shim is exactly what already failed the identical PATH lookup, the
  ;; variable is unset on a host built from the distribution alone, and Home
  ;; Manager installs firefox into the user profile, which is on PATH.
  (let ((firefox (or (executable-find "firefox")
                     (executable-find "firefox-esr"))))
    (unless firefox
      (user-error "firefox not found on PATH (tried firefox, then firefox-esr)"))
    (start-process-shell-command "firefox" nil firefox)))

;; Keyed slots: each frame carries its slot NUMBER in the `emanix/ewm-slot'
;; frame parameter, so `s-3' owns one specific frame rather than "the 3rd
;; frame in the strip". Selecting slot 3 never conjures 1 and 2.
;;
;; No auto-close: under EWM a new frame inherits the current buffer (a
;; terminal surface, not *scratch*), and focus is async/compositor-owned, so
;; "reap the blank slot I just left" has no reliable trigger. Slots close
;; explicitly via `emanix/ewm-close-slot' (s-q); apps that exit are cleaned up
;; by EWM's own close handler.

(defun emanix/ewm--adopt-slots (output)
  "Tag each untagged frame on OUTPUT with the number the tab bar shows.
The bar numbers an untagged frame by its strip position. Adopting those
numbers on first use keeps `s-N' selecting the tab the user can see
instead of creating a duplicate, including after a session restart when
no frame carries a slot parameter yet."
  (let ((pos 0))
    (dolist (frame (ewm--strip-frames output))
      (setq pos (1+ pos))
      (unless (frame-parameter frame 'emanix/ewm-slot)
        (set-frame-parameter frame 'emanix/ewm-slot pos)))))

(defun emanix/ewm--slot-frame (slot output)
  "Return the frame keyed to SLOT on OUTPUT, or nil.
Search `frame-list', not the strip: EWM now asks the compositor for the
strip, so a frame created this instant is absent from it until the map
round-trip. Its `ewm-output' parameter is set synchronously by
`make-frame' and is enough to scope the search."
  (seq-find (lambda (f)
              (and (eql slot (frame-parameter f 'emanix/ewm-slot))
                   (equal output (frame-parameter f 'ewm-output))))
            (frame-list)))

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
  (delete-frame (ewm--focused-frame))
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
  (let* ((frame (ewm--focused-frame))
         (output (frame-parameter frame 'ewm-output)))
    (unless output
      (user-error "Current frame has no EWM output"))
    (emanix/ewm--adopt-slots output)
    (if-let* ((existing (emanix/ewm--slot-frame slot output)))
        (emanix/ewm--goto existing)
      ;; `ewm-frame-new' returns the frame it made. Do not diff the strip for
      ;; it: the compositor has not reported the new frame yet, so the
      ;; difference is empty and the frame would never get its slot number.
      ;; EWM focuses it on map via `ewm-focus-on-create'.
      (let ((new (ewm-frame-new)))
        (unless new
          (user-error "Slot %d creation failed" slot))
        (set-frame-parameter new 'emanix/ewm-slot slot)
        (force-mode-line-update t)))))

(defun emanix/ewm-rename-workspace (name)
  "Rename the current EWM workspace/slot to NAME (shown in the tab bar).
An empty NAME clears the custom label, falling back to the frame name."
  (interactive "sWorkspace name: ")
  (unless (bound-and-true-p ewm--module-mode)
    (user-error "EWM is not active"))
  (let ((frame (ewm--focused-frame)))
    (ewm-workspace-rename name frame)
    (set-frame-parameter frame 'ewm-workspace-name
                         (unless (string-empty-p name) name))
    (force-mode-line-update t)))

;; The slot key block, shared by config.el and fallback.el so the two cannot
;; drift: fallback.el existed as a hand-copied subset of config.el's bindings.
(defun emanix/ewm-bind-slot-keys (map)
  "Bind the EWM slot keys on MAP (normally `ewm-mode-map').
s-1 .. s-9 and s-0 (slot 10) select a slot, creating it once; s-r renames the
current slot; s-q closes it (mirrors Hyprland's `$mod, Q, killactive'); s-w
launches Firefox into it; s-<return> opens a Ghostty terminal."
  (dotimes (i 9)
    (let ((slot (1+ i)))
      (define-key map (kbd (format "s-%d" slot))
        (lambda ()
          (interactive)
          (emanix/ewm-select-slot slot)))))
  (define-key map (kbd "s-0")
    (lambda ()
      (interactive)
      (emanix/ewm-select-slot 10)))
  (define-key map (kbd "s-r") #'emanix/ewm-rename-workspace)
  (define-key map (kbd "s-q") #'emanix/ewm-close-slot)
  (define-key map (kbd "s-w") #'emanix/ewm-launch-firefox)
  (define-key map (kbd "s-<return>")
    (lambda ()
      (interactive)
      (start-process "ghostty" nil "ghostty"))))

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
