;;; fallback.el --- minimum viable desktop -*- lexical-binding: t; -*-

;; Loaded by init.el ONLY when config.el failed to load. On rafik Emacs is the
;; Wayland compositor, so "config.el has an error" means "no top bar, no s-d,
;; no window navigation" — which happened twice on 2026-08-10 from unrelated
;; faults (an unbalanced paren, and a bare require that signalled).
;;
;; Two rules for this file:
;;
;; 1. Nothing here may fail. No package requires, no :vc, no network. Only
;;    lisp/ modules, which are plain elisp from the checkout.
;; 2. Every form is individually guarded, so a fault in one still leaves the
;;    rest applied. A fallback that collapses is not a fallback.
;;
;; Scope is what was actually lost in those incidents, not a guess: the top bar,
;; the launcher, the EWM slot commands and a theme. Completion, meow, magit,
;; org, apheleia and the rest are recoverable by fixing config.el and are not
;; the desktop.

(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

;; require with :no-error returns nil for a missing file, but can still signal
;; on an error INSIDE the file — hence the condition-case as well.
(dolist (feature '(scott-ewm-slots scott-modeline scott-launcher scott-theme))
  (condition-case e
      (require feature nil :no-error)
    (error (message "fallback: %s failed to load: %S" feature e))))

(condition-case e
    (when (fboundp 'scott/theme-init) (scott/theme-init))
  (error (message "fallback: theme-init failed: %S" e)))

(condition-case e
    (when (fboundp 'scott/modeline-mode) (scott/modeline-mode 1))
  (error (message "fallback: modeline-mode failed: %S" e)))

(condition-case e
    (when (fboundp 'scott/launch-app)
      (global-set-key (kbd "C-c o") #'scott/launch-app))
  (error (message "fallback: launcher binding failed: %S" e)))

(defun scott/fallback-tab-bar-item ()
  "Tab-bar item announcing that `config.el' failed to load.
Deliberately loud. A silent degraded mode is worse than a hard failure: on
2026-08-10 a broken config survived a reboot without being noticed, and the
visible symptoms pointed somewhere other than the fault."
  `((fallback menu-item
              ,(propertize " ⚠ CONFIG FAILED — see scott/init-error "
                           'face 'error)
              ignore)))

(condition-case e
    (progn
      (setq tab-bar-format
            (append '(scott/fallback-tab-bar-item)
                    (and (fboundp 'scott/ewm-tab-bar-slots)
                         '(scott/ewm-tab-bar-slots))
                    '(tab-bar-format-align-right)
                    (and (fboundp 'scott/tab-bar-status)
                         '(scott/tab-bar-status))))
      (setq tab-bar-show t)
      (tab-bar-mode 1))
  (error (message "fallback: tab-bar setup failed: %S" e)))

;; Slot keys only — config.el's `with-eval-after-load 'ewm' block also binds
;; s-i (elisa) and s-S-<return> (ghostty-pi), neither of which this file
;; requires, so those are deliberately left out here. EWM's own keymap
;; already provides s-d and s-<arrows>, so the launcher and directional
;; navigation survive without any of this; only slot switching was M-x-only
;; before this block existed.
(condition-case e
    (with-eval-after-load 'ewm
      (when (boundp 'ewm-mode-map)
        (dotimes (i 9)
          (let ((slot (1+ i)))
            (define-key ewm-mode-map (kbd (format "s-%d" slot))
              (lambda ()
                (interactive)
                (scott/ewm-select-slot slot)))))
        (define-key ewm-mode-map (kbd "s-0")
          (lambda ()
            (interactive)
            (scott/ewm-select-slot 10)))
        (define-key ewm-mode-map (kbd "s-r") #'scott/ewm-rename-workspace)
        (define-key ewm-mode-map (kbd "s-q") #'scott/ewm-close-slot)
        (define-key ewm-mode-map (kbd "s-w") #'scott/ewm-launch-firefox)
        (define-key ewm-mode-map (kbd "s-<return>")
          (lambda ()
            (interactive)
            (start-process "ghostty" nil "ghostty")))))
  (error (message "fallback: ewm slot keys failed: %S" e)))

(provide 'fallback)
;;; fallback.el ends here
