# agent-shell + ACP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `claude-code-ide.el` and `emanix-pi.el` with agent-shell over ACP, so Claude Code and pi are Emacs buffers that edit the buffer you are editing.

**Architecture:** Nix supplies a store-pinned node wrapper around an imperatively-installed npm adapter (cpgw's rule); the emacs-overlay supplies `agent-shell`/`acp`/`shell-maker`; one new elisp module carries the configuration plus a buffer-coherence patch that exists because `claude-agent-acp` ignores ACP's client filesystem capability. The patch's logic is kept free of any `agent-shell` dependency so it is unit-testable under bare `emacs -Q --batch`.

**Tech Stack:** Nix (Home Manager modules, `runCommand` checks), Emacs Lisp (ERT), Node/npm (adapter payload only).

**Spec:** `docs/superpowers/specs/2026-09-07-agent-shell-acp-design.md`

## Global Constraints

- **Hosts:** whistle and rafik only. datacore is excluded.
- **Repo:** `~/projects/emanix`, branch `main`. All work is in this repo.
- **Adapter package:** `@agentclientprotocol/claude-agent-acp` (NOT the superseded `@zed-industries/claude-code-acp`).
- **Adapter payload path:** `${XDG_DATA_HOME:-$HOME/.local/share}/claude-agent-acp`, entry point `lib/node_modules/@agentclientprotocol/claude-agent-acp/dist/index.js`.
- **Emacs package versions in the pinned overlay:** `agent-shell-20260901.930`, `acp`, `shell-maker`. Verified to contain `agent-shell-subscribe-to`, the `tool-call-update` event, `:raw-input`, `:diffs`, `agent-shell-send-region`, `agent-shell-pi-start-agent`, `agent-shell-mode-hook`.
- **Keybindings:** `C-c C-'` → Claude shell; `C-c p` → pi shell (guarded: bound only when a pi ACP adapter exists); `C-c r` → `agent-shell-send-region`; `s-S-<return>` → Claude shell from an EWM slot.
- **Commit trailers:** none. Never add `Co-Authored-By`.
- **No new top-level `$HOME` directories.** The four-directory home rule (docs/dotfiles/downloads/projects) holds; the adapter payload lives under `~/.local/share`.
- **Naming:** `emanix.*` is the distro's option namespace; `emanix/` prefixes elisp symbols. This work declares **no new nix option**.

## Hazard: live elisp goes live before the switch

On hosts with `emanix.src.liveElisp`, `emacs/lisp` is an out-of-store symlink into the checkout. Editing or deleting a lisp file takes effect on the **next Emacs restart, before any `nixos-rebuild switch`**. So deleting `emanix-pi.el` (Task 4) immediately removes `C-c p` on a live host, while the replacement binding also arrives immediately from the same commit. Do not split those two changes across commits, and do not restart Emacs between them.

`ioshi/i-intelligence/emacs/config.el` is likewise out-of-store. `ioshi/i-intelligence/emacs/packages.nix` is not — package changes need a rebuild.

## File Structure

| File | Responsibility |
| --- | --- |
| `ioshi/i-intelligence/agent-acp/wrappers.nix` | **Create.** Pure `{ pkgs }: { adapter; updater; }`. Split from the HM module so the check can build *and run* the scripts with nothing but `pkgs`. |
| `ioshi/i-intelligence/agent-acp.nix` | **Create.** Home Manager module; puts the two wrappers in `home.packages`. |
| `checks/agent-acp-wrapper.nix` | **Create.** Executes the wrapper; asserts store-pinned node and a useful error when the payload is absent. |
| `ioshi/i-intelligence/emacs/lisp/emanix-agent-shell.el` | **Create.** Pure sync logic (Task 2) + agent-shell wiring (Task 3). |
| `ioshi/i-intelligence/emacs/lisp/emanix-agent-shell-tests.el` | **Create.** ERT tests for the pure logic. |
| `checks/agent-shell-sync.nix` | **Create.** Runs the ERT suite under `emacs -Q --batch`. |
| `checks/agent-shell-glue.nix` | **Create.** Grep invariants over the elisp, modelled on `checks/arc-glue.nix`. |
| `checks/agent-shell-api.nix` | **Create.** Asserts the upstream agent-shell symbols and event this integration depends on, against the pinned overlay. |
| `flake.nix` | **Modify.** Register four checks. |
| `ioshi/i-intelligence/default.nix` | **Modify.** Import `./agent-acp.nix`. |
| `ioshi/i-intelligence/emacs/packages.nix` | **Modify.** Add three packages, remove two. |
| `ioshi/i-intelligence/emacs/config.el` | **Modify.** Remove the claude-code-ide block; swap the feature list entry; rebind `s-S-<return>`. |
| `ioshi/i-intelligence/emacs/lisp/emanix-pi.el` | **Delete.** |
| `ioshi/i-intelligence/zsh.nix` | **Modify.** One stale comment. |

---

### Task 1: The adapter wrappers

**Files:**
- Create: `ioshi/i-intelligence/agent-acp/wrappers.nix`
- Create: `ioshi/i-intelligence/agent-acp.nix`
- Create: `checks/agent-acp-wrapper.nix`
- Modify: `flake.nix` (checks block, after the `arc-glue` entry near line 231)
- Modify: `ioshi/i-intelligence/default.nix` (imports list)

**Interfaces:**
- Produces: `wrappers.nix` evaluates to an attrset `{ adapter, updater; }` of two derivations. `adapter` provides `bin/claude-agent-acp`; `updater` provides `bin/claude-acp-update`. Task 3's elisp finds `claude-agent-acp` via `executable-find`, so the binary name is the contract.

- [ ] **Step 1: Write the failing check**

Create `checks/agent-acp-wrapper.nix`:

```nix
# The Emacs daemon runs under systemd with a minimal PATH. An adapter that
# resolves `node' through PATH -- or relies on the payload's own
# `#!/usr/bin/env node' shebang -- works in a terminal and dies in the daemon.
# That is the same trap emacs/config.el:786 documents for ~/.local/bin/claude,
# and it is invisible until the day you need the agent.
#
# So this check does not read the wrapper, it RUNS it.
{ pkgs, ... }:
let
  wrappers = import ../ioshi/i-intelligence/agent-acp/wrappers.nix { inherit pkgs; };
in
pkgs.runCommand "agent-acp-wrapper" { } ''
  adapter=${wrappers.adapter}/bin/claude-agent-acp

  # 1. node must be a store path, not a PATH lookup.
  if ! grep -q '/nix/store/.*/bin/node' "$adapter"; then
    echo "claude-agent-acp does not exec a store-pinned node" >&2
    exit 1
  fi
  if grep -qE 'env node|exec node ' "$adapter"; then
    echo "claude-agent-acp resolves node through PATH" >&2
    exit 1
  fi

  # 2. With no payload installed it must fail loudly and name the fix, rather
  #    than emitting a node error about a missing file.
  export HOME=$(mktemp -d)
  export XDG_DATA_HOME="$HOME/.local/share"
  set +e
  msg=$("$adapter" --version 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "adapter reported success with no payload installed" >&2
    exit 1
  fi
  case "$msg" in
    *claude-acp-update*) : ;;
    *) echo "adapter did not name its fix; it said: $msg" >&2; exit 1 ;;
  esac

  touch $out
''
```

Register it in `flake.nix`, immediately after the `arc-glue` entry:

```nix
          # The ACP adapter wrapper, executed rather than read: the failure it
          # guards (node resolved through PATH) only appears inside the
          # systemd-run Emacs daemon. See checks/agent-acp-wrapper.nix.
          agent-acp-wrapper = import ./checks/agent-acp-wrapper.nix { inherit pkgs; };
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `cd ~/projects/emanix && nix flake check --no-build 2>&1 | tail -20`
Expected: FAIL — `path '/nix/store/...-source/ioshi/i-intelligence/agent-acp/wrappers.nix' does not exist` (the check is real; its subject is not written yet).

- [ ] **Step 3: Write the wrappers**

Create `ioshi/i-intelligence/agent-acp/wrappers.nix`:

```nix
# The ACP adapter's runtime, split out from the Home Manager module so
# checks/agent-acp-wrapper.nix can build and RUN these with nothing but pkgs.
# A check that cannot execute the script it guards only guards its existence.
#
# The payload is imperative on purpose, following dotfiles' cpgw.nix: "Nix
# supplies the JVM and the units, not the payload." claude-agent-acp published
# 0.75.1 two days before this was written, and a pinned npmDepsHash would
# silently hold back Claude Code features behind a hash nobody remembers to
# bump. Nix supplies node and these wrappers; npm supplies the rest.
{ pkgs }:
let
  package = "@agentclientprotocol/claude-agent-acp";
  entryPath = "lib/node_modules/@agentclientprotocol/claude-agent-acp/dist/index.js";
in
{
  adapter = pkgs.writeShellScriptBin "claude-agent-acp" ''
    set -eu
    state="''${XDG_DATA_HOME:-$HOME/.local/share}/claude-agent-acp"
    entry="$state/${entryPath}"
    if [ ! -f "$entry" ]; then
      echo "claude-agent-acp: adapter payload is not installed at $entry" >&2
      echo "Run: claude-acp-update" >&2
      exit 127
    fi
    # node by store path, never the payload's own env-shebang: see
    # checks/agent-acp-wrapper.nix for why this is the whole point.
    exec ${pkgs.nodejs}/bin/node "$entry" "$@"
  '';

  updater = pkgs.writeShellScriptBin "claude-acp-update" ''
    set -eu
    state="''${XDG_DATA_HOME:-$HOME/.local/share}/claude-agent-acp"
    mkdir -p "$state"
    echo "Installing ${package} into $state" >&2
    exec ${pkgs.nodejs}/bin/npm install --global --prefix "$state" ${package}
  '';
}
```

Create `ioshi/i-intelligence/agent-acp.nix`:

```nix
# The ACP adapter that agent-shell drives to reach Claude Code.
#
# No `emanix.*' option: these are two small scripts, and the elisp guards on
# the binary's presence, so a host with no Claude subscription loses a
# keybinding rather than failing to build -- the same shape as the guard that
# used to wrap the claude-code-ide checkout.
{ pkgs, ... }:
let
  wrappers = import ./agent-acp/wrappers.nix { inherit pkgs; };
in
{
  home.packages = [ wrappers.adapter wrappers.updater ];
}
```

Add to the imports list in `ioshi/i-intelligence/default.nix`, after `./emacs-daemon.nix`:

```nix
    ./agent-acp.nix
```

- [ ] **Step 4: Run the check to verify it passes**

Run: `cd ~/projects/emanix && nix build .#checks.x86_64-linux.agent-acp-wrapper --no-link`
Expected: builds successfully, no output.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/emanix
git add ioshi/i-intelligence/agent-acp.nix ioshi/i-intelligence/agent-acp/wrappers.nix \
        checks/agent-acp-wrapper.nix flake.nix ioshi/i-intelligence/default.nix
git commit -m "agent-acp: a store-pinned node wrapper around an imperative payload

The Emacs daemon runs under systemd with a minimal PATH, so the payload's
own env-shebang would work in a terminal and die in the daemon. The check
runs the wrapper rather than reading it, because that is the only way the
failure shows up."
```

---

### Task 2: The buffer-sync logic, with tests

The pure half of `emanix-agent-shell.el`. It has **no dependency on agent-shell**, which is what makes it testable under bare `emacs -Q --batch` and is also why the module must not `require` agent-shell at top level.

**Files:**
- Create: `ioshi/i-intelligence/emacs/lisp/emanix-agent-shell.el`
- Create: `ioshi/i-intelligence/emacs/lisp/emanix-agent-shell-tests.el`
- Create: `checks/agent-shell-sync.nix`
- Modify: `flake.nix` (checks block)

**Interfaces:**
- Produces, and Task 3 consumes:
  - `(emanix/agent-shell--tool-call-paths TOOL-CALL)` → list of strings
  - `(emanix/agent-shell--sync-from-disk PATH)` → `synced` | `skipped-dirty` | `nil`
  - `(emanix/agent-shell--save-project-buffers ROOT)` → list of saved filenames

- [ ] **Step 1: Write the failing tests**

Create `ioshi/i-intelligence/emacs/lisp/emanix-agent-shell-tests.el`:

```elisp
;;; emanix-agent-shell-tests.el --- Tests for the buffer-sync patch -*- lexical-binding: t; -*-
;;
;; These cover the half of emanix-agent-shell.el that has no agent-shell
;; dependency, which is deliberately the half where every measured failure
;; lived. Run by checks/agent-shell-sync.nix on every `nix flake check'.

(require 'ert)
(require 'emanix-agent-shell)

(defmacro emanix/agent-shell-test--with-file (var contents &rest body)
  "Bind VAR to a temp file containing CONTENTS and run BODY."
  (declare (indent 2))
  `(let ((,var (make-temp-file "emanix-agent-shell-test-" nil ".txt" ,contents)))
     (unwind-protect (progn ,@body)
       (dolist (b (buffer-list))
         (when (equal (buffer-file-name b) ,var)
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-file ,var))))

;; The payload mixes key styles: keywords at the top level of the tool call,
;; plain symbols inside the JSON-derived vectors. Getting this wrong fails
;; SILENTLY -- the handler runs, matches nothing, logs nothing -- which is
;; exactly how it failed during the probe.
(ert-deftest emanix/agent-shell-tool-call-paths-handles-both-key-styles ()
  (let ((tool-call
         '((:title . "Edit x.py")
           (:status . "completed")
           (:content . [((type . "diff") (path . "/tmp/from-content"))])
           (:raw-input (file_path . "/tmp/from-raw-input"))
           (:locations . [((path . "/tmp/from-locations") (line . 3))])
           (:diffs ((:file . "/tmp/from-diffs") (:line . 3))))))
    (let ((paths (emanix/agent-shell--tool-call-paths tool-call)))
      (dolist (expected '("/tmp/from-content" "/tmp/from-raw-input"
                          "/tmp/from-locations" "/tmp/from-diffs"))
        (should (member expected paths))))))

(ert-deftest emanix/agent-shell-tool-call-paths-deduplicates ()
  (let ((tool-call
         '((:raw-input (file_path . "/tmp/same"))
           (:locations . [((path . "/tmp/same"))])
           (:diffs ((:file . "/tmp/same"))))))
    (should (equal (emanix/agent-shell--tool-call-paths tool-call) '("/tmp/same")))))

(ert-deftest emanix/agent-shell-sync-updates-clean-buffer ()
  (emanix/agent-shell-test--with-file f "line1\nline2\n"
    (let ((buf (find-file-noselect f)))
      (write-region "line1\nline2\nline3\n" nil f nil 0)
      (should (eq (emanix/agent-shell--sync-from-disk f) 'synced))
      (with-current-buffer buf
        (should (equal (buffer-string) "line1\nline2\nline3\n"))
        (should-not (buffer-modified-p))))))

(ert-deftest emanix/agent-shell-sync-preserves-point ()
  (emanix/agent-shell-test--with-file f "line1\nline2\n"
    (let ((buf (find-file-noselect f)))
      (with-current-buffer buf (goto-char 4))
      (write-region "line1\nline2\nline3\n" nil f nil 0)
      (emanix/agent-shell--sync-from-disk f)
      (with-current-buffer buf (should (= (point) 4))))))

;; The reason this uses `replace-buffer-contents' and not `revert-buffer':
;; an agent's edit must be undoable like any other edit.
(ert-deftest emanix/agent-shell-sync-preserves-undo ()
  (emanix/agent-shell-test--with-file f "line1\nline2\n"
    (let ((buf (find-file-noselect f)))
      (write-region "line1\nline2\nline3\n" nil f nil 0)
      (emanix/agent-shell--sync-from-disk f)
      (with-current-buffer buf
        (undo-start)
        (undo-more 1)
        (should (equal (buffer-string) "line1\nline2\n"))))))

(ert-deftest emanix/agent-shell-sync-refuses-dirty-buffer ()
  (emanix/agent-shell-test--with-file f "line1\nline2\n"
    (let ((buf (find-file-noselect f)))
      (with-current-buffer buf
        (goto-char (point-max))
        (insert "MY-UNSAVED\n"))
      (write-region "line1\nline2\nline3\n" nil f nil 0)
      (should (eq (emanix/agent-shell--sync-from-disk f) 'skipped-dirty))
      (with-current-buffer buf
        (should (string-match-p "MY-UNSAVED" (buffer-string)))))))

;; Scoping matters: an agent shell's `default-directory' is one project, and
;; saving every modified buffer in the session would commit unrelated work.
;; The two files must therefore live in genuinely different directories --
;; sharing $TMPDIR would let a broken implementation pass.
(ert-deftest emanix/agent-shell-save-project-buffers-saves-only-under-root ()
  (let* ((root (make-temp-file "emanix-agent-shell-root-" t))
         (inside (expand-file-name "inside.txt" root))
         (outside (make-temp-file "emanix-agent-shell-outside-" nil ".txt" "b\n")))
    (unwind-protect
        (progn
          (write-region "a\n" nil inside)
          (dolist (f (list inside outside))
            (with-current-buffer (find-file-noselect f)
              (goto-char (point-max))
              (insert "edited\n")))
          (let ((saved (emanix/agent-shell--save-project-buffers root)))
            (should (member inside saved))
            (should-not (member outside saved)))
          (with-current-buffer (find-file-noselect inside)
            (should-not (buffer-modified-p)))
          ;; The buffer outside the root must still be dirty and unwritten.
          (with-current-buffer (find-file-noselect outside)
            (should (buffer-modified-p))))
      (dolist (f (list inside outside))
        (when-let* ((b (find-buffer-visiting f)))
          (with-current-buffer b (set-buffer-modified-p nil))
          (kill-buffer b)))
      (delete-directory root t)
      (delete-file outside))))

(provide 'emanix-agent-shell-tests)
;;; emanix-agent-shell-tests.el ends here
```

Create `checks/agent-shell-sync.nix`:

```nix
# The buffer-sync patch, unit-tested. This is the half of emanix-agent-shell.el
# with no agent-shell dependency -- deliberately, because it is also the half
# where every measured failure lived, and because that independence is what
# lets a plain batch Emacs run it on every `nix flake check'.
{ pkgs, ... }:
pkgs.runCommand "agent-shell-sync-tests" { } ''
  export HOME=$(mktemp -d)
  ${pkgs.emacs-nox}/bin/emacs -Q --batch \
    -L ${../ioshi/i-intelligence/emacs/lisp} \
    -l ert \
    -l emanix-agent-shell \
    -l emanix-agent-shell-tests \
    -f ert-run-tests-batch-and-exit
  touch $out
''
```

Register in `flake.nix` after the `agent-acp-wrapper` entry:

```nix
          # The buffer-sync patch's unit tests. See checks/agent-shell-sync.nix.
          agent-shell-sync = import ./checks/agent-shell-sync.nix { inherit pkgs; };
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/projects/emanix && nix build .#checks.x86_64-linux.agent-shell-sync --no-link 2>&1 | tail -20`
Expected: FAIL — `Cannot open load file: emanix-agent-shell`.

- [ ] **Step 3: Write the pure logic**

Create `ioshi/i-intelligence/emacs/lisp/emanix-agent-shell.el`:

```elisp
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

(provide 'emanix-agent-shell)
;;; emanix-agent-shell.el ends here
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/projects/emanix && nix build .#checks.x86_64-linux.agent-shell-sync --no-link`
Expected: builds successfully. All 7 tests pass.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/emanix
git add ioshi/i-intelligence/emacs/lisp/emanix-agent-shell.el \
        ioshi/i-intelligence/emacs/lisp/emanix-agent-shell-tests.el \
        checks/agent-shell-sync.nix flake.nix
git commit -m "agent-shell: the buffer-sync patch, with tests

claude-agent-acp ignores ACP's client filesystem capability, so the agent
writes to disk while you edit a buffer and agent-shell has no fallback.
This is the pure half of the fix, kept free of any agent-shell dependency
so a bare batch Emacs can test it -- which is also the half where every
measured failure lived: the supersession wedge and the mixed key styles."
```

---

### Task 3: Wiring agent-shell

**Files:**
- Modify: `ioshi/i-intelligence/emacs/lisp/emanix-agent-shell.el` (append)
- Create: `checks/agent-shell-glue.nix`
- Create: `checks/agent-shell-api.nix`
- Modify: `flake.nix` (checks block)

**Interfaces:**
- Consumes from Task 2: `emanix/agent-shell--tool-call-paths`, `emanix/agent-shell--sync-from-disk`, `emanix/agent-shell--save-project-buffers`.
- Produces: interactive commands bound in Task 4's config — `agent-shell-anthropic-start-claude-code`, `agent-shell-pi-start-agent`, `agent-shell-send-region` (all upstream commands, autoloaded here).

- [ ] **Step 1: Write the failing glue check**

Create `checks/agent-shell-glue.nix`:

```nix
# Modelled on checks/arc-glue.nix: cheap greps over one file, run on every
# `nix flake check' rather than whenever someone remembers to look.
#
# Each grep guards a failure that is SILENT in practice. A missing autoload
# gives you a keybinding that reports a void function only when you press it.
# A top-level `require' of agent-shell would break checks/agent-shell-sync.nix,
# but only there, so it would look fine on a real host. And the two mixed key
# styles in the tool-call payload fail by matching nothing at all.
{ pkgs, ... }:
pkgs.runCommand "agent-shell-glue-sane" { } ''
  src=${../ioshi/i-intelligence/emacs/lisp/emanix-agent-shell.el}

  # 1. No absolute home path, ever. The distro cannot know the operator's name.
  if grep -nE '"/home/[a-z]' "$src"; then
    echo "emanix-agent-shell.el contains an absolute home path" >&2
    exit 1
  fi

  # 2. No top-level require of agent-shell. It must stay loadable under the
  #    bare batch Emacs that runs the unit tests.
  if grep -nE '^\(require .agent-shell' "$src"; then
    echo "emanix-agent-shell.el requires agent-shell at top level; use with-eval-after-load" >&2
    exit 1
  fi

  # 3. The adapter is found on PATH, never hardcoded to a store path: config.el
  #    is out-of-store live elisp and cannot interpolate nix.
  if grep -nE '"/nix/store' "$src"; then
    echo "emanix-agent-shell.el hardcodes a store path" >&2
    exit 1
  fi

  # 4. Both key styles must still be read. Drop either and the sync silently
  #    stops finding files.
  for required in ':raw-input' ':locations' ':diffs' "'path"; do
    if ! grep -qF -- "$required" "$src"; then
      echo "emanix-agent-shell.el no longer reads $required from the tool call" >&2
      exit 1
    fi
  done

  # 5. The three commands the keybindings name must be autoloaded.
  for cmd in \
    agent-shell-anthropic-start-claude-code \
    agent-shell-pi-start-agent \
    agent-shell-send-region
  do
    if ! grep -q "autoload '$cmd" "$src"; then
      echo "emanix-agent-shell.el does not autoload $cmd" >&2
      exit 1
    fi
  done

  touch $out
''
```

Register in `flake.nix` after `agent-shell-sync`:

```nix
          # The agent-shell glue's autoloads and payload parsing. See
          # checks/agent-shell-glue.nix.
          agent-shell-glue = import ./checks/agent-shell-glue.nix { inherit pkgs; };
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `cd ~/projects/emanix && nix build .#checks.x86_64-linux.agent-shell-glue --no-link 2>&1 | tail -10`
Expected: FAIL — `emanix-agent-shell.el does not autoload agent-shell-anthropic-start-claude-code`.

- [ ] **Step 3: Append the wiring**

Append to `ioshi/i-intelligence/emacs/lisp/emanix-agent-shell.el`, **before** the closing `(provide 'emanix-agent-shell)`:

```elisp
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
```

- [ ] **Step 4: Pin the upstream API this file depends on**

The glue check greps *our* file. Nothing yet guards the other direction: an
emacs-overlay bump that renames or drops an upstream symbol we autoload, or the
`tool-call-update` event this patch is built on. That was verified by hand
against `agent-shell-20260901.930`; hand-verification does not survive a bump.

Create `checks/agent-shell-api.nix`:

```nix
# The upstream API this integration is built on, asserted against the package
# the overlay actually pins.
#
# agent-shell's author describes the API as unstable and acp.el as not yet
# API-stable, and emanix-agent-shell.el reads an undocumented event payload.
# A bump that renames `agent-shell-subscribe-to' or drops agent-shell-pi would
# otherwise surface as a keybinding that errors when pressed, weeks later.
{ pkgs, ... }:
let
  emacsWithAgentShell =
    (pkgs.emacsPackagesFor pkgs.emacs-nox).emacsWithPackages
      (epkgs: [ epkgs.agent-shell epkgs.acp epkgs.shell-maker ]);
in
pkgs.runCommand "agent-shell-api" { } ''
  export HOME=$(mktemp -d)
  ${emacsWithAgentShell}/bin/emacs -Q --batch --eval '(progn
    (require (quote agent-shell))
    (require (quote agent-shell-anthropic))
    (require (quote agent-shell-pi))
    (dolist (sym (quote (agent-shell-subscribe-to
                         agent-shell-submit
                         agent-shell-send-region
                         agent-shell-anthropic-start-claude-code
                         agent-shell-pi-start-agent)))
      (unless (fboundp sym)
        (error "agent-shell no longer defines %s" sym)))
    (dolist (var (quote (agent-shell-mode-hook
                         agent-shell-anthropic-claude-acp-command
                         agent-shell-text-file-capabilities)))
      (unless (boundp var)
        (error "agent-shell no longer defines %s" var)))
    ;; The event name the buffer-sync patch subscribes to. Documented only in
    ;; agent-shell-subscribe-to'"'"'s docstring, so assert against that.
    (unless (string-match-p "tool-call-update"
                            (documentation (quote agent-shell-subscribe-to)))
      (error "agent-shell no longer documents the tool-call-update event")))'
  touch $out
''
```

Register in `flake.nix` after `agent-shell-glue`:

```nix
          # The upstream agent-shell API this integration depends on, asserted
          # against the pinned overlay. See checks/agent-shell-api.nix.
          agent-shell-api = import ./checks/agent-shell-api.nix { inherit pkgs; };
```

- [ ] **Step 5: Run all three elisp checks to verify they pass**

Run:
```bash
cd ~/projects/emanix
nix build .#checks.x86_64-linux.agent-shell-glue --no-link
nix build .#checks.x86_64-linux.agent-shell-sync --no-link
nix build .#checks.x86_64-linux.agent-shell-api --no-link
```
Expected: all three build. The sync tests must still pass — the appended wiring must not have introduced a top-level agent-shell dependency. `agent-shell-api` is the slowest (it builds an Emacs closure) and is the one that will fail first on a future overlay bump.

- [ ] **Step 6: Commit**

```bash
cd ~/projects/emanix
git add ioshi/i-intelligence/emacs/lisp/emanix-agent-shell.el \
        checks/agent-shell-glue.nix checks/agent-shell-api.nix flake.nix
git commit -m "agent-shell: wire the shells, the adapter and the sync hook

Autoloads are explicit because upstream autoloads none of these three and
the daemon does not reliably see a nix package's own autoloads. The adapter
is found with executable-find rather than a store path: this file is
out-of-store live elisp and cannot interpolate nix."
```

---

### Task 4: The cutover

Retires claude-code-ide and the pi launcher, and moves the package set. **Single commit** — see the live-elisp hazard above: deleting `emanix-pi.el` takes `C-c p` away the moment Emacs restarts, and the replacement binding must arrive with it.

**Files:**
- Modify: `ioshi/i-intelligence/emacs/packages.nix:82-96` (the Claude Code IDE block)
- Modify: `ioshi/i-intelligence/emacs/config.el:651` (feature list)
- Modify: `ioshi/i-intelligence/emacs/config.el:755-796` (delete the claude-code-ide block)
- Modify: `ioshi/i-intelligence/emacs/config.el:882-886` (`s-S-<return>`)
- Delete: `ioshi/i-intelligence/emacs/lisp/emanix-pi.el`
- Modify: `ioshi/i-intelligence/zsh.nix:137`

**Interfaces:**
- Consumes from Task 3: the three autoloaded commands.

- [ ] **Step 1: Move the package set**

In `ioshi/i-intelligence/emacs/packages.nix`, replace the `--- Claude Code IDE (trial, 2026-08-24) ---` block (lines 82-96) with:

```nix
    # --- Agent shell (ACP) ---
    # Claude Code and pi as Emacs buffers rather than terminals. agent-shell
    # speaks ACP -- "LSP for coding agents" -- to the real CLI, so CLAUDE.md,
    # skills, plugins, hooks and settings permissions all still apply.
    #
    # Replaced claude-code-ide.el on 2026-09-07, which was a terminal in a side
    # window and needed websocket + web-server for its MCP server. Those two
    # had no other consumer and left with it; so did the Emacs MCP tools it
    # exposed (xref, imenu, project), a deliberate trade recorded in
    # docs/superpowers/specs/2026-09-07-agent-shell-acp-design.md.
    agent-shell
    acp # the protocol client agent-shell drives
    shell-maker # agent-shell's buffer/prompt substrate
    ghostel # NOT agent-shell's: the buffer terminal in its own right, C-c t
    transient # magit needs it; listed since ghostel's menu uses it directly
```

- [ ] **Step 2: Verify nothing else needed the removed packages**

Run: `cd ~/projects/emanix && grep -rn 'websocket\|web-server' --include='*.el' --include='*.nix' . | grep -v '\.git/'`
Expected: no hits outside the spec and plan documents. If `config.el` still mentions them, that text is inside the block deleted in Step 3.

- [ ] **Step 3: Delete the claude-code-ide block from config.el**

Delete lines 755-796 entirely — the comment block beginning `;; Claude Code IDE (trial, 2026-08-24)` through the closing `(claude-code-ide-emacs-tools-setup))))`. This removes the `C-c C-'` binding with it.

Replace with:

```elisp
;; Agent shell (ACP) — Claude Code and pi as Emacs buffers, configured in
;; lisp/emanix-agent-shell.el. Replaced claude-code-ide.el on 2026-09-07:
;; that put Claude in an Emacs *window* but the window held a terminal, so the
;; transcript had no isearch, no yank, no capture. C-c C-' keeps its job.
(global-set-key (kbd "C-c C-'") #'agent-shell-anthropic-start-claude-code)
(global-set-key (kbd "C-c p") #'agent-shell-pi-start-agent)
;; C-c r was force-unset by emanix-pi.el, which reserved it for
;; emanix/pi-send-region and never bound it. It does that job now.
(global-set-key (kbd "C-c r") #'agent-shell-send-region)
```

- [ ] **Step 4: Swap the feature list and the EWM binding**

At `config.el:651`, replace `emanix-pi` with `emanix-agent-shell`:

```elisp
(dolist (feature '(emanix-theme emanix-weather emanix-openrouter emanix-modeline emanix-launcher emanix-agent-shell emanix-quarterly emanix-prose emanix-web))
  (require feature nil :no-error))
```

At `config.el:882-886`, replace the Ghostty-pi launcher:

```elisp
    ;; Super+Shift+Enter: the Claude agent shell, from any slot. Was pi in a
    ;; Ghostty window until 2026-09-07 — the agent is a buffer now, so this
    ;; summons a buffer.
    (define-key ewm-mode-map (kbd "s-S-<return>")
      #'agent-shell-anthropic-start-claude-code)
```

- [ ] **Step 5: Delete emanix-pi.el and fix the stale comment**

```bash
cd ~/projects/emanix
git rm ioshi/i-intelligence/emacs/lisp/emanix-pi.el
```

In `zsh.nix`, replace the sentence at line 137 (`emanix-pi.el's fallback documents the daemon as its reason for existing, so the daemon is the case that must work, not the one that may be missed.`) with:

```
  # The calendar-sync binding documents the daemon as its reason for existing,
  # so the daemon is the case that must work, not the one that may be missed.
  # (emanix-pi.el used to make this point; it retired with the pi launcher on
  # 2026-09-07, but the reasoning is a property of the daemon, not that file.)
```

Also update line 132's parenthetical, which lists "the pi fallback" as an example of elisp resolving `$EMANIX_BIN_DIR`: drop that item, leaving the calendar-sync binding and the EWM firefox slot.

- [ ] **Step 6: Verify the whole flake still evaluates and builds**

Run:
```bash
cd ~/projects/emanix
nix flake check 2>&1 | tail -20
```
Expected: all checks pass, including the three new ones and the three `role-*` host evaluations. A failure in `role-wsl` here means the package set change broke the whistle configuration.

- [ ] **Step 7: Commit**

```bash
cd ~/projects/emanix
git add ioshi/i-intelligence/emacs/packages.nix ioshi/i-intelligence/emacs/config.el \
        ioshi/i-intelligence/zsh.nix
git commit -m "agent-shell: retire claude-code-ide and the pi Ghostty launcher

One commit on purpose. emacs/lisp is an out-of-store symlink on liveElisp
hosts, so deleting emanix-pi.el takes C-c p away at the next Emacs restart,
before any switch — the replacement binding has to arrive in the same
change or the key is dead in the window between them.

websocket and web-server go too; claude-code-ide was their only consumer.
The Emacs MCP tools it exposed go with it, which is a deliberate trade."
```

---

### Task 5: Rollout and verification on whistle and rafik

No code. This is the task that proves the one genuinely new failure mode — the adapter under systemd, not under your shell.

**Files:** none.

- [ ] **Step 1: Build both host configurations**

**This branch must be MERGED TO `main` in `~/projects/emanix` before it can be tested at
all — a worktree will not do.** Two independent reasons, and the second is the hard one:

1. `~/dotfiles` consumes emanix as `github:scott-whitson/emanix`, not as a local path, so a
   plain rebuild builds the *pushed* emanix and silently verifies the old code.
2. `dotfiles/home/scott/default.nix:210` sets `emanix.src.path = "$HOME/projects/emanix"`, and
   `emacs.nix` symlinks `config.el` and `lisp/` out of store from that path. So the LIVE ELISP
   always comes from the main checkout, whatever `--override-input` says. Overriding the input
   to a worktree gets you the new nix packages with the OLD elisp: `emanix-pi.el` still
   present, `emanix-agent-shell.el` still missing. Half-applied and confusing.

```bash
cd ~/projects/emanix
git merge --ff-only agent-shell-acp
nix flake check
sudo nixos-rebuild switch --flake ~/dotfiles#whistle \
  --override-input emanix path:/home/scott/projects/emanix
```

Note the window this opens, and do not restart Emacs inside it: the merge changes the live
elisp IMMEDIATELY, so `emanix-pi.el` is gone and `emanix-agent-shell.el` is present before the
switch has installed the agent-shell package. Between merge and switch, `C-c C-'` and `C-c r`
are void functions. Merge and switch back to back.

Once the branch is pushed, the override is no longer needed:
```bash
cd ~/dotfiles && nix flake update emanix
sudo nixos-rebuild switch --flake ~/dotfiles#whistle
```
Pushing emanix from whistle needs the rafik relay — the GitHub identity whistle uses has no
access to the emanix repo.

Expected: switch completes.

- [ ] **Step 2: Install the adapter payload**

Run: `claude-acp-update`
Expected: npm installs `@agentclientprotocol/claude-agent-acp`. Then confirm the wrapper works:

```bash
claude-agent-acp --version
```
Expected: a version number (0.75.1 or later), not the "payload is not installed" error.

- [ ] **Step 3: Prove it under systemd, not just the shell**

This is the check that matters. The Emacs daemon is a systemd user service with a minimal PATH; a wrapper that only works in your interactive shell passes every earlier step and still fails in use.

```bash
systemd-run --user --pipe --wait --quiet claude-agent-acp --version
```
Expected: the same version number. A `command not found` or a shebang error here means the wrapper is not on the user manager's PATH and the elisp `executable-find` will fail the same way.

- [ ] **Step 4: Restart Emacs and start a Claude shell**

```bash
systemctl --user restart emacs
```
Then in Emacs: `C-c C-'`.
Expected: an agent-shell buffer, ASCII banner, "Agent capabilities" list, and a `Claude>` prompt — with **no authentication prompt**, because it uses the existing `claude` subscription login.

- [ ] **Step 5: Verify the real Claude Code config loaded**

At the `Claude>` prompt, type `/` and submit.
Expected: the slash command list includes your plugin commands (`/security-review`, `/skill-doctor`, `/team-onboarding`). Their presence is the proof that `settingSources ["user" "project" "local"]` reached a real Claude Code — CLAUDE.md, skills and hooks come with them.

- [ ] **Step 6: Verify buffer coherence, all four behaviours**

In a scratch git repo:

1. **Write, clean buffer.** Open a file, put point mid-buffer, ask the agent to append a line. Expected: the buffer updates without a revert prompt, point does not move, the buffer is not marked modified.
2. **Undo.** Press `C-/`. Expected: the agent's edit is undone. (A `revert-buffer` implementation would fail here — this is the assertion that proves `replace-buffer-contents` is doing its job.)
3. **Write, dirty buffer.** Make an unsaved edit, then ask the agent to change the same file. Expected: the echo area says `... changed on disk but the buffer has unsaved edits`, and your edit survives.
4. **Read.** Type a distinctive token into a buffer without saving, then ask the agent what the file's last line is. Expected: it answers with your unsaved token.

- [ ] **Step 7: Verify pi and send-region**

- `C-c p` → reports that a pi ACP adapter is missing. This is correct, not a failure: no
  `pi-acp` binary is packaged, and choosing among the community forks was left to you. It
  opens a real pi shell only once one is installed.
- Select a region in a file, press `C-c r` → the region reaches an agent shell.

- [ ] **Step 8: Repeat Steps 1-7 on rafik**

```bash
ssh rafik
cd ~/projects/emanix && git fetch --all && git checkout agent-shell-acp
sudo nixos-rebuild switch --flake ~/dotfiles#rafik \
  --override-input emanix path:/home/scott/projects/emanix
claude-acp-update
```
Then Steps 3-7 again. rafik is a different role (workstation, not WSL) and runs EWM, so **Step 7 must also cover `s-S-<return>` from an EWM slot** — that binding does not exist on whistle.

- [ ] **Step 9: Commit nothing, report**

There is nothing to commit. Report which of the four coherence behaviours passed on each host. If any failed, the failure is in Task 3's wiring, not Task 2's logic — Task 2's tests already passed in CI, so start by checking whether `agent-shell-mode-hook` fired (`M-x` `emanix/agent-shell--install` should be on it) rather than re-reading the sync function.

---

## Rollback

Every task is one commit and the elisp is live-symlinked, so recovery is `git revert` plus `systemctl --user restart emacs` — no rebuild needed for the elisp half. The package set and the wrapper do need a rebuild.

The terminal route is untouched throughout: `claude` and `pi` remain on PATH, and ghostel/zellij still work. Immediate cutover removes the *Emacs* integration, not the agents.

## Deferred

Named here so they are not rediscovered as surprises:

- **The Emacs MCP tools** (xref, apropos, tree-sitter, imenu, project, flymake) that claude-code-ide exposed to Claude. `claude-code-ide-mcp-server-ensure-server` can run standalone, so restoring them is possible and would be its own spec.
- **zellaude** becomes dead weight once Claude stops running in zellij, but it is Syncthing-replicated with no push target and deserves its own decision.
- **The upstream issue** against `claude-agent-acp` asking it to honour `clientCapabilities.fs`, with Gemini CLI's gating as the reference implementation. Outward-facing, so it needs its own approval.
