#!/usr/bin/env bash
# One-shot: consolidate work quarter notes into $WORK_ORG_DIR/Quarterly/.
#
# Renames <timestamp>-YYYY_qN.org (loose in the work root, or in
# "Quarterly Notes/") to Quarterly/YYYY-QN.org and appends " (Work)" to the
# title. The :ID: property is never touched — every inbound link to these
# notes is an [[id:]] link and resolves through the roam DB by ID.
#
# Usage: migrate-work-quarters.sh [--dry-run]
set -euo pipefail

WORK="${WORK_ORG_DIR:-$HOME/docs/org/work}"
DEST="$WORK/Quarterly"
LEGACY="$WORK/Quarterly Notes"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

[[ -d "$WORK" ]] || { echo "no such work dir: $WORK" >&2; exit 1; }

mapfile -t files < <(find "$WORK" -maxdepth 2 -type f -regextype posix-extended \
  -regex '.*/[0-9]{14}-[0-9]{4}_q[1-4]\.org' | sort)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "nothing to migrate — no <timestamp>-YYYY_qN.org files under $WORK"
  exit 0
fi

for src in "${files[@]}"; do
  base=$(basename "$src" .org)   # 20260718100853-2026_q3
  stem=${base#*-}                # 2026_q3
  year=${stem%%_*}               # 2026
  quarter=${stem##*_q}           # 3
  name="${year}-Q${quarter}"     # 2026-Q3
  target="$DEST/$name.org"

  if [[ -e "$target" ]]; then
    echo "ABORT: $target already exists (would clobber)" >&2
    exit 1
  fi

  # awk, not `grep -oP`: grep here is ugrep, whose PCRE support is partial.
  # ID extraction is what makes these renames link-safe — it must not be clever.
  id=$(awk '/^:ID:/{print $2; exit}' "$src")
  if [[ -z "$id" ]]; then
    echo "ABORT: $src has no :ID: — refusing to move a note whose links cannot resolve" >&2
    exit 1
  fi

  if [[ $DRY -eq 1 ]]; then
    echo "would move: $src"
    echo "        ->: $target"
    echo "      title: #+title: $name (Work)   (id $id preserved)"
    continue
  fi

  mkdir -p "$DEST"
  mv "$src" "$target"
  # Rewrite only the first #+title: line.
  sed -i "0,/^#+title:.*/s//#+title: $name (Work)/" "$target"
  echo "moved: $name"
done

if [[ $DRY -eq 1 ]]; then
  echo "(dry run — nothing changed)"
  exit 0
fi

if [[ -d "$LEGACY" ]]; then
  if [[ -z "$(ls -A "$LEGACY")" ]]; then
    rmdir "$LEGACY"
    echo "removed empty: $LEGACY"
  else
    echo "NOTE: $LEGACY still has files, leaving it in place:" >&2
    ls -A "$LEGACY" >&2
  fi
fi
