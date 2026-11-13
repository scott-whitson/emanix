;;; emanix-ewm-screenshot.el --- PrintScreen: region, then save or copy -*- lexical-binding: t; -*-

;; PrintScreen already reaches Emacs: EWM's own keymap intercepts <Print> with
;; no command (`ewm-key :intercept' in ewm-input.el), so the key is reserved and
;; currently does nothing. This fills it.
;;
;; Capture is slurp (region) + grim (pixels) + wl-copy (clipboard); all three
;; are already emanix packages (home/packages.nix), so a host that runs EWM has
;; them. The post-capture choice is a minibuffer prompt and not a menu program:
;; none is installed, and under EWM this Emacs already owns the keyboard.
;;
;; Loaded only on EWM hosts, from emanix-ewm.el. Rationale, and the alternatives
;; rejected: docs/decisions/ewm-screenshot.md.

;;; Code:

(require 'seq)

(defgroup emanix-screenshot nil
  "PrintScreen capture under EWM."
  :group 'emanix)

(defcustom emanix/screenshot-directory (expand-file-name "~/Pictures/screenshots")
  "Directory the PrintScreen command saves captures to.
Only the save choice consults this; a clipboard-only capture never writes here.
A consumer overrides it from personal.el."
  :type 'directory
  :group 'emanix-screenshot)

(defun emanix/ewm--slurp-geometry ()
  "Run slurp; return the selected geometry string, or nil when cancelled."
  (with-temp-buffer
    (when (eq 0 (call-process "slurp" nil t nil))
      (let ((geometry (string-trim (buffer-string))))
        (unless (string-empty-p geometry) geometry)))))

(defun emanix/ewm--grim (geometry file)
  "Capture GEOMETRY (nil means the whole output) into FILE; return exit status."
  (if geometry
      (call-process "grim" nil nil nil "-g" geometry file)
    (call-process "grim" nil nil nil file)))

(defun emanix/ewm--copy (file)
  "Put FILE on the Wayland clipboard as PNG, or signal when wl-copy fails."
  (unless (eq 0 (call-process "wl-copy" file nil nil "--type" "image/png"))
    (user-error "wl-copy failed")))

(defun emanix/ewm--save (file)
  "Move FILE into `emanix/screenshot-directory' and return the new path."
  (make-directory emanix/screenshot-directory t)
  (let ((final (expand-file-name (format-time-string "screenshot-%Y%m%d-%H%M%S.png")
                                 emanix/screenshot-directory)))
    (rename-file file final)
    final))

(defun emanix/ewm--choose-action ()
  "Ask what to do with the capture; return `save', `copy', `both' or nil."
  (pcase (car (read-multiple-choice
               "Screenshot"
               '((?s "save" "Save it to disk")
                 (?c "copy" "Copy it to the clipboard")
                 (?b "both" "Save it and copy it")
                 (?q "cancel" "Discard it"))))
    (?s 'save)
    (?c 'copy)
    (?b 'both)
    (_ nil)))

;;;###autoload
(defun emanix/ewm-screenshot (&optional full)
  "Capture a region, then save it, copy it, or both.
With prefix argument FULL, capture the whole output instead of a region.
The region comes from slurp; the choice is a minibuffer prompt."
  (interactive "P")
  (let ((geometry (unless full (emanix/ewm--slurp-geometry))))
    (if (and (not full) (null geometry))
        (message "Screenshot cancelled")
      (let ((tmp (make-temp-file "emanix-screenshot-" nil ".png")))
        (if (not (zerop (emanix/ewm--grim geometry tmp)))
            (progn (delete-file tmp nil) (user-error "grim failed"))
          (pcase (emanix/ewm--choose-action)
            ('save
             (let ((final (emanix/ewm--save tmp)))
               (kill-new final)
               (message "Screenshot saved: %s" final)))
            ('copy
             (emanix/ewm--copy tmp)
             (delete-file tmp nil)
             (message "Screenshot copied to the clipboard"))
            ('both
             (let ((final (emanix/ewm--save tmp)))
               (emanix/ewm--copy final)
               (kill-new final)
               (message "Screenshot saved and copied: %s" final)))
            (_
             (delete-file tmp nil)
             (message "Screenshot discarded"))))))))

(defun emanix/ewm-screenshot-full ()
  "Capture the whole output, then save it, copy it, or both."
  (interactive)
  (emanix/ewm-screenshot t))

(declare-function ewm-key "ewm-input")
(defvar ewm-mode-map)

;; The sibling S-<Print> is whole-output. Both carry :fullscreen: EWM only
;; intercepts an ewm-mode-map binding over a fullscreen client with it, and a
;; screenshot of a fullscreen video is the case worth having.
(with-eval-after-load 'ewm-input
  (when (boundp 'ewm-mode-map)
    (keymap-set ewm-mode-map "<print>" (ewm-key #'emanix/ewm-screenshot :fullscreen))
    (keymap-set ewm-mode-map "S-<print>"
                (ewm-key #'emanix/ewm-screenshot-full :fullscreen))))

(provide 'emanix-ewm-screenshot)
;;; emanix-ewm-screenshot.el ends here
