# Telegram Org Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture text notes and whiteboard photos sent to a Telegram bot into the `New This Quarter` section of the current work quarterly tracker, running as a container on datacore.

**Architecture:** Part A lands the already-written work-quarterly-tracker branch and runs its file migration, so the capture target is a constructed path rather than a search. Part B builds a Python service whose org-writing core is a pure function over file text — tested on the laptop against copies of the real quarter notes — wrapped by a Telegram long-polling loop. The only model call is whiteboard transcription; text notes need none.

**Tech Stack:** Python 3.13, python-telegram-bot (long polling), Pillow, httpx, pytest, Docker Compose, Emacs Lisp/ERT (Part A), bash (Part A migration), org-roam, Syncthing.

**Spec:** `docs/superpowers/specs/2026-08-12-telegram-org-capture-design.md`

## Global Constraints

- **No `Co-Authored-By` trailers in any commit.**
- **Everything the service writes lives under `~/docs/org/work/`.** That directory holds `.stfolder`; anything outside it does not sync.
- **The service never creates a quarter note.** A missing note parks the capture. On 2026-07-16 an empty `2026-Q3` won a Syncthing conflict and quarantined the real note.
- **Org-escape all inserted body text.** Any line matching `^\*+ ` or `^#\+` gets a leading comma. Applies to user text and model output alike.
- **Writes are append-only and atomic:** build in memory, write a tempfile in the same directory, fsync, `os.replace`. No existing line is ever rewritten.
- **The OpenRouter key is read only from `~/.pi/agent/auth.json`** (`openrouter.key`). It is never copied into `.env`, the image, or compose.
- **Part A must preserve every `:ID:` byte-for-byte.** All inbound links to quarter notes are `[[id:]]` links.
- **Container timezone is `America/New_York`** — datacore's system zone.
- **Python:** `requires-python = ">=3.12"`. Laptop has 3.13.13, datacore 3.13.5.
- **Virtualenv convention:** create `.venv` and invoke tools as `.venv/bin/pytest`, never `uv run`.
- **Section heading text is exactly `New This Quarter`**, matched at level 1 (`* `).
- **Capture heading tag is `:capture:`, right-aligned to column 77** (Emacs `org-tags-column` default).

## File Structure

**Part A** — existing files in `~/dotfiles`, no new structure.

**Part B** — new project at `~/projects/orgcapture/` on the laptop, Syncthing-delivered to datacore as `~/projects/work/orgcapture/`:

| File | Responsibility |
|---|---|
| `pyproject.toml` | Package metadata, deps, pytest config |
| `src/orgcapture/quarter.py` | Date → quarter name → quarter note path. Nothing else. |
| `src/orgcapture/orgtext.py` | Org escaping and entry rendering. Pure string functions. |
| `src/orgcapture/writer.py` | Insert/remove a capture subtree in org file text. Pure; no I/O. |
| `src/orgcapture/store.py` | Atomic file write, journal, pending queue, poll offset. All disk I/O. |
| `src/orgcapture/vision.py` | OpenRouter key loading and whiteboard transcription. |
| `src/orgcapture/images.py` | Photo downscale, archive path, relative org link. |
| `src/orgcapture/capture.py` | Orchestration: config, capture_text, capture_photo, undo, flush. |
| `src/orgcapture/bot.py` | Telegram handlers, auth, polling loop, entrypoint. |
| `tests/` | One test module per source module. |
| `Dockerfile`, `docker-compose.yml`, `.env.example`, `.gitignore`, `README.md` | Packaging and deploy |

The split keeps every file that can be tested without network or Telegram free of both. `writer.py` and `orgtext.py` are the correctness-critical core and are pure functions of their inputs.

---

# Part A — Land the work quarterly tracker

Part B targets the post-migration layout and cannot start until Task A3 is verified.

### Task A1: Commit the pending refinements on the quarterly branch

The worktree at `~/dotfiles/.claude/worktrees/work-quarterly-tracker` has four modified files that refine the six committed ones: the `scott-quarterly-name` → `scott-quarterly--name` private rename, a file-level `:ID:` guard that stops searching at the first heading, an `init.el` load-order fix folding `scott-quarterly` into the `dolist` require block, and hardening in the migration script.

**Files:**
- Modify: `ioshi/i-intelligence/emacs/init.el`
- Modify: `ioshi/i-intelligence/emacs/lisp/scott-quarterly.el`
- Modify: `ioshi/i-intelligence/emacs/test/scott-quarterly-test.el`
- Modify: `tools/migrate-work-quarters.sh`

**Interfaces:**
- Produces: `scott-quarterly-open` (interactive, `C-c q`), `scott-quarterly--name`, `scott-quarterly--file`, `scott-quarterly--sections`. Part B reimplements the `--name` rule in Python; nothing else crosses.

- [ ] **Step 1: Run the ERT suite to confirm the working tree is green**

```bash
cd ~/dotfiles/.claude/worktrees/work-quarterly-tracker/ioshi/i-intelligence/emacs
emacs -Q --batch -L lisp -L test -l test/scott-quarterly-test.el -f ert-run-tests-batch-and-exit
```

Expected: `Ran 14 tests, 14 results as expected, 0 unexpected`. If any test fails, stop — this task assumes the pending changes are complete work, and a failure means they are not.

- [ ] **Step 2: Read the full diff before committing**

```bash
cd ~/dotfiles/.claude/worktrees/work-quarterly-tracker
git diff
```

Confirm the diff contains only the four changes described above. Anything else is unexplained and must be understood before it lands on `main`.

- [ ] **Step 3: Commit**

```bash
cd ~/dotfiles/.claude/worktrees/work-quarterly-tracker
git add ioshi/i-intelligence/emacs/init.el \
        ioshi/i-intelligence/emacs/lisp/scott-quarterly.el \
        ioshi/i-intelligence/emacs/test/scott-quarterly-test.el \
        tools/migrate-work-quarters.sh
git commit -m "feat(emacs): private quarterly names, file-level ID guard, load-order fix"
```

### Task A2: Merge the branch to main and remove the worktree

**Files:**
- Modify: `~/dotfiles` on branch `main`

**Interfaces:**
- Consumes: the committed branch from Task A1.
- Produces: `lisp/scott-quarterly.el` and `tools/migrate-work-quarters.sh` present on `main`.

- [ ] **Step 1: Confirm main is clean and up to date**

```bash
cd ~/dotfiles
git status --short
git fetch --all
git log --oneline -1 main
```

Expected: no uncommitted changes. `~/dotfiles` has two remotes (`origin` = GitHub, `rafik` = T14 over tailscale); fetching both before merging avoids merging onto a stale main.

- [ ] **Step 2: Merge**

```bash
cd ~/dotfiles
git merge --no-ff worktree-work-quarterly-tracker \
  -m "feat(emacs): work-scoped quarterly tracker on C-c q"
```

- [ ] **Step 3: Run the ERT suite from main**

```bash
cd ~/dotfiles/ioshi/i-intelligence/emacs
emacs -Q --batch -L lisp -L test -l test/scott-quarterly-test.el -f ert-run-tests-batch-and-exit
```

Expected: `Ran 14 tests, 14 results as expected, 0 unexpected`.

- [ ] **Step 4: Remove the worktree and its branch**

```bash
cd ~/dotfiles
git worktree remove .claude/worktrees/work-quarterly-tracker
git branch -d worktree-work-quarterly-tracker
git worktree list
```

Expected: only `/home/scott/dotfiles` remains.

- [ ] **Step 5: Restart Emacs and confirm the key is live**

Elisp is an out-of-store symlink, so no `nixos-rebuild` is needed — restart Emacs, then run `C-h k C-c q`.

Expected: `C-c q` is bound to `scott-quarterly-open`. Do **not** press `C-c q` itself yet: `work/Quarterly/` does not exist until Task A3, so the command would offer to create a note in the wrong place.

- [ ] **Step 6: Push**

```bash
cd ~/dotfiles
git push origin main
```

Confirm with Scott before pushing — other machines pull from this remote.

### Task A3: Run the file migration

Destructive and one-shot. `~/docs/org/work` is a Syncthing folder with no git history, so the tar snapshot is the only undo. The script mutates only after a full validation pass, so `--dry-run` is a true predicate of the real run.

**Files:**
- Modify: six notes under `~/docs/org/work/` (moved into `Quarterly/`, titles suffixed)
- Delete: `~/docs/org/work/Quarterly Notes/` (once empty)

**Interfaces:**
- Produces: `~/docs/org/work/Quarterly/{2025-Q2,2025-Q3,2025-Q4,2026-Q1,2026-Q2,2026-Q3}.org`. Part B's `quarter_path()` targets exactly this layout.

- [ ] **Step 1: Quiesce Syncthing on the other two peers**

The migration must mutate on exactly one machine. Run it on the work laptop, where `C-c q` is verified at the end.

```bash
ssh rafik    'systemctl --user stop syncthing'
ssh datacore 'systemctl --user stop syncthing'
systemctl --user status syncthing --no-pager | head -3
```

Expected: stopped on rafik and datacore, still running locally.

- [ ] **Step 2: Check for pre-existing conflict files**

```bash
find ~/docs/org/work -name '*.sync-conflict-*' -print
```

Expected: no output. Any hit must be resolved by hand first — migrating a tree that is already in conflict compounds it.

- [ ] **Step 3: Record every `:ID:` before touching anything**

```bash
mkdir -p /tmp/claude-1000/-home-scott/quarterly-migration
cd ~/docs/org/work
for f in *_q[1-4].org "Quarterly Notes"/*_q[1-4].org; do
  printf '%s %s\n' "$(basename "$f" .org)" "$(awk '/^\*+ /{exit} /^:ID:/{print $2; exit}' "$f")"
done | sort > /tmp/claude-1000/-home-scott/quarterly-migration/ids-before.txt
cat /tmp/claude-1000/-home-scott/quarterly-migration/ids-before.txt
```

Expected: six lines, each with a non-empty UUID.

- [ ] **Step 4: Take the tar snapshot, outside the synced folder**

```bash
tar czf ~/quarterly-snapshot-$(date +%F).tar.gz -C ~/docs/org work
ls -lh ~/quarterly-snapshot-$(date +%F).tar.gz
```

The snapshot must land outside `~/docs/org/work`, or it syncs to every peer and is itself at risk. `$HOME` is a permitted top-level location for this; delete it once Task B10 is verified.

- [ ] **Step 5: Dry run**

```bash
~/dotfiles/tools/migrate-work-quarters.sh --dry-run
```

Expected: six `would move:` blocks, each naming a target under `Quarterly/` and a preserved id, ending `(dry run — nothing changed; would migrate 6)`. If it reports fewer than six or aborts, stop and diagnose — do not run the real migration.

- [ ] **Step 6: Migrate**

```bash
~/dotfiles/tools/migrate-work-quarters.sh
```

Expected: six `moved:` lines, `migrated 6 of 6`, `removed empty: …/Quarterly Notes`, then the NEXT hint.

- [ ] **Step 7: Verify IDs are byte-identical and titles are suffixed**

```bash
cd ~/docs/org/work/Quarterly
for f in *.org; do
  printf '%s %s\n' "$(basename "$f" .org)" "$(awk '/^\*+ /{exit} /^:ID:/{print $2; exit}' "$f")"
done | sort > /tmp/claude-1000/-home-scott/quarterly-migration/ids-after.txt

# Strip the org-roam timestamp prefix FIRST, then rewrite YYYY_qN -> YYYY-QN.
# Order matters: with the prefix still attached, '^[0-9]*_q' never matches
# (the prefix is followed by '-', not '_q'), the substitution silently does
# nothing, and the diff below would compare unlike strings.
sed -e 's/^[0-9]\{14\}-//' -e 's/^\([0-9]\{4\}\)_q\([1-4]\)/\1-Q\2/' \
  /tmp/claude-1000/-home-scott/quarterly-migration/ids-before.txt \
  | sort > /tmp/claude-1000/-home-scott/quarterly-migration/ids-before-normalized.txt

head -3 /tmp/claude-1000/-home-scott/quarterly-migration/ids-before-normalized.txt

diff /tmp/claude-1000/-home-scott/quarterly-migration/ids-before-normalized.txt \
     /tmp/claude-1000/-home-scott/quarterly-migration/ids-after.txt && echo "IDS OK"
grep -h '^#+title:' *.org
```

Expected: the `head -3` shows lines like `2025-Q2 <uuid>` (no timestamp prefix, no
`_q`), then `IDS OK`, then six title lines each ending ` (Work)`. If the `head -3`
still shows timestamp prefixes, the normalization did not apply and the `diff` result
means nothing — stop and fix it before trusting the migration.

- [ ] **Step 8: Confirm nothing is left behind**

```bash
ls ~/docs/org/work/*_q[1-4].org 2>&1
ls -d "~/docs/org/work/Quarterly Notes" 2>&1
ls ~/docs/org/work/Quarterly/
```

Expected: the first two commands report "No such file or directory"; the third lists exactly six notes.

- [ ] **Step 9: Restart Syncthing and let it settle**

```bash
ssh rafik    'systemctl --user start syncthing'
ssh datacore 'systemctl --user start syncthing'
```

Wait, then confirm the renames propagated rather than round-tripped:

```bash
ssh datacore 'ls ~/docs/org/work/Quarterly/; find ~/docs/org/work -name "*.sync-conflict-*" -print'
```

Expected: six notes on datacore, no conflict files.

- [ ] **Step 10: Re-index org-roam and verify the key**

Restart Emacs (or `M-x org-roam-db-sync`), then press `C-c q`.

Expected: opens `~/docs/org/work/Quarterly/2026-Q3.org`. Follow its trailing `[[id:...][2026-Q2]]` link and confirm it resolves — that is the real test that the renames were link-safe.

- [ ] **Step 11: Commit nothing, report**

The migration touches only the synced org tree, which is not a git repo. There is nothing to commit. Report the before/after ID diff result before moving to Part B.

---

# Part B — The capture service

### Task B1: Project skeleton and quarter resolution

**Files:**
- Create: `~/projects/orgcapture/pyproject.toml`
- Create: `~/projects/orgcapture/.gitignore`
- Create: `~/projects/orgcapture/src/orgcapture/__init__.py` (empty)
- Create: `~/projects/orgcapture/src/orgcapture/quarter.py`
- Test: `~/projects/orgcapture/tests/test_quarter.py`

**Interfaces:**
- Produces: `quarter_name(when: datetime) -> str` returning e.g. `"2026-Q3"`; `quarter_path(org_root: Path, when: datetime) -> Path` returning `org_root/"Quarterly"/f"{name}.org"`. Used by `capture.py` in Task B5.

- [ ] **Step 1: Create the project and its virtualenv**

```bash
mkdir -p ~/projects/orgcapture/src/orgcapture ~/projects/orgcapture/tests
cd ~/projects/orgcapture
git init
python3 -m venv .venv
```

- [ ] **Step 2: Write `pyproject.toml`**

```toml
[project]
name = "orgcapture"
version = "0.1.0"
description = "Telegram capture into the work quarterly tracker"
requires-python = ">=3.12"
dependencies = [
    "python-telegram-bot>=21.0",
    "httpx>=0.27",
    "Pillow>=10.3",
]

[dependency-groups]
dev = [
    "pytest>=8.0.0",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project.scripts]
orgcapture = "orgcapture.bot:main"

[tool.pytest.ini_options]
testpaths = ["tests"]
```

- [ ] **Step 3: Write `.gitignore`**

```gitignore
.venv/
__pycache__/
*.pyc
.pytest_cache/
.env
```

- [ ] **Step 4: Install the package and dev deps**

```bash
cd ~/projects/orgcapture
.venv/bin/pip install -e . pytest
```

- [ ] **Step 5: Write the failing test**

`tests/test_quarter.py`:

```python
from datetime import datetime
from pathlib import Path

from orgcapture.quarter import quarter_name, quarter_path


def test_quarter_name_maps_months_to_calendar_quarters():
    assert quarter_name(datetime(2026, 1, 15)) == "2026-Q1"
    assert quarter_name(datetime(2026, 3, 31)) == "2026-Q1"
    assert quarter_name(datetime(2026, 4, 1)) == "2026-Q2"
    assert quarter_name(datetime(2026, 8, 12)) == "2026-Q3"
    assert quarter_name(datetime(2026, 12, 31)) == "2026-Q4"


def test_quarter_path_is_constructed_not_searched():
    # No filesystem access: the path is derived, so a missing note is a
    # detectable absence rather than a failed search.
    assert quarter_path(Path("/org/work"), datetime(2026, 8, 12)) == Path(
        "/org/work/Quarterly/2026-Q3.org"
    )
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_quarter.py -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'orgcapture.quarter'`

- [ ] **Step 7: Write the implementation**

`src/orgcapture/quarter.py`:

```python
"""Calendar-quarter naming, mirroring `scott-quarterly--name` in scott-quarterly.el."""

from datetime import datetime
from pathlib import Path


def quarter_name(when: datetime) -> str:
    """Return the quarter name for WHEN as YYYY-QN."""
    return f"{when.year}-Q{(when.month - 1) // 3 + 1}"


def quarter_path(org_root: Path, when: datetime) -> Path:
    """Return the work quarter note path for WHEN under ORG_ROOT."""
    return org_root / "Quarterly" / f"{quarter_name(when)}.org"
```

- [ ] **Step 8: Run the test to verify it passes**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_quarter.py -v`
Expected: 2 passed

- [ ] **Step 9: Commit**

```bash
cd ~/projects/orgcapture
git add pyproject.toml .gitignore src tests
git commit -m "feat: project skeleton and quarter path resolution"
```

### Task B2: Org escaping and entry rendering

The escaping is the single most important safety property in the service: message text is untrusted data spliced into an outline.

**Files:**
- Create: `~/projects/orgcapture/src/orgcapture/orgtext.py`
- Test: `~/projects/orgcapture/tests/test_orgtext.py`

**Interfaces:**
- Produces: `escape_body(text: str) -> str`; `render_entry(when: datetime, body: str) -> str` returning a complete `**` subtree ending in a newline. `TAGS_COLUMN = 77`. Used by `capture.py` in Task B5.

- [ ] **Step 1: Write the failing test**

`tests/test_orgtext.py`:

```python
from datetime import datetime

from orgcapture.orgtext import escape_body, render_entry


def test_escape_body_neutralizes_headings_and_keywords():
    assert escape_body("* Rock") == ",* Rock"
    assert escape_body("*** deep") == ",*** deep"
    assert escape_body("#+title: hijack") == ",#+title: hijack"
    assert escape_body("first\n* Rock\nlast") == "first\n,* Rock\nlast"


def test_escape_body_leaves_ordinary_text_alone():
    # Bold markers mid-line and indented list bullets are not headings.
    assert escape_body("a * b") == "a * b"
    assert escape_body("  * indented bullet") == "  * indented bullet"
    assert escape_body("plain note") == "plain note"


def test_render_entry_stamps_the_heading_and_right_aligns_the_tag():
    entry = render_entry(datetime(2026, 8, 12, 14, 32), "hello")
    head, body = entry.splitlines()
    assert head.startswith("** 2026-08-12 Wed 14:32")
    assert head.endswith(":capture:")
    assert len(head) == 77
    assert body == "hello"
    assert entry.endswith("\n")


def test_render_entry_escapes_its_body():
    entry = render_entry(datetime(2026, 8, 12, 14, 32), "* Rock")
    assert entry.splitlines()[1] == ",* Rock"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_orgtext.py -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'orgcapture.orgtext'`

- [ ] **Step 3: Write the implementation**

`src/orgcapture/orgtext.py`:

```python
"""Rendering captures as org text, and keeping message text from becoming structure."""

import re
from datetime import datetime

TAGS_COLUMN = 77
CAPTURE_TAG = ":capture:"

# A line is structure if it opens with stars-and-a-space, or an org keyword.
# Both get org's own comma escape. Anything indented is list content, not a
# heading, and is left alone.
_STRUCTURE_RE = re.compile(r"^(\*+ |#\+)", re.MULTILINE)


def escape_body(text: str) -> str:
    """Return TEXT with any line that would read as org structure escaped."""
    return _STRUCTURE_RE.sub(r",\1", text)


def render_entry(when: datetime, body: str) -> str:
    """Return a complete level-2 capture subtree for BODY stamped at WHEN."""
    head = f"** {when.strftime('%Y-%m-%d %a %H:%M')}"
    pad = max(1, TAGS_COLUMN - len(head) - len(CAPTURE_TAG))
    return f"{head}{' ' * pad}{CAPTURE_TAG}\n{escape_body(body).rstrip()}\n"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_orgtext.py -v`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
cd ~/projects/orgcapture
git add src/orgcapture/orgtext.py tests/test_orgtext.py
git commit -m "feat: org escaping and capture entry rendering"
```

### Task B3: Insert and remove capture subtrees

Pure functions over file text. No I/O, so they can be tested against copies of the real notes cheaply.

**Files:**
- Create: `~/projects/orgcapture/src/orgcapture/writer.py`
- Test: `~/projects/orgcapture/tests/test_writer.py`

**Interfaces:**
- Produces: `SECTION = "New This Quarter"`; `insert_capture(text: str, entry: str) -> tuple[str, int]` returning the new text and the character offset where `entry` begins; `remove_capture(text: str, offset: int, entry: str) -> str`; `tail_hash(text: str, offset: int) -> str` returning a hex SHA-256 over `text[offset:]`. Used by `capture.py` in Task B5.

- [ ] **Step 1: Write the failing test**

`tests/test_writer.py`:

```python
from orgcapture.writer import SECTION, insert_capture, remove_capture, tail_hash

ENTRY = "** 2026-08-12 Wed 14:32                                        :capture:\nhello\n"

WITH_SECTION = (
    ":PROPERTIES:\n:ID:       abc\n:END:\n"
    "#+title: 2026-Q3 (Work)\n\n"
    "* Rock\n\n"
    "* New This Quarter\n\n"
    "* Workspace\n\n"
)

# 2026-Q3 as it actually exists: no level-1 headings at all, content at ** and ***.
IRREGULAR = (
    ":PROPERTIES:\n:ID:       abc\n:END:\n"
    "#+title: 2026-Q3 (Work)\n\n"
    "** Beta Todos\n:PROPERTIES:\n:CUSTOM_ID: beta-todos\n:END:\n"
    "Set-Operator Set models\n\n"
    "[[id:693fb16d][2026-Q2]]\n"
)


def test_insert_places_the_entry_inside_the_section():
    new, offset = insert_capture(WITH_SECTION, ENTRY)
    assert new[offset : offset + len(ENTRY)] == ENTRY
    assert new.index(ENTRY) > new.index("* New This Quarter")
    assert new.index(ENTRY) < new.index("* Workspace")


def test_insert_leaves_everything_above_the_offset_byte_identical():
    new, offset = insert_capture(WITH_SECTION, ENTRY)
    assert new[:offset] == WITH_SECTION[:offset]


def test_two_captures_become_two_siblings_under_one_section():
    once, _ = insert_capture(WITH_SECTION, ENTRY)
    second = ENTRY.replace("14:32", "15:07")
    twice, _ = insert_capture(once, second)
    assert twice.count(f"* {SECTION}") == 1
    assert twice.count(":capture:") == 2
    assert twice.index(ENTRY) < twice.index(second)


def test_missing_section_is_appended_once_at_end_of_file():
    new, offset = insert_capture(IRREGULAR, ENTRY)
    assert new.startswith(IRREGULAR)
    assert new.count(f"* {SECTION}") == 1
    assert new[offset : offset + len(ENTRY)] == ENTRY
    # The pre-existing ** heading is untouched and still above the new section.
    assert new.index("** Beta Todos") < new.index(f"* {SECTION}")


def test_remove_restores_the_original_byte_for_byte():
    new, offset = insert_capture(WITH_SECTION, ENTRY)
    assert remove_capture(new, offset, ENTRY) == WITH_SECTION


def test_tail_hash_changes_when_the_tail_changes():
    new, offset = insert_capture(WITH_SECTION, ENTRY)
    assert tail_hash(new, offset) == tail_hash(new, offset)
    assert tail_hash(new, offset) != tail_hash(new + "edited\n", offset)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_writer.py -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'orgcapture.writer'`

- [ ] **Step 3: Write the implementation**

`src/orgcapture/writer.py`:

```python
"""Pure transformations of quarter-note text. No I/O lives here."""

import hashlib
import re

SECTION = "New This Quarter"

_SECTION_RE = re.compile(rf"^\* {re.escape(SECTION)}[ \t]*$", re.MULTILINE)
_TOP_HEADING_RE = re.compile(r"^\* ", re.MULTILINE)


def insert_capture(text: str, entry: str) -> tuple[str, int]:
    """Insert ENTRY under the capture section, returning (new_text, offset).

    The section is found by heading text, so moving it in Emacs is safe. When
    it is absent — true of every migrated note — it is appended once at end of
    file rather than injected into someone else's structure.
    """
    match = _SECTION_RE.search(text)
    if match is None:
        prefix = text if text.endswith("\n") or not text else text + "\n"
        prefix = f"{prefix}\n* {SECTION}\n\n"
        return prefix + entry, len(prefix)

    following = _TOP_HEADING_RE.search(text, match.end())
    at = following.start() if following else len(text)
    prefix = text[:at]
    if not prefix.endswith("\n"):
        prefix += "\n"
    return prefix + entry + text[at:], len(prefix)


def remove_capture(text: str, offset: int, entry: str) -> str:
    """Remove ENTRY at OFFSET. Caller must have verified it is still there."""
    if text[offset : offset + len(entry)] != entry:
        raise ValueError("entry is not at the recorded offset")
    return text[:offset] + text[offset + len(entry) :]


def tail_hash(text: str, offset: int) -> str:
    """Hex SHA-256 over TEXT from OFFSET to end of file."""
    return hashlib.sha256(text[offset:].encode("utf-8")).hexdigest()
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_writer.py -v`
Expected: 6 passed

- [ ] **Step 5: Add a regression test against the real quarter note**

Append to `tests/test_writer.py`:

```python
from pathlib import Path

import pytest


def test_insert_into_the_real_current_quarter_note():
    """Guard against the live note's actual shape, not just a synthetic one."""
    real = Path.home() / "docs/org/work/Quarterly/2026-Q3.org"
    if not real.exists():
        pytest.skip("Part A migration has not run on this machine")
    original = real.read_text(encoding="utf-8")
    new, offset = insert_capture(original, ENTRY)
    assert new[:offset] == original[:offset]
    assert remove_capture(new, offset, ENTRY) == original
```

- [ ] **Step 6: Run the suite**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_writer.py -v`
Expected: 7 passed (the last one skips if Part A has not run — it must not skip on the work laptop after Task A3)

- [ ] **Step 7: Commit**

```bash
cd ~/projects/orgcapture
git add src/orgcapture/writer.py tests/test_writer.py
git commit -m "feat: insert and remove capture subtrees in quarter notes"
```

### Task B4: Atomic writes, journal, pending queue

Delivery idempotency comes from the journal, not from a local offset file. Telegram
holds the unconfirmed-update cursor server-side and `Application.run_polling()`
confirms it as it fetches, so a restart redelivers anything unconfirmed; `has()` on
the journal is what makes that redelivery safe.

**Files:**
- Create: `~/projects/orgcapture/src/orgcapture/store.py`
- Test: `~/projects/orgcapture/tests/test_store.py`

**Interfaces:**
- Produces: `atomic_write(path: Path, text: str) -> None`; `@dataclass Record(update_id: int, written_at: str, file: str, entry: str, offset: int, tail_sha256: str)`; `Journal(path: Path)` with `.append(rec)`, `.last() -> Record | None`, `.drop_last()`, `.has(update_id: int) -> bool`; `Pending(path: Path)` with `.append(text: str)`, `.take_all() -> list[str]`. Used by `capture.py` (B5).

- [ ] **Step 1: Write the failing test**

`tests/test_store.py`:

```python
from orgcapture.store import Journal, Pending, Record, atomic_write


def _record(update_id=1, offset=10):
    return Record(
        update_id=update_id,
        written_at="2026-08-12T14:32:00-04:00",
        file="/org/work/Quarterly/2026-Q3.org",
        entry="** stamp\nbody\n",
        offset=offset,
        tail_sha256="deadbeef",
    )


def test_atomic_write_replaces_content_and_leaves_no_temp_files(tmp_path):
    target = tmp_path / "note.org"
    target.write_text("old\n", encoding="utf-8")
    atomic_write(target, "new\n")
    assert target.read_text(encoding="utf-8") == "new\n"
    assert [p.name for p in tmp_path.iterdir()] == ["note.org"]


def test_journal_round_trips_records(tmp_path):
    journal = Journal(tmp_path / "journal.jsonl")
    assert journal.last() is None
    journal.append(_record(update_id=7))
    assert journal.last() == _record(update_id=7)
    assert journal.has(7)
    assert not journal.has(8)


def test_journal_drop_last_removes_only_the_newest(tmp_path):
    journal = Journal(tmp_path / "journal.jsonl")
    journal.append(_record(update_id=1))
    journal.append(_record(update_id=2))
    journal.drop_last()
    assert journal.last() == _record(update_id=1)
    assert not journal.has(2)


def test_pending_takes_all_and_clears(tmp_path):
    pending = Pending(tmp_path / "pending.jsonl")
    assert pending.take_all() == []
    pending.append("first")
    pending.append("second")
    assert pending.take_all() == ["first", "second"]
    assert pending.take_all() == []


def test_appends_are_on_disk_not_just_buffered(tmp_path):
    # A separately constructed reader sees the record, which is what makes
    # dedupe survive a crash. Journal.has() is the only thing standing between
    # Telegram's redelivery and a duplicated capture.
    Journal(tmp_path / "journal.jsonl").append(_record(update_id=9))
    assert Journal(tmp_path / "journal.jsonl").has(9)

    Pending(tmp_path / "pending.jsonl").append("parked")
    assert Pending(tmp_path / "pending.jsonl").take_all() == ["parked"]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_store.py -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'orgcapture.store'`

- [ ] **Step 3: Write the implementation**

`src/orgcapture/store.py`:

```python
"""All disk I/O: atomic note writes plus the service's own state files."""

import json
import os
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path


def atomic_write(path: Path, text: str) -> None:
    """Write TEXT to PATH via a same-directory tempfile and an atomic replace.

    Same directory matters: os.replace is only atomic within a filesystem, and
    a note under a Syncthing folder must never be observed half-written.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".orgcapture-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


@dataclass(frozen=True)
class Record:
    update_id: int
    written_at: str
    file: str
    entry: str
    offset: int
    tail_sha256: str


class Journal:
    """Append-only log of writes; the newest record is what /undo targets."""

    def __init__(self, path: Path) -> None:
        self.path = path

    def _all(self) -> list[Record]:
        if not self.path.exists():
            return []
        return [
            Record(**json.loads(line))
            for line in self.path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]

    def append(self, record: Record) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(asdict(record)) + "\n")
            # Durable on purpose. The note write is fsynced; if this record is
            # not, a crash in the write-back window loses the dedupe entry for
            # a capture that DID land, and Telegram's redelivery writes it twice.
            handle.flush()
            os.fsync(handle.fileno())

    def last(self) -> Record | None:
        records = self._all()
        return records[-1] if records else None

    def drop_last(self) -> None:
        records = self._all()[:-1]
        atomic_write(
            self.path, "".join(json.dumps(asdict(r)) + "\n" for r in records)
        )

    def has(self, update_id: int) -> bool:
        return any(r.update_id == update_id for r in self._all())


class Pending:
    """Captures parked because their quarter note does not exist yet."""

    def __init__(self, path: Path) -> None:
        self.path = path

    def append(self, text: str) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps({"text": text}) + "\n")
            handle.flush()
            os.fsync(handle.fileno())

    def take_all(self) -> list[str]:
        if not self.path.exists():
            return []
        items = [
            json.loads(line)["text"]
            for line in self.path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        self.path.unlink()
        return items
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_store.py -v`
Expected: 5 passed

- [ ] **Step 5: Commit**

```bash
cd ~/projects/orgcapture
git add src/orgcapture/store.py tests/test_store.py
git commit -m "feat: atomic writes, journal, and pending queue"
```

### Task B5: Capture orchestration for text, undo, and flush

**Files:**
- Create: `~/projects/orgcapture/src/orgcapture/capture.py`
- Test: `~/projects/orgcapture/tests/test_capture.py`

**Interfaces:**
- Produces: `@dataclass(frozen=True) Config` with fields `org_root: Path`, `state_dir: Path`, `auth_path: Path`, `vision_model: str`, `bot_token: str`, `allowed_chat_ids: frozenset[int]`, plus `Config.from_env() -> Config`; `class Capturer(config: Config)` with `.capture_text(update_id: int, body: str, when: datetime) -> str`, `.undo() -> str`, `.flush(when: datetime) -> str`, `.target(when: datetime) -> Path`. Each method returns the reply string the bot sends. `capture_photo` is added in Task B7.

- [ ] **Step 1: Write the failing test**

`tests/test_capture.py`:

```python
from datetime import datetime
from pathlib import Path

from orgcapture.capture import Capturer, Config

WHEN = datetime(2026, 8, 12, 14, 32)

QUARTER_NOTE = (
    ":PROPERTIES:\n:ID:       abc\n:END:\n"
    "#+title: 2026-Q3 (Work)\n\n"
    "* Rock\n\n"
    "* New This Quarter\n\n"
    "* Workspace\n\n"
)


def _config(tmp_path):
    return Config(
        org_root=tmp_path / "work",
        state_dir=tmp_path / "state",
        auth_path=tmp_path / "auth.json",
        vision_model="google/gemini-3-flash-preview",
        bot_token="token",
        allowed_chat_ids=frozenset({1}),
    )


def _with_note(tmp_path):
    note = tmp_path / "work/Quarterly/2026-Q3.org"
    note.parent.mkdir(parents=True)
    note.write_text(QUARTER_NOTE, encoding="utf-8")
    return note


def test_capture_text_writes_a_subtree_and_reports_it(tmp_path):
    note = _with_note(tmp_path)
    reply = Capturer(_config(tmp_path)).capture_text(1, "a random note", WHEN)
    text = note.read_text(encoding="utf-8")
    assert "** 2026-08-12 Wed 14:32" in text
    assert "a random note" in text
    assert "2026-Q3.org" in reply
    assert "a random note" in reply


def test_missing_quarter_note_parks_instead_of_creating(tmp_path):
    config = _config(tmp_path)
    reply = Capturer(config).capture_text(1, "a random note", WHEN)
    assert not (config.org_root / "Quarterly/2026-Q3.org").exists()
    assert not (config.org_root / "Quarterly").exists()
    assert "parked" in reply
    assert "2026-Q3" in reply


def test_flush_writes_parked_captures_in_order(tmp_path):
    config = _config(tmp_path)
    capturer = Capturer(config)
    capturer.capture_text(1, "first", WHEN)
    capturer.capture_text(2, "second", WHEN)
    note = _with_note(tmp_path)
    capturer.flush(WHEN)
    text = note.read_text(encoding="utf-8")
    assert text.index("first") < text.index("second")


def test_undo_restores_the_note_byte_for_byte(tmp_path):
    note = _with_note(tmp_path)
    capturer = Capturer(_config(tmp_path))
    capturer.capture_text(1, "a random note", WHEN)
    reply = capturer.undo()
    assert note.read_text(encoding="utf-8") == QUARTER_NOTE
    assert "removed" in reply


def test_undo_refuses_when_the_note_changed_after_the_write(tmp_path):
    note = _with_note(tmp_path)
    capturer = Capturer(_config(tmp_path))
    capturer.capture_text(1, "a random note", WHEN)
    note.write_text(note.read_text(encoding="utf-8") + "edited in Emacs\n", encoding="utf-8")
    reply = capturer.undo()
    assert "changed" in reply
    assert "edited in Emacs" in note.read_text(encoding="utf-8")


def test_replayed_update_id_is_not_written_twice(tmp_path):
    note = _with_note(tmp_path)
    capturer = Capturer(_config(tmp_path))
    capturer.capture_text(1, "a random note", WHEN)
    capturer.capture_text(1, "a random note", WHEN)
    assert note.read_text(encoding="utf-8").count(":capture:") == 1
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_capture.py -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'orgcapture.capture'`

- [ ] **Step 3: Write the implementation**

`src/orgcapture/capture.py`:

```python
"""Orchestration: turn a message into a written subtree, and back out again."""

import os
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from orgcapture.orgtext import render_entry
from orgcapture.quarter import quarter_name, quarter_path
from orgcapture.store import Journal, Pending, Record, atomic_write
from orgcapture.writer import SECTION, insert_capture, remove_capture, tail_hash


@dataclass(frozen=True)
class Config:
    org_root: Path
    state_dir: Path
    auth_path: Path
    vision_model: str
    bot_token: str
    allowed_chat_ids: frozenset[int]

    @classmethod
    def from_env(cls) -> "Config":
        ids = os.environ["TELEGRAM_ALLOWED_CHAT_IDS"]
        return cls(
            org_root=Path(os.environ.get("ORGCAPTURE_ORG_ROOT", "/org/work")),
            state_dir=Path(os.environ.get("ORGCAPTURE_STATE_DIR", "/state")),
            auth_path=Path(os.environ.get("ORGCAPTURE_AUTH_PATH", "/auth/auth.json")),
            vision_model=os.environ.get(
                "ORGCAPTURE_VISION_MODEL", "google/gemini-3-flash-preview"
            ),
            bot_token=os.environ["TELEGRAM_BOT_TOKEN"],
            allowed_chat_ids=frozenset(
                int(part) for part in ids.split(",") if part.strip()
            ),
        )


class Capturer:
    def __init__(self, config: Config) -> None:
        self.config = config
        self.journal = Journal(config.state_dir / "journal.jsonl")
        self.pending = Pending(config.state_dir / "pending.jsonl")

    def target(self, when: datetime) -> Path:
        return quarter_path(self.config.org_root, when)

    def capture_text(self, update_id: int, body: str, when: datetime) -> str:
        if self.journal.has(update_id):
            return "already captured — ignoring a replayed message"
        return self._write(update_id, render_entry(when, body), when)

    def _write(self, update_id: int, entry: str, when: datetime) -> str:
        note = self.target(when)
        if not note.exists():
            # Never create it here. A headless service racing Syncthing is how
            # an empty note wins a conflict and quarantines the real one.
            self.pending.append(entry)
            return (
                f"parked — no {quarter_name(when)} note yet, hit C-c q in Emacs, "
                f"then /flush"
            )
        original = note.read_text(encoding="utf-8")
        new, offset = insert_capture(original, entry)
        atomic_write(note, new)
        self.journal.append(
            Record(
                update_id=update_id,
                written_at=when.isoformat(),
                file=str(note),
                entry=entry,
                offset=offset,
                tail_sha256=tail_hash(new, offset),
            )
        )
        return f"{note.name} → {SECTION}\n\n{entry}"

    def flush(self, when: datetime) -> str:
        note = self.target(when)
        if not note.exists():
            return f"still no {quarter_name(when)} note — nothing flushed"
        entries = self.pending.take_all()
        if not entries:
            return "nothing parked"
        text = note.read_text(encoding="utf-8")
        for entry in entries:
            text, _ = insert_capture(text, entry)
        atomic_write(note, text)
        # Flushed entries are deliberately not journalled: /undo targets the
        # single most recent capture, and a batch has no single subtree to drop.
        return f"flushed {len(entries)} parked capture(s) into {note.name}"

    def undo(self) -> str:
        record = self.journal.last()
        if record is None:
            return "nothing to undo"
        note = Path(record.file)
        if not note.exists():
            return f"cannot undo — {note.name} is gone"
        text = note.read_text(encoding="utf-8")
        if tail_hash(text, record.offset) != record.tail_sha256:
            return (
                f"refusing to undo — {note.name} changed since that capture "
                f"(edited in Emacs, or Syncthing delivered a change). "
                f"Remove the subtree by hand."
            )
        atomic_write(note, remove_capture(text, record.offset, record.entry))
        self.journal.drop_last()
        return f"removed the last capture from {note.name}"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_capture.py -v`
Expected: 6 passed

- [ ] **Step 5: Commit**

```bash
cd ~/projects/orgcapture
git add src/orgcapture/capture.py tests/test_capture.py
git commit -m "feat: text capture, parking, flush, and undo"
```

### Task B6: OpenRouter whiteboard transcription

**Files:**
- Create: `~/projects/orgcapture/src/orgcapture/vision.py`
- Test: `~/projects/orgcapture/tests/test_vision.py`

**Interfaces:**
- Produces: `class VisionError(RuntimeError)`; `openrouter_key(auth_path: Path) -> str`; `transcribe(image: bytes, *, model: str, api_key: str, timeout: float = 60.0) -> str`. Used by `capture.capture_photo` in Task B7.

- [ ] **Step 1: Write the failing test**

`tests/test_vision.py`:

```python
import json

import httpx
import pytest

from orgcapture import vision
from orgcapture.vision import VisionError, openrouter_key, transcribe


def test_openrouter_key_reads_the_pi_auth_file(tmp_path):
    auth = tmp_path / "auth.json"
    auth.write_text(
        json.dumps({"openrouter": {"key": "sk-or-123"}, "openrouter-management": {"key": "x"}}),
        encoding="utf-8",
    )
    assert openrouter_key(auth) == "sk-or-123"


def test_openrouter_key_raises_when_absent(tmp_path):
    auth = tmp_path / "auth.json"
    auth.write_text(json.dumps({"anthropic": {"key": "x"}}), encoding="utf-8")
    with pytest.raises(VisionError):
        openrouter_key(auth)


def test_transcribe_returns_the_message_content(monkeypatch):
    def fake_post(url, **kwargs):
        payload = kwargs["json"]
        assert payload["model"] == "test-model"
        assert payload["messages"][0]["content"][1]["image_url"]["url"].startswith(
            "data:image/jpeg;base64,"
        )
        return httpx.Response(
            200,
            json={"choices": [{"message": {"content": "- board line\n"}}]},
            request=httpx.Request("POST", url),
        )

    monkeypatch.setattr(vision.httpx, "post", fake_post)
    assert transcribe(b"jpegbytes", model="test-model", api_key="k") == "- board line"


def test_transcribe_raises_vision_error_on_http_failure(monkeypatch):
    def fake_post(url, **kwargs):
        return httpx.Response(429, text="rate limited", request=httpx.Request("POST", url))

    monkeypatch.setattr(vision.httpx, "post", fake_post)
    with pytest.raises(VisionError) as excinfo:
        transcribe(b"jpegbytes", model="test-model", api_key="k")
    assert "429" in str(excinfo.value)


def test_transcribe_raises_vision_error_on_transport_failure(monkeypatch):
    def fake_post(url, **kwargs):
        raise httpx.ConnectTimeout("timed out")

    monkeypatch.setattr(vision.httpx, "post", fake_post)
    with pytest.raises(VisionError):
        transcribe(b"jpegbytes", model="test-model", api_key="k")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_vision.py -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'orgcapture.vision'`

- [ ] **Step 3: Write the implementation**

`src/orgcapture/vision.py`:

```python
"""Whiteboard transcription via OpenRouter, keyed from the pi auth file."""

import base64
import json
from pathlib import Path

import httpx

ENDPOINT = "https://openrouter.ai/api/v1/chat/completions"

PROMPT = """Transcribe this photograph of a whiteboard or notepad into Org-mode body text.

Rules:
- Preserve the structure you see. Nested points become nested "-" lists.
- Transcribe only what is visibly written. Do not infer, complete, or tidy up
  the author's thinking.
- Mark anything you cannot read as [?].
- Output body text only. Do not emit any heading line starting with "*", and do
  not wrap the output in code fences.
- If the image contains no legible writing, reply with exactly: (no legible content)
"""


class VisionError(RuntimeError):
    """Any failure to obtain a transcription."""


def openrouter_key(auth_path: Path) -> str:
    """Return the OpenRouter key from the agenix-managed pi auth file."""
    try:
        data = json.loads(auth_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise VisionError(f"cannot read {auth_path}: {exc}") from exc
    key = data.get("openrouter", {}).get("key")
    if not key:
        raise VisionError(f"no openrouter.key in {auth_path}")
    return key


def transcribe(
    image: bytes, *, model: str, api_key: str, timeout: float = 60.0
) -> str:
    """Return the transcription of IMAGE, or raise VisionError."""
    encoded = base64.b64encode(image).decode("ascii")
    payload = {
        "model": model,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": PROMPT},
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/jpeg;base64,{encoded}"},
                    },
                ],
            }
        ],
    }
    try:
        response = httpx.post(
            ENDPOINT,
            json=payload,
            headers={"Authorization": f"Bearer {api_key}"},
            timeout=timeout,
        )
    except httpx.HTTPError as exc:
        raise VisionError(f"transport error: {exc}") from exc

    if response.status_code != 200:
        raise VisionError(f"HTTP {response.status_code}: {response.text[:200]}")

    try:
        content = response.json()["choices"][0]["message"]["content"]
    except (KeyError, IndexError, ValueError) as exc:
        raise VisionError(f"unexpected response shape: {exc}") from exc
    return content.strip()
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_vision.py -v`
Expected: 5 passed

- [ ] **Step 5: Commit**

```bash
cd ~/projects/orgcapture
git add src/orgcapture/vision.py tests/test_vision.py
git commit -m "feat: openrouter whiteboard transcription"
```

### Task B7: Photo archiving and the photo capture path

**Files:**
- Create: `~/projects/orgcapture/src/orgcapture/images.py`
- Modify: `~/projects/orgcapture/src/orgcapture/capture.py`
- Test: `~/projects/orgcapture/tests/test_images.py`
- Test: `~/projects/orgcapture/tests/test_capture.py` (append)

**Interfaces:**
- Produces: `downscale(image: bytes, max_edge: int = 1568) -> bytes`; `archive_path(org_root: Path, when: datetime) -> Path`; `org_link(note: Path, image: Path) -> str`. Adds `Capturer.capture_photo(update_id: int, image: bytes, caption: str, when: datetime) -> str`.

- [ ] **Step 1: Write the failing test for images**

`tests/test_images.py`:

```python
import io
from datetime import datetime
from pathlib import Path

from PIL import Image

from orgcapture.images import archive_path, downscale, org_link


def _jpeg(width, height):
    buffer = io.BytesIO()
    Image.new("RGB", (width, height), "white").save(buffer, format="JPEG")
    return buffer.getvalue()


def test_downscale_caps_the_long_edge_and_keeps_aspect():
    out = Image.open(io.BytesIO(downscale(_jpeg(4000, 2000), max_edge=1568)))
    assert out.size == (1568, 784)


def test_downscale_leaves_small_images_alone():
    out = Image.open(io.BytesIO(downscale(_jpeg(800, 600), max_edge=1568)))
    assert out.size == (800, 600)


def test_archive_path_is_year_bucketed_under_the_synced_work_tree():
    assert archive_path(Path("/org/work"), datetime(2026, 8, 12, 14, 32, 7)) == Path(
        "/org/work/assets/captures/2026/2026-08-12-143207.jpg"
    )


def test_org_link_is_relative_to_the_quarter_note():
    link = org_link(
        Path("/org/work/Quarterly/2026-Q3.org"),
        Path("/org/work/assets/captures/2026/2026-08-12-143207.jpg"),
    )
    assert link == "[[file:../assets/captures/2026/2026-08-12-143207.jpg]]"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_images.py -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'orgcapture.images'`

- [ ] **Step 3: Write the images implementation**

`src/orgcapture/images.py`:

```python
"""Photo archiving: downscale for the vision call, and link it from the note."""

import io
import os
from datetime import datetime
from pathlib import Path

from PIL import Image


def downscale(image: bytes, max_edge: int = 1568) -> bytes:
    """Return IMAGE with its long edge capped at MAX_EDGE, re-encoded as JPEG.

    1568px is the useful ceiling for these vision models; a raw phone photo is
    several times that and costs proportionally more for no added legibility.
    """
    original = Image.open(io.BytesIO(image))
    if max(original.size) <= max_edge:
        return image
    original.thumbnail((max_edge, max_edge))
    buffer = io.BytesIO()
    original.convert("RGB").save(buffer, format="JPEG", quality=88)
    return buffer.getvalue()


def archive_path(org_root: Path, when: datetime) -> Path:
    """Where the original photo is kept. Must sit under the synced work tree."""
    stamp = when.strftime("%Y-%m-%d-%H%M%S")
    return org_root / "assets" / "captures" / str(when.year) / f"{stamp}.jpg"


def org_link(note: Path, image: Path) -> str:
    """A file link from NOTE to IMAGE, relative so it resolves on every machine."""
    return f"[[file:{os.path.relpath(image, note.parent)}]]"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_images.py -v`
Expected: 4 passed

- [ ] **Step 5: Write the failing test for the photo capture path**

Append to `tests/test_capture.py`:

```python
import io

from PIL import Image

from orgcapture import capture as capture_module
from orgcapture.vision import VisionError


def _jpeg():
    buffer = io.BytesIO()
    Image.new("RGB", (100, 80), "white").save(buffer, format="JPEG")
    return buffer.getvalue()


def _auth(tmp_path):
    (tmp_path / "auth.json").write_text(
        '{"openrouter": {"key": "sk-or-test"}}', encoding="utf-8"
    )


def test_capture_photo_archives_transcribes_and_links(tmp_path, monkeypatch):
    note = _with_note(tmp_path)
    _auth(tmp_path)
    monkeypatch.setattr(
        capture_module, "transcribe", lambda *a, **k: "- top left idea\n- arrow to X"
    )
    reply = Capturer(_config(tmp_path)).capture_photo(1, _jpeg(), "", WHEN)
    text = note.read_text(encoding="utf-8")
    archived = tmp_path / "work/assets/captures/2026/2026-08-12-143200.jpg"
    assert archived.exists()
    assert "- top left idea" in text
    assert "[[file:../assets/captures/2026/2026-08-12-143200.jpg]]" in text
    assert "top left idea" in reply


def test_capture_photo_writes_the_entry_even_when_transcription_fails(
    tmp_path, monkeypatch
):
    note = _with_note(tmp_path)
    _auth(tmp_path)

    def boom(*args, **kwargs):
        raise VisionError("HTTP 429: rate limited")

    monkeypatch.setattr(capture_module, "transcribe", boom)
    reply = Capturer(_config(tmp_path)).capture_photo(1, _jpeg(), "", WHEN)
    text = note.read_text(encoding="utf-8")
    assert "transcription failed" in text
    assert "[[file:../assets/captures/2026/2026-08-12-143200.jpg]]" in text
    assert "transcription failed" in reply


def test_capture_photo_puts_the_caption_above_the_transcription(tmp_path, monkeypatch):
    note = _with_note(tmp_path)
    _auth(tmp_path)
    monkeypatch.setattr(capture_module, "transcribe", lambda *a, **k: "- board")
    Capturer(_config(tmp_path)).capture_photo(1, _jpeg(), "Vesco kickoff", WHEN)
    text = note.read_text(encoding="utf-8")
    assert text.index("Vesco kickoff") < text.index("- board")
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_capture.py -v`
Expected: FAIL, `AttributeError: 'Capturer' object has no attribute 'capture_photo'`

- [ ] **Step 7: Extend `capture.py`**

Add these imports at the top of `src/orgcapture/capture.py`, beside the existing ones:

```python
from orgcapture.images import archive_path, downscale, org_link
from orgcapture.vision import VisionError, openrouter_key, transcribe
```

Add this method to `Capturer`, after `capture_text`:

```python
    def capture_photo(
        self, update_id: int, image: bytes, caption: str, when: datetime
    ) -> str:
        if self.journal.has(update_id):
            return "already captured — ignoring a replayed message"

        # Archive first, unconditionally. The photo must survive even if every
        # step after this one fails.
        archived = archive_path(self.config.org_root, when)
        archived.parent.mkdir(parents=True, exist_ok=True)
        archived.write_bytes(image)

        try:
            text = transcribe(
                downscale(image),
                model=self.config.vision_model,
                api_key=openrouter_key(self.config.auth_path),
            )
        except VisionError as exc:
            text = f"(transcription failed: {exc})"

        parts = [part for part in (caption.strip(), text) if part]
        body = "\n\n".join(parts) + "\n\n" + org_link(self.target(when), archived)
        return self._write(update_id, render_entry(when, body), when)
```

Note that `org_link` is computed against `self.target(when)` whether or not that
note exists yet; a parked photo capture therefore carries a link that becomes
correct the moment the note is created.

- [ ] **Step 8: Run the full suite**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest -v`
Expected: 30 tests across the six modules, all green. The real-note regression in
`test_writer.py` skips on a machine where Part A has not landed — on the work
laptop it must not skip.

- [ ] **Step 9: Commit**

```bash
cd ~/projects/orgcapture
git add src/orgcapture/images.py src/orgcapture/capture.py tests/test_images.py tests/test_capture.py
git commit -m "feat: archive, transcribe, and link whiteboard photos"
```

### Task B8: The Telegram bot

**Files:**
- Create: `~/projects/orgcapture/src/orgcapture/bot.py`
- Test: `~/projects/orgcapture/tests/test_bot.py`

**Interfaces:**
- Produces: `authorized(chat_id: int, allowed: frozenset[int]) -> bool`; `Handlers(capturer: Capturer)` with async `on_text`, `on_photo`, `on_undo`, `on_where`, `on_flush`, `on_unsupported`; `main() -> None` as the console entrypoint.

- [ ] **Step 1: Write the failing test**

Only the pure authorization predicate and the reply routing are unit-tested; the polling loop itself is exercised by the manual smoke in Task B10.

`tests/test_bot.py`:

```python
from orgcapture.bot import authorized


def test_authorized_accepts_only_listed_chats():
    allowed = frozenset({111, 222})
    assert authorized(111, allowed)
    assert authorized(222, allowed)
    assert not authorized(333, allowed)


def test_authorized_denies_everything_when_the_list_is_empty():
    assert not authorized(111, frozenset())
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_bot.py -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'orgcapture.bot'`

- [ ] **Step 3: Write the implementation**

`src/orgcapture/bot.py`:

```python
"""Telegram long-polling front end. All org logic lives in capture.py."""

import logging
from datetime import datetime

from telegram import Update
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

from orgcapture.capture import Capturer, Config

log = logging.getLogger("orgcapture")


def authorized(chat_id: int, allowed: frozenset[int]) -> bool:
    return chat_id in allowed


class Handlers:
    def __init__(self, capturer: Capturer) -> None:
        self.capturer = capturer

    def _ok(self, update: Update) -> bool:
        chat = update.effective_chat
        if chat is None or not authorized(chat.id, self.capturer.config.allowed_chat_ids):
            # Silent on purpose: an unauthorized prober should not learn the
            # bot is live.
            log.warning("ignoring message from unauthorized chat %s", chat and chat.id)
            return False
        return True

    async def _reply(self, update: Update, text: str) -> None:
        await update.effective_message.reply_text(text)

    async def on_text(self, update: Update, _: ContextTypes.DEFAULT_TYPE) -> None:
        if not self._ok(update):
            return
        message = update.effective_message
        await self._reply(
            update,
            self.capturer.capture_text(
                update.update_id, message.text or "", datetime.now()
            ),
        )

    async def on_photo(self, update: Update, _: ContextTypes.DEFAULT_TYPE) -> None:
        if not self._ok(update):
            return
        message = update.effective_message
        # message.photo is ordered smallest to largest.
        photo = await message.photo[-1].get_file()
        image = bytes(await photo.download_as_bytearray())
        await self._reply(
            update,
            self.capturer.capture_photo(
                update.update_id, image, message.caption or "", datetime.now()
            ),
        )

    async def on_undo(self, update: Update, _: ContextTypes.DEFAULT_TYPE) -> None:
        if not self._ok(update):
            return
        await self._reply(update, self.capturer.undo())

    async def on_where(self, update: Update, _: ContextTypes.DEFAULT_TYPE) -> None:
        if not self._ok(update):
            return
        note = self.capturer.target(datetime.now())
        state = "exists" if note.exists() else "MISSING — captures will park"
        await self._reply(update, f"{note} ({state})")

    async def on_flush(self, update: Update, _: ContextTypes.DEFAULT_TYPE) -> None:
        if not self._ok(update):
            return
        await self._reply(update, self.capturer.flush(datetime.now()))

    async def on_unsupported(self, update: Update, _: ContextTypes.DEFAULT_TYPE) -> None:
        if not self._ok(update):
            return
        await self._reply(
            update, "not handled yet — this phase captures text and photos only"
        )


async def on_error(update: object, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Report failures to the sender. A dropped message is worse than a noisy one."""
    log.exception("handler failed", exc_info=context.error)
    if isinstance(update, Update) and update.effective_message is not None:
        await update.effective_message.reply_text(f"failed: {context.error}")


def main() -> None:
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s"
    )
    config = Config.from_env()
    handlers = Handlers(Capturer(config))

    app = Application.builder().token(config.bot_token).build()
    app.add_handler(CommandHandler("undo", handlers.on_undo))
    app.add_handler(CommandHandler("where", handlers.on_where))
    app.add_handler(CommandHandler("flush", handlers.on_flush))
    app.add_handler(MessageHandler(filters.PHOTO, handlers.on_photo))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handlers.on_text))
    app.add_handler(
        MessageHandler(
            filters.VOICE | filters.AUDIO | filters.Document.ALL | filters.VIDEO,
            handlers.on_unsupported,
        )
    )
    app.add_error_handler(on_error)

    log.info("polling; org root %s", config.org_root)
    app.run_polling(allowed_updates=["message"])
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd ~/projects/orgcapture && .venv/bin/pytest tests/test_bot.py -v`
Expected: 2 passed

- [ ] **Step 5: Verify the module imports cleanly**

Run: `cd ~/projects/orgcapture && .venv/bin/python -c "import orgcapture.bot; print('ok')"`
Expected: `ok`. This catches python-telegram-bot API drift (`filters.Document.ALL`, `Application.builder`) before it reaches datacore.

- [ ] **Step 6: Commit**

```bash
cd ~/projects/orgcapture
git add src/orgcapture/bot.py tests/test_bot.py
git commit -m "feat: telegram handlers and polling entrypoint"
```

### Task B9: Packaging

**Files:**
- Create: `~/projects/orgcapture/Dockerfile`
- Create: `~/projects/orgcapture/docker-compose.yml`
- Create: `~/projects/orgcapture/.env.example`
- Create: `~/projects/orgcapture/README.md`

**Interfaces:**
- Consumes: the `orgcapture` console script from `pyproject.toml` (Task B1).
- Produces: a `docker compose up -d --build` deployable stack named `orgcapture`.

- [ ] **Step 1: Write the Dockerfile**

```dockerfile
FROM python:3.13-slim

WORKDIR /app
COPY pyproject.toml ./
COPY src ./src
RUN pip install --no-cache-dir .

# Runs as Scott's uid so files land in the Syncthing tree with the right owner.
USER 1000:1000

CMD ["orgcapture"]
```

- [ ] **Step 2: Confirm the uid assumption on datacore**

```bash
ssh datacore 'id -u; id -g'
```

Expected: `1000` and `1000`. If they differ, change the `USER` line and the compose `user:` line to match before continuing — files written with the wrong owner into a synced tree are a mess to unpick.

- [ ] **Step 3: Write `docker-compose.yml`**

```yaml
name: orgcapture

services:
  orgcapture:
    build: .
    container_name: orgcapture
    restart: unless-stopped
    user: "1000:1000"
    env_file:
      - .env
    environment:
      TZ: America/New_York
      ORGCAPTURE_ORG_ROOT: /org/work
      ORGCAPTURE_STATE_DIR: /state
      ORGCAPTURE_AUTH_PATH: /auth/auth.json
      ORGCAPTURE_VISION_MODEL: ${ORGCAPTURE_VISION_MODEL:-google/gemini-3-flash-preview}
    volumes:
      - /home/scott/docs/org/work:/org/work
      - /home/scott/.pi/agent/auth.json:/auth/auth.json:ro
      - /srv/data/stacks-state/orgcapture:/state
```

- [ ] **Step 4: Write `.env.example`**

```bash
# Copy to .env and fill in. .env is gitignored.
# Note: .env lives in a Syncthing-replicated directory, so this token reaches
# every peer syncing ~/projects. Move it to agenix after the NixOS cutover.
TELEGRAM_BOT_TOKEN=123456:replace-me
TELEGRAM_ALLOWED_CHAT_IDS=000000000
```

- [ ] **Step 5: Write `README.md`**

```markdown
# orgcapture

Telegram → `New This Quarter` in the current work quarterly tracker.

Send the bot a text message and it lands as a `:capture:` subtree in
`~/docs/org/work/Quarterly/<YYYY>-Q<N>.org`. Send a whiteboard photo and the
photo is archived under `assets/captures/` and transcribed into the same place.

## Commands

| Command | Effect |
|---|---|
| *(any text)* | Capture it |
| *(any photo)* | Archive, transcribe, capture |
| `/where` | Show the note it would write to right now |
| `/undo` | Remove the most recent capture |
| `/flush` | Write captures parked while the quarter note was missing |

## Deploy

Runs on datacore, delivered there by Syncthing as `~/projects/work/orgcapture`.

```bash
cp .env.example .env    # fill in the bot token and your chat id
docker compose up -d --build
docker compose logs -f
```

## Tests

```bash
python3 -m venv .venv && .venv/bin/pip install -e . pytest
.venv/bin/pytest
```

## Notes

- The service never creates a quarter note. If this quarter's note does not
  exist, captures park and `/where` says so — open it with `C-c q` in Emacs,
  then `/flush`. This is deliberate: an empty note created by a headless
  service can win a Syncthing conflict and quarantine the real one.
- The OpenRouter key is read from `~/.pi/agent/auth.json`, never copied here.
- Runtime state is in `/srv/data/stacks-state/orgcapture/`, off the synced tree.
```

- [ ] **Step 6: Commit**

```bash
cd ~/projects/orgcapture
git add Dockerfile docker-compose.yml .env.example README.md
git commit -m "feat: container packaging and deploy docs"
```

### Task B10: Deploy to datacore and smoke test

**Files:**
- Create: `~/projects/orgcapture/.env` on datacore (uncommitted)
- Create: `/srv/data/stacks-state/orgcapture/` on datacore

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Create the bot and record its token**

In Telegram, message `@BotFather`: `/newbot`, give it a name and username. Record the token. This is a **new** bot, separate from the uptime-kuma notifier — do not reuse that token.

Then send the new bot any message and read your chat id:

```bash
curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates" | head -40
```

Record `result[0].message.chat.id`.

- [ ] **Step 2: Confirm Syncthing delivered the project to datacore**

```bash
ssh datacore 'ls ~/projects/work/orgcapture/'
```

Expected: `Dockerfile docker-compose.yml pyproject.toml README.md src tests .env.example`. If it is absent, Syncthing has not caught up — wait rather than copying by hand, or the two copies diverge.

- [ ] **Step 3: Create the state directory and `.env` on datacore**

```bash
ssh datacore 'sudo install -d -o 1000 -g 1000 /srv/data/stacks-state/orgcapture && ls -ld /srv/data/stacks-state/orgcapture'
```

Then write `.env` on datacore (not on the laptop — it would sync to rafik too):

```bash
ssh datacore 'cat > ~/projects/work/orgcapture/.env <<EOF
TELEGRAM_BOT_TOKEN=<token from step 1>
TELEGRAM_ALLOWED_CHAT_IDS=<chat id from step 1>
EOF
chmod 600 ~/projects/work/orgcapture/.env'
```

- [ ] **Step 4: Build and start**

```bash
ssh datacore 'cd ~/projects/work/orgcapture && docker compose up -d --build'
ssh datacore 'cd ~/projects/work/orgcapture && docker compose logs --tail 30'
```

Expected: a log line `polling; org root /org/work` and no traceback.

- [ ] **Step 5: Smoke test `/where`**

Send `/where` from the phone.
Expected: `/org/work/Quarterly/2026-Q3.org (exists)`. If it says MISSING, Part A did not propagate — stop and check.

- [ ] **Step 6: Smoke test a text capture**

Send `smoke test from the phone`.

Expected: a reply naming `2026-Q3.org → New This Quarter` and echoing the org subtree. Then on the laptop, after sync settles:

```bash
tail -5 ~/docs/org/work/Quarterly/2026-Q3.org
find ~/docs/org/work -name '*.sync-conflict-*' -print
```

Expected: the capture subtree present, no conflict files.

- [ ] **Step 7: Smoke test `/undo`**

Send `/undo`.

Expected: `removed the last capture from 2026-Q3.org`, and the note back to its previous content.

- [ ] **Step 8: Smoke test a whiteboard photo**

Photograph a whiteboard (or any handwriting) and send it.

Expected: a reply containing a transcription and a `[[file:../assets/...]]` link. Then in Emacs, open the note, put point on the link, and press `C-c C-o`.

Expected: the archived photo opens.

- [ ] **Step 9: Verify restart safety**

```bash
ssh datacore 'cd ~/projects/work/orgcapture && docker compose stop'
```

Send two messages while it is down, then:

```bash
ssh datacore 'cd ~/projects/work/orgcapture && docker compose start && sleep 20 && docker compose logs --tail 20'
```

Expected: both messages are captured exactly once — neither lost nor duplicated.

- [ ] **Step 10: Verify no key leaked into the image**

```bash
ssh datacore 'docker run --rm --entrypoint sh orgcapture-orgcapture -c "grep -rl \"sk-or\" / 2>/dev/null | head"'
```

Expected: no output.

- [ ] **Step 11: Remove the Part A snapshot**

Only once every check above has passed:

```bash
rm ~/quarterly-snapshot-*.tar.gz
```

- [ ] **Step 12: Final commit and push**

```bash
cd ~/projects/orgcapture
.venv/bin/pytest
git add -A
git commit -m "chore: verified deploy on datacore"
```

Confirm with Scott before creating any GitHub remote for this repo — it contains no secrets, but publishing is his call.

---

## Verification checklist

Run these after Task B10, and record the output:

- [ ] `cd ~/projects/orgcapture && .venv/bin/pytest` — all green, no skips on the work laptop
- [ ] `/where` reports `/org/work/Quarterly/2026-Q3.org (exists)`
- [ ] A text capture appears under `New This Quarter` on the laptop with no `.sync-conflict-*` files anywhere in `~/docs/org/work`
- [ ] A whiteboard photo yields a transcription plus a link that opens with `C-c C-o`
- [ ] Stop/start loses and duplicates nothing
- [ ] `grep -rl "sk-or" /` inside the image finds nothing
- [ ] Six notes in `~/docs/org/work/Quarterly/`, all `:ID:`s unchanged from `ids-before.txt`
