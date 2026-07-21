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
            if anchor:
                log.append(f"    anchor dropped: [[{bang}{name}{anchor}]]")
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
    converted = skipped = failed = 0
    for md_rel, uid, org_rel in entries:
        src, dst = vault / md_rel, vault / org_rel
        if dst.exists():
            log.append(f"    already converted, skipping: {md_rel}")
            skipped += 1
            continue

        def resolve(name, _here=Path(md_rel).parent):
            cands = index.get(name.strip().lower(), [])
            if len(cands) == 1:
                return cands[0][1]
            for cand_rel, cand_uid in cands:  # prefer same directory
                if Path(cand_rel).parent == _here:
                    return cand_uid
            return None

        try:
            meta, body, dropped = split_frontmatter(src.read_text())
            title = meta.get("title", Path(md_rel).stem)
            protected, tokens = protect(body)
            org = convert_body(protected)
        except subprocess.CalledProcessError as e:
            stderr = e.stderr or str(e)
            first_line = stderr.splitlines()[0] if stderr else ""
            log.append(f"    PANDOC-FAILED: {md_rel}: {first_line}")
            failed += 1
            continue

        log.append(f"{md_rel} -> {org_rel} ({uid})")
        for key in dropped:
            log.append(f"    frontmatter key dropped: {key}")
        org = restore(org, tokens, resolve, log)
        org = drop_dup_heading(org, title)
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(org_header(uid, title, meta.get("tags", [])) + org)
        converted += 1

    with (vault / LOG_NAME).open("a") as f:
        f.write("\n".join(log) + "\n")
    dangling = sum(1 for l in log if "dangling" in l)
    print(f"converted {converted} notes ({skipped} skipped, {failed} failed); "
          f"{dangling} dangling links; log: {vault / LOG_NAME}")
    if failed > 0:
        sys.exit(1)


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
