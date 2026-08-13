#!/usr/bin/env bash
# One-shot: consolidate work quarter notes into $WORK_ORG_DIR/Quarterly/.
#
# Renames <timestamp>-YYYY_qN.org (loose in the work root, or in
# "Quarterly Notes/") to Quarterly/YYYY-QN.org and appends " (Work)" to the
# title. The :ID: property is never touched — every inbound link to these
# notes is an [[id:]] link and resolves through the roam DB by ID.
#
# Usage: migrate-work-quarters.sh [--dry-run]
#        migrate-work-quarters.sh --help
#
# Take a snapshot FIRST. The work tree is a Syncthing folder with no git
# history, so a tar is the only undo — and it must land OUTSIDE the synced
# folder, or the backup syncs to every peer and is itself at risk:
#
#     tar czf ~/quarterly-snapshot-$(date +%F).tar.gz -C ~/docs/org work
#
# Required order. Every inbound link resolves through org-roam's DB, which
# maps ID -> file path; the rename leaves those paths stale until a full
# re-index, so the sync step is not optional:
#
#     1. tar snapshot (above, outside the synced folder)
#     2. migrate-work-quarters.sh --dry-run     # review the plan
#     3. migrate-work-quarters.sh               # perform it
#     4. restart Emacs, or M-x org-roam-db-sync # re-index ID -> path
#     5. verify C-u C-c q opens Quarterly/YYYY-QN.org, links resolve
#
# Structure: pass 1 validates every candidate (file-level :ID: present, title
# line present, target free, no two sources colliding on one target) and
# builds the full src -> target map. Pass 2 mutates, and only runs when the
# whole map is clean. That makes --dry-run a true predicate of the real run.
set -euo pipefail

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

DRY=0
case "${1:-}" in
  --dry-run) DRY=1 ;;
  "")        DRY=0 ;;
  -h|--help) usage; exit 0 ;;
  *)         echo "unknown argument: $1 (expected --dry-run)" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "too many arguments" >&2; exit 2; }

WORK="${WORK_ORG_DIR:-$HOME/docs/org/work}"
DEST="$WORK/Quarterly"
LEGACY="$WORK/Quarterly Notes"

[[ -d "$WORK" ]] || { echo "no such work dir: $WORK" >&2; exit 1; }

# find runs into a temp file, not a pipeline into mapfile: inside a process
# substitution neither `set -e` nor pipefail can see a failing find, so a
# broken scan would read as "nothing to migrate" and exit 0 — indistinguishable
# from "already done".
#
# -name '.*' -prune keeps the scan out of dot-directories. Syncthing's Trash
# Can versioning preserves original filenames, so .stversions/ holds files that
# match the regex exactly; LC_ALL=C sorts '.' before letters, which would
# migrate the stale archived copy first and let it win the target. Both the
# scan and the sort are locale-pinned so the ordering is the same under cron,
# systemd and `ssh host 'cmd'` as it is interactively.
list=$(mktemp)
trap 'rm -f "$list"' EXIT
if ! LC_ALL=C find "$WORK" -mindepth 1 -maxdepth 2 \
      -name '.*' -prune -o \
      -type f -regextype posix-extended \
      -regex '.*/[0-9]{14}-[0-9]{4}_q[1-4]\.org' -print > "$list"; then
  echo "ABORT: find failed while scanning $WORK" >&2
  exit 1
fi
LC_ALL=C sort -o "$list" "$list"
mapfile -t files < "$list"

if [[ ${#files[@]} -eq 0 ]]; then
  echo "nothing to migrate — no <timestamp>-YYYY_qN.org files under $WORK"
  exit 0
fi

# ---------------------------------------------------------------- pass 1 ----
# Validate everything and build the map. Nothing is written in this pass, so
# any abort below leaves the tree exactly as it was found.
srcs=(); targets=(); names=(); ids=()
declare -A claimed_by

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

  if [[ -n "${claimed_by[$target]:-}" ]]; then
    echo "ABORT: two sources map to $target (would clobber):" >&2
    echo "         ${claimed_by[$target]}" >&2
    echo "         $src" >&2
    exit 1
  fi
  claimed_by[$target]=$src

  # awk, not `grep -oP`: grep here is ugrep, whose PCRE support is partial.
  # ID extraction is what makes these renames link-safe — it must not be
  # clever. The scan stops at the first heading: with `org-adapt-indentation'
  # nil (the Org 9.5 default) a subheading's property drawer also sits at
  # column 0, so an unbounded scan would accept a heading's ID from a note
  # that has no file-level drawer — exactly the unresolvable-links case this
  # guard exists to prevent.
  id=$(awk '/^\*+ /{exit} /^:ID:/{print $2; exit}' "$src")
  if [[ -z "$id" ]]; then
    echo "ABORT: $src has no file-level :ID: — refusing to move a note whose links cannot resolve" >&2
    exit 1
  fi

  # Org accepts #+title: or #+TITLE: (any per-letter case). Checked here, in
  # the validation pass, so a note we cannot retitle never gets touched.
  has_title=$(awk '/^#\+[Tt][Ii][Tt][Ll][Ee]:/{print "1"; exit}' "$src")
  if [[ -z "$has_title" ]]; then
    echo "ABORT: $src has no #+title: line — refusing to move a note we can't retitle" >&2
    exit 1
  fi

  srcs+=("$src"); targets+=("$target"); names+=("$name"); ids+=("$id")
done

total=${#srcs[@]}

if [[ $DRY -eq 1 ]]; then
  for i in "${!srcs[@]}"; do
    echo "would move: ${srcs[$i]}"
    echo "        ->: ${targets[$i]}"
    echo "      title: #+title: ${names[$i]} (Work)   (id ${ids[$i]} preserved)"
  done
  echo "(dry run — nothing changed; would migrate $total)"
  exit 0
fi

# ---------------------------------------------------------------- pass 2 ----
# Mutate. The map is fully validated, so the only failures left are I/O.
migrated=0
fail() {
  echo "$1" >&2
  echo "migrated $migrated of $total — INCOMPLETE; re-running is safe" >&2
  exit 1
}

for i in "${!srcs[@]}"; do
  src=${srcs[$i]}; target=${targets[$i]}; name=${names[$i]}

  # mkdir stays inside the loop, after validation: creating Quarterly/ up front
  # would propagate an empty directory to every Syncthing peer on a run that
  # never moves anything.
  mkdir -p "$DEST" || fail "ABORT: cannot create $DEST"

  # Retitle first, THEN move. If the rewrite fails the note is still at its
  # original path and still matches the scan regex, so a re-run revisits it;
  # move-first would leave a correctly-named note with the old title that no
  # later run ever sees again. The substitution is idempotent — "#+title:
  # 2026-Q2 (Work)" re-matches and reproduces itself — so an interrupted run
  # leaves a fully re-runnable source.
  #
  # Only the first #+title:/#+TITLE: line is rewritten (case-insensitive
  # bracket pattern, same convention as the has_title detector above).
  sed -i "0,/^#+[Tt][Ii][Tt][Ll][Ee]:.*/s//#+title: $name (Work)/" "$src" \
    || fail "ABORT: title rewrite failed for $src"
  mv "$src" "$target" || fail "ABORT: mv failed: $src -> $target"
  migrated=$((migrated + 1))
  echo "moved: $name"
done

echo "migrated $migrated of $total"

if [[ -d "$LEGACY" ]]; then
  if [[ -z "$(ls -A "$LEGACY")" ]]; then
    rmdir "$LEGACY"
    echo "removed empty: $LEGACY"
  else
    echo "NOTE: $LEGACY still has files, leaving it in place:" >&2
    ls -A "$LEGACY" >&2
  fi
fi

echo "NEXT: restart Emacs (or M-x org-roam-db-sync) to re-index ID -> path,"
echo "      then verify C-u C-c q opens Quarterly/ and its links resolve."
