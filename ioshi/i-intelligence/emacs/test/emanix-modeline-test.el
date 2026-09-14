;;; emanix-modeline-test.el --- ERT tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'emanix-modeline)

;; `emanix/modeline-extra-segments' is the consumer extension point: a
;; consuming flake's personal.el (which is loaded long after this file) needs a
;; way to add a segment without advising the private render function.

(defmacro emanix-modeline-test--rendering (&rest body)
  "Run BODY with every system-reading segment stubbed to a fixed value.
The render path reads /proc and /sys, and the nix build sandbox this
runs in has neither -- but the composition under test does not depend
on any of it, so pin them and assert the whole string exactly."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'emanix/modeline--volume-segment) (lambda () "vol"))
             ((symbol-function 'emanix/modeline--wifi)           (lambda () nil))
             ((symbol-function 'emanix/modeline--cpu)            (lambda () 0))
             ((symbol-function 'emanix/modeline--ram)            (lambda () 0))
             ((symbol-function 'emanix/modeline--gpu)            (lambda () nil))
             ((symbol-function 'emanix/modeline--clock)          (lambda () "CLOCK"))
             ((symbol-function 'emanix/modeline--battery)        (lambda () nil)))
     ,@body))

(ert-deftest emanix-modeline-renders-extra-segments ()
  "A function on `emanix/modeline-extra-segments' contributes its string."
  (emanix-modeline-test--rendering
    (let ((emanix/modeline-extra-segments (list (lambda () "ib✓"))))
      (emanix/modeline--render)
      (should (equal emanix/modeline-status "vol   ib✓   CLOCK")))))

(ert-deftest emanix-modeline-drops-nil-extra-segments ()
  "A segment function returning nil contributes nothing, like wifi/battery.
No stray separator is left where it would have been."
  (emanix-modeline-test--rendering
    (let ((emanix/modeline-extra-segments
           (list (lambda () nil) (lambda () "shown"))))
      (emanix/modeline--render)
      (should (equal emanix/modeline-status "vol   shown   CLOCK")))))

(ert-deftest emanix-modeline-extra-segments-precede-the-clock ()
  "Extras join the system-state group; clock and battery stay the right anchor."
  (emanix-modeline-test--rendering
    (let ((emanix/modeline-extra-segments (list (lambda () "MARKER"))))
      (emanix/modeline--render)
      (should (< (string-match-p "MARKER" emanix/modeline-status)
                 (string-match-p "CLOCK" emanix/modeline-status))))))

(ert-deftest emanix-modeline-survives-a-signalling-extra-segment ()
  "A consumer segment that signals is dropped, not propagated.
Under EWM this Emacs is the compositor: an error escaping the render
timer takes the status bar and the redraw down with it."
  (emanix-modeline-test--rendering
    (let ((emanix/modeline-extra-segments
           (list (lambda () (error "boom")) (lambda () "survivor"))))
      (emanix/modeline--render)
      (should (equal emanix/modeline-status "vol   survivor   CLOCK")))))

(ert-deftest emanix-modeline-extra-segments-defaults-empty ()
  "The distribution ships no extras of its own."
  (should (null (default-value 'emanix/modeline-extra-segments))))

;; The render runs on a timer, several times a minute, whether or not the
;; composed string moved. Under EWM this Emacs is the compositor, so anything
;; the render does to the frame is paid by every managed client -- a Ghostty
;; window is resized by a repaint it had no part in. The next three tests fix
;; the cost of a tick.

(ert-deftest emanix-modeline-repaints-only-when-the-status-changes ()
  "A tick composing the string it composed last time repaints nothing.
The timer fires every `emanix/modeline-interval' seconds and the string
is unchanged for most of them, so an unchanged tick has to be free."
  (emanix-modeline-test--rendering
    (let ((emanix/modeline-status "")
          (emanix/modeline-extra-segments nil)
          (repaints 0))
      (cl-letf (((symbol-function 'force-mode-line-update)
                 (lambda (&optional _all) (setq repaints (1+ repaints)))))
        (emanix/modeline--render)
        (emanix/modeline--render)
        (emanix/modeline--render))
      (should (equal emanix/modeline-status "vol   CLOCK"))
      (should (= repaints 1)))))

(ert-deftest emanix-modeline-never-redraws-the-whole-display ()
  "The render never calls `redraw-display'.
That clears and repaints every frame -- nine of them on a running EWM
session -- and is seen as the whole screen flashing on each tick.
`force-mode-line-update' already repaints the tab-bar the status is in."
  (emanix-modeline-test--rendering
    (let ((emanix/modeline-status "")
          (emanix/modeline-extra-segments nil)
          (redraws 0))
      (cl-letf (((symbol-function 'redraw-display)
                 (lambda (&rest _) (setq redraws (1+ redraws)))))
        (emanix/modeline--render))
      (should (= redraws 0)))))

(ert-deftest emanix-modeline-never-resets-the-tab-bar-line-count ()
  "The render never calls `tab-bar--update-tab-bar-lines'.
Assigning `tab-bar-lines' takes Emacs' frame-resize path even when the
line count is unchanged, and so fires `window-size-change-functions'.
EWM refreshes its layout from that hook and reconfigures every surface
it manages, which is why the terminals resize on a timer.  Nothing the
status bar renders can change the tab-bar's line count anyway."
  (emanix-modeline-test--rendering
    (let ((emanix/modeline-status "")
          (emanix/modeline-extra-segments nil)
          (updates 0))
      (cl-letf (((symbol-function 'tab-bar--update-tab-bar-lines)
                 (lambda (&rest _) (setq updates (1+ updates)))))
        (emanix/modeline--render))
      (should (= updates 0)))))
