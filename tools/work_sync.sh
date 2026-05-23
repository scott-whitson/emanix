#!/usr/bin/env bash
set -euo pipefail

# work_sync — pull ~/projects/ from the work laptop into ~/projects/work/.
# Usage: work_sync [--dry-run]
#
# Work laptop is source of truth; this is a one-way mirror. Local changes
# under ~/projects/work/ will be overwritten or deleted to match the remote.

REMOTE="${WORK_SYNC_REMOTE:-swhitson-11l}"
SRC="${REMOTE}:projects/"
DEST="$HOME/projects/work/"

DRY_RUN=()
if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
    DRY_RUN=(--dry-run)
    echo "[work_sync] DRY RUN — no changes will be made"
fi

mkdir -p "$DEST"

# Exclude the clients/ directory and common dev/temp dirs.
rsync -avh --delete "${DRY_RUN[@]}" \
    --exclude='clients/' \
    --exclude='.venv/' \
    --exclude='venv/' \
    --exclude='node_modules/' \
    --exclude='__pycache__/' \
    --exclude='.pytest_cache/' \
    --exclude='.ruff_cache/' \
    --exclude='.mypy_cache/' \
    --exclude='.next/' \
    --exclude='.nuxt/' \
    --exclude='dist/' \
    --exclude='build/' \
    --exclude='target/' \
    --exclude='.cache/' \
    --exclude='*.pyc' \
    --exclude='.DS_Store' \
    "$SRC" "$DEST"

echo "[work_sync] Done. Synced ${SRC} -> ${DEST}"
