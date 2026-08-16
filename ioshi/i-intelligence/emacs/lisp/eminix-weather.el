;;; eminix-weather.el --- Phoenix NY weather surface (super+n) -*- lexical-binding: t; -*-
;; Replaces base/bin hypr-weather: NWS hourly forecast table plus NOAA
;; satellite/radar imagery, rendered in a *weather* buffer.
(require 'url)
(require 'iso8601)
(require 'json)

(defconst eminix-weather--lat "43.2312")
(defconst eminix-weather--lon "-76.3007")
(defconst eminix-weather--images
  '(("satellite.jpg" . "https://cdn.star.nesdis.noaa.gov/GOES16/ABI/SECTOR/ne/GEOCOLOR/latest.jpg")
    ("airmass.jpg"   . "https://cdn.star.nesdis.noaa.gov/GOES16/ABI/SECTOR/ne/AirMass/latest.jpg")
    ("radar.gif"     . "https://radar.weather.gov/ridge/standard/NORTHEAST_loop.gif")))

(defvar url-user-agent)
(setq url-user-agent "eminix (NixOS Emacs)")

(defun eminix-weather--fetch-json (url)
  "GET URL and return the body parsed as an alist tree."
  (with-current-buffer (url-retrieve-synchronously url t t 15)
    (goto-char url-http-end-of-headers)
    (prog1 (json-parse-buffer :object-type 'alist :array-type 'list
                              :null-object nil)
      (kill-buffer))))

(defun eminix-weather--format-periods (periods &optional zone)
  "Format the first 8 of PERIODS (NWS hourly alists) as table lines.
ZONE is passed to `format-time-string' (nil = local time)."
  (mapconcat
   (lambda (p)
     (let* ((start (alist-get 'startTime p))
            (time (format-time-string
                   "%a %-l%p" (encode-time (iso8601-parse start)) zone))
            (temp (alist-get 'temperature p))
            (pop (or (alist-get 'value (alist-get 'probabilityOfPrecipitation p)) 0))
            (short (alist-get 'shortForecast p)))
       (format "%-9s %3d°  %3d%%  %s" time temp pop short)))
   (seq-take periods 8) "\n"))

(defun eminix-weather--cache-dir ()
  (let ((dir (expand-file-name "eminix-weather"
                               (or (getenv "XDG_CACHE_HOME") "~/.cache"))))
    (make-directory dir t)
    dir))

(defun eminix-weather--insert-images (buf)
  "Asynchronously download NOAA imagery and append it to BUF."
  (let ((dir (eminix-weather--cache-dir)))
    (dolist (spec eminix-weather--images)
      (let ((file (expand-file-name (car spec) dir)))
        (make-process
         :name (concat "eminix-weather-" (car spec))
         :command (list "curl" "-sfLo" file (cdr spec))
         :sentinel
         (lambda (_proc event)
           (when (and (string= event "finished\n") (buffer-live-p buf))
             (with-current-buffer buf
               (let ((inhibit-read-only t))
                 (save-excursion
                   (goto-char (point-max))
                   (insert-image (create-image file nil nil :max-width 950))
                   (insert "\n\n")))))))))))

;;;###autoload
(defun eminix/weather ()
  "Show the Phoenix, NY hourly forecast and NOAA imagery."
  (interactive)
  (let* ((points (eminix-weather--fetch-json
                  (format "https://api.weather.gov/points/%s,%s"
                          eminix-weather--lat eminix-weather--lon)))
         (hourly-url (alist-get 'forecastHourly (alist-get 'properties points)))
         (periods (alist-get 'periods
                             (alist-get 'properties
                                        (eminix-weather--fetch-json hourly-url))))
         (buf (get-buffer-create "*weather*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "☁ Phoenix, NY — hourly\n\n"
                (eminix-weather--format-periods periods)
                "\n\n"))
      (special-mode))
    (pop-to-buffer buf)
    (eminix-weather--insert-images buf)))

(defun eminix/weather-frame ()
  "Hyprland entry point: `eminix/weather' in a dedicated floating frame."
  (let ((frame (make-frame '((name . "emacs-weather")
                             (title . "emacs-weather")))))
    (select-frame-set-input-focus frame)
    (eminix/weather)))

(provide 'eminix-weather)
;;; eminix-weather.el ends here
