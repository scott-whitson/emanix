#!/usr/bin/env bash
# install/11-services.sh — enable systemd user units stowed from base/systemd/
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# base/systemd/ stows to ~/.config/systemd/user/*.service + *.timer
UNIT_DIR="$HOME/.config/systemd/user"

if [[ ! -d "$UNIT_DIR" ]]; then
    log "no user systemd unit directory ($UNIT_DIR); skipping"
    exit 0
fi

systemctl --user daemon-reload

for unit_file in "$UNIT_DIR"/*.timer "$UNIT_DIR"/*.service; do
    [[ -e "$unit_file" ]] || continue
    unit_name="$(basename "$unit_file")"
    log "enabling $unit_name"
    systemctl --user enable --now "$unit_name" 2>&1 | grep -v '^Created symlink' || true
done
