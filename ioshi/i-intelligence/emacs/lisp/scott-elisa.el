;;; scott-elisa.el --- elisa: the eminix distribution assistant -*- lexical-binding: t; -*-
;; Local, config-aware Emacs/Linux/NixOS assistant. RAG via a sqlite-vec fork
;; of ELISA + ellama, served by a local Ollama. See
;; docs/superpowers/specs/2026-07-18-ni-eminix-assistant-design.md.
;;
;; ELISA is loaded LAZILY (first elisa command) so daemon start never blocks on
;; Ollama: requiring elisa builds its embeddings table, which calls the
;; embedding model. By first-use time the Ollama user service is up.

(require 'llm-ollama)

(defgroup scott-elisa nil "elisa, the eminix assistant." :group 'tools)

(defconst scott/elisa-models '("qwen2.5-coder:3b" "qwen2.5-coder:7b")
  "Chat models elisa can toggle; car is the default (snappy, RAG-grounded).")

(defvar scott/elisa-model (car scott/elisa-models)
  "Current elisa chat model.")

(defcustom scott/elisa-collections '("/home/scott/dotfiles" "builtin manuals")
  "Default-on collections elisa retrieves from (dir path = collection name)."
  :type '(repeat string) :group 'scott-elisa)

(defcustom scott/elisa-org-directory "/home/scott/docs/org"
  "org-roam vault; indexed only by `scott/elisa-ask-notes' (default-off)."
  :type 'directory :group 'scott-elisa)

(defcustom scott/elisa-nixpkgs-path nil
  "Optional nixpkgs checkout to index (default-off; huge)."
  :type '(choice (const nil) directory) :group 'scott-elisa)

(defvar scott/elisa--ready nil)

(defun scott/elisa--provider ()
  (make-llm-ollama :chat-model scott/elisa-model
                   :embedding-model "nomic-embed-text"))

(defun scott/elisa--setup ()
  "Load ELISA and point it at Ollama + the elisa framing. Idempotent."
  (require 'elisa)
  (setq elisa-chat-provider (scott/elisa--provider)
        elisa-embeddings-provider (make-llm-ollama :embedding-model "nomic-embed-text")
        elisa-chat-prompt-template
        (concat
         "You are elisa, the eminix distribution assistant. eminix is a NixOS + EWM "
         "(Emacs Wayland) laptop. Answer about Emacs, Elisp, Linux, and NixOS, "
         "grounded strictly in the context above. Prefer the user's own dotfiles "
         "and this machine's actual NixOS options over generic advice. "
         "Say \"not enough data\" if the context does not answer it. User query:\n%s"))
  (setq scott/elisa--ready t))

;;;###autoload
(defun scott/elisa-ask (prompt)
  "Ask elisa a question, retrieving from `scott/elisa-collections'."
  (interactive "sni> ")
  (unless scott/elisa--ready (scott/elisa--setup))
  (elisa-chat prompt scott/elisa-collections))

;;;###autoload
(defun scott/elisa-reindex ()
  "Re-embed elisa's default collections (incremental)."
  (interactive)
  (unless scott/elisa--ready (scott/elisa--setup))
  (elisa-parse-builtin-manuals)
  (elisa-async-parse-directory "/home/scott/dotfiles")
  (when scott/elisa-nixpkgs-path
    (elisa-async-parse-directory scott/elisa-nixpkgs-path))
  (message "elisa: reindexing collections in the background"))

;;;###autoload
(defun scott/elisa-toggle-model ()
  "Flip the elisa chat model between 3b and 7b."
  (interactive)
  (setq scott/elisa-model
        (if (string= scott/elisa-model (car scott/elisa-models))
            (cadr scott/elisa-models) (car scott/elisa-models)))
  (when scott/elisa--ready (setq elisa-chat-provider (scott/elisa--provider)))
  (message "elisa model: %s" scott/elisa-model))

;;;###autoload
(defun scott/elisa-ask-notes (prompt)
  "Ask elisa against the org-roam vault only (personal notes)."
  (interactive "sni notes> ")
  (unless scott/elisa--ready (scott/elisa--setup))
  (elisa-async-parse-directory scott/elisa-org-directory)
  (elisa-chat prompt (list scott/elisa-org-directory)))

(defvar scott/elisa-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "i") #'scott/elisa-ask)
    (define-key m (kbd "r") #'scott/elisa-reindex)
    (define-key m (kbd "m") #'scott/elisa-toggle-model)
    (define-key m (kbd "n") #'scott/elisa-ask-notes)
    m)
  "elisa command map.")
(global-set-key (kbd "C-c i") scott/elisa-map)

(provide 'scott-elisa)
;;; scott-elisa.el ends here
