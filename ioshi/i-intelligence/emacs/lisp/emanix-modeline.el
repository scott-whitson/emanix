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

(defvar emanix/modeline-status ""
  "Cached status string displayed via `global-mode-string'.")
(put 'emanix/modeline-status 'risky-local-variable t)

(defvar emanix/modeline--timer nil)
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
  (when-let* ((f (car (file-expand-wildcards
                       "/sys/class/drm/card*/device/gpu_busy_percent"))))
    (string-trim (with-temp-buffer (insert-file-contents f) (buffer-string)))) )

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
  (when-let* ((bat (car (file-expand-wildcards "/sys/class/power_supply/BAT*"))))
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

(defun emanix/modeline--render ()
  "Compose and redraw the current EWM status bar."
  (setq emanix/modeline-status
        (mapconcat
         #'identity
         (delq nil
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
                           (format "gpu %s%%" g))))
                     (emanix/modeline--clock)
                     (emanix/modeline--battery)))
         "   "))
  (force-mode-line-update t)
  (when (fboundp 'tab-bar--update-tab-bar-lines)
    (tab-bar--update-tab-bar-lines))
  (redraw-display))

(defun emanix/modeline--wifi ()
  "Wireless status, or nil when connected or absent."
  (when-let* ((dev (seq-find
                    (lambda (d) (file-exists-p (format "/sys/class/net/%s/wireless" d)))
                    (directory-files "/sys/class/net" nil "^[^.]") )))
    (let ((connected-p
           (if (executable-find "nmcli")
               (let* ((lines (split-string (shell-command-to-string
                                            "nmcli -t -f TYPE,STATE dev status 2>/dev/null")
                                           "\n" t))
                      (line (seq-find (lambda (s) (string-prefix-p "wifi:" s)) lines))
                      (state (and line (cadr (split-string line ":" t)))))
                 (string= state "connected"))
             (string= (string-trim
                       (with-temp-buffer
                         (insert-file-contents (format "/sys/class/net/%s/operstate" dev))
                         (buffer-string)))
                      "up"))))
      (unless connected-p "wifi✗"))))

(defun emanix/modeline--update ()
  (emanix/modeline--poll-volume)
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
        (setq emanix/modeline--timer
              (run-at-time 0 emanix/modeline-interval #'emanix/modeline--update)))
    (when emanix/modeline--timer
      (cancel-timer emanix/modeline--timer)
      (setq emanix/modeline--timer nil))))

(provide 'emanix-modeline)
;;; emanix-modeline.el ends here
