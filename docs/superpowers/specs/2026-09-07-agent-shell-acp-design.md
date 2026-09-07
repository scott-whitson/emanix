# The agent moves into the buffer

**Date:** 2026-09-07
**Status:** design, approved in brainstorm; not yet planned

## Problem

Working with Claude Code or pi means leaving the document. Both run as TUIs in
a terminal — Claude Code through ghostel or zellij, pi in its own Ghostty
window via `emanix-pi.el` — while the file being discussed is open in Emacs.
The agent and the editor look at the same path and never at the same buffer.

`claude-code-ide.el` (trial, 2026-08-24) moved the conversation into an Emacs
side window but not into Emacs: the window holds a terminal emulator, so the
transcript has no isearch, no yanking a reply into a buffer, no org capture. It
narrowed the gap without closing it.

The goal is one interaction surface: the conversation is text in a buffer, and
the agent edits the buffer you are editing.

## Why not ECA

ECA was the obvious candidate — established, editor-agnostic, and its author
maintains clojure-lsp. It was rejected on a measured fact, not a preference.

**ECA runs its own agent loop.** It re-implements skills, subagents, hooks, MCP
and approvals natively, and `/login` accepts a Claude Max/Pro subscription, so
the cost objection does not apply. But it is not Claude Code: adopting it means
re-earning CLAUDE.md, `~/.claude/skills`, the superpowers plugin, settings
permissions and slash commands inside a second configuration surface.

**ECA's server owns file I/O.** Its protocol defines exactly four server→editor
requests — `editor/getDiagnostics`, `editor/getDefinition`,
`editor/getReferences`, `chat/askQuestion`. There is no "read this buffer" and
no "apply this edit"; `read_file` / `write_file` / `edit_file` are server-side
filesystem operations. Its only `revert-buffer` call sits in
`eca-editor--ensure-diagnostics-fresh`, on the diagnostics path, not after its
own writes.

ECA keeps two advantages worth recording, because they are the conditions under
which this decision should be revisited: **TRAMP** (eca-emacs runs the server on
remote hosts over SSH and Docker; agent-shell contains zero `tramp` or
`file-remote-p` references) and **model flexibility** (Ollama and any
OpenAI-compatible endpoint, which composes with arc's local-GPU work).

If remote editing over TRAMP becomes the dominant need, ECA is the answer and
this spec should be reopened.

## What was measured

A throwaway probe on whistle ran agent-shell against
`@agentclientprotocol/claude-agent-acp` 0.75.1. Results, not claims:

| Question | Result | Evidence |
| --- | --- | --- |
| Runs, authenticates on the existing subscription | yes | No auth prompt; picked up the `claude` login |
| Loads the real Claude Code config | yes | `settingSources: ["user","project","local"]`, `acp-agent.js:5962`; session listed plugin slash commands |
| Honors `settings.json` permissions | yes | A project `.claude/settings.local.json` allow-list took permission requests 1 → 0 |
| Permission UX | native | Emacs card with an inline unified diff before the edit |
| **Reads unsaved buffer state** | **no** | Buffer held a token absent from disk; agent returned the disk content |
| **Edits the live buffer** | **no** | Edit landed on disk; the open buffer stayed stale, `modified: nil` |

The second pair is the important one, and it is not agent-shell's fault. Emacs
advertised the capability honestly —

    "clientCapabilities":{"fs":{"readTextFile":true,"writeTextFile":true}}

— and across a full session in which the agent successfully edited a file, the
wire carried **zero** `fs/read_text_file` or `fs/write_text_file` calls. The
adapter defines both methods at `acp-agent.js:5104-5110`, calls neither, and
gates on `clientCapabilities.fs` nowhere.

agent-shell's side is correct and unreachable:
`agent-shell--on-fs-read-text-file-request` prefers `find-buffer-visiting`, and
the write handler uses `replace-buffer-contents` on the live buffer. That code
never runs with this agent, and there is **no fallback** — agent-shell's only
`revert-buffer` sits inside the read handler that never fires, so the buffer
goes stale silently.

### This is an ecosystem gap, not a bug awaiting a fix

The ACP specification carries only a negative obligation — if the capability is
absent or false the agent "**MUST NOT** attempt to call the corresponding
filesystem method" — and no affirmative duty to use it when it is advertised.
The same non-compliance is publicly reported against Cursor CLI and OpenClaw's
bridge.

But it is implementable, and implemented. Gemini CLI gates correctly:

    if (this.clientCapabilities?.fs) {
      const acpFileSystemService = new AcpFileSystemService(this.connection, …)

and routes every tool through `getFileSystemService().readTextFile(…)`. So
xenodium's "edits are applied to live Emacs buffers" is true — for Gemini.

The conclusion that matters for planning: a local patch is the durable answer,
not a stopgap, and if `claude-agent-acp` ever honors `fs` the patch becomes dead
code and true live editing arrives with no migration.

## What the patch does, and what it costs

Measured with the patch installed:

| Test | Result |
| --- | --- |
| Agent edits, buffer clean | Buffer updated live; point preserved; `modified: nil` |
| `C-/` after an agent edit | Reverses the agent's change — undo history survives |
| Agent edits, buffer dirty | Refused with a warning; the unsaved edit kept |
| Agent reads a file with unsaved buffer edits | Sees them |

Two directions, two mechanisms. The write direction subscribes to
`tool-call-update` and, on `:status "completed"`, syncs every buffer named by
the tool call. The read direction saves modified project buffers before each
prompt.

The residual costs are real and belong in the record:

- **Forced saves.** Every prompt commits unsaved work to disk, entangling your
  edits with the agent's in file history. "Type freely, save when I mean it"
  is gone. This is behind a defcustom so it is visible and switchable.
- **Dirty-buffer writes** produce a warning and a stale buffer to reconcile by
  hand. Refusing is the right default: silently clobbering unsaved work is
  worse than saying so.

## Architecture

Three pieces. Nothing new at the top of `$HOME`.

### 1. `ioshi/i-intelligence/agent-acp.nix` — the adapter

Follows `dotfiles/ioshi/i-intelligence/cpgw.nix`, whose rule reads: *Nix
supplies the JVM and the units, not the payload.* Here Nix supplies node and
the wrappers; the npm payload stays imperative in
`~/.local/share/claude-agent-acp`, because upstream published 0.75.1 two days
before this spec and a pinned `npmDepsHash` would silently hold back Claude
Code features.

Two `writeShellScriptBin` outputs in `home.packages`, with
`STATE=${XDG_DATA_HOME:-$HOME/.local/share}/claude-agent-acp`:

- `claude-agent-acp` — execs a store-pinned node against
  `$STATE/lib/node_modules/@agentclientprotocol/claude-agent-acp/dist/index.js`,
  and exits with a clear "run claude-acp-update" message if that file is absent
- `claude-acp-update` — `npm install --global --prefix "$STATE"
  @agentclientprotocol/claude-agent-acp`, which produces exactly that layout

**The wrapper is load-bearing, not tidiness.** The payload's entry point is a
node script with a `#!/usr/bin/env node` shebang, and the Emacs daemon runs
under systemd with a minimal PATH — the trap `emacs/config.el:786` already
documents for `claude` at `~/.local/bin`, and the same class as datacore's
"systemd units get a MINIMAL PATH incl. no bash for the shebang". Pinning node
by store path makes "works in a terminal, dead in the daemon" structurally
impossible rather than a thing rediscovered.

No new `emanix.*` option. The wrappers are two small scripts and the elisp
guards on the payload's presence, so a host without a Claude subscription loses
a keybinding rather than failing to build — the same shape as the existing
`file-directory-p` guard on the claude-code-ide checkout.

### 2. `emacs/packages.nix` — the package set

Add `agent-shell`, `acp`, `shell-maker`, listed explicitly with comments as the
file already does for other consumers' dependencies. All three are present in
the pinned emacs-overlay and were verified to carry every API the patch needs
(`agent-shell-subscribe-to`, `tool-call-update`, `:raw-input`, `:diffs`,
`agent-shell-send-region`, `agent-shell-pi.el`).

The overlay is at `agent-shell-20260901.930`; MELPA is at `20260907.1057`. The
lag is acceptable *because* it was checked rather than assumed — and checking
it is now part of the bump procedure, not a one-off.

Remove `websocket` and `web-server` (packages.nix:93-94). A grep confirms
claude-code-ide was their only consumer. `transient` stays — magit needs it.

### 3. `emacs/lisp/emanix-agent-shell.el` — config and the patch

Sets `agent-shell-anthropic-claude-acp-command` to the wrapper's absolute path,
adds explicit autoloads (neither `agent-shell-anthropic-start-claude-code` nor
`agent-shell-send-region` is autoloaded upstream, and the existing config
already documents why nix-installed autoloads do not reliably reach the
daemon), and installs the patch per-shell from `agent-shell-mode-hook` —
upstream guarantees session state is available there.

Three details are load-bearing, each found the hard way:

**`set-visited-file-modtime` before touching the buffer.** The file changed on
disk underneath; modifying the buffer otherwise trips Emacs's file-supersession
guard, which errors in batch and *wedges a daemon* on a prompt nobody can
answer. This hung an Emacs during the probe.

**Mixed key styles in the payload.** The tool call uses keyword keys at the top
level (`:status`, `:locations`, `:raw-input`) but plain symbols inside the JSON
vectors — `:locations` is a *vector* of `((path . "…") (line . 3))`. Getting
this wrong fails silently: the handler runs, matches nothing, logs nothing.

**`replace-buffer-contents`, never `revert-buffer`.** A revert would work and
would destroy undo history, point and markers. `replace-buffer-contents`
applies a minimal diff, which is the entire reason `C-/` still undoes an agent
edit.

Shape of the core:

```elisp
(defun emanix/agent-shell--sync-from-disk (path)
  (when-let* ((buf (find-buffer-visiting path)))
    (if (buffer-modified-p buf)
        (message "agent-shell: %s changed on disk but the buffer has unsaved edits"
                 (buffer-name buf))
      (let ((tmp (generate-new-buffer " *agent-shell-sync*")))
        (unwind-protect
            (progn
              (with-current-buffer tmp (insert-file-contents path))
              (with-current-buffer buf
                (set-visited-file-modtime)   ; MUST precede the edit
                (save-restriction (widen) (replace-buffer-contents tmp 1.0))
                (set-buffer-modified-p nil)))
          (kill-buffer tmp))))))
```

Two fixes over the probe version: per-turn path dedupe (several fields of one
tool call name the same file, so the probe synced twice), and save-before-prompt
behind a defcustom defaulting on.

The whole patch is guarded so that an upstream shape change costs the sync
feature and not a working Emacs. It reads undocumented internals of a package
whose author calls the API unstable; that is an accepted risk, contained.

## What changes and what retires

| File | Change |
| --- | --- |
| `emacs/config.el` 755-796 | The claude-code-ide `let` block and `C-c C-'` |
| `emacs/config.el` 651 | `emanix-pi` out of the feature list, `emanix-agent-shell` in |
| `emacs/config.el` 882-886 | The `s-S-<return>` Ghostty-pi binding in `ewm-mode-map` |
| `emacs/lisp/emanix-pi.el` | Deleted |
| `emacs/packages.nix` 93-94 | `websocket`, `web-server` |
| `zsh.nix:137` | A comment citing emanix-pi's fallback as its reason for existing |
| `i-intelligence/default.nix` | Import `./agent-acp.nix` |

`~/.config/emacs/site-lisp/claude-code-ide.el` is outside the repo; the switch
stops loading it and the checkout can be removed by hand.

**Accepted loss:** claude-code-ide exposed xref, apropos, tree-sitter, imenu,
project and flymake to Claude over MCP. agent-shell has no equivalent and this
spec does not replace it. Claude falls back to ripgrep and reading files, which
is how it already works in the terminal. Recorded as a deliberate trade, not an
oversight — `claude-code-ide-mcp-server-ensure-server` can run standalone, so
restoring the tools later is possible and would be its own spec.

`ghostel`, `vterm`, `transient` and zellij all stay: terminals and a magit
dependency, not Claude plumbing. **zellaude is out of scope** — it exists to
signal blocked Claude sessions in zellij, so it becomes dead weight once Claude
stops running there, but it is Syncthing-replicated with no push target and
deserves its own decision rather than a silent deletion here.

## Keybindings

Every key was already doing this job. Nothing new is taken.

| Key | Was | Becomes |
| --- | --- | --- |
| `C-c C-'` | `claude-code-ide-menu` | Claude agent shell |
| `C-c p` | `emanix/pi` (Ghostty) | pi agent shell (`agent-shell-pi-start-agent`) |
| `s-S-<return>` | pi in Ghostty, from an EWM slot | Claude agent shell from an EWM slot |
| `C-c r` | force-unset by `emanix-pi.el` | `agent-shell-send-region` |

`C-c r` replaces the `emanix/pi-send-region` capability lost with
`emanix-pi.el`, on the key that module was already reserving.

## Scope

whistle and rafik. Both run the interactive Emacs daemon and both have the
Claude CLI. datacore is excluded: it is in the server role, and the way you
would reach an agent there is over SSH, which is exactly the TRAMP case
agent-shell does not support.

## Verification

1. `nix build` both host configurations.
2. Restart the Emacs daemon and confirm `claude-agent-acp` resolves **under
   systemd**, not merely in an interactive shell. This is the one genuinely new
   failure mode and the reason the wrapper exists.
3. `claude-acp-update`, then start a Claude shell and confirm it authenticates
   with no prompt.
4. Confirm the session lists your plugin slash commands — proof the settings
   chain loaded.
5. The four patch assertions: clean-buffer sync with point preserved; `C-/`
   reverses an agent edit; a dirty buffer is refused with a warning; the agent
   reads a token present only in the buffer.
6. `C-c p` opens a pi shell.

## Risks

**No fallback.** Immediate cutover was chosen deliberately: claude-code-ide and
the pi launcher leave in the same change, so a bad day has no second path to an
agent. The mitigation is that `claude` and `pi` remain on PATH — the terminal
route survives, it just stops being wired into Emacs.

**Unstable upstream.** agent-shell's author describes the API as unstable and
acp.el as not yet API-stable. The patch depends on an undocumented event shape.
Guarded, and the bump procedure now includes re-checking the API list above.

**Forced saves change a habit.** Named in full under "What the patch does".

## Out of scope

- Restoring the Emacs MCP tools.
- zellaude's retirement.
- TRAMP / remote agents — the condition under which ECA gets reconsidered.
- Filing the `claude-agent-acp` upstream issue about honoring
  `clientCapabilities.fs`. Worth doing, outward-facing, and a separate decision.
