;;; emanix-arc.el --- arc: the emanix distribution assistant -*- lexical-binding: t; -*-

;; Local, offline, config-aware oracle for Emacs, Elisp, Linux, NixOS and the
;; org-roam vault.  RAG over this machine's own configuration through
;; sqlite-vec, answered by a local Ollama.  arc itself lives in its own repo
;; (scott-whitson/arc) and is packaged by emacs/packages.nix; this file is
;; only the distro glue that points arc at THIS machine.

;; Replaces emanix-elisa.el.  Two things that file got wrong, which this one
;; exists not to repeat:
;;
;;   1. It hardcoded /home/emanix/dotfiles and /home/emanix/docs/org --
;;      paths that exist on no machine here.  The config corpus was
;;      therefore never indexed for six weeks and nothing ever said so:
;;      elisa answered from the Emacs manuals alone and looked fine doing
;;      it.  Every path below is derived from $HOME, and checks/arc-glue.nix
;;      fails the build if one of them stops existing.
;;
;;   2. arc's own upstream defaults still name the collection, and its
;;      projects directory, after the distro's PRE-RENAME name -- a
;;      directory that no longer exists on any host here.  Both the
;;      directory alist and the index plan are therefore overridden below
;;      rather than inherited.  checks/arc-glue.nix fails the build if that
;;      old name reappears in this file, or if either override goes missing
;;      and arc silently falls back to indexing nothing.
;;
;; arc is required eagerly, unlike elisa.  It is safe: `arc-db' opens the
;; database lazily on first query, and constructing the llm-ollama providers
;; contacts nothing.  Nothing here touches Ollama at load time, so daemon
;; start does not block on it.

(require 'arc nil :no-error)
;; arc-eval.el carries an autoload cookie but no arc module requires it, so
;; `M-x arc-eval' would be void until something loaded the file. It is the
;; retrieval measurement harness -- small, and the whole point is that it is
;; there when a retrieval change needs justifying rather than guessing.
;; `arc-eval-set-file' already defaults to ~/docs/org/arc-eval.eld, which is
;; where this machine's question set lives, deliberately outside the public
;; arc repo.
(require 'arc-eval nil :no-error)
;; Keep the mutable half of the corpus current: re-index a saved file arc
;; already knows, and sweep for drift on an idle timer. The sweep is the half
;; that matters here -- this machine's dotfiles and vault change from git
;; pulls and Syncthing as much as from editing, and neither fires
;; `after-save-hook'. Derived collections (options, manuals) are deliberately
;; never auto-rebuilt; see arc-watch.el's commentary.
(require 'arc-watch nil :no-error)
;; The document-level retrieval UI is newer than the pinned ARC package. Keep
;; this optional so the distro can boot with the old answer-oriented package
;; while the ARC pin catches up.
(require 'arc-search-ui nil :no-error)

(defgroup emanix-arc nil
  "arc, the emanix distribution assistant."
  :group 'tools)

;;; Corpus -------------------------------------------------------------------

(when (featurep 'arc)
  (setq
   ;; $HOME-derived, never an absolute home path.  The "emanix" entry
   ;; replaces arc's stale pre-rename default.
   arc-collection-directory-alist
   `(("dotfiles" . ,(expand-file-name "dotfiles" (getenv "HOME")))
     ("emanix"   . ,(expand-file-name "projects/emanix" (getenv "HOME")))
     ("vault"    . ,(expand-file-name "docs/org" (getenv "HOME"))))

   arc-index-plan
   '(("dotfiles" . file) ("emanix" . file) ("vault" . org)
     ("nix options" . nixopt) ("hm options" . hmopt)
     ("builtin manuals" . info))

   ;; arc ships with only ("builtin manuals") enabled, which would make
   ;; `C-c i i' answer Emacs questions and know nothing about this machine --
   ;; the whole point of the thing.  Enable the full corpus.
   arc-enabled-collections
   '("dotfiles" "emanix" "vault" "nix options" "hm options" "builtin manuals")))

;; Deliberately NOT set, because arc's own defaults are already correct for
;; this machine and duplicating them here would just be somewhere else to
;; drift from:
;;
;;   arc-nixopt-flake / arc-hm-flake  -- both default to ~/dotfiles, which is
;;                                       the flake nixos-rebuild actually
;;                                       builds (#rafik lives there).
;;   arc-vault-collections            -- ("vault")
;;   arc-option-collections           -- ("nix options" "hm options")
;;   arc-chat-models                  -- ("qwen2.5-coder:3b" "qwen2.5:7b"),
;;                                       matching ollama.nix's loadModels in
;;                                       the dotfiles flake.  Those two lists
;;                                       are the one duplication left; if
;;                                       they ever disagree, ollama.nix wins,
;;                                       because it is what is actually
;;                                       pulled.

;;; Capture ------------------------------------------------------------------

(defcustom emanix/arc-capture-target
  (expand-file-name "docs/org/arc.org" (getenv "HOME"))
  "Org file that `w' in the arc answer buffer files answers into."
  :type 'file :group 'emanix-arc)

(defun emanix/arc-capture (text)
  "File TEXT, one arc answer subtree, into `emanix/arc-capture-target'.
TEXT arrives as a `**' question heading, the answer body, and a
`Sources' subtree, so appending it to a file yields a readable log
without any template.  arc refuses to guess where notes live -- that
assumption is what let the elisa path bug ship -- so this function is
what makes the `w' key do anything at all."
  (let ((file emanix/arc-capture-target))
    (with-current-buffer (find-file-noselect file)
      (save-excursion
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert text)
        (unless (bolp) (insert "\n")))
      (save-buffer))
    (message "arc: captured to %s" (abbreviate-file-name file))))

(when (and (featurep 'arc) (boundp 'arc-ui-capture-function))
  (setq arc-ui-capture-function #'emanix/arc-capture))

;;; Commands and keys --------------------------------------------------------

(defun emanix/arc--ollama-running-p ()
  "Return non-nil when Ollama answers on localhost:11434."
  (ignore-errors
    (with-current-buffer (url-retrieve-synchronously
                          "http://localhost:11434/api/tags" nil nil 1)
      (let ((status (buffer-substring (point-min) (line-end-position))))
        (kill-buffer)
        (string-prefix-p "HTTP/1.1 200" status)))))

;;;###autoload
(defun emanix/arc-ask (prompt)
  "Ask arc PROMPT through the pinned answer-oriented ARC package.
This is the compatibility fallback while the newer retrieval surface is
absent. EWM binds `s-i' to `emanix/arc-search', not to this function, so
that one intercepted key can move to retrieval without changing again."
  (interactive "sarc> ")
  (unless (fboundp 'arc-ask)
    (user-error "arc is not installed: `arc-ask' is not defined"))
  (unless (emanix/arc--ollama-running-p)
    (user-error "Ollama is not running -- start it with `systemctl --user start ollama'"))
  (arc-ask prompt))

(defun emanix/arc-search (prompt)
  "Search ARC for PROMPT, falling back to the old answer path.
The document-level `arc-search-show' surface is present only in newer ARC
revisions. Keep the old `arc-ask' path available until Emanix's package pin
catches up, but make the distro-owned command the only binding target."
  (interactive "sarc search> ")
  (if (fboundp 'arc-search-show)
      (arc-search-show prompt)
    (emanix/arc-ask prompt)))

(defun emanix/arc--scope-preset (name)
  "Return the ARC scope preset NAME, or nil when it is unavailable.
The presets are the current scoped-retrieval surface. They replaced the
per-concern collection variables (`arc-vault-collections',
`arc-option-collections') that the old answer commands read, so a preset is
the only way to scope a search on the pinned ARC. `arc.el' requires
`arc-scope', so both the variable and the constructor are present whenever
arc itself is."
  (and (boundp 'arc-scope-presets)
       (alist-get name arc-scope-presets nil nil #'equal)))

(defun emanix/arc--scoped-search (prompt scope fallback)
  "Search PROMPT in SCOPE, or invoke FALLBACK when neither is available.
SCOPE is an arc scope plist or nil. A partial new ARC surface must never
silently broaden a scoped request to the whole corpus, so a nil scope is an
error rather than an unscoped search."
  (cond
   ((and (fboundp 'arc-search-show) scope)
    (arc-search-show prompt scope))
   ((fboundp fallback)
    (funcall fallback prompt))
   (t
    (user-error "arc: scoped retrieval is unavailable"))))

(defun emanix/arc-search-vault (prompt)
  "Search the org-roam vault, with the pinned ARC answer fallback."
  (interactive "sarc vault> ")
  (emanix/arc--scoped-search prompt
                             (emanix/arc--scope-preset "vault")
                             #'arc-ask-vault))

(defun emanix/arc-search-options (prompt)
  "Search NixOS and Home Manager options, with the pinned ARC fallback."
  (interactive "sarc options> ")
  (emanix/arc--scoped-search prompt
                             (emanix/arc--scope-preset "options")
                             #'arc-ask-options))

(defun emanix/arc-reindex ()
  "Reindex ARC's configured corpus when the command exists."
  (interactive)
  (if (fboundp 'arc-reindex-all)
      (call-interactively #'arc-reindex-all)
    (user-error "arc: reindex command is unavailable")))

(defun emanix/arc-cancel-reindex ()
  "Cancel ARC's running reindex when the command exists."
  (interactive)
  (if (fboundp 'arc-reindex-cancel)
      (call-interactively #'arc-reindex-cancel)
    (user-error "arc: reindex cancellation is unavailable")))

(defvar emanix/arc-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "i") #'emanix/arc-search)
    (define-key map (kbd "n") #'emanix/arc-search-vault)
    (define-key map (kbd "o") #'emanix/arc-search-options)
    (define-key map (kbd "R") #'emanix/arc-reindex)
    (define-key map (kbd "c") #'emanix/arc-cancel-reindex)
    map)
  "Emanix-owned ARC prefix map.
ARC's own answer command map is an implementation detail of the old package;
keeping this map here lets the distro own the key contract across the
retrieval-only transition. Every command has a compatibility fallback where
the old pinned package can provide one.")

(when (featurep 'arc)
  (keymap-set global-map "C-c i" emanix/arc-command-map))

(when (featurep 'arc-watch)
  (arc-watch-mode 1))

(provide 'emanix-arc)
;;; emanix-arc.el ends here
