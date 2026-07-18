# ni — eminix distribution assistant — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A local, offline, config-aware Emacs assistant ("ni") that answers Emacs/Linux/NixOS questions grounded in eminix's own configuration via RAG.

**Architecture:** A forked ELISA (ported from the abandoned `sqlite-vss` to the maintained `sqlite-vec`) runs inside Emacs, retrieves from local collections (dotfiles, NixOS options, Emacs Info manuals), and answers via `ellama`, with all inference served by a local Ollama (`qwen2.5-coder:3b` chat + `nomic-embed-text` embeddings). Two repos: the `scott-whitson/elisa` fork and `dotfiles`.

**Tech Stack:** NixOS + Home-Manager (flakes), Emacs (nix-built `emacs-pgtk`, liveElisp), Ollama, sqlite-vec, ELISA/ellama/llm (Elisp).

## Global Constraints

- **Fork:** all ELISA changes land on `github.com/scott-whitson/elisa`, branch `sqlite-vec` (public, GPL-3.0). Never edit upstream.
- **sqlite-vec extension path:** `${pkgs.sqlite-vec}/lib/vec0.so` (built path on eminix today: `/nix/store/77440dch8lnph95xaj5fs634iwvgvmja-sqlite-vec-0.1.6/lib/vec0.so`). Passed to Emacs via env var `ELISA_VEC0_PATH`; never hard-code a store path in elisp (liveElisp files are out-of-store).
- **Models:** chat default `qwen2.5-coder:3b`, toggle `qwen2.5-coder:7b`; embeddings `nomic-embed-text`. CPU-only (Radeon 780M / gfx1103 ROCm unsupported — do not enable acceleration).
- **Keybind prefix:** `C-c i` (verify no collision before binding).
- **Testing runs on eminix** (`ssh eminix`) — the only host with Emacs + deps + sqlite-vec + Ollama. The WSL box has no Nix and no Emacs; it is the git-push host only.
- **No `git add -A`** in `dotfiles` (avoids the perpetually-dirty `base/claude/.claude/settings.json`) — always add explicit paths.
- **No `Co-Authored-By` trailers** in any commit (dotfiles or fork).
- **Propagation of `dotfiles` changes** (eminix has no GitHub key): commit+push on WSL → GitHub; on datacore `cd ~/dotfiles && git pull`; on eminix `cd ~/dotfiles && git fetch && git merge --ff-only origin/main` (eminix `origin` = datacore mirror). Elisp files are liveElisp (the `lisp/` dir and `init.el` are symlinked into the checkout) → a git pull on eminix makes them live; only **reload/restart Emacs**, no rebuild. Nix changes (`*.nix`) require `sudo nixos-rebuild switch --flake .#eminix` on eminix.
- **Emacs reload after elisp change:** `XDG_RUNTIME_DIR=/run/user/1000 emacsclient -e '(load "scott-ni")'` (or restart the daemon).

## File Structure

**Fork repo (`scott-whitson/elisa`, branch `sqlite-vec`):**
- Modify `elisa.el` — port vector backend sqlite-vss → sqlite-vec (~8 localized spots).

**dotfiles repo:**
- Create `ioshi/i-intelligence/ollama.nix` — HM Ollama service + models.
- Create `ioshi/i-intelligence/emacs/lisp/scott-ni.el` — ni glue (providers, prompt, collections, keybinds, model toggle).
- Create `ioshi/os-system/ni-options-doc.nix` — system module rendering NixOS options → `/etc/ni/nixos-options.md` for indexing.
- Modify `ioshi/i-intelligence/emacs/packages.nix` — add `ellama`, `llm`, and the forked `elisa` (fetchFromGitHub + overrideAttrs).
- Modify `ioshi/i-intelligence/ewm.nix` — export `ELISA_VEC0_PATH` to the Emacs session.
- Modify `ioshi/i-intelligence/default.nix` — import `ollama.nix`.
- Modify `ioshi/i-intelligence/emacs/init.el` — require `scott-ni`.
- Modify `hosts/eminix/configuration.nix` — import `ni-options-doc.nix`.
- Create test scratch `~/src/ni-tests/` on eminix (not committed) — batch ERT harnesses.

---

## Task 1: Validate the sqlite-vec SQL forms end-to-end (keystone)

Proves the exact CREATE / INSERT / KNN SQL the port will generate actually works with the real `vec0` extension in eminix's Emacs — before touching ELISA. No ELISA deps, no Ollama.

**Files:**
- Test (eminix, scratch): `~/src/ni-tests/test-vec0.el`

**Interfaces:**
- Produces (the validated SQL forms every later task reuses):
  - vector literal: `vec_f32('[<json-array>]')`
  - create: `CREATE VIRTUAL TABLE ... USING vec0(embedding float[N]);`
  - insert: `INSERT INTO t(rowid, embedding) VALUES (<int>, vec_f32('[...]'));`
  - KNN: `SELECT rowid, distance FROM t WHERE embedding MATCH vec_f32('[...]') AND k = N ORDER BY distance ASC;`

- [ ] **Step 1: Write the failing test**

Create `~/src/ni-tests/test-vec0.el` on eminix:

```elisp
;;; test-vec0.el --- validate sqlite-vec SQL forms -*- lexical-binding: t; -*-
(require 'ert)
(require 'json)

(defvar tv-vec0 (or (getenv "ELISA_VEC0_PATH")
                    "/nix/store/77440dch8lnph95xaj5fs634iwvgvmja-sqlite-vec-0.1.6/lib/vec0.so"))

(defun tv-lit (v) (format "vec_f32('%s')" (json-encode v)))

(ert-deftest tv-create-insert-knn ()
  (should (fboundp 'sqlite-load-extension))
  (should (file-exists-p tv-vec0))
  (let ((db (sqlite-open)))            ; in-memory
    (sqlite-load-extension db tv-vec0)
    (sqlite-execute db "CREATE VIRTUAL TABLE t USING vec0(embedding float[3]);")
    (sqlite-execute db (format "INSERT INTO t(rowid, embedding) VALUES (1, %s);" (tv-lit [1.0 0.0 0.0])))
    (sqlite-execute db (format "INSERT INTO t(rowid, embedding) VALUES (2, %s);" (tv-lit [0.0 1.0 0.0])))
    (sqlite-execute db (format "INSERT INTO t(rowid, embedding) VALUES (3, %s);" (tv-lit [0.9 0.1 0.0])))
    (let ((res (sqlite-select
                db (format "SELECT rowid, distance FROM t WHERE embedding MATCH %s AND k = 2 ORDER BY distance ASC;"
                           (tv-lit [1.0 0.0 0.0])))))
      ;; nearest to [1,0,0] is rowid 1, then rowid 3
      (should (equal (mapcar #'car res) '(1 3))))))
```

- [ ] **Step 2: Run it and watch it pass (or fail loudly)**

Run:
```bash
ssh eminix 'mkdir -p ~/src/ni-tests && cat > ~/src/ni-tests/test-vec0.el' < <printed-file>   # or scp the file
ssh eminix 'ELISA_VEC0_PATH=$(nix build --no-link --print-out-paths nixpkgs#sqlite-vec)/lib/vec0.so \
  emacs -Q --batch -l ert -l ~/src/ni-tests/test-vec0.el -f ert-run-tests-batch-and-exit'
```
Expected: `Ran 1 tests ... 0 unexpected`. If it fails on `MATCH ... AND k =` syntax or the distance column, STOP — the SQL forms are wrong and every later task inherits them; fix here first.

- [ ] **Step 3: No commit** (scratch test, eminix-only). Record the confirmed SQL forms in the task's Interfaces block above as the source of truth.

---

## Task 2: Ollama service + models (HM module)

ELISA calls the embedding provider at load time (its `data_embeddings` table dimension comes from `nomic-embed-text`), so Ollama + models must exist before the ported ELISA runs.

**Files:**
- Create: `ioshi/i-intelligence/ollama.nix`
- Modify: `ioshi/i-intelligence/default.nix` (add import)

**Interfaces:**
- Produces: a running user service at `http://localhost:11434` with models `qwen2.5-coder:3b`, `qwen2.5-coder:7b`, `nomic-embed-text` present.

- [ ] **Step 1: Write `ollama.nix`**

```nix
{ config, lib, pkgs, ... }:
{
  # Local inference host for ni (the eminix assistant). Home-Manager user
  # service — keeps ni in the i-intelligence tree next to pi.nix. CPU-only:
  # the Radeon 780M (gfx1103) is unsupported by ROCm, and Ollama auto-detects
  # CPU cores, so no acceleration or num_thread tuning is set here.
  services.ollama = {
    enable = true;
    loadModels = [
      "qwen2.5-coder:3b"   # ni default chat model (snappy, RAG-grounded)
      "qwen2.5-coder:7b"   # heavier reasoning toggle
      "nomic-embed-text"   # embeddings for ELISA
    ];
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "30m";   # keep the model warm between questions
    };
  };
}
```

- [ ] **Step 2: Import it**

In `ioshi/i-intelligence/default.nix`, add `./ollama.nix` to the "Core" imports (next to `./pi.nix`).

- [ ] **Step 3: Propagate + rebuild**

Commit both files (`git add ioshi/i-intelligence/ollama.nix ioshi/i-intelligence/default.nix`), push, propagate to eminix (see Global Constraints), then:
```bash
ssh eminix 'cd ~/dotfiles && sudo nixos-rebuild switch --flake .#eminix'
```

- [ ] **Step 4: Verify service + models**

Run:
```bash
ssh eminix 'systemctl --user is-active ollama; curl -s localhost:11434/api/tags | grep -o "qwen2.5-coder:[0-9]*b\|nomic-embed-text"'
```
Expected: `active`, and all three model names listed (model pulls may take minutes on first switch; re-run until present).

- [ ] **Step 5: Commit** — already committed in Step 3.

---

## Task 3: Export `ELISA_VEC0_PATH` to the Emacs session

**Files:**
- Modify: `ioshi/i-intelligence/ewm.nix`

**Interfaces:**
- Produces: env var `ELISA_VEC0_PATH=${pkgs.sqlite-vec}/lib/vec0.so` present in the EWM Emacs daemon's environment.

- [ ] **Step 1: Add the session variable**

In `ioshi/i-intelligence/ewm.nix`, inside the module attrset (e.g. after `hardware.graphics.enable = true;`), add:

```nix
  # ni reads this to load the sqlite-vec (vec0) extension into ELISA's DB;
  # keeps the /nix/store path in Nix so the liveElisp scott-ni.el stays
  # store-path-free. Present in the login shell → inherited by the EWM daemon.
  environment.sessionVariables.ELISA_VEC0_PATH = "${pkgs.sqlite-vec}/lib/vec0.so";
```

- [ ] **Step 2: Propagate + rebuild**

`git add ioshi/i-intelligence/ewm.nix`, commit, push, propagate, rebuild (as Task 2 Step 3).

- [ ] **Step 3: Verify in the live daemon**

Run:
```bash
ssh eminix 'XDG_RUNTIME_DIR=/run/user/1000 emacsclient -e "(getenv \"ELISA_VEC0_PATH\")"'
```
Expected: a `/nix/store/...-sqlite-vec-.../lib/vec0.so` path (non-nil). If nil, the daemon predates the rebuild — restart EWM (log out of tty1) and re-check.

- [ ] **Step 4: Commit** — already committed in Step 2.

---

## Task 4: Fork checkout + Emacs deps (ellama, llm) for porting

Provides the dev environment: the fork cloned for editing (WSL) and testing (eminix), with ELISA's deps present in eminix's Emacs so the fork's `elisa.el` can be loaded during port testing.

**Files:**
- Modify: `ioshi/i-intelligence/emacs/packages.nix` (add `ellama`, `llm`)

**Interfaces:**
- Produces: `~/src/elisa` clones on WSL (pushable) and eminix (testable); `(require 'llm-ollama)` and `(require 'ellama)` succeed in eminix's Emacs.

- [ ] **Step 1: Clone the fork (WSL, canonical/pushable)**

```bash
git clone git@github.com:scott-whitson/elisa.git ~/src/elisa
cd ~/src/elisa && git checkout -b sqlite-vec
```

- [ ] **Step 2: Clone the fork (eminix, read-only for tests)**

```bash
ssh eminix 'git clone https://github.com/scott-whitson/elisa.git ~/src/elisa 2>/dev/null; cd ~/src/elisa && git fetch && git checkout -B sqlite-vec origin/main'
```
(Public HTTPS clone needs no key; we sync the working file via `scp` during porting.)

- [ ] **Step 3: Add deps to the Emacs package set**

In `ioshi/i-intelligence/emacs/packages.nix`, in the `list = epkgs: with epkgs; [ ... ]` vector, add (near `magit`):
```nix
    ellama
    llm
```

- [ ] **Step 4: Propagate + rebuild, then verify deps load**

Commit (`git add ioshi/i-intelligence/emacs/packages.nix`), push, propagate, rebuild (Task 2 Step 3). Then:
```bash
ssh eminix 'emacs --batch --eval "(progn (require (quote llm-ollama)) (require (quote ellama)) (princ :ok))"'
```
Expected: prints `:ok` with no error.

- [ ] **Step 5: Commit** — already committed in Step 4.

---

## Task 5: Port ELISA — extension load + defcustoms (remove sqlite-vss)

**Files:**
- Modify (fork): `~/src/elisa/elisa.el`
- Test (eminix scratch): `~/src/ni-tests/test-elisa-init.el`

**Interfaces:**
- Consumes: the validated SQL forms (Task 1); `ELISA_VEC0_PATH` (Task 3).
- Produces: new defcustom `elisa-sqlite-vec-path` (default `(getenv "ELISA_VEC0_PATH")`); `elisa--init-db` loads the single `vec0` extension. Removes `elisa-sqlite-vss-version`, `elisa-sqlite-vss-path`, `elisa-sqlite-vector-path`, `elisa--vss-path`, `elisa--vector-path`, `elisa-sqlite-vss-download-url`, `elisa-download-sqlite-vss`.

- [ ] **Step 1: Write the failing test**

`~/src/ni-tests/test-elisa-init.el` — loads the fork's elisa.el and checks the DB initialized (embeddings table created via vec0) without the vss machinery. Requires Ollama up (Task 2) for `elisa-get-embedding-size`.

```elisp
;;; test-elisa-init.el -*- lexical-binding: t; -*-
(require 'ert)
(add-to-list 'load-path (expand-file-name "~/src/elisa"))
(setenv "ELISA_VEC0_PATH"
        (or (getenv "ELISA_VEC0_PATH")
            "/nix/store/77440dch8lnph95xaj5fs634iwvgvmja-sqlite-vec-0.1.6/lib/vec0.so"))

(ert-deftest ei-no-vss-symbols ()
  (require 'elisa)
  (should (boundp 'elisa-sqlite-vec-path))
  (should-not (fboundp 'elisa--vss-path))
  (should-not (fboundp 'elisa-download-sqlite-vss))
  (should-not (boundp 'elisa-sqlite-vss-path)))

(ert-deftest ei-embeddings-table-is-vec0 ()
  (require 'elisa)
  ;; data_embeddings must exist and be a vec0 virtual table
  (let ((sql (caar (sqlite-select
                    elisa-db
                    "SELECT sql FROM sqlite_master WHERE name = 'data_embeddings';"))))
    (should (string-match-p "USING vec0" sql))))
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
scp ~/src/elisa/elisa.el eminix:~/src/elisa/elisa.el   # current (unported) copy
scp ~/src/ni-tests/test-elisa-init.el eminix:~/src/ni-tests/
ssh eminix 'emacs --batch -l ert -l ~/src/ni-tests/test-elisa-init.el -f ert-run-tests-batch-and-exit'
```
Expected: FAIL (`elisa-sqlite-vec-path` unbound; `data_embeddings` uses `vss0`, and load warns to run `elisa-download-sqlite-vss`).

- [ ] **Step 3: Port the defcustoms**

In `~/src/elisa/elisa.el`, replace this block:
```elisp
(defcustom elisa-sqlite-vss-version "v0.1.2"
  "Sqlite VSS version."
  :type 'string)

(defcustom elisa-sqlite-vss-path nil
  "Path to sqlite-vss extension."
  :type 'file)

(defcustom elisa-sqlite-vector-path nil
  "Path to sqlite-vector extension."
  :type 'file)
```
with:
```elisp
(defcustom elisa-sqlite-vec-path (getenv "ELISA_VEC0_PATH")
  "Path to the sqlite-vec (vec0) loadable extension.
Defaults to the ELISA_VEC0_PATH environment variable (set by Nix)."
  :type '(choice (const nil) file))
```

- [ ] **Step 4: Delete the download machinery**

Delete the four contiguous defuns `elisa-sqlite-vss-download-url`, `elisa--vss-path`, `elisa--vector-path`, and `elisa-download-sqlite-vss` (they run from the first `(defun elisa-sqlite-vss-download-url ...` through the closing `(elisa--reopen-db))` of `elisa-download-sqlite-vss`). Verify none remain:
```bash
grep -nE "vss-download-url|elisa--vss-path|elisa--vector-path|elisa-download-sqlite-vss" ~/src/elisa/elisa.el
```
Expected: no output.

- [ ] **Step 5: Port `elisa--init-db`**

Replace the `if`-guard and the two `sqlite-load-extension` lines:
```elisp
  (if (not (file-exists-p (elisa--vss-path)))
      (warn "Please run M-x `elisa-download-sqlite-vss' to use this package")
    (sqlite-pragma db "PRAGMA journal_mode=WAL;")
    (sqlite-load-extension db (elisa--vector-path))
    (sqlite-load-extension db (elisa--vss-path))
```
with:
```elisp
  (if (not (and elisa-sqlite-vec-path (file-exists-p elisa-sqlite-vec-path)))
      (warn "Set `elisa-sqlite-vec-path' (or ELISA_VEC0_PATH) to the sqlite-vec vec0 extension")
    (sqlite-pragma db "PRAGMA journal_mode=WAL;")
    (sqlite-load-extension db elisa-sqlite-vec-path)
```
(Leave the remaining `sqlite-execute` table-creation lines unchanged.)

- [ ] **Step 6: Port the create-table SQL**

Replace:
```elisp
  (format "CREATE VIRTUAL TABLE IF NOT EXISTS data_embeddings USING vss0(embedding(%d));"
	  (elisa-get-embedding-size)))
```
with:
```elisp
  (format "CREATE VIRTUAL TABLE IF NOT EXISTS data_embeddings USING vec0(embedding float[%d]);"
	  (elisa-get-embedding-size)))
```

- [ ] **Step 7: Run the test to confirm it passes**

```bash
scp ~/src/elisa/elisa.el eminix:~/src/elisa/elisa.el
ssh eminix 'rm -f ~/.config/emacs/elisa/elisa.sqlite 2>/dev/null; rm -f ~/.emacs.d/elisa/elisa.sqlite 2>/dev/null; emacs --batch -l ert -l ~/src/ni-tests/test-elisa-init.el -f ert-run-tests-batch-and-exit'
```
(The `rm` clears any stale vss-era DB so the table is recreated as vec0.)
Expected: `Ran 2 tests ... 0 unexpected`.

- [ ] **Step 8: Commit (fork)**

```bash
cd ~/src/elisa && git add elisa.el && git commit -m "port: load sqlite-vec vec0 extension; drop sqlite-vss download machinery"
```

---

## Task 6: Port ELISA — vector literal, KNN query, async injection

**Files:**
- Modify (fork): `~/src/elisa/elisa.el`
- Test (eminix scratch): `~/src/ni-tests/test-elisa-search.el`

**Interfaces:**
- Consumes: Task 5's ported load path.
- Produces: `elisa-vector-to-sqlite` emits `vec_f32('[...]')`; `elisa--find-similar`'s `vector_search` CTE uses `embedding MATCH %s AND k = 40`; the async worker injects `elisa-sqlite-vec-path` (not the two removed vars). After this task the fork is fully ported and byte-compiles clean.

- [ ] **Step 1: Write the failing test**

`~/src/ni-tests/test-elisa-search.el` — exercises the ported vector functions against a real vec0 table.

```elisp
;;; test-elisa-search.el -*- lexical-binding: t; -*-
(require 'ert)
(add-to-list 'load-path (expand-file-name "~/src/elisa"))
(setenv "ELISA_VEC0_PATH"
        (or (getenv "ELISA_VEC0_PATH")
            "/nix/store/77440dch8lnph95xaj5fs634iwvgvmja-sqlite-vec-0.1.6/lib/vec0.so"))
(require 'elisa)

(ert-deftest es-vector-literal ()
  (should (equal (elisa-vector-to-sqlite [0.5 0.25])
                 "vec_f32('[0.5,0.25]')")))

(ert-deftest es-knn-roundtrip ()
  (let ((db (sqlite-open)))
    (sqlite-load-extension db elisa-sqlite-vec-path)
    (sqlite-execute db "CREATE VIRTUAL TABLE data_embeddings USING vec0(embedding float[3]);")
    (dolist (row '((1 . [1.0 0.0 0.0]) (2 . [0.0 1.0 0.0]) (3 . [0.9 0.1 0.0])))
      (sqlite-execute db (format "INSERT INTO data_embeddings(rowid, embedding) VALUES (%d, %s);"
                                 (car row) (elisa-vector-to-sqlite (cdr row)))))
    (let ((res (sqlite-select
                db (format "SELECT rowid, distance FROM data_embeddings WHERE embedding MATCH %s AND k = 2 ORDER BY distance ASC;"
                           (elisa-vector-to-sqlite [1.0 0.0 0.0])))))
      (should (equal (mapcar #'car res) '(1 3))))))

(ert-deftest es-async-injects-vec-path ()
  ;; the async worker must no longer reference the removed vars
  (with-temp-buffer
    (insert-file-contents (expand-file-name "~/src/elisa/elisa.el"))
    (should (search-forward "async-inject-variables \"elisa-sqlite-vec-path\"" nil t))
    (goto-char (point-min))
    (should-not (search-forward "elisa-sqlite-vss-path" nil t))
    (goto-char (point-min))
    (should-not (search-forward "elisa-sqlite-vector-path" nil t))))
```

- [ ] **Step 2: Run to confirm failure**

```bash
scp ~/src/ni-tests/test-elisa-search.el eminix:~/src/ni-tests/
ssh eminix 'emacs --batch -l ert -l ~/src/ni-tests/test-elisa-search.el -f ert-run-tests-batch-and-exit'
```
Expected: FAIL (`elisa-vector-to-sqlite` still emits `vector_from_json(...)`; async still injects the old vars).

- [ ] **Step 3: Port `elisa-vector-to-sqlite`**

Replace:
```elisp
  (format "vector_from_json(json('%s'))" (json-encode data)))
```
with:
```elisp
  (format "vec_f32('%s')" (json-encode data)))
```

- [ ] **Step 4: Port the KNN CTE in `elisa--find-similar`**

Replace:
```elisp
  SELECT rowid, distance
  FROM data_embeddings
  WHERE vss_search(embedding, %s)
  ORDER BY distance ASC
  LIMIT 40
```
with:
```elisp
  SELECT rowid, distance
  FROM data_embeddings
  WHERE embedding MATCH %s
    AND k = 40
  ORDER BY distance ASC
```

- [ ] **Step 5: Port the async var injection**

Replace:
```elisp
		    ,(async-inject-variables "elisa-sqlite-vector-path")
		    ,(async-inject-variables "elisa-sqlite-vss-path")
```
with:
```elisp
		    ,(async-inject-variables "elisa-sqlite-vec-path")
```

- [ ] **Step 6: Confirm no vss remnants anywhere**

```bash
grep -nE "vss|vector_from_json|vector0" ~/src/elisa/elisa.el
```
Expected: no output (all references gone).

- [ ] **Step 7: Run the tests + byte-compile clean**

```bash
scp ~/src/elisa/elisa.el eminix:~/src/elisa/elisa.el
ssh eminix 'emacs --batch -l ert -l ~/src/ni-tests/test-elisa-search.el -f ert-run-tests-batch-and-exit'
ssh eminix 'emacs --batch --eval "(setq byte-compile-error-on-warn nil)" -f batch-byte-compile ~/src/elisa/elisa.el'
```
Expected: `Ran 3 tests ... 0 unexpected`; byte-compile produces `elisa.elc` with no errors (undefined-function/unresolved warnings about the removed defuns must be absent).

- [ ] **Step 8: Commit + push the fork**

```bash
cd ~/src/elisa && git add elisa.el && git commit -m "port: sqlite-vec KNN (MATCH/k), vec_f32 literal, single async path var" && git push -u origin sqlite-vec
```
Record the pushed commit SHA — Task 7 pins it.

---

## Task 7: Wire the forked ELISA into the Emacs build

**Files:**
- Modify: `ioshi/i-intelligence/emacs/packages.nix`

**Interfaces:**
- Consumes: the pushed fork commit (Task 6).
- Produces: `epkgs.elisa` in `theEmacs` built from the sqlite-vec fork; `(require 'elisa)` succeeds in the built Emacs (Ollama up, `ELISA_VEC0_PATH` set).

- [ ] **Step 1: Get the fetchFromGitHub hash**

```bash
ssh eminix 'nix run nixpkgs#nix-prefetch-github -- scott-whitson elisa --rev <PORT_COMMIT_SHA>'
```
Copy the `hash` value from the JSON output.

- [ ] **Step 2: Override elisa's source in `packages.nix`**

In `ioshi/i-intelligence/emacs/packages.nix`, in the `list` vector, replace the bare `ellama`/`llm` additions region by adding the forked elisa alongside them:
```nix
    ellama
    llm
    (elisa.overrideAttrs (_: {
      src = pkgs.fetchFromGitHub {
        owner = "scott-whitson";
        repo = "elisa";
        rev = "<PORT_COMMIT_SHA>";
        hash = "<HASH_FROM_STEP_1>";
      };
    }))
```
(`elisa`'s MELPA recipe pulls `llm`, `ellama`, `async`, `plz` transitively; `ellama`/`llm` are listed explicitly because ni configures them directly.)

- [ ] **Step 3: Propagate + rebuild**

`git add ioshi/i-intelligence/emacs/packages.nix`, commit, push, propagate, rebuild (Task 2 Step 3).

- [ ] **Step 4: Verify elisa loads from the built Emacs**

```bash
ssh eminix 'XDG_RUNTIME_DIR=/run/user/1000 emacsclient -e "(progn (require (quote elisa)) (list (boundp (quote elisa-sqlite-vec-path)) elisa-sqlite-vec-path))"'
```
Expected: `(t "/nix/store/...vec0.so")`. No "run elisa-download-sqlite-vss" warning in `*Messages*`.

- [ ] **Step 5: Commit** — already committed in Step 3.

---

## Task 8: `scott-ni.el` — providers, prompt, keybinds, model toggle

**Files:**
- Create: `ioshi/i-intelligence/emacs/lisp/scott-ni.el`
- Modify: `ioshi/i-intelligence/emacs/init.el`

**Interfaces:**
- Consumes: built forked elisa (Task 7); Ollama (Task 2).
- Produces: interactive commands `scott/ni-ask`, `scott/ni-reindex`, `scott/ni-toggle-model`, `scott/ni-ask-notes`; keymap under `C-c i`.

- [ ] **Step 1: Confirm the keybind prefix is free**

```bash
ssh eminix 'XDG_RUNTIME_DIR=/run/user/1000 emacsclient -e "(key-binding (kbd \"C-c i\"))"'
```
Expected: `nil` (unbound). If bound, choose an alternate prefix and use it consistently below.

- [ ] **Step 2: Write `scott-ni.el`**

```elisp
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
```

- [ ] **Step 3: Require it from `init.el`**

At the end of `ioshi/i-intelligence/emacs/init.el` (after the theme/surfaces block), add:
```elisp
;; ni — local config-aware eminix assistant (Emacs/Linux/NixOS RAG).
(require 'scott-ni nil :no-error)
```

- [ ] **Step 4: Propagate (elisp = pull + reload, no rebuild)**

`git add ioshi/i-intelligence/emacs/lisp/scott-ni.el ioshi/i-intelligence/emacs/init.el`, commit, push, propagate to eminix, then reload:
```bash
ssh eminix 'XDG_RUNTIME_DIR=/run/user/1000 emacsclient -e "(load \"scott-ni\")"'
```

- [ ] **Step 5: Verify commands + keymap**

```bash
ssh eminix 'XDG_RUNTIME_DIR=/run/user/1000 emacsclient -e "(list (commandp (quote scott/ni-ask)) (keymapp scott/ni-map) scott/ni-model)"'
```
Expected: `(t t "qwen2.5-coder:3b")`.

- [ ] **Step 6: Commit** — already committed in Step 4.

---

## Task 9: Corpus — NixOS options doc + first index + smoke

**Files:**
- Create: `ioshi/os-system/ni-options-doc.nix`
- Modify: `hosts/eminix/configuration.nix` (import it)

**Interfaces:**
- Consumes: `scott/ni-*` commands (Task 8).
- Produces: `/etc/ni/nixos-options.md` on eminix (indexable NixOS options corpus); ni's three default collections populated; a working end-to-end answer.

- [ ] **Step 1: Write the options-doc module**

`ioshi/os-system/ni-options-doc.nix` renders the system's own options JSON (a standard NixOS manual build product) to markdown:
```nix
{ config, lib, pkgs, ... }:
let
  # Render THIS machine's declared NixOS options to markdown so ni can retrieve
  # correct option names/types/defaults instead of hallucinating them. Sourced
  # from the manual's optionsJSON (built anyway for the system manual).
  optionsMd = pkgs.runCommand "ni-nixos-options.md" { } ''
    ${pkgs.jq}/bin/jq -r '
      to_entries[]
      | "## \(.key)\n\nType: \(.value.type // "n/a")\nDefault: \(.value.default.text // "n/a")\n\n\(.value.description // "")\n"
    ' ${config.system.build.manual.optionsJSON}/share/doc/nixos/options.json > $out
  '';
in {
  environment.etc."ni/nixos-options.md".source = optionsMd;
}
```

- [ ] **Step 2: Import it**

In `hosts/eminix/configuration.nix`, add `../../ioshi/os-system/ni-options-doc.nix` to that host's `imports` (match the existing relative-path style in that file).

- [ ] **Step 3: Propagate + rebuild + verify the file**

`git add ioshi/os-system/ni-options-doc.nix hosts/eminix/configuration.nix`, commit, push, propagate, rebuild. Then:
```bash
ssh eminix 'wc -l /etc/ni/nixos-options.md && head -20 /etc/ni/nixos-options.md'
```
Expected: a large file (thousands of lines) beginning with `## <option>` entries. If the build is prohibitively slow, note it and reduce scope by pointing `jq` at a filtered subset — but the full doc is the target.

- [ ] **Step 4: Run the first index**

```bash
ssh eminix 'XDG_RUNTIME_DIR=/run/user/1000 emacsclient -e "(scott/ni-reindex)"'
```
This runs in the background (async). Wait for the collections to populate:
```bash
ssh eminix 'sleep 60; XDG_RUNTIME_DIR=/run/user/1000 emacsclient -e "(require (quote elisa))" -e "(sqlite-select elisa-db \"SELECT name, count(*) FROM data JOIN collections ON collection_id=collections.rowid GROUP BY name;\")"'
```
Expected: nonzero row counts for `/home/scott/dotfiles`, `/etc/ni`, and the manuals collections (indexing large corpora can take several minutes; re-check).

- [ ] **Step 5: End-to-end smoke (the spec's verification)**

```bash
ssh eminix 'XDG_RUNTIME_DIR=/run/user/1000 emacsclient -e "(scott/ni-ask \"Which module enables tap-to-click on eminix and how is the touchpad configured?\")"'
```
Expected: an `*elisa*` chat buffer answer that references the user's actual config (e.g. `services.libinput` / `scott-ewm.el` tap settings) — grounded, not generic. Manually confirm in the EWM session that the answer is config-aware and the model responds within a reasonable time on `3b`.

- [ ] **Step 6: Commit** — already committed in Step 3. The plan's feature work is complete.

---

## Self-Review

**Spec coverage:**
- Fork + port to sqlite-vec → Tasks 5–7. ✓
- Ollama service, 3b default/7b toggle, nomic-embed, keep_alive, CPU-only → Task 2, Task 8 (`scott/ni-toggle-model`). ✓ (num_thread dropped: Ollama auto-detects cores; noted in Task 2.)
- Corpus default-on: dotfiles, NixOS options, Emacs Info, lisp → Task 9 (dotfiles collection includes `emacs/lisp`), Task 8 collection list. ✓
- Corpus toggles default-off: nixpkgs (`scott/ni-nixpkgs-path`), org (`scott/ni-ask-notes`) → Task 8. ✓
- Interaction: `C-c i` prefix, ni-ask/reindex/toggle-model/ask-notes → Task 8. ✓
- Manual reindex → Task 8 `scott/ni-reindex`. ✓
- `ELISA_VEC0_PATH` env, liveElisp-safe → Task 3. ✓
- Fork consumed via fetchFromGitHub override (no impure download) → Task 7. ✓
- Emacs sqlite + load-extension capability → verified pre-plan (`(:sqlite t :loadext t)`). ✓

**HM-options note (scope-honest deviation):** the spec listed Home-Manager options in the default-on corpus. Task 9 ships **NixOS** options via `optionsJSON`; HM options lack an equivalent standard JSON product, and the dotfiles collection already carries the machine's actual HM usage. HM-options rendering is deferred as a follow-up (not blocking v1). Flagged here rather than silently dropped.

**Placeholder scan:** `<PORT_COMMIT_SHA>` / `<HASH_FROM_STEP_1>` are real values produced within Tasks 6–7 and consumed in Task 7 (not open TODOs). No other placeholders.

**Type/name consistency:** command names (`scott/ni-ask`, `scott/ni-reindex`, `scott/ni-toggle-model`, `scott/ni-ask-notes`), keymap (`scott/ni-map`), vars (`scott/ni-model`, `scott/ni-collections`), and the elisa symbols (`elisa-sqlite-vec-path`, `elisa-chat`, `elisa-async-parse-directory`, `elisa-parse-builtin-manuals`) are consistent across Tasks 5–9 and match the verified ELISA source.
