;;; init.el --- managed in dotfiles repo: modules/home-manager/emacs/ -*- lexical-binding: t; -*-
;; Packages are installed by Nix (modules/home-manager/emacs.nix).
;; This file only configures them.

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

;; Modeline clock + battery — no status bar under EWM.
(setq display-time-format "%a %b %e %H:%M"
      display-time-default-load-average nil)
(display-time-mode 1)
(display-battery-mode 1)
(setq display-line-numbers-type t)
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
(setq corfu-auto t corfu-auto-delay 0.15)

;; --- Meow: modal editing (qwerty layout, per meow README) ---
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
  "Open the current-quarter tracker note."
  (interactive)
  (let* ((name (scott/current-quarter-name))
         (file (scott/current-quarter-file))
         (new-file (not (file-exists-p file))))
    (find-file file)
    (when (and new-file (zerop (buffer-size)))
      (insert ":PROPERTIES:\n:ID:       " (org-id-new) "\n:END:\n")
      (insert "#+title: " name "\n\n")
      (insert "* Goals\n\n")
      (insert "* Active work\n\n")
      (insert "* Notes\n\n")
      (save-buffer))))

(global-set-key (kbd "C-c q") #'scott/open-quarterly-tracker)

;; --- Theme + custom surfaces (files appear as they are implemented) ---
(dolist (feature '(scott-theme scott-weather scott-openrouter))
  (require feature nil :no-error))
(when (fboundp 'scott/theme-init)
  (scott/theme-init))
