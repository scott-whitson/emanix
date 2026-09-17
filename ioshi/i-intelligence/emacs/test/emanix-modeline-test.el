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

(ert-deftest emanix-modeline-repaints-every-tick-even-when-unchanged ()
  "Every tick marks the tab bar for repaint, unchanged status or not.

The status is not the only item in this tab bar: `emanix/ewm-tab-bar-slots'
renders every frame's label and highlights the focused one, so a change in
frame A has to repaint frame B, and only a global force-update does that.
Nothing else reliably forces it -- not EWM's close handler, not
compositor-driven focus, not a client retitling itself -- so gating this on
the status string left the slot list stale for up to a minute.

It is not worth gating.  `force-mode-line-update' only sets the update
flags; redisplay paints nothing when no glyph moved."
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
      (should (= repaints 3)))))

(ert-deftest emanix-modeline-wifi-segment-is-a-cache-read ()
  "The wifi segment reads a variable and runs no subprocess.

`nmcli' is a fork, an exec and a wait on NetworkManager.  On the render
timer, in the process that is also the compositor, that is the desktop's
own latency several times a minute -- the same hazard that made the
volume poll asynchronous."
  (let ((emanix/modeline--wifi-status "wifi✗"))
    (cl-letf (((symbol-function 'shell-command-to-string)
               (lambda (&rest _) (error "render shelled out")))
              ((symbol-function 'call-process)
               (lambda (&rest _) (error "render shelled out"))))
      (should (equal (emanix/modeline--wifi) "wifi✗")))))

(ert-deftest emanix-modeline-wifi-parses-nmcli-output ()
  "Connected wifi renders nothing; anything else renders the marker.
The parse runs at process exit rather than in the filter, because a
filter can be handed half a line and this reply has several."
  (should (null (emanix/modeline--wifi-parse
                 "wifi:connected\nethernet:connected\n")))
  (should (equal "wifi✗" (emanix/modeline--wifi-parse
                          "wifi:disconnected\nethernet:connected\n")))
  (should (equal "wifi✗" (emanix/modeline--wifi-parse
                          "wifi:unavailable\n")))
  ;; Split across filter calls in the worst place: the parse only ever
  ;; sees the whole thing, so a torn line is not its problem -- but an
  ;; empty or truncated reply must not read as connected.
  (should (equal "wifi✗" (emanix/modeline--wifi-parse "wifi:conn")))
  (should (equal "wifi✗" (emanix/modeline--wifi-parse ""))))

(ert-deftest emanix-modeline-sysfs-globs-are-probed-once ()
  "The gpu and battery sysfs paths are found once, not on every tick.
`file-expand-wildcards' is a directory scan, and neither the graphics
card nor the battery moves during a session."
  (let ((emanix/modeline--gpu-file 'unset)
        (emanix/modeline--battery-dir 'unset)
        (scans 0))
    (cl-letf (((symbol-function 'file-expand-wildcards)
               (lambda (&rest _) (setq scans (1+ scans)) nil)))
      (emanix/modeline--gpu)
      (emanix/modeline--gpu)
      (emanix/modeline--gpu)
      (should (= scans 1))
      (setq scans 0)
      (emanix/modeline--battery)
      (emanix/modeline--battery)
      (should (= scans 1)))))

(ert-deftest emanix-modeline-wifi-device-is-probed-once ()
  "The wireless interface is looked up once, not scanned every tick."
  (let ((emanix/modeline--wifi-dev 'unset)
        (scans 0))
    (cl-letf (((symbol-function 'directory-files)
               (lambda (&rest _) (setq scans (1+ scans)) nil)))
      (emanix/modeline--wifi-device)
      (emanix/modeline--wifi-device)
      (emanix/modeline--wifi-device)
      (should (= scans 1)))))

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
