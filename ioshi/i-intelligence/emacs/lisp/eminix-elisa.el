;;; eminix-elisa.el --- elisa: the eminix distribution assistant -*- lexical-binding: t; -*-
;; Local, config-aware Emacs/Linux/NixOS assistant. RAG via a sqlite-vec fork
;; of ELISA + ellama, served by a local Ollama. See
;; docs/superpowers/specs/2026-07-18-ni-eminix-assistant-design.md.
;;
;; ELISA is loaded LAZILY (first elisa command) so daemon start never blocks on
;; Ollama: requiring elisa builds its embeddings table, which calls the
;; embedding model. By first-use time the Ollama user service is up.

(require 'llm-ollama)

(defgroup eminix-elisa nil "elisa, the eminix assistant." :group 'tools)

(defconst eminix/elisa-models '("qwen2.5-coder:3b" "qwen2.5:7b")
  "Chat models elisa can toggle; car is the default (snappy, RAG-grounded).
The 3b coder is code-focused and lightweight; the 7b is general-purpose
for broader Emacs/NixOS/Linux questions (needs more RAM).")

(defvar eminix/elisa-model (car eminix/elisa-models)
  "Current elisa chat model.")

(defcustom eminix/elisa-collections '("/home/eminix/dotfiles" "builtin manuals")
  "Default-on collections elisa retrieves from (dir path = collection name)."
  :type '(repeat string) :group 'eminix-elisa)

(defcustom eminix/elisa-org-directory "/home/eminix/docs/org"
  "org-roam vault; indexed only by `eminix/elisa-ask-notes' (default-off)."
  :type 'directory :group 'eminix-elisa)

(defcustom eminix/elisa-nixpkgs-path nil
  "Optional nixpkgs checkout to index (default-off; huge)."
  :type '(choice (const nil) directory) :group 'eminix-elisa)

(defvar eminix/elisa--ready nil)

(defun eminix/elisa--provider ()
  (make-llm-ollama :chat-model eminix/elisa-model
                   :embedding-model "nomic-embed-text"))

(defun eminix/elisa--ollama-running-p ()
  "Return non-nil if Ollama is reachable on localhost:11434."
  (ignore-errors
    (with-current-buffer (url-retrieve-synchronously
                          "http://localhost:11434/api/tags" nil nil 1)
      (let ((status (buffer-substring
                     (point-min)
                     (line-end-position))))
        (kill-buffer)
        (string-prefix-p "HTTP/1.1 200" status)))))

(defun eminix/elisa--setup ()
  "Load ELISA and point it at Ollama + the elisa framing. Idempotent."
  (unless (eminix/elisa--ollama-running-p)
    (user-error "Ollama is not running — start it with `ollama serve' or systemctl --user start ollama"))
  (require 'elisa)
  ;; ELISA calls `ellama-context-add-*-quote-noninteractive', which live in
  ;; ellama-context.el and are NOT autoloaded (ellama only requires that file
  ;; lazily inside its own commands). Load it so those calls aren't void.
  (require 'ellama-context)
  (setq elisa-chat-provider (eminix/elisa--provider)
        elisa-embeddings-provider (make-llm-ollama :embedding-model "nomic-embed-text")
        elisa-sqlite-vec-path (or elisa-sqlite-vec-path (getenv "ELISA_VEC0_PATH"))
        elisa-chat-prompt-template
        (concat
         "You are elisa, the eminix distribution assistant. eminix is a NixOS + EWM "
         "(Emacs Wayland) laptop. Answer about Emacs, Elisp, Linux, and NixOS, "
         "grounded strictly in the context above. Prefer the user's own dotfiles "
         "and this machine's actual NixOS options over generic advice. "
         "Say \"not enough data\" if the context does not answer it. User query:\n%s"))
  (setq eminix/elisa--ready t))

;;;###autoload
(defun eminix/elisa-ask (prompt)
  "Ask elisa a question, retrieving from `eminix/elisa-collections'."
  (interactive "selisa> ")
  (unless eminix/elisa--ready (eminix/elisa--setup))
  (elisa-chat prompt eminix/elisa-collections))

;;;###autoload
(defun eminix/elisa-reindex ()
  "Re-embed elisa's default collections (incremental)."
  (interactive)
  (unless eminix/elisa--ready (eminix/elisa--setup))
  (elisa-parse-builtin-manuals)
  (elisa-async-parse-directory "/home/eminix/dotfiles")
  (when eminix/elisa-nixpkgs-path
    (elisa-async-parse-directory eminix/elisa-nixpkgs-path))
  (message "elisa: reindexing collections in the background"))

;;;###autoload
(defun eminix/elisa-reindex-notes ()
  "Re-embed the org-roam vault (incremental)."
  (interactive)
  (unless eminix/elisa--ready (eminix/elisa--setup))
  (elisa-async-parse-directory eminix/elisa-org-directory)
  (message "elisa: reindexing notes in the background"))

;;;###autoload
(defun eminix/elisa-toggle-model ()
  "Flip the elisa chat model between 3b and 7b."
  (interactive)
  (setq eminix/elisa-model
        (if (string= eminix/elisa-model (car eminix/elisa-models))
            (cadr eminix/elisa-models) (car eminix/elisa-models)))
  (when eminix/elisa--ready (setq elisa-chat-provider (eminix/elisa--provider)))
  (message "elisa model: %s" eminix/elisa-model))

;;;###autoload
(defun eminix/elisa-ask-notes (prompt)
  "Ask elisa against the org-roam vault only (personal notes).
Note: run `eminix/elisa-reindex-notes' first if you've added new notes."
  (interactive "selisa notes> ")
  (unless eminix/elisa--ready (eminix/elisa--setup))
  (elisa-chat prompt (list eminix/elisa-org-directory)))

(defvar eminix/elisa-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "i") #'eminix/elisa-ask)
    (define-key m (kbd "r") #'eminix/elisa-reindex)
    (define-key m (kbd "R") #'eminix/elisa-reindex-notes)
    (define-key m (kbd "m") #'eminix/elisa-toggle-model)
    (define-key m (kbd "n") #'eminix/elisa-ask-notes)
    m)
  "elisa command map.")
(global-set-key (kbd "C-c i") eminix/elisa-map)

(provide 'eminix-elisa)
;;; eminix-elisa.el ends here
