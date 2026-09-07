;;; emanix-agent-shell.el --- Claude Code and pi as Emacs buffers -*- lexical-binding: t; -*-
;;
;; agent-shell speaks ACP to a real Claude Code process, so the conversation is
;; an Emacs buffer and the agent is the CLI you already configured: CLAUDE.md,
;; ~/.claude/skills, plugins, hooks, subagents and settings permissions all
;; load, because the adapter passes settingSources ["user" "project" "local"].
;; Replaces claude-code-ide.el (a terminal in a side window) and emanix-pi.el
;; (pi in a separate Ghostty window).
;;
;; WHY THIS FILE CARRIES A BUFFER-SYNC PATCH
;;
;; ACP lets a client offer `fs/read_text_file' and `fs/write_text_file' so the
;; agent reads and writes the EDITOR's buffer, unsaved state included.
;; agent-shell offers both and implements them correctly -- its read handler
;; prefers `find-buffer-visiting' and its write handler uses
;; `replace-buffer-contents' on the live buffer.
;;
;; claude-agent-acp never calls them. Measured 2026-09-07: Emacs advertised
;; {"fs":{"readTextFile":true,"writeTextFile":true}} and a whole session that
;; successfully edited a file carried ZERO fs/* requests. The adapter defines
;; both methods and gates on clientCapabilities.fs nowhere. The ACP spec has
;; only a negative obligation -- MUST NOT call when the capability is absent --
;; and no duty to use it when present, so this does not self-heal. Gemini CLI
;; does gate on it correctly, which is what makes this an adapter gap rather
;; than a protocol one, and what makes a local patch worth writing.
;;
;; Consequence without a patch: the agent writes to disk while you edit a
;; buffer, and agent-shell has no fallback -- its only `revert-buffer' sits
;; inside the read handler that never fires, so the buffer goes stale in
;; silence.
;;
;; Everything below `--- buffer coherence ---' closes that in two directions.
;; It reads undocumented internals of a package whose author calls the API
;; unstable, so it is written to fail soft: a shape change costs the sync
;; feature, not a working Emacs.
;;
;; This file deliberately does NOT `require' agent-shell at top level. That
;; keeps the logic below loadable -- and unit-testable -- under a bare batch
;; Emacs, which is what checks/agent-shell-sync.nix relies on.

(require 'map)
(require 'seq)

;;; --- buffer coherence: shared logic ---

(defun emanix/agent-shell--tool-call-paths (tool-call)
  "Return the file paths named anywhere in TOOL-CALL, de-duplicated.

TOOL-CALL mixes two key styles and both must be read.  Its own fields use
KEYWORD keys (`:locations', `:raw-input', `:diffs'), while the JSON payloads
nested inside arrive as VECTORS of SYMBOL-keyed alists -- `:locations' is a
vector of ((path . \"...\") (line . 3)).  Reading only one style finds
nothing and reports nothing, which is precisely how this failed the first
time it was written."
  (let (paths)
    (dolist (d (map-elt tool-call :diffs))
      (when-let* ((p (map-elt d :file))) (push p paths)))
    (seq-doseq (loc (map-elt tool-call :locations))
      (when-let* ((p (map-elt loc 'path))) (push p paths)))
    (seq-doseq (c (map-elt tool-call :content))
      (when-let* ((p (map-elt c 'path))) (push p paths)))
    (when-let* ((p (map-nested-elt tool-call '(:raw-input file_path))))
      (push p paths))
    ;; Several fields routinely name the same file, and syncing twice per turn
    ;; is visible as a double flicker.
    (delete-dups (nreverse paths))))

(defun emanix/agent-shell--sync-from-disk (path)
  "Update the buffer visiting PATH from disk.

Return `synced', `skipped-dirty', or nil when no buffer visits PATH.

Two choices here are load-bearing:

`set-visited-file-modtime' MUST run before the buffer is touched.  The file
changed on disk underneath us, so any modification otherwise raises Emacs's
file-supersession threat -- which errors outright in batch and, worse, prompts
interactively and WEDGES A DAEMON on a question nobody can answer.

`replace-buffer-contents', never `revert-buffer'.  A revert would work and
would discard undo history, point and markers.  The minimal diff is the whole
reason an agent's edit is still undoable with \\[undo]."
  (let ((buf (find-buffer-visiting path)))
    (cond
     ((null buf) nil)
     ;; Refusing is the right default: silently overwriting unsaved work is
     ;; worse than saying so and letting the human reconcile.
     ((buffer-modified-p buf)
      (message "agent-shell: %s changed on disk but the buffer has unsaved edits"
               (buffer-name buf))
      'skipped-dirty)
     (t
      (let ((tmp (generate-new-buffer " *emanix-agent-shell-sync*")))
        (unwind-protect
            (progn
              (with-current-buffer tmp (insert-file-contents path))
              (with-current-buffer buf
                (set-visited-file-modtime)
                (save-restriction
                  (widen)
                  (replace-buffer-contents tmp 1.0))
                (set-buffer-modified-p nil)))
          (kill-buffer tmp)))
      'synced))))

(defun emanix/agent-shell--save-project-buffers (root)
  "Save modified file-visiting buffers under ROOT.  Return the paths saved.

This is the read half of the patch.  The agent reads from disk, so unsaved
buffers are invisible to it; saving first is the only way to be asked about
the text actually on screen.  The cost is real and is why the caller puts it
behind a defcustom: it commits your unsaved work on every prompt."
  (let ((root (file-name-as-directory (expand-file-name root)))
        saved)
    (dolist (buf (buffer-list))
      (with-current-buffer buf
        (when (and buffer-file-name
                   (buffer-modified-p)
                   (string-prefix-p root (expand-file-name buffer-file-name)))
          (save-buffer)
          (push buffer-file-name saved))))
    (nreverse saved)))

;;; --- buffer coherence: wiring ---

(defcustom emanix/agent-shell-save-before-prompt t
  "When non-nil, save modified project buffers before each agent prompt.

The agent reads files from disk, so without this it cannot see edits you
have not saved.  With it, every prompt commits your unsaved work -- which
entangles your edits with the agent's in file history and takes away \"type
freely, save when I mean it\".  That trade is real, so it is a setting
rather than a silent behaviour.

Unnecessary if `claude-agent-acp' ever honours ACP's client filesystem
capability; see this file's header."
  :type 'boolean
  :group 'emanix)

(defun emanix/agent-shell--on-tool-call-update (event)
  "Sync buffers named by a completed tool call in EVENT."
  (let ((tool-call (map-nested-elt event '(:data :tool-call))))
    (when (equal (map-elt tool-call :status) "completed")
      (dolist (path (emanix/agent-shell--tool-call-paths tool-call))
        (when (file-exists-p path)
          (emanix/agent-shell--sync-from-disk path))))))

(defun emanix/agent-shell--submit-advice (&rest _)
  "Save modified project buffers before submitting, per `emanix/agent-shell-save-before-prompt'."
  (when emanix/agent-shell-save-before-prompt
    (emanix/agent-shell--save-project-buffers default-directory)))

(defun emanix/agent-shell--install ()
  "Subscribe the current agent shell to tool-call updates.

Runs from `agent-shell-mode-hook', where upstream guarantees session state is
already available.  Wrapped so that an upstream event-shape change costs the
sync feature and not a working shell."
  (when (fboundp 'agent-shell-subscribe-to)
    (condition-case err
        (agent-shell-subscribe-to
         :shell-buffer (current-buffer)
         :event 'tool-call-update
         :on-event #'emanix/agent-shell--on-tool-call-update)
      (error
       (message "emanix-agent-shell: buffer sync unavailable (%s)"
                (error-message-string err))))))

;;; --- agent-shell configuration ---

;; Explicit autoloads for the same reason config.el gives for vterm and
;; ghostel: the nix-installed package's own autoloads do not reliably reach
;; the daemon session. Upstream autoloads none of these three anyway.
(autoload 'agent-shell-anthropic-start-claude-code "agent-shell-anthropic"
  "Start an interactive Claude Code shell." t)
(autoload 'agent-shell-pi-start-agent "agent-shell-pi"
  "Start an interactive pi shell." t)
(autoload 'agent-shell-send-region "agent-shell"
  "Send the region to an agent shell." t)

(with-eval-after-load 'agent-shell
  (add-hook 'agent-shell-mode-hook #'emanix/agent-shell--install)
  (advice-add 'agent-shell-submit :before #'emanix/agent-shell--submit-advice))

(with-eval-after-load 'agent-shell-anthropic
  ;; `executable-find', not a store path: this file is out-of-store live elisp
  ;; and cannot interpolate nix. The wrapper arrives through home.packages, so
  ;; it lands on the profile PATH the daemon does have -- unlike ~/.local/bin,
  ;; which is the gap config.el:786 documents for the claude CLI itself.
  ;; Absent adapter = the command errors when pressed, not a broken config.
  (when-let* ((adapter (executable-find "claude-agent-acp")))
    (setq agent-shell-anthropic-claude-acp-command (list adapter))))

(provide 'emanix-agent-shell)
;;; emanix-agent-shell.el ends here
