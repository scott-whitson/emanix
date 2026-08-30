;;; emanix-elisa.el --- elisa: the emanix distribution assistant -*- lexical-binding: t; -*-
;; Local, config-aware Emacs/Linux/NixOS assistant. RAG via a sqlite-vec fork
;; of ELISA + ellama, served by a local Ollama. See
;; docs/superpowers/specs/2026-07-18-ni-emanix-assistant-design.md.
;;
;; ELISA is loaded LAZILY (first elisa command) so daemon start never blocks on
;; Ollama: requiring elisa builds its embeddings table, which calls the
;; embedding model. By first-use time the Ollama user service is up.

(require 'llm-ollama)

(defgroup emanix-elisa nil "elisa, the emanix assistant." :group 'tools)

(defconst emanix/elisa-models '("qwen2.5-coder:3b" "qwen2.5:7b")
  "Chat models elisa can toggle; car is the default (snappy, RAG-grounded).
The 3b coder is code-focused and lightweight; the 7b is general-purpose
for broader Emacs/NixOS/Linux questions (needs more RAM).")

(defvar emanix/elisa-model (car emanix/elisa-models)
  "Current elisa chat model.")

(defcustom emanix/elisa-collections '("/home/emanix/dotfiles" "builtin manuals")
  "Default-on collections elisa retrieves from (dir path = collection name)."
  :type '(repeat string) :group 'emanix-elisa)

(defcustom emanix/elisa-org-directory "/home/emanix/docs/org"
  "org-roam vault; indexed only by `emanix/elisa-ask-notes' (default-off)."
  :type 'directory :group 'emanix-elisa)

(defcustom emanix/elisa-nixpkgs-path nil
  "Optional nixpkgs checkout to index (default-off; huge)."
  :type '(choice (const nil) directory) :group 'emanix-elisa)

(defvar emanix/elisa--ready nil)

(defun emanix/elisa--provider ()
  (make-llm-ollama :chat-model emanix/elisa-model
                   :embedding-model "nomic-embed-text"))

(defun emanix/elisa--ollama-running-p ()
  "Return non-nil if Ollama is reachable on localhost:11434."
  (ignore-errors
    (with-current-buffer (url-retrieve-synchronously
                          "http://localhost:11434/api/tags" nil nil 1)
      (let ((status (buffer-substring
                     (point-min)
                     (line-end-position))))
        (kill-buffer)
        (string-prefix-p "HTTP/1.1 200" status)))))

(defun emanix/elisa--setup ()
  "Load ELISA and point it at Ollama + the elisa framing. Idempotent."
  (unless (emanix/elisa--ollama-running-p)
    (user-error "Ollama is not running — start it with `ollama serve' or systemctl --user start ollama"))
  (require 'elisa)
  ;; ELISA calls `ellama-context-add-*-quote-noninteractive', which live in
  ;; ellama-context.el and are NOT autoloaded (ellama only requires that file
  ;; lazily inside its own commands). Load it so those calls aren't void.
  (require 'ellama-context)
  (setq elisa-chat-provider (emanix/elisa--provider)
        elisa-embeddings-provider (make-llm-ollama :embedding-model "nomic-embed-text")
        elisa-sqlite-vec-path (or elisa-sqlite-vec-path (getenv "ELISA_VEC0_PATH"))
        elisa-chat-prompt-template
        (concat
         "You are elisa, the emanix distribution assistant. emanix is a NixOS + EWM "
         "(Emacs Wayland) laptop. Answer about Emacs, Elisp, Linux, and NixOS, "
         "grounded strictly in the context above. Prefer the user's own dotfiles "
         "and this machine's actual NixOS options over generic advice. "
         "Say \"not enough data\" if the context does not answer it. User query:\n%s"))
  (setq emanix/elisa--ready t))

;;;###autoload
(defun emanix/elisa-ask (prompt)
  "Ask elisa a question, retrieving from `emanix/elisa-collections'."
  (interactive "selisa> ")
  (unless emanix/elisa--ready (emanix/elisa--setup))
  (elisa-chat prompt emanix/elisa-collections))

;;;###autoload
(defun emanix/elisa-reindex ()
  "Re-embed elisa's default collections (incremental)."
  (interactive)
  (unless emanix/elisa--ready (emanix/elisa--setup))
  (elisa-parse-builtin-manuals)
  (elisa-async-parse-directory "/home/emanix/dotfiles")
  (when emanix/elisa-nixpkgs-path
    (elisa-async-parse-directory emanix/elisa-nixpkgs-path))
  (message "elisa: reindexing collections in the background"))

;;;###autoload
(defun emanix/elisa-reindex-notes ()
  "Re-embed the org-roam vault (incremental)."
  (interactive)
  (unless emanix/elisa--ready (emanix/elisa--setup))
  (elisa-async-parse-directory emanix/elisa-org-directory)
  (message "elisa: reindexing notes in the background"))

;;;###autoload
(defun emanix/elisa-toggle-model ()
  "Flip the elisa chat model between 3b and 7b."
  (interactive)
  (setq emanix/elisa-model
        (if (string= emanix/elisa-model (car emanix/elisa-models))
            (cadr emanix/elisa-models) (car emanix/elisa-models)))
  (when emanix/elisa--ready (setq elisa-chat-provider (emanix/elisa--provider)))
  (message "elisa model: %s" emanix/elisa-model))

;;;###autoload
(defun emanix/elisa-ask-notes (prompt)
  "Ask elisa against the org-roam vault only (personal notes).
Note: run `emanix/elisa-reindex-notes' first if you've added new notes."
  (interactive "selisa notes> ")
  (unless emanix/elisa--ready (emanix/elisa--setup))
  (elisa-chat prompt (list emanix/elisa-org-directory)))

(defvar emanix/elisa-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "i") #'emanix/elisa-ask)
    (define-key m (kbd "r") #'emanix/elisa-reindex)
    (define-key m (kbd "R") #'emanix/elisa-reindex-notes)
    (define-key m (kbd "m") #'emanix/elisa-toggle-model)
    (define-key m (kbd "n") #'emanix/elisa-ask-notes)
    m)
  "elisa command map.")
(global-set-key (kbd "C-c i") emanix/elisa-map)

(provide 'emanix-elisa)
;;; emanix-elisa.el ends here
