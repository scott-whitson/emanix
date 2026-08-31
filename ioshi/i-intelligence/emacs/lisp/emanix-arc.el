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
;;      it.  Every path below is derived from $HOME, and checks/arc-paths.nix
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

(when (featurep 'arc)
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
  "Ask arc PROMPT, checking Ollama first so the failure names its cause.
EWM binds this to `s-i', reachable from any slot -- the `C-c i' prefix
cannot be completed from a focused Wayland surface, because the
follow-up key goes to the surface rather than to Emacs.

`C-c i i' calls `arc-ask' directly instead of this, and a down Ollama
surfaces there as \"arc: retrieval failed\" rendered into the answer
buffer.  That is a real error path, not a silent one, so it is left
alone rather than wrapped."
  (interactive "sarc> ")
  (unless (fboundp 'arc-ask)
    (user-error "arc is not installed: `arc-ask' is not defined"))
  (unless (emanix/arc--ollama-running-p)
    (user-error "Ollama is not running -- start it with `systemctl --user start ollama'"))
  (arc-ask prompt))

;; arc's own prefix map, bound whole rather than mirrored, so a key added to
;; arc upstream arrives here without this file needing an edit.  Today that
;; is: i ask, n vault only, o options only, m toggle chat model, R reindex,
;; c cancel a running reindex.
(when (featurep 'arc)
  (keymap-set global-map "C-c i" arc-command-map))

(when (featurep 'arc-watch)
  (arc-watch-mode 1))

(provide 'emanix-arc)
;;; emanix-arc.el ends here
