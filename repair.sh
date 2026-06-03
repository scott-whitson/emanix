#!/usr/bin/env bash
# repair.sh — fresh-clone entrypoint for rerunning install scripts
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/bin/dot-repair" "$@"
