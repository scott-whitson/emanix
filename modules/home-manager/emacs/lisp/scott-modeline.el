;;; scott-modeline.el --- system status in the modeline -*- lexical-binding: t; -*-

;; EWM has no status bar; these segments replace waybar:
;; volume/mute, wifi, cpu%, ram%, gpu% (clock + battery come from
;; display-time-mode / display-battery-mode in init.el).
;; Everything reads sysfs/procfs except volume, which shells out to
;; wpctl — cheap enough at the update interval.

(defgroup scott/modeline nil
  "System status segments for the modeline."
  :group 'mode-line)

(defcustom scott/modeline-interval 3
  "Seconds between status refreshes."
  :type 'integer)

(defvar scott/modeline-status ""
  "Cached status string displayed via `global-mode-string'.")
(put 'scott/modeline-status 'risky-local-variable t)

(defvar scott/modeline--timer nil)
(defvar scott/modeline--prev-cpu nil
  "Cons of (idle . total) jiffies from the previous sample.")

(defun scott/modeline--cpu ()
  "CPU busy percent since the last sample (0 on the first)."
  (let* ((fields (with-temp-buffer
                   (insert-file-contents "/proc/stat")
                   (mapcar #'string-to-number
                           (cdr (split-string
                                 (buffer-substring (point-min) (line-end-position)))))))
         ;; idle = idle + iowait
         (idle (+ (nth 3 fields) (nth 4 fields)))
         (total (apply #'+ fields))
         (prev scott/modeline--prev-cpu))
    (setq scott/modeline--prev-cpu (cons idle total))
    (if (and prev (> (- total (cdr prev)) 0))
        (round (* 100 (- 1.0 (/ (float (- idle (car prev)))
                                (- total (cdr prev))))))
      0)))

(defun scott/modeline--ram ()
  "RAM used percent, by MemAvailable."
  (with-temp-buffer
    (insert-file-contents "/proc/meminfo")
    (let ((total (and (re-search-forward "MemTotal:\\s-+\\([0-9]+\\)" nil t)
                      (string-to-number (match-string 1))))
          (avail (and (re-search-forward "MemAvailable:\\s-+\\([0-9]+\\)" nil t)
                      (string-to-number (match-string 1)))))
      (when (and total avail (> total 0))
        (round (* 100 (- 1.0 (/ (float avail) total))))))))

(defun scott/modeline--gpu ()
  "GPU busy percent from amdgpu sysfs, or nil."
  (when-let* ((f (car (file-expand-wildcards
                       "/sys/class/drm/card*/device/gpu_busy_percent"))))
    (string-trim (with-temp-buffer (insert-file-contents f) (buffer-string)))))

(defvar scott/modeline--volume nil
  "Cached volume string from the last wpctl poll.")

(defun scott/modeline--poll-volume ()
  "Refresh `scott/modeline--volume' asynchronously.
Never blocks: in EWM this emacs IS the compositor, and a wedged
pipewire behind a synchronous call would hiccup the whole desktop.
The displayed value lags one update interval."
  (when (and (executable-find "wpctl")
             (not (get-process "scott-modeline-wpctl")))
    (make-process
     :name "scott-modeline-wpctl"
     :command '("wpctl" "get-volume" "@DEFAULT_AUDIO_SINK@")
     :noquery t
     :filter (lambda (_proc out)
               (setq scott/modeline--volume
                     (when (string-match "Volume: \\([0-9.]+\\)\\(.*\\[MUTED\\]\\)?" out)
                       (if (match-string 2 out)
                           "mute"
                         (format "%d%%" (round (* 100 (string-to-number
                                                       (match-string 1 out))))))))))))

(defun scott/modeline--wifi ()
  "\"✓\" when a wireless interface is up, \"✗\" when down, nil if none."
  (when-let* ((dev (seq-find
                    (lambda (d) (file-exists-p (format "/sys/class/net/%s/wireless" d)))
                    (directory-files "/sys/class/net" nil "^[^.]"))))
    (if (string= (string-trim
                  (with-temp-buffer
                    (insert-file-contents (format "/sys/class/net/%s/operstate" dev))
                    (buffer-string)))
                 "up")
        "✓" "✗")))

(defun scott/modeline--update ()
  (scott/modeline--poll-volume)
  (setq scott/modeline-status
        (concat
         (mapconcat
          #'identity
          (delq nil
                (list (when-let* ((v scott/modeline--volume)) (concat "♪" v))
                      (when-let* ((w (scott/modeline--wifi))) (concat "wifi" w))
                      (format "cpu%d%%" (scott/modeline--cpu))
                      (when-let* ((r (scott/modeline--ram))) (format "ram%d%%" r))
                      (when-let* ((g (scott/modeline--gpu))) (concat "gpu" g "%"))))
          " ")
         "  "))
  (force-mode-line-update t))

;;;###autoload
(define-minor-mode scott/modeline-mode
  "Show volume, wifi, cpu, ram, and gpu status in the modeline."
  :global t
  (if scott/modeline-mode
      (progn
        (unless (memq 'scott/modeline-status global-mode-string)
          (setq global-mode-string
                (append (or global-mode-string '("")) '(scott/modeline-status))))
        (setq scott/modeline--prev-cpu nil)
        (setq scott/modeline--timer
              (run-at-time 0 scott/modeline-interval #'scott/modeline--update)))
    (when scott/modeline--timer
      (cancel-timer scott/modeline--timer)
      (setq scott/modeline--timer nil))
    (setq global-mode-string (delq 'scott/modeline-status global-mode-string))))

(provide 'scott-modeline)
;;; scott-modeline.el ends here
