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
