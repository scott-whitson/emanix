#!/usr/bin/env bash
# install/11-services.sh — enable systemd user units stowed from base/systemd/
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# base/systemd/ stows to ~/.config/systemd/user/*.service + *.timer
UNIT_DIR="$HOME/.config/systemd/user"
HOST_NAME="${HOSTNAME%%.*}"

if [[ ! -d "$UNIT_DIR" ]]; then
	log "no user systemd unit directory ($UNIT_DIR); skipping"
	exit 0
fi

systemctl --user daemon-reload

for unit_file in "$UNIT_DIR"/*.timer "$UNIT_DIR"/*.service; do
	[[ -e "$unit_file" ]] || continue
	unit_name="$(basename "$unit_file")"
	if [[ "$unit_name" == *"@.service" ]]; then
		log "skipping template unit $unit_name"
		continue
	fi
	if [[ "$HOST_NAME" != "datacore" ]] && [[ "$unit_name" == ib-* || "$unit_name" == minne-ib-* ]]; then
		log "skipping $unit_name on $HOST_NAME (datacore-only)"
		continue
	fi
	log "enabling $unit_name"
	if output="$(systemctl --user enable --now "$unit_name" 2>&1)"; then
		printf '%s\n' "$output" | grep -v '^Created symlink' || true
	else
		printf '%s\n' "$output" >&2
		exit 1
	fi
done
