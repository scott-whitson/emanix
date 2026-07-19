;;; scott-ni.el --- ni: the eminix distribution assistant -*- lexical-binding: t; -*-
;; Local, config-aware Emacs/Linux/NixOS assistant. RAG via a sqlite-vec fork
;; of ELISA + ellama, served by a local Ollama. See
;; docs/superpowers/specs/2026-07-18-ni-eminix-assistant-design.md.
;;
;; ELISA is loaded LAZILY (first ni command) so daemon start never blocks on
;; Ollama: requiring elisa builds its embeddings table, which calls the
;; embedding model. By first-use time the Ollama user service is up.

(require 'llm-ollama)

(defgroup scott-ni nil "ni, the eminix assistant." :group 'tools)

(defconst scott/ni-models '("qwen2.5-coder:3b" "qwen2.5-coder:7b")
  "Chat models ni can toggle; car is the default (snappy, RAG-grounded).")

(defvar scott/ni-model (car scott/ni-models)
  "Current ni chat model.")

(defcustom scott/ni-collections '("/home/scott/dotfiles" "/etc/ni" "builtin manuals")
  "Default-on collections ni retrieves from (dir path = collection name)."
  :type '(repeat string) :group 'scott-ni)

(defcustom scott/ni-org-directory "/home/scott/docs/org"
  "org-roam vault; indexed only by `scott/ni-ask-notes' (default-off)."
  :type 'directory :group 'scott-ni)

(defcustom scott/ni-nixpkgs-path nil
  "Optional nixpkgs checkout to index (default-off; huge)."
  :type '(choice (const nil) directory) :group 'scott-ni)

(defvar scott/ni--ready nil)

(defun scott/ni--provider ()
  (make-llm-ollama :chat-model scott/ni-model
                   :embedding-model "nomic-embed-text"))

(defun scott/ni--setup ()
  "Load ELISA and point it at Ollama + the ni framing. Idempotent."
  (require 'elisa)
  (setq elisa-chat-provider (scott/ni--provider)
        elisa-embeddings-provider (make-llm-ollama :embedding-model "nomic-embed-text")
        elisa-chat-prompt-template
        (concat
         "You are ni, the eminix distribution assistant. eminix is a NixOS + EWM "
         "(Emacs Wayland) laptop. Answer about Emacs, Elisp, Linux, and NixOS, "
         "grounded strictly in the context above. Prefer the user's own dotfiles "
         "and this machine's actual NixOS options over generic advice. "
         "Say \"not enough data\" if the context does not answer it. User query:\n%s"))
  (setq scott/ni--ready t))

;;;###autoload
(defun scott/ni-ask (prompt)
  "Ask ni a question, retrieving from `scott/ni-collections'."
  (interactive "sni> ")
  (unless scott/ni--ready (scott/ni--setup))
  (elisa-chat prompt scott/ni-collections))

;;;###autoload
(defun scott/ni-reindex ()
  "Re-embed ni's default collections (incremental)."
  (interactive)
  (unless scott/ni--ready (scott/ni--setup))
  (elisa-parse-builtin-manuals)
  (elisa-async-parse-directory "/home/scott/dotfiles")
  (elisa-async-parse-directory "/etc/ni")
  (when scott/ni-nixpkgs-path
    (elisa-async-parse-directory scott/ni-nixpkgs-path))
  (message "ni: reindexing collections in the background"))

;;;###autoload
(defun scott/ni-toggle-model ()
  "Flip the ni chat model between 3b and 7b."
  (interactive)
  (setq scott/ni-model
        (if (string= scott/ni-model (car scott/ni-models))
            (cadr scott/ni-models) (car scott/ni-models)))
  (when scott/ni--ready (setq elisa-chat-provider (scott/ni--provider)))
  (message "ni model: %s" scott/ni-model))

;;;###autoload
(defun scott/ni-ask-notes (prompt)
  "Ask ni against the org-roam vault only (personal notes)."
  (interactive "sni notes> ")
  (unless scott/ni--ready (scott/ni--setup))
  (elisa-async-parse-directory scott/ni-org-directory)
  (elisa-chat prompt (list scott/ni-org-directory)))

(defvar scott/ni-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "i") #'scott/ni-ask)
    (define-key m (kbd "r") #'scott/ni-reindex)
    (define-key m (kbd "m") #'scott/ni-toggle-model)
    (define-key m (kbd "n") #'scott/ni-ask-notes)
    m)
  "ni command map.")
(global-set-key (kbd "C-c i") scott/ni-map)

(provide 'scott-ni)
;;; scott-ni.el ends here
