# ni — the eminix distribution assistant

**Date:** 2026-07-18
**Status:** design approved, pre-implementation
**Host:** eminix (ThinkPad T14 Gen 5 AMD, Ryzen 8-core, Radeon 780M, 16 GB RAM)

## Goal

A local, offline, **config-aware** assistant that lives inside Emacs and answers
Emacs / Linux / NixOS questions grounded in *this machine's actual configuration*
via retrieval-augmented generation (RAG). It should feel like a piece of the
eminix OS — invoked by keybinding, no cloud, no API keys. Working name: **ni**
(from em-i-nix).

Non-goals for v1 are listed under [Out of scope](#out-of-scope).

## Approach

Chosen: **A1 — fork ELISA and port its vector backend from `sqlite-vss` to
`sqlite-vec`.**

ELISA ("Emacs Lisp Information System Assistant", by the ellama author) is a
local RAG system for Emacs: it indexes Info manuals, files, and directories,
embeds them, and answers questions via a local model through `ellama`/`llm`. It
is the near-perfect substrate for ni. But it hard-depends on `sqlite-vss`, which
is:

- **abandoned upstream** (asg017 moved to `sqlite-vec`);
- **`broken = true` in nixpkgs** (`available = false`, refuses to evaluate —
  verified on eminix);
- a **known pain point in ELISA itself** — open issues #26 ("Port to
  sqlite-vec") and #39 ("no such module: vss0").

`sqlite-vec` (the maintained successor) **builds clean on eminix**
(`nixpkgs#sqlite-vec` → v0.1.6). ELISA is **GPL-3.0**, dormant (~17 months since
last commit as of this writing) but historically PR-friendly. Its README invites
exactly this: *"you can write a module and share it on a different archive."*

Rejected alternatives:

- **A2 — patchelf the prebuilt sqlite-vss binaries.** Works today but props up a
  dead extension the project itself is trying to leave; fragile long-term
  maintenance of abandoned faiss binaries. Rejected.
- **C — custom RAG on sqlite-vec, no ELISA.** Avoids the broken dep but throws
  away ELISA's Info-manual indexing, hybrid search, chunking, and reranking —
  all code we'd rewrite. Kept only as an emergency fallback if the port proves
  intractable.

**Sequencing: fork-first.** No patchelf spike. The port is step one; nothing
downstream depends on sqlite-vss ever running here.

## Fork

- Upstream: `github.com/s-kostyaev/elisa` (GPL-3.0).
- Fork: **`github.com/scott-whitson/elisa`** (public). Port work lands on a
  branch here (e.g. `sqlite-vec`).
- Upstream contribution is **optional and deferred**: a change this size is a
  "major contribution" and ELISA is ELPA-bound, so merging upstream would
  require **FSF copyright-assignment papers**. The fork is self-sufficient and
  used directly regardless; issue #26 is the future PR target if Scott ever
  chooses to do the paperwork.

## Architecture

```
  ┌─ Emacs (EWM) ─────────────────────────────────┐
  │  scott-ni.el  →  elisa (fork)  ←→  ellama/llm  │
  │      (collections, prompt, keybinds, model)    │
  │           │ sqlite + vec0.so (Nix store)       │
  │           ▼                                    │
  │   ~/.emacs.d/elisa.db  (vectors + FTS5)        │
  └───────────┬─────────────────────────────────────┘
              │ HTTP :11434
  ┌───────────▼──── Ollama (HM user systemd svc) ──┐
  │  chat:  qwen2.5-coder:3b (default) / :7b        │
  │  embed: nomic-embed-text                         │
  └──────────────────────────────────────────────────┘
```

Everything runs locally on eminix. No network calls at query time; no secrets
(a local model needs none — the agenix/OpenRouter pattern is unrelated here).

### Components & repo placement

`i-intelligence/` is the Home-Manager tree; ni lives there alongside `pi.nix`.

| Component | Location | Notes |
|---|---|---|
| Ollama service + models | **new** `ioshi/i-intelligence/ollama.nix` | HM `services.ollama`; added to `i-intelligence/default.nix` imports. |
| Emacs packages (`ellama`, `llm`, forked `elisa`) | `ioshi/i-intelligence/emacs/packages.nix` | forked elisa consumed via a flake input + `src` override (see below). |
| ni glue | **new** `ioshi/i-intelligence/emacs/lisp/scott-ni.el` | collections, system prompt, model toggle, keybinds, extension path. |
| init wiring | `ioshi/i-intelligence/emacs/init.el` | `(require 'scott-ni nil :no-error)`. |
| vec0 extension | `nixpkgs#sqlite-vec` | no custom derivation; path passed to Emacs via env var (below). |

### Consuming the fork in Nix

Add the fork as a flake input:

```nix
elisa-src = { url = "github:scott-whitson/elisa/sqlite-vec"; flake = false; };
```

In `emacs/packages.nix`, override the emacs-overlay `elisa` recipe's source to
the fork (keeps the working build recipe, swaps in ported code):

```nix
elisa = esuper.elisa.overrideAttrs (_: { src = inputs.elisa-src; });
```

(Exact override site — overlay vs. `withPackages` list — is a plan detail.)

### Passing the vec0 path (liveElisp-safe)

`scott-ni.el` is an out-of-store live symlink (liveElisp mode), so it must not
contain a hard-coded `/nix/store/...` path. Instead the EWM/emacs session
exports `ELISA_VEC0_PATH=${pkgs.sqlite-vec}/lib/vec0.so` (set where the emacs
daemon's environment is defined, e.g. `ewm.nix`), and `scott-ni.el` reads it via
`(getenv "ELISA_VEC0_PATH")` to set the ported `elisa-sqlite-vec-path`. This
keeps the store reference in Nix and the elisp editable live.

## The port (sqlite-vss → sqlite-vec)

Confined to ~8 spots in `elisa.el` (1537 lines); the rest is untouched.

**Delete** (impure download machinery, unnecessary under Nix):
- `elisa-sqlite-vss-version`, `elisa-sqlite-vss-path`, `elisa-sqlite-vector-path`
  defcustoms (147–155).
- `elisa-sqlite-vss-download-url` (292–312), `elisa-download-sqlite-vss`
  (330–340), `elisa--vss-path` / `elisa--vector-path` (315–327).

**Add:** `elisa-sqlite-vec-path` defcustom (single extension path), defaulting
to `(getenv "ELISA_VEC0_PATH")`.

**Rewrite:**
- **CREATE** (355): `... USING vss0(embedding(DIM));`
  → `... USING vec0(embedding float[DIM]);`
- **Extension load** (400–404): the `vector0` + `vss0` pair → a single
  `sqlite-load-extension db <vec0>`, and the "please run
  elisa-download-sqlite-vss" warning → a clear "set ELISA_VEC0_PATH / install
  sqlite-vec" message.
- **INSERT** (548) + `elisa-vector-to-sqlite`: emit an embedding literal
  sqlite-vec accepts (JSON array text `'[...]'`).
- **KNN search SELECT**: vss's `vss_search(embedding, vss_search_params(?, k))`
  → sqlite-vec's `WHERE embedding MATCH '[...]' AND k = N ORDER BY distance`.

**Untouched:** FTS5 table + hybrid (semantic + full-text) search, reranking,
`collections`/`kinds`/`data`/`files` schema, Info-manual parsing, async
chunking/embedding, progress reporting.

**Verification of the port:** create the vec0 table, insert a known embedding,
run a KNN query, confirm a plausible nearest-neighbor result end-to-end through
`elisa-chat` against Ollama.

## Corpus & collections

Default **on** (the distro-assistant core):

1. **Your `dotfiles/` repo** — nix + elisp; the "knows-my-box" win.
2. **NixOS + Home-Manager options** — generated from *this machine's own*
   `nixosConfigurations.eminix` option docs so names/types/defaults are correct
   and version-matched (kills the top hallucination class). Generation method is
   a plan detail (e.g. `optionsDoc` → text/markdown fed as a file collection).
3. **Emacs + Elisp Info manuals** — ELISA's native strength.
4. **Your `emacs/lisp/*.el`** — your own `scott-*.el` conventions.

Default **off**, one-line toggle in `scott-ni.el`:

5. **nixpkgs source** — huge; opt-in only.
6. **`~/docs/org` (org-roam vault)** — personal notes. Kept out of distro answers
   by default; when enabled it is wired to its **own** command (`ni-ask-notes`),
   so notes never bleed into "how do I configure X" answers.

## Interaction surface

Keybind prefix `C-c i` ("intelligence"); confirm no collision with the existing
map before binding.

| Binding | Command | Action |
|---|---|---|
| `C-c i i` | `ni-ask` | ELISA chat with the distro system prompt. |
| `C-c i r` | `ni-reindex` | Manual, incremental re-embed of changed collections. |
| `C-c i m` | `ni-toggle-model` | Flip chat model 3b ⇄ 7b live. |
| `C-c i n` | `ni-ask-notes` | Query the org-roam vault (only bound if that toggle is on). |

System prompt frames ni as *"the eminix assistant — Emacs / NixOS / Linux;
answer from retrieved context; say when unsure."*

## Models & performance

- `services.ollama.loadModels = [ "qwen2.5-coder:3b" "qwen2.5-coder:7b"
  "nomic-embed-text" ]`.
- Default chat model: **`qwen2.5-coder:3b`** (snappy, ~20–25 tok/s on CPU;
  RAG grounding covers the smaller model). `7b` installed as the live toggle for
  harder reasoning (~8–14 tok/s).
- Embeddings: `nomic-embed-text`.
- `num_thread` = physical core count; `keep_alive` long (e.g. `"30m"`) so the
  model stays warm between questions.
- **CPU-only.** ROCm on the Radeon 780M (gfx1103) is officially unsupported and
  needs `HSA_OVERRIDE_GFX_VERSION` hacks — documented as a default-off future
  experiment, not a v1 dependency. Engine stays **Ollama** (it *is* llama.cpp
  underneath; swapping engines buys ~0 CPU throughput for real integration cost).

## Reindexing

**Manual only** for v1 — `ni-reindex`, incremental (ELISA re-embeds only changed
chunks). Rebuild-activation hook and systemd timer are explicitly deferred (each
a later one-liner if manual becomes tedious).

## Out of scope

Apache Tika / PDF ingestion; web-search augmentation; the rebuild-activation
reindex hook; ROCm acceleration; multi-machine sync of the vector DB (it is a
local rebuild artifact — regenerated per box, never synced); upstreaming the
fork (deferred, optional).

## Risks

| Risk | Mitigation |
|---|---|
| Port harder than scoped (KNN/embedding literal semantics differ). | Scope is ~8 localized spots; verify with a one-doc end-to-end test before wiring the full corpus. Fallback C (custom on sqlite-vec) reuses the same Ollama/ellama/corpus design if the port is intractable. |
| `sqlite-load-extension` unavailable in the Nix-built Emacs. | ELISA already relies on it; confirm the emacs-overlay build enables sqlite + load-extension early. |
| Fork `src` override fights the emacs-overlay recipe. | Pin as `flake = false` input; if `overrideAttrs` is awkward, build via `melpaBuild`/`trivialBuild` in the package list. |
| NixOS options corpus generation format. | Plan-phase spike; `optionsDoc` text is the likely source. |
| 3b too weak even with RAG. | One-line switch to 7b already built in (`ni-toggle-model`). |

## Propagation

Standard eminix path: commit on the WSL box or datacore → push to GitHub → eminix
`git fetch && merge --ff-only origin/main` (eminix has no GitHub key; pulls via
datacore mirror). The forked-elisa flake input resolves over public HTTPS at eval
time, so eminix needs no GitHub SSH key for it. Never `git add -A` (avoids the
perpetually-dirty `base/claude/.claude/settings.json`).
