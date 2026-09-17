;;; emanix-modeline.el --- system status for the EWM tab-bar panel -*- lexical-binding: t; -*-

(require 'subr-x)

;; EWM has no status bar; these segments replace the old desktop status bar:
;; volume/mute, wifi, cpu%, ram%, gpu%, clock, battery.
;; Everything reads sysfs/procfs except volume, which shells out to
;; wpctl — cheap enough at the update interval.
;;
;; The status is rendered in the frame-global TAB-BAR (see
;; `emanix/tab-bar-status', wired into `tab-bar-format' in init.el), not the
;; per-window mode-line — so it shows once, not once per buffer/split.

(defgroup emanix/modeline nil
  "System status segments for the modeline."
  :group 'mode-line)

(defcustom emanix/modeline-interval 3
  "Seconds between status refreshes."
  :type 'integer)

(defcustom emanix/modeline-threshold 25
  "Minimum percent before cpu/ram/gpu segments are shown."
  :type 'integer)

(defcustom emanix/modeline-battery-hide-capacity 99
  "Hide the battery segment at or above this capacity when not charging."
  :type 'integer)

(defcustom emanix/modeline-extra-segments nil
  "Functions contributing extra status segments.
Each is called with no arguments and returns a string to display or
nil to show nothing, following the wifi/battery convention of staying
silent when there is nothing to say.

This is the CONSUMER extension point. The distribution ships none of
its own: a consuming flake's personal.el registers here instead of
advising `emanix/modeline--render', which is private and moves.
Segments render after gpu and before the clock, so clock and battery
remain the fixed right-hand anchor."
  :type '(repeat function))

(defvar emanix/modeline-status ""
  "Cached status string displayed via `global-mode-string'.")
(put 'emanix/modeline-status 'risky-local-variable t)

(defvar emanix/modeline--timer nil)
(defvar emanix/modeline--gpu-file 'unset
  "Cached amdgpu busy-percent sysfs path, nil if absent, `unset' if unprobed.
`file-expand-wildcards' is a directory scan, and the render runs on a
timer; the card does not move for the life of the session.")

(defvar emanix/modeline--battery-dir 'unset
  "Cached BAT* sysfs directory, nil if absent, `unset' if unprobed.
Same reason as `emanix/modeline--gpu-file'.")

(defvar emanix/modeline--wifi-dev 'unset
  "Cached wireless interface name, nil if none, `unset' if unprobed.")

(defvar emanix/modeline--wifi-status nil
  "Rendered wireless segment, or nil.  Written by `emanix/modeline--poll-wifi'.")

(defvar emanix/modeline--wifi-output ""
  "Accumulated stdout of the running `nmcli', parsed when it exits.")

(defvar emanix/modeline--prev-cpu nil
  "Cons of (idle . total) jiffies from the previous sample.")

(defun emanix/modeline--cpu ()
  "CPU busy percent since the last sample (0 on the first)."
  (let* ((fields (with-temp-buffer
                   (insert-file-contents "/proc/stat")
                   (mapcar #'string-to-number
                           (cdr (split-string
                                 (buffer-substring (point-min) (line-end-position)))))))
         ;; idle = idle + iowait
         (idle (+ (nth 3 fields) (nth 4 fields)))
         (total (apply #'+ fields))
         (prev emanix/modeline--prev-cpu))
    (setq emanix/modeline--prev-cpu (cons idle total))
    (if (and prev (> (- total (cdr prev)) 0))
        (round (* 100 (- 1.0 (/ (float (- idle (car prev)))
                                (- total (cdr prev))))))
      0)))

(defun emanix/modeline--ram ()
  "RAM used percent, by MemAvailable."
  (with-temp-buffer
    (insert-file-contents "/proc/meminfo")
    (let ((total (and (re-search-forward "MemTotal:\\s-+\\([0-9]+\\)" nil t)
                      (string-to-number (match-string 1))))
          (avail (and (re-search-forward "MemAvailable:\\s-+\\([0-9]+\\)" nil t)
                      (string-to-number (match-string 1)))))
      (when (and total avail (> total 0))
        (round (* 100 (- 1.0 (/ (float avail) total))))))))

(defun emanix/modeline--gpu ()
  "GPU busy percent from amdgpu sysfs, or nil."
  (when (eq emanix/modeline--gpu-file 'unset)
    (setq emanix/modeline--gpu-file
          (car (file-expand-wildcards
                "/sys/class/drm/card*/device/gpu_busy_percent"))))
  (when-let* ((f emanix/modeline--gpu-file))
    (string-trim (with-temp-buffer (insert-file-contents f) (buffer-string)))))

(defun emanix/modeline--clock ()
  "Day, weekday, and 12-hour time; a trailing period marks PM.
The period is the PM indicator, so it appears only in the afternoon
\(24-hour hour >= 12: noon is PM, midnight is AM)."
  (concat (format-time-string "%e %a %I:%M")
          (if (>= (string-to-number (format-time-string "%H")) 12) "." "")))

(defun emanix/modeline--battery-icon (capacity)
  "Return a battery icon for CAPACITY."
  (cond
   ((>= capacity 96) "󰁹")
   ((>= capacity 86) "󰂂")
   ((>= capacity 76) "󰂁")
   ((>= capacity 66) "󰂀")
   ((>= capacity 56) "󰁿")
   ((>= capacity 46) "󰁾")
   ((>= capacity 36) "󰁽")
   ((>= capacity 26) "󰁼")
   ((>= capacity 16) "󰁻")
   ((>= capacity 6)  "󰁺")
   (t                "󰂎")))

(defun emanix/modeline--battery ()
  "Battery status, or nil when the machine is full and idle."
  (when (eq emanix/modeline--battery-dir 'unset)
    (setq emanix/modeline--battery-dir
          (car (file-expand-wildcards "/sys/class/power_supply/BAT*"))))
  (when-let* ((bat emanix/modeline--battery-dir))
    (let* ((status (string-trim (with-temp-buffer
                                  (insert-file-contents (expand-file-name "status" bat))
                                  (buffer-string))))
           (capacity (string-to-number
                      (string-trim (with-temp-buffer
                                     (insert-file-contents (expand-file-name "capacity" bat))
                                     (buffer-string))))))
      (when (or (member status '("Charging" "Discharging"))
                (< capacity emanix/modeline-battery-hide-capacity))
        (format "%s %s%%"
                (if (string= status "Charging")
                    "󰂄"
                  (emanix/modeline--battery-icon capacity))
                capacity)))))

(defvar emanix/modeline--volume nil
  "Cached volume string from the last wpctl poll.")

(defun emanix/modeline--poll-volume ()
  "Refresh `emanix/modeline--volume' asynchronously.
Never blocks: in EWM this emacs IS the compositor, and a wedged
pipewire behind a synchronous call would hiccup the whole desktop.
The displayed value lags one update interval."
  (when (and (executable-find "wpctl")
             (not (get-process "emanix-modeline-wpctl")))
    (make-process
     :name "emanix-modeline-wpctl"
     :command '("wpctl" "get-volume" "@DEFAULT_AUDIO_SINK@")
     :noquery t
     :filter (lambda (_proc out)
               (setq emanix/modeline--volume
                     (when (string-match "Volume: \\([0-9.]+\\)\\(.*\\[MUTED\\]\\)?" out)
                       (if (match-string 2 out)
                           "mute"
                         (number-to-string
                          (round (* 100 (string-to-number
                                         (match-string 1 out))))))))
               (emanix/modeline--render)))))

(defun emanix/modeline--volume-segment ()
  "Return the rendered volume segment, if any."
  (when-let* ((v emanix/modeline--volume))
    (if (string= v "mute")
        "󰖁"
      (let* ((pct (string-to-number v))
             (icon (cond ((< pct 34) "󰕿")
                         ((< pct 67) "󰖀")
                         (t "󰕾"))))
        (format "%s %s%%" icon pct)))))

(defun emanix/modeline--extra-segments ()
  "Call each of `emanix/modeline-extra-segments', dropping nil results.
A segment that signals is dropped too, not propagated: under EWM this
Emacs is the compositor, so a consumer's broken segment must not take
the status bar -- or the redraw that follows it -- down with it."
  (mapcar (lambda (f)
            (condition-case err
                (funcall f)
              (error
               (message "emanix/modeline: segment %S failed: %S" f err)
               nil)))
          emanix/modeline-extra-segments))

(defun emanix/modeline--render ()
  "Compose the EWM status bar and mark the tab bar for repaint.

The repaint is unconditional, and has to be.  The status is not the only
item in this tab bar: `emanix/ewm-tab-bar-slots' renders every frame's
label and highlights the focused one, so a change in frame A must repaint
frame B's bar, and only a global force-update does that.  Only the s-N,
close and rename commands force it themselves -- not EWM's own close
handler, not compositor-driven focus, not a client retitling itself.  An
earlier version of this function gated the force-update on the status
string having changed, which left the slot list stale for up to a minute
on an idle desktop, because every other segment here is either
event-driven, threshold-gated or minute-granular.

Gating it bought nothing anyway.  `force-mode-line-update' only sets the
update flags; redisplay compares glyphs and paints nothing when nothing
moved.  The calls that actually cost something were the two removed
below, not this one.

`force-mode-line-update' is the whole repaint.  It is enough: the status
is a `tab-bar-format' item, and the tab bar is recomposed with the mode
lines.  Neither `redraw-display' nor `tab-bar--update-tab-bar-lines'
belongs here -- the first clears and repaints every frame, and the second
assigns `tab-bar-lines', which takes the frame-resize path even when the
line count is unchanged and so fires `window-size-change-functions'.  On
an EWM session both are paid by every managed client: a flash, and a
resize, on a timer."
  (let ((status
         (mapconcat
          #'identity
          (delq nil
                (append
                 (list (emanix/modeline--volume-segment)
                       (when-let* ((w (emanix/modeline--wifi))) w)
                       (let ((cpu (emanix/modeline--cpu)))
                         (when (> cpu emanix/modeline-threshold)
                           (format "cpu %d%%" cpu)))
                       (when-let* ((r (emanix/modeline--ram)))
                         (when (> r emanix/modeline-threshold)
                           (format "ram %d%%" r)))
                       (when-let* ((g (emanix/modeline--gpu)))
                         (let ((gpu (string-to-number g)))
                           (when (> gpu emanix/modeline-threshold)
                             (format "gpu %s%%" g)))))
                 (emanix/modeline--extra-segments)
                 (list (emanix/modeline--clock)
                       (emanix/modeline--battery))))
          "   ")))
    (setq emanix/modeline-status status)
    (force-mode-line-update t)))

(defun emanix/modeline--wifi-device ()
  "Return the wireless interface name, or nil.  Probed once."
  (when (eq emanix/modeline--wifi-dev 'unset)
    (setq emanix/modeline--wifi-dev
          (seq-find
           (lambda (d) (file-exists-p (format "/sys/class/net/%s/wireless" d)))
           (directory-files "/sys/class/net" nil "^[^.]"))))
  emanix/modeline--wifi-dev)

(defun emanix/modeline--wifi-parse (out)
  "Return the wifi segment for `nmcli' device-status output OUT.
Its own function so the parse is testable without spawning anything:
inlined in the sentinel, the only way to cover it was to restate it."
  (let* ((lines (split-string out "\n" t))
         (line (seq-find (lambda (s) (string-prefix-p "wifi:" s)) lines))
         (state (and line (cadr (split-string line ":" t)))))
    (unless (equal state "connected") "wifi✗")))

(defun emanix/modeline--poll-wifi ()
  "Refresh `emanix/modeline--wifi-status', without blocking the render.

Same reason `emanix/modeline--poll-volume' is asynchronous: under EWM
this Emacs is the compositor, and `nmcli' is a fork, an exec, and a wait
on NetworkManager.  On the render timer that is the whole desktop's
latency, several times a minute.  The displayed value lags one interval.

The `nmcli' output is accumulated and parsed when the process exits: a
filter can be handed a partial line, and this reply is several lines."
  (let ((dev (emanix/modeline--wifi-device)))
    (cond
     ((null dev)
      (setq emanix/modeline--wifi-status nil))
     ((not (executable-find "nmcli"))
      ;; No NetworkManager: operstate is one small sysfs read, cheap inline.
      (setq emanix/modeline--wifi-status
            (unless (equal "up"
                           (string-trim
                            (with-temp-buffer
                              (insert-file-contents
                               (format "/sys/class/net/%s/operstate" dev))
                              (buffer-string))))
              "wifi✗")))
     ((not (get-process "emanix-modeline-nmcli"))
      (setq emanix/modeline--wifi-output "")
      (make-process
       :name "emanix-modeline-nmcli"
       :command '("nmcli" "-t" "-f" "TYPE,STATE" "dev" "status")
       :noquery t
       :connection-type 'pipe
       :filter (lambda (_proc out)
                 (setq emanix/modeline--wifi-output
                       (concat emanix/modeline--wifi-output out)))
       :sentinel (lambda (_proc event)
                   (when (string-prefix-p "finished" event)
                     (setq emanix/modeline--wifi-status
                           (emanix/modeline--wifi-parse
                            emanix/modeline--wifi-output))
                     (setq emanix/modeline--wifi-output "")
                     (emanix/modeline--render))))))))

(defun emanix/modeline--wifi ()
  "Wireless status, or nil when connected or absent.
A plain read of `emanix/modeline--wifi-status'; the work that produces it
happens in `emanix/modeline--poll-wifi', off the render path."
  emanix/modeline--wifi-status)

(defun emanix/modeline--update ()
  (emanix/modeline--poll-volume)
  (emanix/modeline--poll-wifi)
  (emanix/modeline--render))

(defun emanix/tab-bar-status ()
  "Right-aligned tab-bar item: system stats + clock + battery.
Frame-global — rendered once, unlike the per-window mode-line.
Add to `tab-bar-format' (see init.el)."
  `((global menu-item
            ,(if (equal emanix/modeline-status "")
                 " "
               (concat emanix/modeline-status "  "))
            ignore)))

;;;###autoload
(define-minor-mode emanix/modeline-mode
  "Poll volume/wifi/cpu/ram/gpu into `emanix/modeline-status'.
The value is displayed by `emanix/tab-bar-status' in the tab-bar, not
the mode-line; this mode only drives the refresh timer."
  :global t
  (if emanix/modeline-mode
      (progn
        (setq emanix/modeline--prev-cpu nil)
        ;; Re-probe on re-enable: hardware may have been hotplugged since.
        (setq emanix/modeline--gpu-file 'unset
              emanix/modeline--battery-dir 'unset
              emanix/modeline--wifi-dev 'unset)
        (setq emanix/modeline--timer
              (run-at-time 0 emanix/modeline-interval #'emanix/modeline--update)))
    (when emanix/modeline--timer
      (cancel-timer emanix/modeline--timer)
      (setq emanix/modeline--timer nil))))

(provide 'emanix-modeline)
;;; emanix-modeline.el ends here
