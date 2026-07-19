;;; init.el --- managed in dotfiles repo: modules/home-manager/emacs/ -*- lexical-binding: t; -*-
;; Packages are installed by Nix (modules/home-manager/emacs.nix).
;; This file only configures them.

(eval-and-compile
  (defvar display-time-format)
  (defvar display-time-default-load-average)
  (defvar display-line-numbers-type)
  (defvar corfu-auto)
  (defvar corfu-auto-delay)
  (defvar dired-listing-switches)
  (defvar dired-dwim-target)
  (defvar org-directory)
  (defvar org-roam-directory)
  (defvar tab-bar-format)
  (defvar tab-bar-show)
  (defvar meow-cheatsheet-layout)
  (declare-function ewm--focused-frame "ewm")
  (declare-function ewm--strip-frames "ewm")
  (declare-function ewm-frame-new "ewm")
  (declare-function ewm-workspace-rename "ewm")
  (declare-function ewm--strip-frames "ewm")
  (declare-function ewm--send-intercept-keys "ewm-input")
  (declare-function org-roam-capture "org-roam")
  (declare-function org-roam-node-find "org-roam")
  (declare-function org-roam-node-insert "org-roam")
  (declare-function org-roam-db-autosync-mode "org-roam")
  (declare-function embark-act "embark")
  (declare-function embark-bindings "embark"))

(add-to-list 'load-path (locate-user-emacs-file "lisp"))
(setq custom-file (locate-user-emacs-file "custom.el"))
(load custom-file :no-error)

;; --- Basics ---
(set-face-attribute 'default nil :family "JetBrainsMono Nerd Font" :height 110)
(setq make-backup-files nil
      auto-save-default nil
      create-lockfiles nil
      use-short-answers t
      ring-bell-function #'ignore)
(savehist-mode 1)
(recentf-mode 1)
(global-auto-revert-mode 1)
(column-number-mode 1)

;; Clock + battery + status for the EWM tab-bar panel (no status bar under EWM).
;; Volume/wifi/cpu/ram/gpu/clock/battery all render once in the tab-bar via
;; scott/tab-bar-status, not the mode-line.
(setq-default display-time-format "%a %b %e %I:%M %p"
              display-time-default-load-average nil)
(display-time-mode 1)
(display-battery-mode 1)
;; Keep the per-window mode-line clean — the panel lives in the tab-bar now.
(setq global-mode-string nil)
(setq-default display-line-numbers-type t)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)

;; --- Minibuffer completion: vertico + orderless + consult + marginalia + embark ---
(require 'vertico)
(require 'orderless)
(require 'marginalia)
(require 'consult)
(require 'corfu)
(vertico-mode 1)
(marginalia-mode 1)
(setq completion-styles '(orderless basic)
      completion-category-defaults nil
      completion-category-overrides '((file (styles partial-completion))))
(global-set-key (kbd "C-s") #'consult-line)
(global-set-key (kbd "C-x b") #'consult-buffer)
(global-set-key (kbd "M-g g") #'consult-goto-line)
(global-set-key (kbd "M-y") #'consult-yank-pop)
(global-set-key (kbd "C-c f") #'consult-ripgrep)
(global-set-key (kbd "C-.") #'embark-act)
(global-set-key (kbd "C-h B") #'embark-bindings)

;; --- In-buffer completion ---
(global-corfu-mode 1)
(setq corfu-auto t)
(setq-default corfu-auto-delay 0.15)

;; --- Meow: modal editing (qwerty layout, per meow README) ---
(require 'avy)
(require 'meow)
(defun meow-setup ()
  (setq meow-cheatsheet-layout meow-cheatsheet-layout-qwerty)
  (meow-motion-define-key
   '("j" . meow-next)
   '("k" . meow-prev)
   '("<escape>" . ignore))
  (meow-leader-define-key
   '("j" . "H-j") '("k" . "H-k")
   '("1" . meow-digit-argument) '("2" . meow-digit-argument)
   '("3" . meow-digit-argument) '("4" . meow-digit-argument)
   '("5" . meow-digit-argument) '("6" . meow-digit-argument)
   '("7" . meow-digit-argument) '("8" . meow-digit-argument)
   '("9" . meow-digit-argument) '("0" . meow-digit-argument)
   '("/" . meow-keypad-describe-key)
   '("?" . meow-cheatsheet))
  (meow-normal-define-key
   '("0" . meow-expand-0) '("9" . meow-expand-9) '("8" . meow-expand-8)
   '("7" . meow-expand-7) '("6" . meow-expand-6) '("5" . meow-expand-5)
   '("4" . meow-expand-4) '("3" . meow-expand-3) '("2" . meow-expand-2)
   '("1" . meow-expand-1)
   '("-" . negative-argument)
   '(";" . meow-reverse)
   '("," . meow-inner-of-thing)
   '("." . meow-bounds-of-thing)
   '("[" . meow-beginning-of-thing)
   '("]" . meow-end-of-thing)
   '("a" . meow-append)
   '("A" . meow-open-below)
   '("b" . meow-back-word)
   '("B" . meow-back-symbol)
   '("c" . meow-change)
   '("d" . meow-delete)
   '("D" . meow-backward-delete)
   '("e" . meow-next-word)
   '("E" . meow-next-symbol)
   '("f" . meow-find)
   '("F" . avy-goto-char-2)
   '("g" . meow-cancel-selection)
   '("G" . meow-grab)
   '("h" . meow-left)
   '("H" . meow-left-expand)
   '("i" . meow-insert)
   '("I" . meow-open-above)
   '("j" . meow-next)
   '("J" . meow-next-expand)
   '("k" . meow-prev)
   '("K" . meow-prev-expand)
   '("l" . meow-right)
   '("L" . meow-right-expand)
   '("m" . meow-join)
   '("n" . meow-search)
   '("o" . meow-block)
   '("O" . meow-to-block)
   '("p" . meow-yank)
   '("q" . meow-quit)
   '("Q" . meow-goto-line)
   '("r" . meow-replace)
   '("R" . meow-swap-grab)
   '("s" . meow-kill)
   '("t" . meow-till)
   '("u" . meow-undo)
   '("U" . meow-undo-in-selection)
   '("v" . meow-visit)
   '("w" . meow-mark-word)
   '("W" . meow-mark-symbol)
   '("x" . meow-line)
   '("X" . meow-goto-line)
   '("y" . meow-save)
   '("Y" . meow-sync-grab)
   '("z" . meow-pop-selection)
   '("'" . repeat)
   '("<escape>" . ignore)))
(meow-setup)
(meow-global-mode 1)

;; --- Files: dired + dirvish ---
(require 'dirvish)
(dirvish-override-dired-mode 1)
(setq dired-listing-switches "-alh --group-directories-first"
      dired-dwim-target t)
(global-set-key (kbd "C-c d") #'dirvish)

;; --- Git ---
(require 'magit)
(global-set-key (kbd "C-x g") #'magit-status)

;; --- Org + org-roam ---
(require 'org)
(setq org-return-follows-link t)
(require 'org-id)
;; Org-roam root. Full vault migrated from the Obsidian vault
;; (~/docs/vault/Whitsgrove) on 2026-07-11 via ~/docs/convert-vault.py.
;; 315 .md → .org files converted, originals archived to
;; ~/docs/vault/Whitsgrove/_obsidian_archive/. Vault is now clean —
;; only sync-conflict detritus remains.
(setq org-directory (expand-file-name "~/docs/org"))
(make-directory org-directory t)
(when (require 'org-roam nil :no-error)
  (setq org-roam-directory org-directory)
  (org-roam-db-autosync-mode 1)
  (global-set-key (kbd "C-c n f") #'org-roam-node-find)
  (global-set-key (kbd "C-c n i") #'org-roam-node-insert)
  (global-set-key (kbd "C-c n c") #'org-roam-capture))
(global-set-key (kbd "C-c a") #'org-agenda)

(defun scott/current-quarter-name (&optional time)
  "Return the current quarter name in YYYY-QN format."
  (let* ((time (or time (current-time)))
         (month (string-to-number (format-time-string "%m" time)))
         (quarter (1+ (/ (1- month) 3))))
    (format "%s-Q%d" (format-time-string "%Y" time) quarter)))

(defun scott/current-quarter-file ()
  "Return the current-quarter note path, preferring root then Quarterly/."
  (let* ((name (scott/current-quarter-name))
         (root (expand-file-name (concat name ".org") org-directory))
         (archived (expand-file-name (concat "Quarterly/" name ".org") org-directory)))
    (cond ((file-exists-p root) root)
          ((file-exists-p archived) archived)
          (t root))))

(defun scott/open-quarterly-tracker ()
  "Open the current-quarter tracker note.
If the note does not exist on this machine, do NOT silently create and
save an empty template — that races with Syncthing: on a freshly-synced
box the empty file can win the conflict and quarantine the real,
populated note (happened 2026-07-16 with 2026-Q3). Instead confirm
first, so an unsynced note gets a chance to arrive rather than be
clobbered; only a genuinely new quarter gets a fresh template."
  (interactive)
  (let* ((name (scott/current-quarter-name))
         (file (scott/current-quarter-file)))
    (if (file-exists-p file)
        (find-file file)
      (if (yes-or-no-p
           (format "No %s note here — create it? (choose no if it may just be unsynced) "
                   name))
          (progn
            (find-file file)
            (when (zerop (buffer-size))
              (insert ":PROPERTIES:\n:ID:       " (org-id-new) "\n:END:\n")
              (insert "#+title: " name "\n\n")
              (insert "* Goals\n\n")
              (insert "* Active work\n\n")
              (insert "* Notes\n\n")
              (save-buffer)))
        (message
         "Not creating %s — waiting for sync. Re-run C-c q once it arrives."
         name)))))

(global-set-key (kbd "C-c q") #'scott/open-quarterly-tracker)

;; --- Theme + custom surfaces (files appear as they are implemented) ---
(dolist (feature '(scott-theme scott-weather scott-openrouter scott-modeline))
  (require feature nil :no-error))
(when (fboundp 'scott/theme-init)
  (scott/theme-init))
(when (fboundp 'scott/modeline-mode)
  (scott/modeline-mode 1))

;; Slots are generic: no app or name is tied to a number. Apps launch into
;; whatever slot you're on (e.g. `s-w' → Firefox), and you name slots yourself
;; with `s-r'.

(defun scott/ewm-launch-firefox ()
  "Launch Firefox in the current EWM session."
  (interactive)
  (start-process-shell-command
   "firefox" nil
   (or (executable-find "firefox")
       (executable-find "firefox-esr")
       "~/.local/bin/firefox")))

;; Keyed slots: each frame carries its slot NUMBER in the `scott/ewm-slot'
;; frame parameter, so `s-3' owns one specific frame rather than "the 3rd
;; frame in the strip". Selecting slot 3 never conjures 1 and 2.
;;
;; No auto-close: under EWM a new frame inherits the current buffer (a
;; terminal surface, not *scratch*), and focus is async/compositor-owned, so
;; "reap the blank slot I just left" has no reliable trigger. Slots close
;; explicitly via `scott/ewm-close-slot' (s-w); apps that exit are cleaned up
;; by EWM's own close handler.

(defun scott/ewm--slot-frame (slot output)
  "Return the frame keyed to SLOT on OUTPUT, or nil."
  (seq-find (lambda (f) (eql slot (frame-parameter f 'scott/ewm-slot)))
            (ewm--strip-frames output)))

(defun scott/ewm--goto (target)
  "Focus TARGET and refresh the bar.
The force-update defeats tab-bar's per-frame cache so the highlight
tracks the switch."
  (select-frame-set-input-focus target)
  (force-mode-line-update t))

(defun scott/ewm-close-slot ()
  "Close the current EWM slot/frame.
EWM's delete-frame handling refocuses a same-output neighbour and drops
the frame from the strip; its advice refuses to close the last frame."
  (interactive)
  (unless (bound-and-true-p ewm--module-mode)
    (user-error "EWM is not active"))
  (delete-frame (if (fboundp 'ewm--focused-frame)
                    (ewm--focused-frame)
                  (selected-frame)))
  (force-mode-line-update t))

(defun scott/ewm-select-slot (slot)
  "Focus the frame keyed to SLOT on the current output, creating it once.
Slots are identified by number, not strip position, so selecting slot 3
never creates 1 and 2."
  (interactive "nSlot: ")
  (unless (and (integerp slot) (>= slot 1))
    (user-error "Slot must be a positive integer"))
  (unless (bound-and-true-p ewm--module-mode)
    (user-error "EWM is not active"))
  (let* ((frame (if (fboundp 'ewm--focused-frame)
                    (ewm--focused-frame)
                  (selected-frame)))
         (output (frame-parameter frame 'ewm-output)))
    (unless output
      (user-error "Current frame has no EWM output"))
    ;; Adopt the leftmost frame as slot 1 (home) the first time, so it shows
    ;; in the bar as a numbered slot.
    (unless (scott/ewm--slot-frame 1 output)
      (when-let* ((home (car (ewm--strip-frames output))))
        (set-frame-parameter home 'scott/ewm-slot 1)))
    (if-let* ((existing (scott/ewm--slot-frame slot output)))
        (scott/ewm--goto existing)
      (let ((before (ewm--strip-frames output)))
        (ewm-frame-new)
        (let ((new (car (seq-difference (ewm--strip-frames output) before))))
          (unless new
            (user-error "Slot %d creation failed" slot))
          (set-frame-parameter new 'scott/ewm-slot slot)
          (scott/ewm--goto new))))))

(defun scott/ewm-rename-workspace (name)
  "Rename the current EWM workspace/slot to NAME (shown in the tab bar).
An empty NAME clears the custom label, falling back to the frame name."
  (interactive "sWorkspace name: ")
  (unless (bound-and-true-p ewm--module-mode)
    (user-error "EWM is not active"))
  (let ((frame (if (fboundp 'ewm--focused-frame)
                   (ewm--focused-frame)
                 (selected-frame))))
    (ewm-workspace-rename name frame)
    (set-frame-parameter frame 'ewm-workspace-name
                         (unless (string-empty-p name) name))
    (force-mode-line-update t)))

(defun scott/ewm--slot-label (frame)
  "Short display label for FRAME's slot.
Prefers the tracked workspace name, else the frame name, decorations
stripped and truncated for the bar."
  (let ((n (or (frame-parameter frame 'ewm-workspace-name)
               (frame-parameter frame 'name)
               "")))
    (setq n (replace-regexp-in-string "\\`\\*ewm:[ \t]*" "" n))
    (setq n (replace-regexp-in-string "\\*\\'" "" n))
    (setq n (string-trim n))
    (if (string-empty-p n) "?"
      (truncate-string-to-width n 10 nil nil "…"))))

(defun scott/ewm-tab-bar-slots ()
  "Tab-bar segment listing EWM slots on the focused output, sorted by slot
number, current one highlighted, each clickable to focus it.
Returns nil off EWM, so it is a no-op in a plain Emacs frame."
  (when (fboundp 'ewm--focused-frame)
    (let* ((focused (ewm--focused-frame))
           (output (frame-parameter focused 'ewm-output))
           (frames (and output (ewm--strip-frames output)))
           (pos 0)
           pairs)
      ;; Pair each frame with its slot number (its `scott/ewm-slot' tag, or
      ;; its strip position for any not-yet-adopted frame), then sort so the
      ;; bar reads 1, 2, 3 … regardless of physical strip order.
      (dolist (f frames)
        (setq pos (1+ pos))
        (push (cons (or (frame-parameter f 'scott/ewm-slot) pos) f) pairs))
      (setq pairs (sort (nreverse pairs) (lambda (a b) (< (car a) (car b)))))
      (mapcar
       (lambda (pair)
         (let* ((num (car pair))
                (f (cdr pair))
                (cur (eq f focused))
                (label (format " %d:%s " num (scott/ewm--slot-label f)))
                (face (if cur 'tab-bar-tab 'tab-bar-tab-inactive)))
           (list (intern (format "ewm-slot-%d" num))
                 'menu-item
                 (propertize label 'face face)
                 (lambda () (interactive) (scott/ewm--goto f)))))
       pairs))))

;; Frame-global panel: system stats + clock + battery, rendered ONCE at the top
;; of the (full-screen, under EWM) frame — the actual bar.
(when (fboundp 'scott/tab-bar-status)
  ;; Left: EWM slot list (scott/ewm-tab-bar-slots, no-op off EWM).
  ;; Right: system stats + clock + battery.
  (setq tab-bar-format '(scott/ewm-tab-bar-slots
                         tab-bar-format-align-right
                         scott/tab-bar-status))
  (setq tab-bar-show t)   ; always show the panel, even with a single/zero tab
  (tab-bar-mode 1))

;; elisa — local, config-aware eminix assistant (Emacs/Linux/NixOS RAG via a
;; sqlite-vec ELISA fork + ellama + local Ollama). Binds the C-c i map.
(require 'scott-elisa nil :no-error)

;; EWM-only session glue (swayidle/swaylock + touchpad) — no-op elsewhere.
;; EWM is loaded via `emacs --eval (require 'ewm)' which runs AFTER this init
;; file, so `(featurep 'ewm)' is still nil here: a plain `when' guard skips
;; the require and input/session glue never loads (symptom: tap-to-click and
;; swayidle silently absent, (fboundp 'scott/ewm-start-swayidle) => nil).
;; Defer to the moment the ewm feature actually arrives; on non-EWM hosts it
;; never loads, so this stays a no-op there.
(with-eval-after-load 'ewm
  (require 'scott-ewm nil :no-error)
  (when (boundp 'ewm-mode-map)
    ;; Super+number restores the old workspace-switch rhythm, but in EWM frame
    ;; slots. Slots create on demand: super-3 opens/switches to slot 3.
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
    ;; Rename the current frame/slot in the top bar.
    (define-key ewm-mode-map (kbd "s-r") #'scott/ewm-rename-workspace)
    ;; Close the current slot (manual lifecycle; no auto-close under EWM).
    ;; s-q mirrors Hyprland's `$mod, Q, killactive' muscle memory.
    (define-key ewm-mode-map (kbd "s-q") #'scott/ewm-close-slot)
    ;; Launch Firefox into the current slot (was s-w under Hyprland).
    (define-key ewm-mode-map (kbd "s-w") #'scott/ewm-launch-firefox)
    ;; Summon elisa (ask) from ANY slot. It must be a single intercepted key:
    ;; the C-c i prefix can't reach Emacs from a focused Wayland surface (the
    ;; follow-up key goes to the surface). C-c i still gives the full command
    ;; set when a native Emacs frame is focused.
    (when (fboundp 'scott/elisa-ask)
      (define-key ewm-mode-map (kbd "s-i") #'scott/elisa-ask))
    (when (fboundp 'ewm--send-intercept-keys)
      (ewm--send-intercept-keys))))
