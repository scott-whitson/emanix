#!/usr/bin/env bash
# install/13-docs-sync.sh — Syncthing docs vault sync
#
# Bakes the docs tree into the install flow:
# - runtime desktops use ~/docs as the synced vault root
# - datacore remains the canonical peer
# - zord can bootstrap the pairing automatically over SSH once datacore trust exists
set -euo pipefail
source "$(dirname "$0")/_common.sh"

HOST_NAME="${HOSTNAME%%.*}"
REMOTE_HOST="${DOCS_SYNC_REMOTE_HOST:-datacore}"
DOCS_FOLDER_ID="${DOCS_SYNC_FOLDER_ID:-docs}"
DOCS_FOLDER_PATH="${DOCS_SYNC_FOLDER_PATH:-$HOME/docs}"
ST_HOME="${XDG_STATE_HOME:-$HOME/.local/state}/syncthing"

json_myid() {
	python3 -c 'import json, sys; print(json.load(sys.stdin)["myID"])'
}

wait_for_syncthing() {
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		if syncthing cli show system >/dev/null 2>&1; then
			return 0
		fi
		sleep 1
	done
	return 1
}

ensure_syncthing_identity() {
	if [[ ! -f "$ST_HOME/cert.pem" ]] || [[ ! -f "$ST_HOME/key.pem" ]]; then
		log "initializing Syncthing identity in $ST_HOME"
		mkdir -p "$ST_HOME"
		syncthing generate --home "$ST_HOME" --skip-port-probing >/dev/null
	fi
}

ensure_local_service() {
	systemctl --user daemon-reload
	systemctl --user enable --now syncthing.service >/dev/null 2>&1 || true
	if ! wait_for_syncthing; then
		warn "Syncthing REST API not reachable yet; will continue and retry after restart"
	fi
}

syncthing_local_id() {
	syncthing cli show system | json_myid
}

syncthing_remote_id() {
	local host="$1"
	ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" 'syncthing cli show system | python3 -c "import json, sys; print(json.load(sys.stdin)[\"myID\"])"'
}

ensure_device() {
	local device_id="$1" device_name="$2"
	if ! syncthing cli config devices list | grep -qx "$device_id"; then
		log "adding Syncthing device $device_name"
		syncthing cli config devices add --device-id "$device_id" --name "$device_name" >/dev/null
	fi
}

ensure_folder() {
	if ! syncthing cli config folders list | grep -qx "$DOCS_FOLDER_ID"; then
		log "creating Syncthing docs folder at $DOCS_FOLDER_PATH"
		syncthing cli config folders add --id "$DOCS_FOLDER_ID" --label docs --path "$DOCS_FOLDER_PATH" --type sendreceive >/dev/null
	else
		syncthing cli config folders "$DOCS_FOLDER_ID" path set "$DOCS_FOLDER_PATH" >/dev/null 2>&1 || true
	fi
}

ensure_folder_device() {
	local device_id="$1"
	if ! syncthing cli config folders "$DOCS_FOLDER_ID" devices list | grep -qx "$device_id"; then
		syncthing cli config folders "$DOCS_FOLDER_ID" devices add --device-id "$device_id" >/dev/null
	fi
}

configure_remote_peer() {
	local local_id="$1"
	if [[ "$HOST_NAME" == "$REMOTE_HOST" ]]; then
		return 0
	fi
	if ! command -v ssh >/dev/null 2>&1; then
		warn "ssh missing; cannot auto-configure docs sync peer $REMOTE_HOST"
		return 0
	fi
	if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE_HOST" true >/dev/null 2>&1; then
		warn "cannot reach $REMOTE_HOST over SSH; skipping remote Syncthing config"
		return 0
	fi
	log "configuring Syncthing peer on $REMOTE_HOST"
	ssh -o BatchMode=yes "$REMOTE_HOST" "DOCS_SYNC_REMOTE_ID='$local_id' DOCS_SYNC_REMOTE_NAME='$HOST_NAME' DOCS_SYNC_FOLDER_ID='$DOCS_FOLDER_ID' DOCS_SYNC_FOLDER_PATH='$DOCS_FOLDER_PATH' bash -s" <<'REMOTE'
set -euo pipefail
if ! syncthing cli config devices list | grep -qx "$DOCS_SYNC_REMOTE_ID"; then
	syncthing cli config devices add --device-id "$DOCS_SYNC_REMOTE_ID" --name "$DOCS_SYNC_REMOTE_NAME" >/dev/null
fi
if ! syncthing cli config folders list | grep -qx "$DOCS_SYNC_FOLDER_ID"; then
	syncthing cli config folders add --id "$DOCS_SYNC_FOLDER_ID" --label docs --path "$DOCS_SYNC_FOLDER_PATH" --type sendreceive >/dev/null
else
	syncthing cli config folders "$DOCS_SYNC_FOLDER_ID" path set "$DOCS_SYNC_FOLDER_PATH" >/dev/null 2>&1 || true
fi
if ! syncthing cli config folders "$DOCS_SYNC_FOLDER_ID" devices list | grep -qx "$DOCS_SYNC_REMOTE_ID"; then
	syncthing cli config folders "$DOCS_SYNC_FOLDER_ID" devices add --device-id "$DOCS_SYNC_REMOTE_ID" >/dev/null
fi
systemctl --user restart syncthing.service >/dev/null 2>&1 || true
REMOTE
}

log "preparing Syncthing docs sync"

if ! command -v syncthing >/dev/null 2>&1; then
	warn "syncthing not installed; skipping docs sync (install via 01-core.sh or 05-desktop.sh)"
	exit 0
fi

mkdir -p "$DOCS_FOLDER_PATH" "$DOCS_FOLDER_PATH/vault"
ensure_syncthing_identity
ensure_local_service

local_id="$(syncthing_local_id)"
log "local Syncthing device id: $local_id"

ensure_device "$local_id" "$HOST_NAME"
ensure_folder
ensure_folder_device "$local_id"

if [[ "$HOST_NAME" != "$REMOTE_HOST" ]]; then
	remote_id="$(syncthing_remote_id "$REMOTE_HOST")"
	log "$REMOTE_HOST Syncthing device id: $remote_id"
	ensure_device "$remote_id" "$REMOTE_HOST"
	ensure_folder_device "$remote_id"
	configure_remote_peer "$local_id"
fi

systemctl --user restart syncthing.service >/dev/null 2>&1 || true
log "Syncthing docs sync ready at $DOCS_FOLDER_PATH"
