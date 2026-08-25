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
  ;; Defined in org.el. Declared here because the buffer-hygiene section sits
  ;; above the point where org is required.
  (defvar org-agenda-new-buffers)
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
;; eminix/tab-bar-status, not the mode-line.
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

(eminix-quarterly-open)
(eminix/calendar-sync)
(org-agenda nil \"w\")
(magit-status (getenv \"EMINIX\"))
(eminix/weather)
(eminix/openrouter-cost)
(call-interactively #'eminix/launch-app)
")

;; --- Buffer hygiene: kill buffers by named group ---
;;
;; Long-lived daemons accumulate buffers faster than you close them, and the
;; worst offender is any command that opens files to scan them — the org
;; agenda opens one buffer per agenda file. `eminix/org-agenda-release-buffers'
;; handles the case where you quit the agenda properly, but nothing cleans up
;; if you follow a TODO with RET and never go back.
;;
;; Emacs already ships `kill-matching-buffers-no-ask' (by regexp),
;; `clean-buffer-list' (by age) and ibuffer's filter groups. What it lacks is
;; a NAMED group behind a single prompt, including a "*" that wipes back to
;; roughly a fresh daemon without dropping the daemon.
;;
;; Every kill goes through `kill-buffer', so a modified file still offers to
;; save and a buffer with a live process still asks. No group, "*" included,
;; can silently lose work.

(defvar eminix/buffer-protect-names '("*scratch*" "*Messages*")
  "Buffer names `eminix/kill-buffer-group' will never kill.")

(defun eminix/buffer-protected-p (buf)
  "Non-nil if BUF must survive a group kill.
Buffers whose name begins with a space are protected wholesale. By Emacs
convention those are internal — the minibuffers, ` *server*', encoding
scratch space — and killing ` *server*' in a daemon takes emacsclient down
with it, which on this setup means every frame across every zellij session.
Nothing a user means by \"close my buffers\" lives in that namespace.

NOT VERIFIED: whether EWM represents client windows as buffers on the
graphical hosts. It appears to work in frames (`ewm-frame-new',
`ewm--focused-frame'), which the \"*\" group does not touch, but if a wipe
ever disturbs the window manager on rafik, add its buffers here."
  (or (eq buf (current-buffer))
      (minibufferp buf)
      (string-prefix-p " " (buffer-name buf))
      (member (buffer-name buf) eminix/buffer-protect-names)))

(defun eminix/buffer-under-p (buf dir)
  "Non-nil if BUF visits a file under DIR."
  (when-let* ((f (buffer-file-name buf)))
    (string-prefix-p (expand-file-name dir) (file-truename f))))

(defvar eminix/buffer-group-alist
  (list
   ;; The precise one: only what the last agenda run had to open.
   (cons "agenda" (lambda (buf) (memq buf org-agenda-new-buffers)))
   (cons "org"    (lambda (buf) (with-current-buffer buf (derived-mode-p 'org-mode))))
   (cons "dired"  (lambda (buf) (with-current-buffer buf (derived-mode-p 'dired-mode))))
   (cons "files"  (lambda (buf) (buffer-file-name buf)))
   ;; The wildcard: everything not protected.
   (cons "*"      (lambda (_buf) t)))
  "Alist of (NAME . PREDICATE) for `eminix/kill-buffer-group'.
PREDICATE is called with a buffer and returns non-nil to kill it.
Protected buffers (see `eminix/buffer-protected-p') are filtered out before
any predicate runs, so no group can reach them.  Consumers add their own
path-specific groups from the personal layer.")

(defun eminix/kill-buffer-group (name)
  "Kill every buffer matching the group NAME in `eminix/buffer-group-alist'."
  (interactive
   (list (completing-read "Kill buffer group: "
                          (mapcar #'car eminix/buffer-group-alist)
                          nil t)))
  (let ((pred (cdr (assoc name eminix/buffer-group-alist)))
        (killed 0))
    (unless pred (user-error "No such buffer group: %s" name))
    (dolist (buf (buffer-list))
      (when (and (not (eminix/buffer-protected-p buf))
                 (funcall pred buf)
                 (kill-buffer buf))
        (setq killed (1+ killed))))
    ;; Drop dead references, or `org-agenda-new-buffers' stops being a usable
    ;; count of what is actually open.
    (setq org-agenda-new-buffers (seq-filter #'buffer-live-p org-agenda-new-buffers))
    (message "Killed %d buffer%s in group %S" killed (if (= killed 1) "" "s") name)))

;; `C-c k' is meow-dispatch; `C-c K' is the super-kill.
(global-set-key (kbd "C-c K") #'eminix/kill-buffer-group)

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
;; Heading navigation — the "table of contents" for markdown and org buffers,
;; and imenu everywhere else. M-g already hosts goto-line, so this extends an
;; existing prefix rather than claiming a new one. Folding needs no binding:
;; markdown-mode already puts markdown-cycle on TAB and markdown-shifttab on
;; S-TAB, org-style.
(global-set-key (kbd "M-g i") #'consult-imenu)
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
(defun eminix-reboot ()
  "Reboot the system."
  (interactive)
  (when (yes-or-no-p "Reboot now? ")
    (start-process "reboot" nil "sudo" "reboot")))

(defun eminix-shutdown ()
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
;; Org-roam root. The default is the conventional ~/docs/org; consumers can
;; override org-directory/org-roam-directory in their personal layer.
(setq org-directory (expand-file-name "~/docs/org"))
(make-directory org-directory t)
(when (require 'org-roam nil :no-error)
  (setq org-roam-directory org-directory)
  (org-roam-db-autosync-mode 1)
  (global-set-key (kbd "C-c n f") #'org-roam-node-find)
  (global-set-key (kbd "C-c n i") #'org-roam-node-insert)
  (global-set-key (kbd "C-c n c") #'org-roam-capture))
(global-set-key (kbd "C-c a") #'org-agenda)

;; Release the org buffers the agenda opened for scanning.
;;
;; This replaces an earlier version that hung a kill-every-org-buffer function
;; on `org-agenda-quit-hook'. THAT HOOK DOES NOT EXIST — grep the org tree and
;; you get zero hits; org has never defined or run it. `add-hook' interns any
;; symbol handed to it without complaint, so the cleanup looked installed and
;; never fired once. Agenda scans leaked a buffer per agenda file, forever.
;;
;; The mechanism that does work is org's own. `org-get-agenda-file-buffer'
;; pushes onto `org-agenda-new-buffers' ONLY buffers it had to create; a file
;; already being visited is returned as-is and never recorded, so buffers the
;; user opened by hand are safe by construction. `org-release-buffers' kills
;; that list, offering to save anything modified first.
;;
;; `x' (org-agenda-exit) already does this. `q' (org-agenda-quit) and `Q'
;; (org-agenda-Quit) do not — hence the advice. Their shared chokepoint
;; `org-agenda--quit' is private, so we attach to the two public commands
;; instead and stay off org's internals. On the `x' path org has already
;; released and nulled the list, making the advice a harmless no-op.
(defun eminix/org-agenda-release-buffers (&rest _)
  "Release only the org buffers the agenda itself opened.
Buffers visited by hand are untouched."
  (org-release-buffers org-agenda-new-buffers)
  (setq org-agenda-new-buffers nil))
(advice-add 'org-agenda-quit :after #'eminix/org-agenda-release-buffers)
(advice-add 'org-agenda-Quit :after #'eminix/org-agenda-release-buffers)

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
;; Agenda file discovery is RECURSIVE. A bare directory in `org-agenda-files'
;; is expanded non-recursively by org, so the previous `(list org-directory)'
;; found only .org files sitting directly in the org root — none at all in a
;; vault that files its notes under subdirectories. Symptom: an empty
;; `C-c a t' with no error to explain it.
;;
;; Recomputed before every agenda build rather than once at startup: this
;; daemon runs for weeks and the list would go stale the first time org-roam
;; captured a new note.
(defun eminix/org-agenda-file-list ()
  "Every .org file under `org-directory', recursively.
Dot-directories are skipped — .stfolder (Syncthing) and .claude (tooling
state) hold no tasks.  The PREDICATE argument of
`directory-files-recursively' receives a full directory path rather than a
base name, hence the `file-name-nondirectory' before the prefix test."
  (directory-files-recursively
   (expand-file-name org-directory)
   "\\.org\\'" nil
   (lambda (dir)
     (not (string-prefix-p "." (file-name-nondirectory dir))))))

(defun eminix/org-refresh-agenda-files (&rest _)
  "Recompute `org-agenda-files' from the current state of the vault."
  (setq org-agenda-files (eminix/org-agenda-file-list)))

(eminix/org-refresh-agenda-files)
(advice-add 'org-agenda    :before #'eminix/org-refresh-agenda-files)
(advice-add 'org-todo-list :before #'eminix/org-refresh-agenda-files)
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

(defun eminix/calendar-sync ()
  "Launch the Python calendar sync tool."
  (interactive)
  (start-process-shell-command
   "calendar-sync" nil
   (expand-file-name "calendar-sync" (or (getenv "EMINIX_BIN_DIR") "")) "sync"))

(global-set-key (kbd "C-c c") #'eminix/calendar-sync)

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
  ;;    After a reboot that meant no top bar (eminix/modeline-mode), no s-d
  ;;    (eminix/launcher) and no EWM window commands (eminix/ewm--goto and
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
        ;; Sync into the org tree, not the package's ~/org/gdocs/ default.
        ;; That default mints a SECOND top-level org directory in $HOME, which
        ;; breaks the four-directory home rule (docs/dotfiles/downloads/
        ;; projects). Deleting the directory is not enough: gdocs--doc-file-path
        ;; calls make-directory on every open, so it comes straight back.
        ;; ~/docs/org is also Syncthing-replicated, so synced docs reach
        ;; datacore like the rest of the org tree.
        (setq gdocs-directory (expand-file-name "~/docs/org/gdocs/"))
        ;; Credentials live outside the checkout (mode 600) so the OAuth
        ;; client secret is never committed. Absent file = no account.
        (load (expand-file-name "gdocs-creds.el" user-emacs-directory)
              :noerror :nomessage))
    (message "gdocs not loadable; skipping (see the comment above)")))

;; --- Theme + custom surfaces (files appear as they are implemented) ---
(dolist (feature '(eminix-theme eminix-weather eminix-openrouter eminix-modeline eminix-launcher eminix-pi eminix-quarterly eminix-prose eminix-web))
  (require feature nil :no-error))
;; Prose rendering — markdown and org files read as documents, not source.
;; C-c z toggles back to raw monospace for heavy editing. Chosen 2026-08-17;
;; C-c a/b/c/d/e/f/i/m/n/o/q/t were already taken.
(when (fboundp 'eminix-prose-mode)
  (add-hook 'markdown-mode-hook #'eminix-prose-mode)
  (add-hook 'org-mode-hook #'eminix-prose-mode)
  (global-set-key (kbd "C-c z") #'eminix-prose-toggle))
;; Web languages — Jinja2 templates, HTML and CSS. Jinja2 here is all plain
;; .html under templates/ dirs, so eminix-web.el picks the mode on path.
;; Format-on-save is gated on the repo declaring its own djlint/prettier
;; config: 134 unconfigured templates would otherwise be rewritten wholesale
;; on first save. See docs/manual/01-keybindings.md for opting a repo in.
(when (fboundp 'eminix-web-setup)
  (eminix-web-setup))
;; Quarterly tracker — C-c q opens this quarter's note, C-u C-c q forces the
;; work one on a machine that has both trees.
(when (fboundp 'eminix-quarterly-open)
  (global-set-key (kbd "C-c q") #'eminix-quarterly-open))
;; App launcher — the EWM s-d experience on every machine (C-c o works
;; under EWM too; s-d remains on eminix).
(when (fboundp 'eminix/launch-app)
  (global-set-key (kbd "C-c o") #'eminix/launch-app))

;; Terminal in a buffer. The 2026-08-04 decision stands — a real terminal app
;; can never be a buffer outside EWM's own compositor — but the buffer terminal
;; is ghostel as of 2026-08-25, not vterm. libghostty-vt (the VT engine behind
;; Ghostty) through a native Zig module: ~4x vterm throughput, ~30fps vs ~10,
;; DEC 2026 synchronized output, real mouse passthrough to TUIs, and password
;; prompts intercepted via `read-passwd' instead of every character of a sudo
;; password landing in `view-lossage' and the recent-keys ring.
;;
;; This does NOT retire ghostty, which is installed on all three hosts and
;; remains the answer for shell and build work: it is an independent window
;; that survives an Emacs wedge, whereas a ghostel buffer rides Emacs's main
;; thread. Buffer terminal and window terminal are different jobs.
;;
;; C-u C-c t = new terminal (same as it did with vterm); a numeric prefix
;; (C-1 C-c t) switches to that numbered one. Explicit autoload for the same
;; reason as before: the nix-installed package's autoloads don't reliably reach
;; the daemon session (observed 2026-08-04 — installed but M-x-less).
;;
;; vterm stays in packages.nix and keeps its autoload as the fallback — ghostel
;; puts a native module in the critical path, and a broken one should cost a
;; terminal, not a working Emacs. Retire vterm only once ghostel has weeks on it.
(autoload 'vterm "vterm" "Open a vterm terminal buffer." t)
(autoload 'ghostel "ghostel" "Open a ghostel terminal buffer." t)
(global-set-key (kbd "C-c t") #'ghostel)

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

(defvar eminix/terminal-glyph-substitutions
  '((?⏴ . ?◀) (?⏵ . ?▶) (?⏸ . ?‖) (?⏹ . ?■) (?⏺ . ?●)
    (?⎿ . ?└) (?✔ . ?✓) (?✘ . ?✗) (?◻ . ?□) (?◼ . ?■))
  "Alist of (WIDE-CHAR . CELL-WIDTH-CHAR) substitutions for terminal buffers.
Each cdr is verified to render at the default face's cell width.")

(defun eminix/terminal-fix-glyph-widths ()
  "Remap off-grid TUI symbols to cell-width glyphs in the current buffer."
  (let ((dt (make-display-table)))
    (pcase-dolist (`(,from . ,to) eminix/terminal-glyph-substitutions)
      (aset dt from (vector (make-glyph-code to))))
    ;; Spinner frames: the dingbat (✳..✿) and braille (⠀..⣿) animations cycle
    ;; through glyphs of differing widths, so the whole line jitters each tick.
    ;; Collapse each set to one static cell-width mark.
    (dotimes (i (1+ (- #x273F #x2733)))
      (aset dt (+ #x2733 i) (vector (make-glyph-code ?*))))
    (dotimes (i (1+ (- #x28FF #x2800)))
      (aset dt (+ #x2800 i) (vector (make-glyph-code ?·))))
    (setq buffer-display-table dt)))

(add-hook 'vterm-mode-hook #'eminix/terminal-fix-glyph-widths)

;; Both backends need it. Those symbols are off-grid because of glyph advance
;; vs the 9px cell — a FONT problem, not a backend one — and neither vterm nor
;; ghostel remaps widths itself, so any TUI misaligns in both identically.
;; Hence the backend-neutral name: ghostel is the primary terminal and vterm the
;; fallback, so naming this after either one would be wrong within a release.
(add-hook 'ghostel-mode-hook #'eminix/terminal-fix-glyph-widths)

;; Claude Code IDE (trial, 2026-08-24) — Claude in an Emacs side window with
;; MCP access to xref/eglot, tree-sitter, imenu, project.el and flymake,
;; instead of the vterm → zellij → claude stack. Coexists with that stack;
;; nothing in zellij.nix or claude.nix changed.
;;
;; The package is a git checkout, not a store path: it is not on MELPA and is
;; early-development (v0.3.0), so `git pull' + restart updates it with no
;; rebuild. packages.nix carries only its deps (websocket, web-server,
;; transient) plus ghostel. The file-directory-p guard means a missing checkout
;; costs one keybinding rather than breaking the config.
;;
;; Autoload from "claude-code-ide", NOT from the file that defines the menu:
;; claude-code-ide-transient.el does not require claude-code-ide.el, so
;; autoloading the menu from there yields a menu whose every action is a void
;; function. claude-code-ide.el requires the transient file, so this direction
;; loads everything. Same explicit-autoload reasoning as vterm above.
;;
;; executeCode stays OFF. It is a bare `(eval (car (read-from-string code)) t)'
;; with no confirmation, allowlist or sandbox, it rides on the core tool list
;; rather than the optional tools server, and this daemon holds the work vault,
;; ecomms credentials, agenix buffers and push-capable magit.
(let ((cci (expand-file-name "~/.config/emacs/site-lisp/claude-code-ide.el")))
  (when (file-directory-p cci)
    (add-to-list 'load-path cci)
    (dolist (cmd '(claude-code-ide-menu claude-code-ide claude-code-ide-check-status))
      (autoload cmd "claude-code-ide" "Claude Code IDE." t))
    (global-set-key (kbd "C-c C-'") #'claude-code-ide-menu)
    (with-eval-after-load 'claude-code-ide
      (setq claude-code-ide-terminal-backend 'ghostel
            claude-code-ide-enable-execute-code nil)
      ;; The daemon runs under systemd, whose PATH has no ~/.local/bin — which
      ;; is exactly where Claude Code's native installer puts the binary. So a
      ;; bare "claude" resolves in an interactive shell and NOT in the daemon.
      ;; Point at it directly when it is there; leave the default alone if the
      ;; CLI is already on exec-path (a store-installed claude elsewhere).
      (unless (executable-find "claude")
        (let ((local (expand-file-name "~/.local/bin/claude")))
          (when (file-executable-p local)
            (setq claude-code-ide-cli-path local))))
      ;; Registers the xref/apropos/treesit/imenu/project tools and sets
      ;; claude-code-ide-enable-mcp-server non-nil itself.
      (claude-code-ide-emacs-tools-setup))))

;; Frame title must ALWAYS contain "emacs": GlazeWM's ignore rule on the
;; work laptop matches WSLg windows by title to leave the Emacs frame
;; unmanaged (the default title is bare "%b" once a second frame exists,
;; which would silently re-enroll Emacs into tiling). Harmless elsewhere.
(setq frame-title-format '("%b — emacs@" system-name))
(when (fboundp 'eminix/theme-init)
  (eminix/theme-init))
(when (fboundp 'eminix/modeline-mode)
  (eminix/modeline-mode 1))

;; Slots are generic: no app or name is tied to a number. Apps launch into
;; whatever slot you're on (e.g. `s-w' → Firefox), and you name slots yourself
;; with `s-r'.

;; Window-management commands, extracted 2026-08-10 to lisp/eminix-ewm-slots.el
;; so fallback.el can require them too. See that file's header for why it must
;; not require `ewm'.
(require 'eminix-ewm-slots nil :no-error)

;; Frame-global panel: system stats + clock + battery, rendered ONCE at the top
;; of the (full-screen, under EWM) frame — the actual bar.
(when (fboundp 'eminix/tab-bar-status)
  ;; Left: EWM slot list (eminix/ewm-tab-bar-slots, no-op off EWM).
  ;; Right: system stats + clock + battery.
  (setq tab-bar-format '(eminix/ewm-tab-bar-slots
                         tab-bar-format-align-right
                         eminix/tab-bar-status))
  (setq tab-bar-show t)   ; always show the panel, even with a single/zero tab
  (tab-bar-mode 1))

;; elisa — local, config-aware eminix assistant (Emacs/Linux/NixOS RAG via a
;; sqlite-vec ELISA fork + ellama + local Ollama). Binds the C-c i map.
(require 'eminix-elisa nil :no-error)

;; EWM-only session glue (swayidle/swaylock + touchpad) — no-op elsewhere.
;; EWM is loaded via `emacs --eval (require 'ewm)' which runs AFTER this init
;; file, so `(featurep 'ewm)' is still nil here: a plain `when' guard skips
;; the require and input/session glue never loads (symptom: tap-to-click and
;; swayidle silently absent, (fboundp 'eminix/ewm-start-swayidle) => nil).
;; Defer to the moment the ewm feature actually arrives; on non-EWM hosts it
;; never loads, so this stays a no-op there.
(with-eval-after-load 'ewm
  (require 'eminix-ewm nil :no-error)
  ;; Restart the compositor session. Global rather than in `ewm-mode-map': it
  ;; only needs to fire while emacs has focus, and it is deliberately a C-c
  ;; chord so a stray super key cannot end the session. Bound inside this
  ;; block so non-EWM hosts (whistle) never get a key that would kill an
  ;; emacs which is not a compositor.
  (global-set-key (kbd "C-c R") #'eminix/ewm-restart)
  (when (boundp 'ewm-mode-map)
    ;; Super+number restores the old workspace-switch rhythm, but in EWM frame
    ;; slots. Slots create on demand: super-3 opens/switches to slot 3.
    (dotimes (i 9)
      (let ((slot (1+ i)))
        (define-key ewm-mode-map (kbd (format "s-%d" slot))
          (lambda ()
            (interactive)
            (eminix/ewm-select-slot slot)))))
    (define-key ewm-mode-map (kbd "s-0")
      (lambda ()
        (interactive)
        (eminix/ewm-select-slot 10)))
    ;; Rename the current frame/slot in the top bar.
    (define-key ewm-mode-map (kbd "s-r") #'eminix/ewm-rename-workspace)
    ;; Close the current slot (manual lifecycle; no auto-close under EWM).
    ;; s-q mirrors Hyprland's `$mod, Q, killactive' muscle memory.
    (define-key ewm-mode-map (kbd "s-q") #'eminix/ewm-close-slot)
    ;; Launch Firefox into the current slot (was s-w under Hyprland).
    (define-key ewm-mode-map (kbd "s-w") #'eminix/ewm-launch-firefox)
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
    (when (fboundp 'eminix/elisa-ask)
      (define-key ewm-mode-map (kbd "s-i") #'eminix/elisa-ask))
    (when (fboundp 'ewm--send-intercept-keys)
      (ewm--send-intercept-keys))))

;; --- Consumer extension point ---
;; Personal elisp ships at ~/.config/emacs/personal.el (written by the
;; consuming flake's Home Manager config) and loads LAST, so it can override
;; anything above. Missing file = no-op; an error is logged, never fatal — a
;; signal here must not trip init.el's fallback (total desktop loss).
(condition-case err
    (load (locate-user-emacs-file "personal.el") :no-error :nomessage)
  (error (message "eminix: personal.el failed (%S)" err)))
