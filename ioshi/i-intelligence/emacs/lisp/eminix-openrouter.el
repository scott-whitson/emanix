;;; eminix-openrouter.el --- OpenRouter 7-day cost surface (super+u) -*- lexical-binding: t; -*-
;; Replaces base/bin hypr-or-cost: exact rolling 7-day cost via the
;; management key (activity API, lags ~1 day) topped up with today's
;; usage from the regular key.
(require 'url)
(require 'iso8601)
(require 'json)

(defconst eminix-openrouter--auth-file "~/.pi/agent/auth.json")

(defun eminix-openrouter--keys ()
  "Return (MANAGEMENT-KEY . REGULAR-KEY) from the pi auth file."
  (let ((auth (json-parse-string
               (with-temp-buffer
                 (insert-file-contents eminix-openrouter--auth-file)
                 (buffer-string))
               :object-type 'alist :null-object nil)))
    (cons (alist-get 'key (alist-get 'openrouter-management auth))
          (alist-get 'key (alist-get 'openrouter auth)))))

(defun eminix-openrouter--fetch-json (url key)
  "GET URL with bearer KEY; return parsed alist tree."
  (let ((url-request-extra-headers
         `(("Authorization" . ,(concat "Bearer " key)))))
    (with-current-buffer (url-retrieve-synchronously url t t 15)
      (goto-char url-http-end-of-headers)
      (prog1 (json-parse-buffer :object-type 'alist :array-type 'list
                                :null-object nil)
        (kill-buffer)))))

(defun eminix-openrouter--summarize (activity key-data now)
  "Summarize ACTIVITY entries and KEY-DATA relative to time NOW.
Mirrors the logic of the retired hypr-or-cost script."
  (let ((cutoff (time-subtract now (days-to-time 7)))
        (today (format-time-string "%Y-%m-%d" now t))
        (rolling 0.0) (requests 0) (models '()) (today-in-activity nil))
    (dolist (e activity)
      (let* ((date-str (car (split-string (or (alist-get 'date e) "") " ")))
             (dt (encode-time (iso8601-parse (concat date-str "T00:00:00Z")))))
        (when (string-prefix-p today (or (alist-get 'date e) ""))
          (setq today-in-activity t))
        (unless (time-less-p dt cutoff)
          (setq rolling (+ rolling (or (alist-get 'usage e) 0))
                requests (+ requests (or (alist-get 'requests e) 0)))
          (push (or (alist-get 'model e) "?") models))))
    (let ((daily (or (alist-get 'usage_daily key-data) 0))
          (monthly (or (alist-get 'usage_monthly key-data) 0))
          (uniq (delete-dups (sort models #'string<))))
      (when (and (not today-in-activity) (> daily 0))
        (setq rolling (+ rolling daily)))
      (concat
       (format "$%.2f — last 7 days (%d requests)\n" rolling requests)
       (if (and uniq (<= (length uniq) 3))
           (format "Models: %s\n" (string-join uniq ", "))
         "")
       (format "$%.2f — this month" monthly)))))

;;;###autoload
(defun eminix/openrouter-cost ()
  "Show the rolling 7-day OpenRouter cost summary."
  (interactive)
  (pcase-let ((`(,mgmt . ,regular) (eminix-openrouter--keys)))
    (unless (and mgmt regular)
      (user-error "OpenRouter keys missing from %s" eminix-openrouter--auth-file))
    (let* ((activity (alist-get 'data (eminix-openrouter--fetch-json
                                       "https://openrouter.ai/api/v1/activity?limit=500" mgmt)))
           (key-data (alist-get 'data (eminix-openrouter--fetch-json
                                       "https://openrouter.ai/api/v1/auth/key" regular)))
           (buf (get-buffer-create "*openrouter*")))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert "OpenRouter Cost\n\n"
                  (eminix-openrouter--summarize activity key-data (current-time))
                  "\n"))
        (special-mode))
      (pop-to-buffer buf))))

(defun eminix/openrouter-cost-frame ()
  "Hyprland entry point: `eminix/openrouter-cost' in a floating frame."
  (let ((frame (make-frame '((name . "emacs-openrouter")
                             (title . "emacs-openrouter")))))
    (select-frame-set-input-focus frame)
    (eminix/openrouter-cost)))

(provide 'eminix-openrouter)
;;; eminix-openrouter.el ends here
