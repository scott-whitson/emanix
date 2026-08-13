;;; config.el --- managed in dotfiles repo: modules/home-manager/emacs/ -*- lexical-binding: t; -*-
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
;; Symbol coverage for TUIs in vterm (Claude Code's ⏵ ⏸ ⏺ ✻ ✦) comes from
;; pkgs.noto-fonts via fontconfig fallback — see ../packages.nix. Deliberately
;; NOT set-fontset-font: on this pgtk/ftcrhb build those calls are inert
;; (verified — forcing a range to another family changes nothing).
(setq make-backup-files nil
      auto-save-default nil
      create-lockfiles nil
      use-short-answers t
      ring-bell-function #'ignore)
(savehist-mode 1)
(recentf-mode 1)
(global-auto-revert-mode 1)
(setq auto-revert-use-file-system-watcher nil  ; force polling — inotify is flaky on NixOS
      auto-revert-interval 1                    ; poll every 1s
      auto-revert-verbose nil)
(column-number-mode 1)

;; Window navigation & resizing (Shift+arrows)
(global-set-key (kbd "S-<left>") #'shrink-window-horizontally)
(global-set-key (kbd "S-<right>") #'enlarge-window-horizontally)
(global-set-key (kbd "S-<down>") #'shrink-window)
(global-set-key (kbd "S-<up>")    #'enlarge-window)

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

;; --- Scratch buffer ---
;; Banner is figlet's `slant' font, generated once and pasted (NOT shelled out
;; at startup). Two constraints on editing it: every line must stay commented,
;; because *scratch* is lisp-interaction-mode and a bare banner breaks
;; `eval-buffer'; and every backslash must be doubled, because this is a string
;; literal. Regenerate with: nix run nixpkgs#figlet -- -f slant Eminix
;; The command list below is a scratchpad, not a menu — churn it freely.
(setq initial-scratch-message "\
;;     ______          _       _
;;    / ____/___ ___  (_)___  (_)  __
;;   / __/ / __ `__ \\/ / __ \\/ / |/_/
;;  / /___/ / / / / / / / / / />  <
;; /_____/_/ /_/ /_/_/_/ /_/_/_/|_|
;;
;;  C-j = eval + print inline     C-x C-e = eval, echo area
;;  M-: = eval from minibuffer    C-x * q = quick calc

(scott/open-quarterly-tracker)
(scott/calendar-sync)
(org-agenda nil \"w\")
(magit-status \"~/dotfiles\")
(scott/weather)
(scott/openrouter-cost)
(call-interactively #'scott/launch-app)
")

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
;; Bookmarks: the built-in binding is C-x r b (register/rectangle family), which
;; nobody remembers. Bookmarked dirs jump into dirvish. See ~/.config/emacs/bookmarks
;; — win-desktop / win-downloads point at the Windows-side folders (Desktop is
;; OneDrive-redirected, hence the unguessable path).
(global-set-key (kbd "C-c b") #'consult-bookmark)
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

;; Line movement (global bindings, works with Meow selections)
;; System commands
(defun scott-reboot ()
  "Reboot the system."
  (interactive)
  (when (yes-or-no-p "Reboot now? ")
    (start-process "reboot" nil "sudo" "reboot")))

(defun scott-shutdown ()
  "Shut down the system."
  (interactive)
  (when (yes-or-no-p "Shut down now? ")
    (start-process "shutdown" nil "sudo" "shutdown" "now")))

;; --- Files: dired + dirvish ---
(require 'dirvish)
(dirvish-override-dired-mode 1)
(setq dired-listing-switches "-alh --group-directories-first"
      dired-dwim-target t)
(global-set-key (kbd "C-c d") #'dirvish)

;; --- Git ---
(require 'magit)
(global-set-key (kbd "C-x g") #'magit-status)

;; --- Code: navigation, LSP, formatting (added 2026-08-07) ---
;; Emacs 30 ships nearly all of this: project.el (C-x p), xref (M-. / M-,),
;; eglot (LSP client), flymake (diagnostics) and python-ts-mode are built in.
;; Only nix-ts-mode, apheleia and the tree-sitter grammars come from Nix —
;; see ../emacs/packages.nix.

;; Tree-sitter grammar discovery. Nix installs grammars as bare .so files in
;; <emacs-packages-deps>/lib/, a directory Emacs never searches, so without
;; this every *-ts-mode silently falls back with no error (verified 2026-08-07).
;; Derive the dir from load-path rather than hardcoding a store path: init.el
;; is a live out-of-store symlink and must survive a rebuild changing hashes.
(require 'treesit)
(dolist (dir load-path)
  (when (string-match "\\`\\(.*\\)/share/emacs/site-lisp\\(?:/\\|\\'\\)" dir)
    (let ((lib (expand-file-name "lib" (match-string 1 dir))))
      (when (file-directory-p lib)
        (add-to-list 'treesit-extra-load-path (file-name-as-directory lib))))))

;; Major modes. Only claim a file extension when its grammar actually loaded,
;; so a grammar dropped from packages.nix degrades to fundamental/python-mode
;; instead of erroring on every visit.
(when (treesit-language-available-p 'nix)
  (autoload 'nix-ts-mode "nix-ts-mode" "Major mode for Nix, via tree-sitter." t)
  (add-to-list 'auto-mode-alist '("\\.nix\\'" . nix-ts-mode)))
(when (treesit-language-available-p 'python)
  (add-to-list 'major-mode-remap-alist '(python-mode . python-ts-mode)))

;; LSP. eglot attaches per-buffer and routes everything through native Emacs
;; machinery — completions reach corfu, errors reach flymake, jumps reach xref.
;; nixd and basedpyright are eglot's own defaults for these modes; they are
;; listed explicitly so the config states its own contract rather than
;; inheriting whatever a future eglot ships.
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs '(nix-ts-mode . ("nixd")))
  (add-to-list 'eglot-server-programs
               '((python-mode python-ts-mode) . ("basedpyright-langserver" "--stdio")))
  ;; Formatting is apheleia's job (below). Letting the server also format on
  ;; save would race it and, for Nix, disagree with nixpkgs-fmt.
  (setq-default eglot-workspace-configuration
                '(:basedpyright (:analysis (:diagnosticMode "workspace")))))

(dolist (hook '(nix-ts-mode-hook python-ts-mode-hook))
  (add-hook hook #'eglot-ensure))

;; Format on save. nixpkgs-fmt is this repo's own formatter (flake.nix exposes
;; it as `formatter`), so `nix fmt` and a save from Emacs produce identical
;; bytes. apheleia formats asynchronously and splices the result, leaving point
;; and undo history intact — unlike a naive before-save-hook.
(require 'apheleia)
(with-eval-after-load 'apheleia
  (setf (alist-get 'nixpkgs-fmt apheleia-formatters) '("nixpkgs-fmt"))
  (setf (alist-get 'nix-ts-mode apheleia-mode-alist) 'nixpkgs-fmt)
  (setf (alist-get 'python-ts-mode apheleia-mode-alist) '(ruff-isort ruff)))
(apheleia-global-mode 1)

;; Diagnostics + refactoring, under one prefix (C-c e, chosen 2026-08-07 —
;; flymake ships no bindings of its own and C-c a/c/d/f/n/o/q/t were taken).
;; Navigation keys are deliberately absent: C-x p (project), M-. / M-, (xref)
;; and C-s / C-c f (consult) already cover it with stock bindings.
(global-set-key (kbd "C-c e n") #'flymake-goto-next-error)
(global-set-key (kbd "C-c e p") #'flymake-goto-prev-error)
(global-set-key (kbd "C-c e l") #'consult-flymake)
(global-set-key (kbd "C-c e r") #'eglot-rename)
(global-set-key (kbd "C-c e a") #'eglot-code-actions)
(global-set-key (kbd "C-c e =") #'apheleia-format-buffer)

;; Show the project name in the mode line's buffer id and let C-x p f start
;; from the current file's project without prompting.
(setq project-mode-line t)

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

;; Auto-update #+DATE: header on save (for weblorg revision dates).
;; Only runs in ~/projects/websites/ to avoid touching other org files.
(defun scott/org-update-revision-date ()
  "Update the #+DATE: header to today's date if the file is in ~/projects/websites/."
  (when (and buffer-file-name
             (string-prefix-p (expand-file-name "~/projects/websites/")
                              (file-truename buffer-file-name)))
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "^\\#\\+DATE:"
                               (if (re-search-forward "^\\* " nil t) (match-beginning 0) (point-max))
                               t)
        (let ((date-str (format-time-string "%Y-%m-%d")))
          (kill-line)
          (insert (format "<%s>" date-str)))))))
(add-hook 'org-mode-hook
          (lambda ()
            (add-hook 'after-save-hook #'scott/org-update-revision-date nil :local)))

;; --- weblorg: pure Emacs Lisp static site generator ---
(when (require 'weblorg nil :no-error)
  ;; weblorg is configured via publish.el files in each site directory.
  ;; Run with: emacs --script publish.el
  ;;
  ;; Keybindings for quick publishing:
  (defun scott/weblorg-publish-eminix ()
    "Publish the eminix.org website."
    (interactive)
    (let ((default-directory "~/projects/websites/eminix"))
      (shell-command "emacs --script publish.el")))

  (defun scott/weblorg-publish-scottwhitson ()
    "Publish scottwhitson.com."
    (interactive)
    (let ((default-directory "~/projects/websites/scottwhitson"))
      (shell-command "emacs --script publish.el")))

  (defun scott/weblorg-publish-whitsoninterfacesystems ()
    "Publish whitsoninterfacesystems.com."
    (interactive)
    (let ((default-directory "~/projects/websites/whitsoninterfacesystems"))
      (shell-command "emacs --script publish.el")))

  ;; Quick access to website directories
  (defun scott/open-websites-dir ()
    "Open the websites directory in dired."
    (interactive)
    (dired "~/projects/websites")))

;; Kill org buffers after agenda closes — they're only opened for scanning.
;; NB: this kills EVERY org-mode buffer, not just the ones the agenda opened,
;; so an org file you were editing yourself also goes when you quit the agenda.
(defun scott/org-agenda-kill-buffers ()
  "Kill all org-mode buffers after closing the agenda."
  (dolist (buf (buffer-list))
    (when (with-current-buffer buf (derived-mode-p 'org-mode))
      (kill-buffer buf))))
(add-hook 'org-agenda-quit-hook #'scott/org-agenda-kill-buffers)

;; org-babel: executable src blocks in notes (the "living ops journal"
;; workflow, adopted 2026-08-05). Shell blocks are off by default — enable.
;; Execution still asks y/n per block (org-confirm-babel-evaluate stays t):
;; notes sync across machines, so a stale block shouldn't run silently.
(org-babel-do-load-languages
 'org-babel-load-languages
 '((emacs-lisp . t)
   (shell . t)
   (python . t)))

;; --- Org agenda ---
(setq org-agenda-files (list org-directory))
(setq org-agenda-include-diary nil)           ; we use org files, not diary
(setq org-deadline-warning-days 14)            ; default lead time
(setq org-agenda-skip-deadline-if-done t)
(setq org-agenda-skip-scheduled-if-done t)     ; don't show done recurring items
;; Show SCHEDULED items as reminders on the day-of (not a deadline)
(setq org-agenda-scheduled-leaders '("" "(S%2d earlier)"))
(setq org-agenda-prefix-format
      '((agenda . " %i %-12:c%?-12t% s")
        (todo   . " %i %-12:c")
        (tags   . " %i %-12:c")
        (search . " %i %-12:c")))

;; Custom agenda commands:
;;   C-c a o  → yearly overview (all notable dates this year)
;;   C-c a m  → month calendar
;;   C-c a w  → week calendar
(setq org-agenda-custom-commands
      '(("o" "Notable dates (year)"
         ((agenda ""
                  ((org-agenda-span 365)
                   (org-agenda-start-day "2026-01-01")
                   (org-deadline-warning-days 0))))
         ((org-agenda-files (list (expand-file-name "Dates.org" org-directory)))))
        ("m" "Month calendar"
         ((agenda "" ((org-agenda-span 'month))))
         ((org-agenda-files (list (expand-file-name "Dates.org" org-directory)))))
        ("w" "Week agenda"
         ((agenda ""))
         ((org-agenda-files (list (expand-file-name "Dates.org" org-directory)))))))

;; --- Calendar sync (Python tool) ---
;; The Google Calendar sync will be handled by a small Python tool.
;; Emacs should stay focused on editing Dates.org and launching the tool.

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

(defun scott/calendar-sync ()
  "Launch the Python calendar sync tool."
  (interactive)
  (start-process-shell-command
   "calendar-sync" nil
   (expand-file-name "~/dotfiles/bin/calendar-sync") "sync"))

(global-set-key (kbd "C-c c") #'scott/calendar-sync)

;; --- Google Docs sync (org ↔ Google Docs) ---
;; Bidirectional sync between org files and Google Docs.
;; Requires: Google Cloud project with Docs API + Drive API enabled,
;; OAuth credentials configured in gdocs-accounts.
;; M-x gdocs-authenticate, then M-x gdocs-create or M-x gdocs-open.
;; rafik-only. init.el is shared by every host, and use-package :vc
;; fetches from GitHub on load - without this guard whistle and datacore
;; would pull gdocs too, for a workflow only rafik has. A wrapping `when`
;; rather than use-package's :if on purpose: :if guards the runtime body,
;; but :vc install work can run at macro-expansion time. A false `when`
;; never expands the macro at all.
(when (equal (system-name) "rafik")
  ;; Two separate problems, both fixed here (2026-08-10):
  ;;
  ;; 1. ~/.config/emacs/elpa is NOT on load-path. This Emacs takes its
  ;;    packages from Nix, so package-activate-all never runs and whatever
  ;;    package-vc downloaded is invisible to `require'. gdocs.el really is
  ;;    at ~/.config/emacs/elpa/gdocs/gdocs.el, but (locate-library "gdocs")
  ;;    returned nil. Add the elpa subdirectories explicitly.
  ;;
  ;; 2. A bare (require 'gdocs) SIGNALS when it fails, and nothing above
  ;;    catches it, so the failure aborted every remaining form in init.el.
  ;;    After a reboot that meant no top bar (scott/modeline-mode), no s-d
  ;;    (scott/launcher) and no EWM window commands (scott/ewm--goto and
  ;;    friends) -- all defined below this point. Never let an optional
  ;;    package take the desktop down: require it with :no-error and only
  ;;    configure it if it actually loaded.
  (let ((elpa (expand-file-name "elpa" user-emacs-directory)))
    (when (file-directory-p elpa)
      (dolist (d (directory-files elpa t "\\`[^.]"))
        (when (file-directory-p d) (add-to-list 'load-path d)))))
  (if (require 'gdocs nil :no-error)
      (progn
        (setq gdocs-auto-push-on-save t)
        ;; Credentials live outside the checkout (mode 600) so the OAuth
        ;; client secret is never committed. Absent file = no account.
        (load (expand-file-name "gdocs-creds.el" user-emacs-directory)
              :noerror :nomessage))
    (message "gdocs not loadable; skipping (see the comment above)")))

;; --- Theme + custom surfaces (files appear as they are implemented) ---
(dolist (feature '(scott-theme scott-weather scott-openrouter scott-modeline scott-launcher scott-pi))
  (require feature nil :no-error))
;; App launcher — the EWM s-d experience on every machine (C-c o works
;; under EWM too; s-d remains on eminix).
(when (fboundp 'scott/launch-app)
  (global-set-key (kbd "C-c o") #'scott/launch-app))

;; Terminal in a buffer — the terminal answer on non-EWM machines (decided
;; 2026-08-04: a real terminal app can never be a buffer outside EWM's own
;; compositor, so vterm IS the "ghostty in a split"). C-u C-c t = new vterm.
;; Explicit autoload: the nix-installed package's autoloads don't reliably
;; reach the daemon session (observed 2026-08-04 — installed but M-x-less).
(autoload 'vterm "vterm" "Open a vterm terminal buffer." t)
(global-set-key (kbd "C-c t") #'vterm)

;; Keep TUI symbols on the character grid (Claude Code, 2026-08-04).
;; Measured against the 9px cell of JetBrainsMono Nerd Font, Claude Code emits
;; several symbols that render 11-14px wide, shoving the rest of the line right:
;; the media-control block (⏵ ⏸ ⏺ — mode indicators), ⎿ (tool-result corner),
;; ✔ ✘, ◻ ◼, and the dingbat + braille spinner frames. No available font fixes
;; this: nothing in nixpkgs draws that block at cell width, set-fontset-font is
;; inert on this pgtk/ftcrhb build, and a proportional fallback cannot be
;; rescaled to a fixed advance (one factor that fits ⏺ shrinks ⏵ to 5px).
;; A display table sidesteps fonts entirely — redisplay substitutes a glyph
;; JetBrains already draws at exactly 9px. Buffer text is untouched (copy/paste
;; and search still see the original char); this is purely what gets painted.
(require 'disp-table)

(defvar scott/vterm-glyph-substitutions
  '((?⏴ . ?◀) (?⏵ . ?▶) (?⏸ . ?‖) (?⏹ . ?■) (?⏺ . ?●)
    (?⎿ . ?└) (?✔ . ?✓) (?✘ . ?✗) (?◻ . ?□) (?◼ . ?■))
  "Alist of (WIDE-CHAR . CELL-WIDTH-CHAR) substitutions for vterm buffers.
Each cdr is verified to render at the default face's cell width.")

(defun scott/vterm-fix-glyph-widths ()
  "Remap off-grid TUI symbols to cell-width glyphs in the current buffer."
  (let ((dt (make-display-table)))
    (pcase-dolist (`(,from . ,to) scott/vterm-glyph-substitutions)
      (aset dt from (vector (make-glyph-code to))))
    ;; Spinner frames: the dingbat (✳..✿) and braille (⠀..⣿) animations cycle
    ;; through glyphs of differing widths, so the whole line jitters each tick.
    ;; Collapse each set to one static cell-width mark.
    (dotimes (i (1+ (- #x273F #x2733)))
      (aset dt (+ #x2733 i) (vector (make-glyph-code ?*))))
    (dotimes (i (1+ (- #x28FF #x2800)))
      (aset dt (+ #x2800 i) (vector (make-glyph-code ?·))))
    (setq buffer-display-table dt)))

(add-hook 'vterm-mode-hook #'scott/vterm-fix-glyph-widths)

;; Frame title must ALWAYS contain "emacs": GlazeWM's ignore rule on the
;; work laptop matches WSLg windows by title to leave the Emacs frame
;; unmanaged (the default title is bare "%b" once a second frame exists,
;; which would silently re-enroll Emacs into tiling). Harmless elsewhere.
(setq frame-title-format '("%b — emacs@" system-name))
(when (fboundp 'scott/theme-init)
  (scott/theme-init))
(when (fboundp 'scott/modeline-mode)
  (scott/modeline-mode 1))

;; Slots are generic: no app or name is tied to a number. Apps launch into
;; whatever slot you're on (e.g. `s-w' → Firefox), and you name slots yourself
;; with `s-r'.

;; Window-management commands, extracted 2026-08-10 to lisp/scott-ewm-slots.el
;; so fallback.el can require them too. See that file's header for why it must
;; not require `ewm'.
(require 'scott-ewm-slots nil :no-error)

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
    ;; Super+Enter: open Ghostty terminal (muscle memory from Hyprland).
    (define-key ewm-mode-map (kbd "s-<return>")
      (lambda ()
        (interactive)
        (start-process "ghostty" nil "ghostty")))
    ;; Super+Shift+Enter: open Pi agent in Ghostty.
    (define-key ewm-mode-map (kbd "s-S-<return>")
      (lambda ()
        (interactive)
        (start-process "ghostty-pi" nil "ghostty" "-e" "pi")))
    ;; Summon elisa (ask) from ANY slot. It must be a single intercepted key:
    ;; the C-c i prefix can't reach Emacs from a focused Wayland surface (the
    ;; follow-up key goes to the surface). C-c i still gives the full command
    ;; set when a native Emacs frame is focused.
    (when (fboundp 'scott/elisa-ask)
      (define-key ewm-mode-map (kbd "s-i") #'scott/elisa-ask))
    (when (fboundp 'ewm--send-intercept-keys)
      (ewm--send-intercept-keys))))
