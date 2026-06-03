#!/usr/bin/env bash
# bootstrap.sh — fresh-clone entrypoint
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/bin/dot-bootstrap" "$@"
