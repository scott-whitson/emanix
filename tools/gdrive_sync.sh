#!/bin/bash
# Bidirectional sync between local ~/gdrive and Google Drive
# Runs via cron every 15 minutes

LOCKFILE="/tmp/gdrive_sync.lock"
LOGFILE="$HOME/.local/log/gdrive_sync.log"

mkdir -p "$(dirname "$LOGFILE")"

# Prevent overlapping runs
if [ -f "$LOCKFILE" ]; then
    pid=$(cat "$LOCKFILE")
    if kill -0 "$pid" 2>/dev/null; then
        echo "$(date -Iseconds) Sync already running (PID $pid), skipping" >> "$LOGFILE"
        exit 0
    fi
    rm -f "$LOCKFILE"
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

echo "$(date -Iseconds) Starting bisync" >> "$LOGFILE"
rclone bisync ~/gdrive gdrive: \
    --transfers 4 \
    --checkers 8 \
    --tpslimit 8 \
    --exclude "lost+found/**" \
    --exclude ".Trash-*/**" \
    --exclude ".git/**" \
    --exclude "node_modules/**" \
    --exclude ".venv/**" \
    --exclude "__pycache__/**" \
    --drive-skip-gdocs \
    2>&1 | tail -5 >> "$LOGFILE"

EXIT_CODE=${PIPESTATUS[0]}
echo "$(date -Iseconds) Bisync finished (exit $EXIT_CODE)" >> "$LOGFILE"
