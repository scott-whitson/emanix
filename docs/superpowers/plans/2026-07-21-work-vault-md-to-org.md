# Work Vault md → org Conversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** All 110 markdown notes in `~/docs/org/work` become org-roam `.org` files (IDs, `id:` links, roam naming); the `.md` originals and old-tool debris are deleted only after three verification gates pass.

**Architecture:** A self-contained Python tool (`tools/md2org/`) with pure, unit-tested transform functions and three subcommands: `map` (title→uuid/target planning), `convert` (writes `.org` + audit log, never deletes), `delete-md` (deletes only logged-converted sources). Pandoc does the body conversion with Obsidian syntax protected behind placeholder tokens. Verification is Emacs itself: batch org parsing plus an `org-roam-db-sync` ID check (`verify-roam.el`).

**Tech Stack:** Python 3 stdlib, pandoc (via `nix shell nixpkgs#pandoc`), emacs --batch + org-roam (the machine's own build).

**Spec:** `docs/superpowers/specs/2026-07-21-work-vault-md-to-org-design.md`

## Global Constraints

- **Never** `git add -A`/`git add .`; stage explicit paths. **No** Co-Authored-By trailers.
- Propagation: push on WSL → `ssh datacore "cd ~/projects/dotfiles && git pull --ff-only"` → eminix ff-merge. Never edit datacore's checkout.
- Everything runs on THIS machine (the work-WSL, the vault's single writer). The vault is `/home/scott/docs/org/work` — live, synced, versioned on datacore. **No step other than Task 3's final gated deletion may remove or overwrite a `.md` file.** `convert` must refuse to overwrite an existing `.org` target.
- Naming: `YYYYMMDDHHMMSS-slug.org` — timestamp from the source file's mtime; slug = lowercase, every non-alphanumeric run → `_`, strip edge `_`. `#+title:` = the original filename stem (frontmatter `title:` overrides `#+title:` only, never the slug).
- Link forms in output: resolved → `[[id:UUID][Name-or-alias]]`; anchors dropped (logged); unresolved → `[[roam:Name]]`; image embeds → `[[file:relative-name]]`. Zero raw Obsidian `[[…]]` may remain.
- Audit log: `~/docs/org/work/.conversion-log.txt` — every file mapping, every link resolution/dangling/anchor-drop, every dropped frontmatter key. Deleted at the very end (it must not sync forever).
- Debris deletion (Task 3, after gates only): `.zk/` and `Templates/` (and Templates' contents even though they contain `.md` — they are excluded from conversion). `.canvas`, `.base`, PNG/pdf/txt files untouched.
- Rollback layers already in place: datacore `.stversions` (30d) + OneDrive `docs-retired-20260720` — deletions are recoverable; never bypass the gates anyway.
- pandoc invocation: `pandoc -f gfm -t org --wrap=none`. Run conversion under `nix shell nixpkgs#pandoc -c …` (do not install pandoc permanently).
- Python tests: stdlib `unittest`, file `tools/md2org/test_md2org.py`, run with `python3 -m unittest discover tools/md2org -v`.

---

### Task 1: The converter tool (TDD) + roam verifier

**Files:**
- Create: `tools/md2org/md2org.py`
- Create: `tools/md2org/test_md2org.py`
- Create: `tools/md2org/verify-roam.el`

**Interfaces:**
- Produces CLI: `python3 tools/md2org/md2org.py {map|convert|delete-md} --vault PATH`. `map` writes `PATH/.conversion-map.tsv` (`md-relpath<TAB>uuid<TAB>org-relpath` per line) and prints a summary; `convert` reads/creates the map, writes `.org` files + `.conversion-log.txt`, deletes nothing; `delete-md` deletes exactly the md files listed in the map whose `.org` target exists. Skip rules: files under `Templates/` and `.zk/` are never mapped/converted.
- Produces `verify-roam.el`: `emacs --batch -l tools/md2org/verify-roam.el` syncs org-roam over `~/docs/org` and exits non-zero unless every uuid in `.conversion-map.tsv` is a registered node.

- [ ] **Step 1: Write the failing tests**

`tools/md2org/test_md2org.py`:

```python
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import md2org


class TestSlugify(unittest.TestCase):
    def test_spaces(self):
        self.assertEqual(md2org.slugify("The Paper Corp"), "the_paper_corp")

    def test_punctuation(self):
        self.assertEqual(md2org.slugify("Rubber, Inc."), "rubber_inc")

    def test_empty(self):
        self.assertEqual(md2org.slugify("!!!"), "untitled")


class TestTargetName(unittest.TestCase):
    def test_mtime_and_collision_bump(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "Note.md"
            p.write_text("x")
            os.utime(p, (1718200530, 1718200530))  # fixed mtime
            used = set()
            first = md2org.target_name(p, used)
            second = md2org.target_name(p, used)  # same file again -> +1s bump
            self.assertRegex(first, r"^\d{14}-note\.org$")
            self.assertNotEqual(first, second)
            self.assertEqual(len(used), 2)


class TestFrontmatter(unittest.TestCase):
    def test_split_and_keys(self):
        text = "---\ntitle: Real Title\ntags: [alpha, beta]\nauthor: scott\n---\nBody here\n"
        meta, body, dropped = md2org.split_frontmatter(text)
        self.assertEqual(meta["title"], "Real Title")
        self.assertEqual(meta["tags"], ["alpha", "beta"])
        self.assertEqual(dropped, ["author"])
        self.assertEqual(body, "Body here\n")

    def test_no_frontmatter(self):
        meta, body, dropped = md2org.split_frontmatter("Just body\n")
        self.assertEqual(meta, {})
        self.assertEqual(body, "Just body\n")
        self.assertEqual(dropped, [])


class TestWikilinks(unittest.TestCase):
    def setUp(self):
        # resolver: name(lower) -> uuid, only 'central data' resolves
        self.resolve = lambda name: (
            "UUID-CD" if name.lower() == "central data" else None
        )

    def roundtrip(self, text):
        protected, tokens = md2org.protect(text)
        self.assertNotIn("[[", protected)
        log = []
        return md2org.restore(protected, tokens, self.resolve, log), log

    def test_resolved(self):
        out, _ = self.roundtrip("see [[Central Data]] now")
        self.assertEqual(out, "see [[id:UUID-CD][Central Data]] now")

    def test_alias(self):
        out, _ = self.roundtrip("see [[Central Data|CD]] now")
        self.assertEqual(out, "see [[id:UUID-CD][CD]] now")

    def test_anchor_dropped_and_logged(self):
        out, log = self.roundtrip("see [[Central Data#Billing]] now")
        self.assertEqual(out, "see [[id:UUID-CD][Central Data]] now")
        self.assertTrue(any("anchor" in line for line in log))

    def test_unresolved(self):
        out, _ = self.roundtrip("see [[Ghost Note]] now")
        self.assertEqual(out, "see [[roam:Ghost Note]] now")

    def test_image_embed(self):
        out, _ = self.roundtrip("![[Pasted image 1.png]]")
        self.assertEqual(out, "[[file:Pasted image 1.png]]")


class TestHeader(unittest.TestCase):
    def test_header_and_filetags(self):
        h = md2org.org_header("U1", "My Note", ["alpha", "beta"])
        self.assertIn(":ID:       U1", h)
        self.assertIn("#+title: My Note", h)
        self.assertIn("#+filetags: :alpha:beta:", h)

    def test_drop_dup_heading(self):
        body = "* The Paper Corp\n\nContent\n"
        self.assertEqual(
            md2org.drop_dup_heading(body, "The Paper Corp"), "\nContent\n"
        )
        self.assertEqual(
            md2org.drop_dup_heading(body, "Other"), body
        )


@unittest.skipUnless(shutil.which("pandoc"), "pandoc not on PATH")
class TestEndToEnd(unittest.TestCase):
    def test_convert_vault(self):
        with tempfile.TemporaryDirectory() as d:
            vault = Path(d)
            (vault / "Central Data.md").write_text("# Central Data\n\nHub note.\n")
            (vault / "Client.md").write_text(
                "---\ntitle: Client X\nauthor: s\n---\n"
                "Linked to [[Central Data]] and [[Missing]].\n\n"
                "| a | b |\n|---|---|\n| 1 | 2 |\n"
            )
            (vault / "Templates").mkdir()
            (vault / "Templates" / "T.md").write_text("[[skip me]]")
            run = lambda *a: subprocess.run(
                ["python3", str(Path(__file__).parent / "md2org.py"), *a,
                 "--vault", str(vault)],
                capture_output=True, text=True)
            r = run("map")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(
                len((vault / ".conversion-map.tsv").read_text().splitlines()), 2)
            r = run("convert")
            self.assertEqual(r.returncode, 0, r.stderr)
            orgs = sorted(vault.glob("*.org"))
            self.assertEqual(len(orgs), 2)
            client = next(p for p in orgs if "client" in p.name).read_text()
            self.assertIn("#+title: Client X", client)     # frontmatter title wins
            self.assertIn("[[id:", client)                  # resolved link
            self.assertIn("[[roam:Missing]]", client)       # dangling link
            self.assertIn("|", client)                      # table survived
            self.assertNotIn("Central Data.org", [p.name for p in orgs])  # roam-named
            # md untouched by convert; Templates skipped
            self.assertTrue((vault / "Client.md").exists())
            self.assertFalse(list((vault / "Templates").glob("*.org")))
            log = (vault / ".conversion-log.txt").read_text()
            self.assertIn("author", log)                    # dropped key logged
            r = run("delete-md")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertFalse((vault / "Client.md").exists())
            self.assertTrue((vault / "Templates" / "T.md").exists())  # never deleted


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/scott/dotfiles && python3 -m unittest discover tools/md2org -v`
Expected: FAIL/ERROR — `md2org` module missing (create an empty `tools/md2org/md2org.py` first if discovery needs it).

- [ ] **Step 3: Implement `tools/md2org/md2org.py`**

```python
#!/usr/bin/env python3
"""Convert an Obsidian markdown vault to org-roam format.

Spec: docs/superpowers/specs/2026-07-21-work-vault-md-to-org-design.md
Subcommands: map / convert / delete-md. `convert` never deletes or
overwrites sources; deletion is a separate, gated step.
"""
import argparse
import datetime
import re
import subprocess
import sys
import uuid as uuidlib
from pathlib import Path

SKIP_DIRS = {"Templates", ".zk"}
MAP_NAME = ".conversion-map.tsv"
LOG_NAME = ".conversion-log.txt"

# !flag, name, optional #anchor, optional |alias
WIKILINK = re.compile(r"(!?)\[\[([^\]\|#]+)(#[^\]\|]*)?(?:\|([^\]]+))?\]\]")


def slugify(title):
    s = re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")
    return s or "untitled"


def target_name(md_path, used):
    ts = datetime.datetime.fromtimestamp(md_path.stat().st_mtime)
    while True:
        name = ts.strftime("%Y%m%d%H%M%S") + "-" + slugify(md_path.stem) + ".org"
        if name not in used:
            used.add(name)
            return name
        ts += datetime.timedelta(seconds=1)


def split_frontmatter(text):
    meta, dropped = {}, []
    if not text.startswith("---\n"):
        return meta, text, dropped
    end = text.find("\n---\n", 4)
    if end == -1:
        return meta, text, dropped
    body = text[end + 5:]
    for line in text[4:end].splitlines():
        m = re.match(r"^(\w[\w-]*):\s*(.*)$", line)
        if not m:
            continue
        key, val = m.group(1), m.group(2).strip()
        if key == "title" and val:
            meta["title"] = val.strip("\"'")
        elif key == "tags":
            meta["tags"] = [t.strip() for t in val.strip("[]").split(",") if t.strip()]
        else:
            dropped.append(key)
    return meta, body, dropped


def protect(text):
    tokens = []

    def repl(m):
        tokens.append(m.groups())  # (bang, name, anchor, alias)
        return f"@@WL{len(tokens) - 1}@@"

    return WIKILINK.sub(repl, text), tokens


def restore(text, tokens, resolve, log):
    for i, (bang, name, anchor, alias) in enumerate(tokens):
        name = name.strip()
        if bang:
            link = f"[[file:{name}]]"
        else:
            target = resolve(name)
            label = (alias or name).strip()
            if anchor:
                log.append(f"    anchor dropped: [[{name}{anchor}]]")
            if target:
                link = f"[[id:{target}][{label}]]"
            else:
                link = f"[[roam:{name}]]"
                log.append(f"    dangling -> [[roam:{name}]]")
        text = text.replace(f"@@WL{i}@@", link)
    return text


def convert_body(md_body):
    r = subprocess.run(
        ["pandoc", "-f", "gfm", "-t", "org", "--wrap=none"],
        input=md_body, capture_output=True, text=True, check=True)
    return r.stdout


def org_header(uid, title, filetags):
    h = f":PROPERTIES:\n:ID:       {uid}\n:END:\n#+title: {title}\n"
    if filetags:
        h += "#+filetags: :" + ":".join(filetags) + ":\n"
    return h + "\n"


def drop_dup_heading(org_text, title):
    lines = org_text.splitlines(keepends=True)
    if lines and re.fullmatch(r"\*\s+" + re.escape(title) + r"\s*",
                              lines[0], re.IGNORECASE):
        return "".join(lines[1:])
    return org_text


def vault_md_files(vault):
    return sorted(
        p for p in vault.rglob("*.md")
        if not any(part in SKIP_DIRS for part in p.relative_to(vault).parts))


def load_map(vault):
    entries = []
    for line in (vault / MAP_NAME).read_text().splitlines():
        md_rel, uid, org_rel = line.split("\t")
        entries.append((md_rel, uid, org_rel))
    return entries


def cmd_map(vault):
    used, lines = set(), []
    for p in vault_md_files(vault):
        uid = str(uuidlib.uuid4())
        org_rel = str(p.relative_to(vault).parent / target_name(p, used))
        lines.append(f"{p.relative_to(vault)}\t{uid}\t{org_rel}")
    (vault / MAP_NAME).write_text("\n".join(lines) + "\n")
    print(f"mapped {len(lines)} notes -> {vault / MAP_NAME}")


def cmd_convert(vault):
    if not (vault / MAP_NAME).exists():
        cmd_map(vault)
    entries = load_map(vault)
    # title index: stem(lower) -> [(md_rel, uid)]
    index = {}
    for md_rel, uid, _ in entries:
        index.setdefault(Path(md_rel).stem.lower(), []).append((md_rel, uid))

    log = [f"conversion run {datetime.datetime.now().isoformat()}"]
    for md_rel, uid, org_rel in entries:
        src, dst = vault / md_rel, vault / org_rel
        if dst.exists():
            sys.exit(f"refusing to overwrite existing {dst}")
        log.append(f"{md_rel} -> {org_rel} ({uid})")

        def resolve(name, _here=Path(md_rel).parent):
            cands = index.get(name.strip().lower(), [])
            if len(cands) == 1:
                return cands[0][1]
            for cand_rel, cand_uid in cands:  # prefer same directory
                if Path(cand_rel).parent == _here:
                    return cand_uid
            return None

        meta, body, dropped = split_frontmatter(src.read_text())
        for key in dropped:
            log.append(f"    frontmatter key dropped: {key}")
        title = meta.get("title", Path(md_rel).stem)
        protected, tokens = protect(body)
        org = convert_body(protected)
        org = restore(org, tokens, resolve, log)
        org = drop_dup_heading(org, title)
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(org_header(uid, title, meta.get("tags", [])) + org)

    with (vault / LOG_NAME).open("a") as f:
        f.write("\n".join(log) + "\n")
    dangling = sum(1 for l in log if "dangling" in l)
    print(f"converted {len(entries)} notes; {dangling} dangling links; "
          f"log: {vault / LOG_NAME}")


def cmd_delete_md(vault):
    deleted = 0
    for md_rel, _uid, org_rel in load_map(vault):
        src, dst = vault / md_rel, vault / org_rel
        if dst.exists() and src.exists():
            src.unlink()
            deleted += 1
        elif not dst.exists():
            sys.exit(f"org target missing for {md_rel} — aborting, nothing more deleted")
    print(f"deleted {deleted} converted .md files")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["map", "convert", "delete-md"])
    ap.add_argument("--vault", default=str(Path.home() / "docs/org/work"))
    args = ap.parse_args()
    vault = Path(args.vault).resolve()
    {"map": cmd_map, "convert": cmd_convert, "delete-md": cmd_delete_md}[args.command](vault)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run the tests**

Run: `cd /home/scott/dotfiles && nix shell nixpkgs#pandoc -c python3 -m unittest discover tools/md2org -v`
Expected: ALL PASS (the end-to-end test needs pandoc; unit tests pass without it — run once plain and once under nix shell so both paths are exercised). Fix code (not tests) until green; if a test itself is wrong, say so in the report.

- [ ] **Step 5: Create `tools/md2org/verify-roam.el`**

```elisp
;;; verify-roam.el --- gate 2: every converted note is a registered org-roam node
;; Run: emacs --batch -l tools/md2org/verify-roam.el
;; Exits non-zero and names the missing IDs if any uuid from the conversion
;; map is absent from the org-roam DB after a full sync.
(require 'org-roam)
(setq org-roam-directory (expand-file-name "~/docs/org"))
(org-roam-db-sync)
(let* ((map-file (expand-file-name "~/docs/org/work/.conversion-map.tsv"))
       (lines (split-string (with-temp-buffer
                              (insert-file-contents map-file)
                              (buffer-string))
                            "\n" t))
       (missing '()))
  (dolist (line lines)
    (let ((uuid (nth 1 (split-string line "\t"))))
      (unless (org-roam-db-query
               [:select id :from nodes :where (= id $s1)] uuid)
        (push uuid missing))))
  (if missing
      (progn (message "MISSING %d IDs: %S" (length missing) missing)
             (kill-emacs 1))
    (message "ALL-REGISTERED: %d nodes" (length lines))))
```

(Do not run it yet — the vault has no map until Task 2. Syntax-check only: `emacs --batch --eval '(progn (check-parens))' tools/md2org/verify-roam.el` wrapped as `emacs --batch --file tools/md2org/verify-roam.el --eval '(check-parens)'` — expected: silent exit 0.)

- [ ] **Step 6: Commit**

```bash
cd /home/scott/dotfiles
git add tools/md2org/md2org.py tools/md2org/test_md2org.py tools/md2org/verify-roam.el
git commit -m "feat(tools): md2org vault converter with gated deletion"
git push
ssh datacore "cd ~/projects/dotfiles && git pull --ff-only"
```

---

### Task 2: Convert the real vault (ops; no deletion, no commits)

**Files:** none in repo. Writes `.org` files + map + log inside `~/docs/org/work`.

**Interfaces:**
- Consumes: `tools/md2org/md2org.py` CLI (Task 1).
- Produces: ~110 `.org` files beside their `.md` sources; `.conversion-map.tsv` + `.conversion-log.txt`; a reviewed summary (converted / dangling / anchors / dropped keys) for the report.

- [ ] **Step 1: Snapshot pre-state**

```bash
cd ~/docs/org/work && find . -name '*.md' -not -path './Templates/*' -not -path './.zk/*' | wc -l; find . -name '*.org' | wc -l
```

Expected: `110` (or the exact current count — record it) and `0`.

- [ ] **Step 2: Map and eyeball**

```bash
cd /home/scott/dotfiles && python3 tools/md2org/md2org.py map
head -5 ~/docs/org/work/.conversion-map.tsv; wc -l ~/docs/org/work/.conversion-map.tsv
```

Expected: `mapped 110 notes …`; tsv lines look like `The Paper Corp.md<TAB><uuid><TAB>20250612101530-the_paper_corp.org`; line count matches Step 1.

- [ ] **Step 3: Convert**

```bash
cd /home/scott/dotfiles && nix shell nixpkgs#pandoc -c python3 tools/md2org/md2org.py convert
```

Expected: `converted 110 notes; N dangling links; log: …`. Record N. If the script aborts (`refusing to overwrite`), STOP and report — do not delete anything to make room.

- [ ] **Step 4: Review the log + spot-check three notes**

```bash
grep -c "dangling" ~/docs/org/work/.conversion-log.txt; grep -c "anchor" ~/docs/org/work/.conversion-log.txt; grep "frontmatter key dropped" ~/docs/org/work/.conversion-log.txt | sort | uniq -c
head -20 "$(ls ~/docs/org/work/*paper_corp*.org 2>/dev/null | head -1)"
```

Expected: counts consistent with Step 3; the spot-checked file shows `:PROPERTIES:/:ID:`, `#+title:`, and org-formatted body. Quote one full converted note (a short one) in your report.

- [ ] **Step 5: Verify sources untouched**

```bash
cd ~/docs/org/work && find . -name '*.md' -not -path './Templates/*' -not -path './.zk/*' | wc -l
```

Expected: same count as Task 2 Step 1 — `convert` deleted nothing.

---

### Task 3: Gates, then deletion (ops; no commits)

**Files:** none in repo. Deletes (only after all gates pass): the mapped `.md` files, `Templates/`, `.zk/`, and finally the map/log files.

**Interfaces:**
- Consumes: converted vault (Task 2), `verify-roam.el` (Task 1).
- Produces: an all-org vault, debris removed, synced everywhere.

- [ ] **Step 1: Gate 1 — every `.org` parses**

```bash
cd ~/docs/org/work && emacs --batch --eval '(progn
  (require (quote org))
  (dolist (f (directory-files-recursively default-directory "\\.org$"))
    (with-temp-buffer (insert-file-contents f) (org-mode) (org-element-parse-buffer)))
  (message "PARSE-OK"))'
```

Expected: `PARSE-OK` (org-element parse errors would abort non-zero). Any failure: STOP, report the file.

- [ ] **Step 2: Gate 2 — org-roam registers every ID**

```bash
cd /home/scott/dotfiles && emacs --batch -l tools/md2org/verify-roam.el
```

Expected: `ALL-REGISTERED: 110 nodes`. `MISSING …` → STOP and report.

- [ ] **Step 3: Gate 3 — link accounting**

```bash
cd ~/docs/org/work
grep -roh '\[\[id:[^]]*\]' --include='*.org' . | wc -l
grep -rn '\[\[' --include='*.org' . | grep -vE '\[\[(id:|roam:|file:|https?://|\*)' | head -5; echo raw-scan-done
```

Expected: the `id:` count ≥ the resolved-link count implied by Task 2 (report both numbers); the raw scan prints NOTHING before `raw-scan-done` (no unconverted `[[…]]` forms). Hits → STOP and report them.

- [ ] **Step 4: Delete — md sources, then debris**

```bash
cd /home/scott/dotfiles && python3 tools/md2org/md2org.py delete-md
cd ~/docs/org/work && rm -rf Templates .zk && find . -name '*.md' | wc -l
```

Expected: `deleted 110 converted .md files`, then `0` remaining `.md` anywhere (Templates' were removed with the directory).

- [ ] **Step 5: Confirm propagation + datacore versions caught the deletions**

```bash
sleep 60; ssh datacore 'find ~/docs/org/work -name "*.org" | wc -l; find ~/docs/org/work -name "*.md" | wc -l; ls ~/docs/org/work/.stversions/ | head -3'
ssh -o ConnectTimeout=5 eminix 'find ~/docs/org/work -name "*.org" | wc -l' 2>/dev/null || echo eminix-later
```

Expected: datacore `110` / `0` with `.stversions` entries present (the deleted mds); eminix `110` if awake (non-blocking otherwise; retry once after 90s on mismatch).

- [ ] **Step 6: Remove the map/log (they must not live in the synced tree forever)**

```bash
cp ~/docs/org/work/.conversion-log.txt ~/.local/backups/md2org-conversion-log-20260721.txt
rm ~/docs/org/work/.conversion-log.txt ~/docs/org/work/.conversion-map.tsv && echo audit-archived
```

Expected: `audit-archived` (log preserved outside the synced tree, map/log gone from the vault).

---

### Task 4: eminix registration + docs touch-up

**Files:**
- Modify: `docs/ioshi/work-sync.md` (one line)

**Interfaces:**
- Consumes: all-org vault synced to eminix.
- Produces: work notes registered in eminix's org-roam; doc no longer claims the vault is markdown.

- [ ] **Step 1: Sync eminix's org-roam DB and count work nodes**

```bash
ssh -o ConnectTimeout=5 eminix "emacs --batch --eval '(progn (require (quote org-roam)) (setq org-roam-directory (expand-file-name \"~/docs/org\")) (org-roam-db-sync) (message \"work nodes: %s\" (caar (org-roam-db-query [:select (funcall count id) :from nodes :where (like file $s1)] \"%/work/%\"))))'" 2>&1 | tail -1
```

Expected: `work nodes: 110` (±: any pre-existing org files under work/ add to it). If eminix is asleep, retry later and report BLOCKED-on-eminix rather than skipping.

- [ ] **Step 2: Update `docs/ioshi/work-sync.md`**

Replace the line:

```
  copy renamed `docs-retired-20260720` (2026-07-20); Emacs/org owns work
  notes now (files stay `.md` until a conversion project).
```

with:

```
  copy renamed `docs-retired-20260720` (2026-07-20); Emacs/org owns work
  notes now (converted to org-roam `.org` on 2026-07-21 — see
  `docs/superpowers/specs/2026-07-21-work-vault-md-to-org-design.md`).
```

- [ ] **Step 3: Commit and propagate everywhere**

```bash
cd /home/scott/dotfiles
git add docs/ioshi/work-sync.md
git commit -m "docs: work vault is org-roam now (md conversion done)"
git push
ssh datacore "cd ~/projects/dotfiles && git pull --ff-only"
ssh -o ConnectTimeout=5 eminix "cd ~/dotfiles && git fetch origin && git merge --ff-only origin/main" 2>&1 | tail -1
```

Expected: all three nodes at the same commit.
