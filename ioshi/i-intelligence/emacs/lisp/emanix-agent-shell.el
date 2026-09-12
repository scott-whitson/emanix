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

(defgroup emanix-agent-shell nil
  "Claude Code and pi as Emacs buffers, over ACP."
  :group 'tools)

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

Return one of:
  nil              no buffer visits PATH
  `unchanged'      the buffer is already in sync with the file
  `skipped-dirty'  the file changed on disk but the buffer has unsaved edits
  `failed'         the replacement signalled and the buffer was left alone
  `synced'         the buffer now matches the file

Four choices here are load-bearing:

The `unchanged' branch comes FIRST.  Every completed tool call reaches this,
including Read and Grep, so most calls arrive on a buffer nothing touched.
Leaving early skips the temp buffer and the diff, and -- for a DIRTY buffer
the agent merely read -- avoids a \"changed on disk\" warning that would
simply be false.

`set-visited-file-modtime' MUST run before the buffer is touched.  The file
changed on disk underneath us, so any modification otherwise raises Emacs's
file-supersession threat -- which errors outright in batch and, worse, prompts
interactively and WEDGES A DAEMON on a question nobody can answer.

Because that stamp comes first, the replacement is wrapped and the OLD
modtime is put back if it signals.  A stamped buffer holding content it never
received is strictly worse than no patch at all: it also suppresses the
supersession warning that would otherwise have told you.  `inhibit-read-only'
is bound for the same reason -- `view-mode', \\[read-only-mode] and an
unwritable file would each signal here, and the agent has ALREADY changed the
file on disk, so refusing to show that is not protecting anything.

`replace-buffer-contents', never `revert-buffer'.  A revert would work and
would discard undo history, point and markers.  The minimal diff is the whole
reason an agent's edit is still undoable with \\[undo].  Note the 1.0-second
cap: on a large or heavily rewritten file `replace-buffer-contents' gives up
on diffing and falls back to a wholesale delete-and-insert, which does move
point and does invalidate markers.  Point preservation is the common case,
not a guarantee."
  (let ((buf (find-buffer-visiting path)))
    (cond
     ((null buf) nil)
     ((with-current-buffer buf (verify-visited-file-modtime)) 'unchanged)
     ;; Refusing is the right default: silently overwriting unsaved work is
     ;; worse than saying so and letting the human reconcile.
     ((buffer-modified-p buf)
      (message "agent-shell: %s changed on disk but the buffer has unsaved edits"
               (buffer-name buf))
      'skipped-dirty)
     (t
      (let ((tmp (generate-new-buffer " *emanix-agent-shell-sync*"))
            (result 'synced))
        (unwind-protect
            (progn
              (with-current-buffer tmp (insert-file-contents path))
              (with-current-buffer buf
                (let ((previous (visited-file-modtime)))
                  (set-visited-file-modtime)
                  (condition-case err
                      (let ((inhibit-read-only t))
                        (save-restriction
                          (widen)
                          (replace-buffer-contents tmp 1.0))
                        (set-buffer-modified-p nil))
                    (error
                     (set-visited-file-modtime previous)
                     (message "agent-shell: could not sync %s (%s)"
                              (buffer-name) (error-message-string err))
                     (setq result 'failed))))))
          (kill-buffer tmp))
        result)))))

(defun emanix/agent-shell--save-root-too-broad-p (root)
  "Return non-nil when ROOT is too broad a scope to force-save.

ROOT is an expanded directory name ending in a slash.  The caller's root
comes from the shell buffer's `default-directory', which upstream's
`agent-shell-cwd' falls back to when `project-current' returns nil -- reachable
by starting a shell from *scratch*, and by the s-S-<return> binding that is
advertised as working from any slot.  Saving under $HOME would then commit the
org-roam vault and every other unsaved buffer in the session, which is not a
cost anyone opted into by pressing RET in a chat buffer."
  (let ((home (file-name-as-directory (expand-file-name "~"))))
    (or (not (file-directory-p root))
        ;; ROOT is $HOME itself, or an ancestor of it -- so "/", "/home/" and
        ;; "~/" are all refused, while "~/projects/emanix/" is not.
        (string-prefix-p root home))))

(defun emanix/agent-shell--save-project-buffers (root)
  "Save modified file-visiting buffers under ROOT.  Return the paths saved.

This is the read half of the patch.  The agent reads from disk, so unsaved
buffers are invisible to it; saving first is the only way to be asked about
the text actually on screen.  The cost is real and is why the caller puts it
behind a defcustom: it commits your unsaved work on every prompt.

Two refusals, both of which would otherwise fire a modal prompt or an error
INSIDE a `:before' advice on `agent-shell-submit' -- where answering no or
signalling silently kills the submit the human just pressed RET for:

ROOT too broad (see `emanix/agent-shell--save-root-too-broad-p') saves
nothing at all and says so.

A buffer that fails `verify-visited-file-modtime' is skipped and named.  That
is exactly the buffer a previous `skipped-dirty' refusal left behind -- dirty,
with the file changed underneath it -- and `basic-save-buffer' greets it with
its own `yes-or-no-p' (\"has changed since visited or saved.  Save anyway?\"),
where yes clobbers the agent's edit and no aborts the prompt.

Every remaining save is individually demoted to a message, so one unwritable
file cannot take the whole submit down with it."
  (let ((root (file-name-as-directory (expand-file-name root))))
    (if (emanix/agent-shell--save-root-too-broad-p root)
        (progn
          (message "agent-shell: not force-saving -- %s is your home or the filesystem root, not a project" root)
          nil)
      (let (saved stale)
        (dolist (buf (buffer-list))
          (with-current-buffer buf
            (when (and buffer-file-name
                       (buffer-modified-p)
                       (string-prefix-p root (expand-file-name buffer-file-name)))
              (if (not (verify-visited-file-modtime))
                  (push buffer-file-name stale)
                (when (with-demoted-errors "agent-shell: could not save buffer: %S"
                        (save-buffer)
                        t)
                  (push buffer-file-name saved))))))
        (when stale
          (message "agent-shell: not saving %d buffer(s) whose file changed on disk: %s"
                   (length stale)
                   (mapconcat #'file-name-nondirectory (nreverse stale) ", ")))
        (nreverse saved)))))

;;; --- buffer coherence: wiring ---

(defcustom emanix/agent-shell-save-before-prompt t
  "When non-nil, save modified project buffers before each agent prompt.

The agent reads files from disk, so without this it cannot see edits you
have not saved.  With it, every prompt commits your unsaved work -- which
entangles your edits with the agent's in file history and takes away \"type
freely, save when I mean it\".  That trade is real, so it is a setting
rather than a silent behaviour.

Note that `apheleia-global-mode' is on in this configuration, so a forced
save does not merely write the buffer, it REFORMATS it.  Pressing RET in an
agent shell can therefore reformat a file you were midway through editing in
another window.

Unnecessary if `claude-agent-acp' ever honours ACP's client filesystem
capability, see this file's header."
  :type 'boolean
  :group 'emanix-agent-shell)

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
    (when-let* ((saved (emanix/agent-shell--save-project-buffers default-directory)))
      ;; The forced save is a cost the spec asks the user to accept, so it is
      ;; not allowed to be invisible.
      (message "agent-shell: saved %d modified buffer(s) before prompting"
               (length saved)))))

(defvar-local emanix/agent-shell--subscription nil
  "Token for this shell buffer's tool-call-update subscription, if any.")

(defun emanix/agent-shell--install ()
  "Subscribe the current agent shell to tool-call updates.

Runs from `agent-shell-mode-hook', where upstream guarantees session state is
already available.  The `condition-case' here guards only this subscription
call, so a failure at install time costs the sync feature and not a working
shell.  It does not (and need not) guard the handler itself: that runs later,
asynchronously, outside this call's dynamic extent, and agent-shell's own
`agent-shell--emit-event' already wraps every subscriber invocation in its
own `condition-case' and messages the error, so a throwing handler cannot
wedge the shell either.

The previous subscription is dropped first.  `agent-shell-mode' can be run
again in a buffer that already has one -- upstream restarts, or a plain
\\[agent-shell-mode] -- and a second subscription would sync every path
twice, which is the exact double-flicker the path dedupe exists to avoid."
  (when (fboundp 'agent-shell-subscribe-to)
    (condition-case err
        (progn
          (when (and emanix/agent-shell--subscription
                     (fboundp 'agent-shell-unsubscribe))
            (agent-shell-unsubscribe :subscription emanix/agent-shell--subscription))
          (setq emanix/agent-shell--subscription
                (agent-shell-subscribe-to
                 :shell-buffer (current-buffer)
                 :event 'tool-call-update
                 :on-event #'emanix/agent-shell--on-tool-call-update)))
      (error
       (message "emanix-agent-shell: buffer sync unavailable (%s)"
                (error-message-string err))))))

;;; --- agent-shell configuration ---

;; Explicit autoloads for the same reason config.el gives for ghostel: the
;; nix-installed package's own autoloads do not reliably reach the daemon
;; session. Upstream autoloads none of these three anyway.
(autoload 'agent-shell-anthropic-start-claude-code "agent-shell-anthropic"
  "Start an interactive Claude Code shell." t)
(autoload 'agent-shell-pi-start-agent "agent-shell-pi"
  "Start an interactive pi shell." t)
(autoload 'agent-shell-send-region "agent-shell"
  "Send the region to an agent shell." t)

(defun emanix/agent-shell-claude (&optional elsewhere)
  "Start a Claude agent shell, in this tree or one you name.

Without a prefix argument this is `agent-shell-anthropic-start-claude-code'
unchanged: the shell starts wherever the current buffer already is.

With \\[universal-argument] (ELSEWHERE non-nil), prompt for a directory and
start there instead -- an agent on a tree you are not currently visiting,
without first having to `find-file' or `dired' into it.

WHY THIS IS A WRAPPER AND NOT AN UPSTREAM ARGUMENT.  agent-shell resolves a
shell's working directory from the CURRENT BUFFER -- `agent-shell-cwd'
returns the project root when `project-current' finds one and
`default-directory' otherwise -- and reads it ONCE, at start.  Nothing
re-reads it afterwards: `M-x cd' in the shell buffer never reaches the
agent, and `agent-shell-restart', which does re-read it, forces a fresh
session.  Choosing a directory therefore has to happen before the command
runs, and that is the whole of what happens here.

Binding `default-directory' is deliberately the entire mechanism.
`agent-shell--new-shell' does take a :location, but it is private AND pins
`session-strategy' to `new'.  Going through the public command instead
leaves the directory as the only thing that differs -- which matters
because ACP sessions are per-cwd: with `agent-shell-session-strategy' at
its default of `prompt', the new shell offers the resumable sessions
belonging to the directory just picked.  Continuing a conversation started
elsewhere is the usual reason for wanting this at all, so a variant that
could only start fresh ones would miss the point.

The prompt names a directory but the shell may start at that directory's
PROJECT ROOT, because `agent-shell-cwd' prefers it.  Naming a repo
subdirectory thus behaves exactly as visiting a file inside it would --
consistent with the unprefixed key, rather than a second set of rules."
  (interactive "P")
  (let ((default-directory
         (if elsewhere
             ;; MUSTMATCH: a non-existent directory would leave the ACP
             ;; process with an unusable cwd, which surfaces as a failure to
             ;; start rather than as a bad path.
             (file-name-as-directory
              (expand-file-name
               (read-directory-name "Start Claude in: " nil nil t)))
           default-directory)))
    (agent-shell-anthropic-start-claude-code)))

(defun emanix/agent-shell--pi-adapter ()
  "Return the pi ACP adapter's executable, or nil when none is installed.

Located exactly like the Claude adapter: `executable-find' on the first
element of the command upstream would run.  `agent-shell-pi-acp-command' is
only bound once agent-shell-pi has loaded, so its upstream default is
restated here for the pre-load case."
  (let ((cmd (car (if (boundp 'agent-shell-pi-acp-command)
                      (symbol-value 'agent-shell-pi-acp-command)
                    '("pi-acp")))))
    (and (stringp cmd) (executable-find cmd))))

(defun emanix/agent-shell-pi ()
  "Start a pi agent shell, or explain what is missing.

NO PI ACP ADAPTER IS VENDORED BY THIS DISTRIBUTION, DELIBERATELY.  Upstream
defaults `agent-shell-pi-acp-command' to (\"pi-acp\"), and nixpkgs'
pi-coding-agent ships `pi' and nothing else, so the binding upstream implies
would simply fail.  Choosing among the competing community adapters is a
supply-chain decision for the operator, not something a distro should make on
their behalf -- so this reports the gap and names the variable instead.

Checked at press time rather than at load time, so installing an adapter
later needs no restart."
  (interactive)
  (if (emanix/agent-shell--pi-adapter)
      (call-interactively #'agent-shell-pi-start-agent)
    (user-error
     "No pi ACP adapter on PATH.  Install one and point `agent-shell-pi-acp-command' at it")))

;; C-c p lives HERE, not beside its two siblings in config.el, because the
;; guard above is the binding: what the key does depends on whether an adapter
;; is installed, and that knowledge belongs with the rest of the agent-shell
;; glue. config.el carries a pointer at the C-c C-' / C-c r site.
(global-set-key (kbd "C-c p") #'emanix/agent-shell-pi)

(defun emanix/agent-shell--sleep-block-latch (block-sleep &rest args)
  "Call BLOCK-SLEEP with ARGS, latching the sleep inhibit off if it fails.

WHAT THIS SILENCES.  agent-shell keeps the system awake for the duration of
a turn, via Emacs 31.1's `system-sleep' library, which asks logind to
Inhibit over D-Bus.  Where logind refuses, that request fails EVERY TIME --
and upstream retries it on every ACP event for as long as the agent is busy,
reporting each failure to the echo area, because a failed attempt stores no
token and so leaves nothing to remember it by.  Measured on a WSL host: 38
identical \"Sleep inhibit unavailable\" messages inside a single turn.

Its own advice is to set `agent-shell-inhibit-system-sleep' to nil, which
does stop it completely (upstream's `when-let*' short-circuits on that
variable).  This does exactly that, but only after the host has actually
proven it cannot inhibit -- so the echo area gets ONE message rather than
dozens, and no host is opted out of a feature that works for it.  The distro
cannot decide this statically: the same config runs where logind allows this
and where it does not.

WHY logind REFUSES, on the host this was written for: an idle inhibitor
needs polkit authorisation, and `security.polkit.enable' is off there, so
every request is denied -- reproducible outside Emacs entirely, with
`systemd-inhibit --what=idle --who=probe --why=test true'.  Nothing is lost
by giving up on it: that host is a WSL guest, where Windows owns power
management and a guest-side inhibitor could not keep the machine awake even
if logind granted it.

Advising `system-sleep-block-sleep' -- an Emacs built-in whose API is stable
-- rather than the agent-shell internals around it, which upstream describes
as unstable.  The error is re-signalled unchanged, so upstream's own
`condition-case' still emits the first message and any other caller of the
built-in sees identical behaviour.

`setq-default' because upstream reads the variable globally and never makes
it buffer-local: the claim being recorded is about the HOST, not about one
shell buffer.  Latched for the session -- if polkit is enabled later, restart
Emacs (or set the variable back to t) to pick the feature up again."
  (condition-case err
      (apply block-sleep args)
    (error
     (setq-default agent-shell-inhibit-system-sleep nil)
     (signal (car err) (cdr err)))))

(with-eval-after-load 'agent-shell
  (add-hook 'agent-shell-mode-hook #'emanix/agent-shell--install)
  (advice-add 'agent-shell-submit :before #'emanix/agent-shell--submit-advice)
  ;; `system-sleep' is a built-in that agent-shell loads lazily, on its first
  ;; inhibit attempt. Requiring it HERE is what lets the advice be guarded by
  ;; `fboundp': advising a void symbol would define its function cell, and
  ;; agent-shell's own `agent-shell--system-sleep-available-p' probes exactly
  ;; that -- so on an Emacs too old to have the library, a bare `advice-add'
  ;; would talk it into calling an API that does not exist.
  (when (and (require 'system-sleep nil t)
             (fboundp 'system-sleep-block-sleep))
    (advice-add 'system-sleep-block-sleep :around
                #'emanix/agent-shell--sleep-block-latch)))

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
