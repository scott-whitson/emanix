# The agent reads and writes Emacs buffers: a capability it never uses

**Applies to** the buffer-sync patch in `emacs/lisp/emanix-agent-shell.el`.
**Decided** 2026-09-07, from the measurement below. **Relocated** here on
2026-11-02, to bring the file header inside the 30-line budget.

## Decision

emanix patches agent-shell so the ACP client's `fs/read_text_file` and
`fs/write_text_file` handlers are actually exercised, rather than trusting the
capability to be used. The patch reads undocumented internals of a package whose
author calls the API unstable, so it is written to fail soft: a shape change
costs the sync feature, not a working Emacs.

## Why a patch, when agent-shell already implements both handlers

ACP lets a client offer `fs/read_text_file` and `fs/write_text_file` so the agent
reads and writes the EDITOR's buffer, unsaved state included. agent-shell offers
both and implements them correctly — its read handler prefers
`find-buffer-visiting` and its write handler uses `replace-buffer-contents` on
the live buffer.

claude-agent-acp never calls them. Measured 2026-09-07: Emacs advertised
`{"fs":{"readTextFile":true,"writeTextFile":true}}` and a whole session that
successfully edited a file carried ZERO `fs/*` requests. The adapter defines both
methods and gates on `clientCapabilities.fs` nowhere. The ACP spec has only a
negative obligation — MUST NOT call when the capability is absent — and no duty
to use it when present, so this does not self-heal. Gemini CLI does gate on it
correctly, which is what makes this an adapter gap rather than a protocol one,
and what makes a local patch worth writing.

## Consequence without it

The agent writes to disk while you edit a buffer, and agent-shell has no
fallback: its only `revert-buffer` sits inside the read handler that never fires,
so the buffer goes stale in silence.

## Shape

Everything below the `--- buffer coherence ---` heading closes that in two
directions. The file deliberately does NOT `require` agent-shell at top level:
that keeps the logic loadable — and unit-testable — under a bare batch Emacs,
which is what `checks/agent-shell-sync.nix` relies on.
