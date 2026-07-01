#!/usr/bin/env bash
# install/11-services.sh — enable systemd user units stowed from base/systemd/
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# base/systemd/ stows to ~/.config/systemd/user/*.service + *.timer
UNIT_DIR="$HOME/.config/systemd/user"

# Deploy drop-in overrides for package-provided units (syncthing, hyprpolkitagent)
# These live in base/systemd/.config/systemd/user/<unit>.d/ and are not stowed
# because the base unit comes from a package, not from dotfiles.
install_unit_overrides() {
	local src_dir="$DOTFILES/base/systemd/.config/systemd/user"
	for unit_d in "$src_dir"/*.service.d; do
		[[ -d "$unit_d" ]] || continue
		local unit_name="$(basename "${unit_d%.d}")"
		local dest="$UNIT_DIR/$unit_name.d"
		mkdir -p "$dest"
		for f in "$unit_d"/*; do
			[[ -f "$f" ]] || continue
			local fname="$(basename "$f")"
			if [[ -f "$dest/$fname" ]] && diff -q "$f" "$dest/$fname" >/dev/null 2>&1; then
				continue
			fi
			log "installing override: $unit_name.d/$fname"
			cp "$f" "$dest/$fname"
		done
	done
}
skip_service() {
	local unit="$1"
	for prefix in ${PROFILE_SERVICE_SKIP_PREFIXES:-}; do
		[[ "$unit" == "$prefix"* ]] && return 0
	done
	return 1
}

if [[ ! -d "$UNIT_DIR" ]]; then
	log "no user systemd unit directory ($UNIT_DIR); skipping"
	exit 0
fi

# Deploy drop-in overrides for package-provided units and wireplumber config
install_unit_overrides

# Deploy wireplumber monitor/property overrides from base/wireplumber/
install_wireplumber_config() {
	local src="$DOTFILES/base/wireplumber/.config/wireplumber"
	local dest="$HOME/.config/wireplumber"
	[[ -d "$src" ]] || return 0
	for wp_d in "$src"/*; do
		[[ -d "$wp_d" ]] || continue
		local wp_name="$(basename "$wp_d")"
		mkdir -p "$dest/$wp_name"
		for f in "$wp_d"/*; do
			[[ -f "$f" ]] || continue
			local fname="$(basename "$f")"
			if [[ -f "$dest/$wp_name/$fname" ]] && diff -q "$f" "$dest/$wp_name/$fname" >/dev/null 2>&1; then
				continue
			fi
			log "installing wireplumber config: $wp_name/$fname"
			cp "$f" "$dest/$wp_name/$fname"
		done
	done
}
install_wireplumber_config
systemctl --user daemon-reload

if systemctl --user list-unit-files syncthing.service >/dev/null 2>&1; then
	log "enabling syncthing.service"
	if output="$(systemctl --user enable --now syncthing.service 2>&1)"; then
		printf '%s\n' "$output" | grep -v '^Created symlink' || true
	else
		printf '%s\n' "$output" >&2
		exit 1
	fi
fi

for unit_file in "$UNIT_DIR"/*.timer "$UNIT_DIR"/*.service; do
	[[ -e "$unit_file" ]] || continue
	unit_name="$(basename "$unit_file")"
	if [[ "$unit_name" == *"@.service" ]]; then
		log "skipping template unit $unit_name"
		continue
	fi
	# A .service with no [Install] section is triggered by its .timer/.socket,
	# not enabled directly — `systemctl enable` errors on it. Skip; the paired
	# .timer (enabled above) pulls it in. (e.g. dot-sync.service, minne-ib-restart.service)
	if [[ "$unit_name" == *.service ]] && ! grep -q '^\[Install\]' "$unit_file"; then
		log "skipping $unit_name (timer-triggered, no [Install])"
		continue
	fi
	if skip_service "$unit_name"; then
		log "skipping $unit_name per profile"
		continue
	fi
	log "enabling $unit_name"
	if [[ "$unit_name" == fragpaper.service ]]; then
		if output="$(systemctl --user enable "$unit_name" 2>&1)"; then
			printf '%s\n' "$output" | grep -v '^Created symlink' || true
			log "deferring $unit_name start to Hyprland session autostart"
		else
			printf '%s\n' "$output" >&2
			exit 1
		fi
		continue
	fi
	if output="$(systemctl --user enable --now "$unit_name" 2>&1)"; then
		printf '%s\n' "$output" | grep -v '^Created symlink' || true
	else
		printf '%s\n' "$output" >&2
		exit 1
	fi
done
