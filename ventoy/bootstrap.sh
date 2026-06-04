#!/usr/bin/env bash
# ventoy/bootstrap.sh — portable first-run installer for Debian machines
#
# Default flow:
#   1. Start datacore bootstrap session
#   2. User logs in on datacore and approves device
#   3. Script receives short-lived bootstrap token
#   4. Join Headscale
#   5. Fetch dotfiles bundle/archive from datacore
#   6. Run repo bootstrap ./bootstrap.sh
#
# Legacy escape hatch:
#   --legacy-login-server + --legacy-headscale-authkey
#   keeps old manual Headscale join for recovery only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${TARGET_DIR:-$HOME/dotfiles}"
LOCAL_SOURCE="${LOCAL_SOURCE:-$SCRIPT_DIR/dotfiles}"
DATACORE_URL="${DATACORE_URL:-}"
DEVICE_NAME="${DEVICE_NAME:-}"
ROLE="${ROLE:-}"
DEVICE_NAME_DEFAULT="$(hostname -s)"
ROLE_DEFAULT="desktop"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
NO_HEADSCALE=0
NO_BROWSER=0
FLOW_MODE="datacore"
LEGACY_LOGIN_SERVER="${LEGACY_LOGIN_SERVER:-}"
LEGACY_HEADSCALE_AUTHKEY="${LEGACY_HEADSCALE_AUTHKEY:-}"
SESSION_ID=""
DEVICE_CODE=""
VERIFY_URL=""
BOOTSTRAP_TOKEN=""
HEADSCALE_LOGIN_SERVER=""
DOTFILES_ARCHIVE_URL=""
DOTFILES_GIT_URL=""
DEVICE_ID=""
APPROVED_HOSTNAME=""
MACHINE_SSH_KEY_PATH="${MACHINE_SSH_KEY_PATH:-$HOME/.ssh/datacore_bootstrap_ed25519}"
DATACORE_SSH_KNOWN_HOSTS_FILE="${DATACORE_SSH_KNOWN_HOSTS_FILE:-$HOME/.ssh/datacore_known_hosts}"
MACHINE_SSH_PUBLIC_KEY=""
SSH_TRUST_BUNDLE=""

msg() { printf '\033[1;34m[ventoy]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ventoy]\033[0m %s\n' "$*" >&2; }
die() {
	printf '\033[1;31m[ventoy]\033[0m %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<EOF
Usage: $(basename "$0") [options]

Default datacore enrollment flow:
  --datacore-url URL    Datacore bootstrap portal base URL
  --device-name NAME    Device name to enroll (default: current hostname)
  --role ROLE          Device role/profile (default: desktop)
  --target DIR         Install dotfiles into DIR (default: ~/dotfiles)
  --source DIR         Local USB dotfiles mirror (default: $SCRIPT_DIR/dotfiles)
  --no-browser         Do not try to open verification URL automatically
  --no-headscale       Skip Headscale join step after enrollment

Legacy rescue flow:
  --legacy-login-server URL
  --legacy-headscale-authkey KEY

Other:
  -h, --help           Show help
EOF
}

prompt_default() {
	local prompt="$1"
	local default="$2"
	local value=""
	read -rp "$prompt [$default]: " value
	printf '%s' "${value:-$default}"
}

json_get() {
	local path="$1"
	python3 -c 'import json, sys
path = sys.argv[1].split(".")
obj = json.load(sys.stdin)
for key in path:
    if isinstance(obj, dict) and key in obj:
        obj = obj[key]
    else:
        raise SystemExit(2)
if obj is None:
    print("")
elif isinstance(obj, bool):
    print("true" if obj else "false")
else:
    print(obj)' "$path"
}

json_get_optional() {
	local path="$1"
	python3 -c 'import json, sys
path = sys.argv[1].split(".")
obj = json.load(sys.stdin)
for key in path:
    if isinstance(obj, dict) and key in obj:
        obj = obj[key]
    else:
        raise SystemExit(3)
if obj is None:
    print("")
elif isinstance(obj, bool):
    print("true" if obj else "false")
else:
    print(obj)' "$path"
}

build_json_payload() {
	python3 - "$DEVICE_NAME" "$ROLE" "$MACHINE_SSH_PUBLIC_KEY" <<'PY'
import json
import sys

device_name, role, machine_ssh_public_key = sys.argv[1:4]
payload = {
    'device_name': device_name,
    'hostname': device_name,
    'role': role,
    'client': 'ventoy-bootstrap',
}
if machine_ssh_public_key:
    payload['machine_ssh_public_key'] = machine_ssh_public_key
print(json.dumps(payload))
PY
}

build_completion_payload() {
	python3 - "$BOOTSTRAP_TOKEN" "$DEVICE_NAME" "$ROLE" "$DEVICE_ID" "$APPROVED_HOSTNAME" <<'PY'
import json
import sys

token, device_name, role, device_id, hostname = sys.argv[1:6]
payload = {
    'status': 'ok',
    'bootstrap_token': token,
    'device_name': device_name,
    'role': role,
    'hostname': hostname,
}
if device_id:
    payload['device_id'] = device_id
print(json.dumps(payload))
PY
}

have() {
	command -v "$1" >/dev/null 2>&1
}

ensure_packages() {
	local missing=()
	for bin in curl python3 ssh-keygen; do
		have "$bin" || missing+=("$bin")
	done
	if [[ ${#missing[@]} -eq 0 ]]; then
		return 0
	fi
	if ! have apt; then
		die "missing tools: ${missing[*]} and apt unavailable"
	fi
	msg "installing missing tools: ${missing[*]}"
	sudo apt update
	sudo apt install -y curl python3 openssh-client ca-certificates
}

ensure_git() {
	have git && return 0
	if ! have apt; then
		die "git missing and apt unavailable"
	fi
	msg "git missing; installing via apt"
	sudo apt update
	sudo apt install -y git openssh-client
}

ensure_tailscale() {
	have tailscale && return 0
	if ! have apt; then
		die "tailscale missing and apt unavailable"
	fi
	msg "tailscale missing; installing via apt"
	sudo apt update
	sudo apt install -y tailscale
}

ensure_machine_ssh_keypair() {
	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"
	if [[ -f "$MACHINE_SSH_KEY_PATH" && -f "$MACHINE_SSH_KEY_PATH.pub" ]]; then
		MACHINE_SSH_PUBLIC_KEY="$(cat "$MACHINE_SSH_KEY_PATH.pub")"
		return 0
	fi
	msg "generating machine SSH keypair for datacore trust"
	ssh-keygen -q -t ed25519 -N '' -f "$MACHINE_SSH_KEY_PATH" -C "$DEVICE_NAME@$APPROVED_HOSTNAME" >/dev/null
	chmod 600 "$MACHINE_SSH_KEY_PATH"
	chmod 644 "$MACHINE_SSH_KEY_PATH.pub"
	MACHINE_SSH_PUBLIC_KEY="$(cat "$MACHINE_SSH_KEY_PATH.pub")"
}

api_post() {
	local path="$1"
	local body="$2"
	curl --fail --silent --show-error --location \
		--retry 3 --retry-delay 2 \
		-X POST "$DATACORE_URL$path" \
		-H 'Content-Type: application/json' \
		-d "$body"
}

api_get() {
	local path="$1"
	curl --fail --silent --show-error --location \
		--retry 3 --retry-delay 2 \
		"$DATACORE_URL$path"
}

api_get_with_status() {
	local path="$1"
	local body_file headers_file code body
	body_file="$(mktemp)"
	headers_file="$(mktemp)"
	code="$(curl --silent --show-error --location \
		--retry 3 --retry-delay 2 \
		-D "$headers_file" -o "$body_file" \
		-w '%{http_code}' \
		"$DATACORE_URL$path")" || {
		rm -f "$body_file" "$headers_file"
		return 1
	}
	body="$(cat "$body_file")"
	rm -f "$body_file" "$headers_file"
	printf '%s\n%s' "$code" "$body"
}

open_browser() {
	local url="$1"
	[[ "$NO_BROWSER" -eq 0 ]] || return 1
	for opener in xdg-open gio sensible-browser firefox; do
		if have "$opener"; then
			case "$opener" in
			gio)
				gio open "$url" >/dev/null 2>&1 && return 0
				;;
			firefox)
				"$opener" "$url" >/dev/null 2>&1 && return 0
				;;
			*)
				"$opener" "$url" >/dev/null 2>&1 && return 0
				;;
			esac
		fi
	done
	return 1
}

trim_url() {
	local raw="$1"
	printf '%s' "$raw" | sed 's:/*$::'
}

prompt_datacore_url() {
	if [[ -n "$DATACORE_URL" ]]; then
		DATACORE_URL="$(trim_url "$DATACORE_URL")"
		return 0
	fi
	DATACORE_URL="$(prompt_default 'Datacore bootstrap URL' 'https://datacore')"
	DATACORE_URL="$(trim_url "$DATACORE_URL")"
}

prompt_device_fields() {
	if [[ -z "$DEVICE_NAME" ]]; then
		DEVICE_NAME="$(prompt_default 'Device name' "$DEVICE_NAME_DEFAULT")"
	fi
	if [[ -z "$ROLE" ]]; then
		ROLE="$(prompt_default 'Device role' "$ROLE_DEFAULT")"
	fi
	APPROVED_HOSTNAME="$DEVICE_NAME"
}

print_enrollment_instructions() {
	msg "Verification URL: ${VERIFY_URL:-${DATACORE_URL}/bootstrap/${SESSION_ID}}"
	if [[ -n "$DEVICE_CODE" ]]; then
		msg "Device code: $DEVICE_CODE"
	fi
	msg "Open URL, sign in, approve device, then return here"
	if [[ "$NO_BROWSER" -eq 0 ]]; then
		open_browser "${VERIFY_URL:-${DATACORE_URL}/bootstrap/${SESSION_ID}}" ||
			warn "No browser opener available; open URL manually"
	fi
}

start_bootstrap_session() {
	local response
	response="$(api_post '/api/bootstrap/sessions' "$(build_json_payload)")"
	SESSION_ID="$(printf '%s' "$response" | json_get session_id)"
	VERIFY_URL="$(printf '%s' "$response" | json_get_optional verification_url || true)"
	DEVICE_CODE="$(printf '%s' "$response" | json_get_optional device_code || true)"
	POLL_INTERVAL="$(printf '%s' "$response" | json_get_optional poll_interval_seconds || true)"
	if [[ -z "$VERIFY_URL" ]]; then
		VERIFY_URL="$DATACORE_URL/bootstrap/$SESSION_ID"
	fi
	if [[ -z "$POLL_INTERVAL" ]]; then
		POLL_INTERVAL=5
	fi
}

wait_for_bootstrap_approval() {
	local response status body state
	while true; do
		response="$(api_get_with_status "/api/bootstrap/sessions/$SESSION_ID")"
		status="${response%%$'\n'*}"
		body="${response#*$'\n'}"
		case "$status" in
		200)
			state="$(printf '%s' "$body" | json_get state)"
			case "$state" in
			pending | waiting)
				sleep "$POLL_INTERVAL"
				;;
			approved)
				BOOTSTRAP_TOKEN="$(printf '%s' "$body" | json_get bootstrap_token)"
				HEADSCALE_LOGIN_SERVER="$(printf '%s' "$body" | json_get_optional headscale_login_server || true)"
				DOTFILES_ARCHIVE_URL="$(printf '%s' "$body" | json_get_optional dotfiles_archive_url || true)"
				DOTFILES_GIT_URL="$(printf '%s' "$body" | json_get_optional dotfiles_git_url || true)"
				DEVICE_ID="$(printf '%s' "$body" | json_get_optional device_id || true)"
				SSH_TRUST_BUNDLE="$body"
				APPROVED_HOSTNAME="$(printf '%s' "$body" | json_get_optional hostname || true)"
				APPROVED_HOSTNAME="${APPROVED_HOSTNAME:-$DEVICE_NAME}"
				[[ -n "$BOOTSTRAP_TOKEN" ]] || die "datacore approved session but no bootstrap token"
				return 0
				;;
			denied | expired | rejected)
				die "datacore bootstrap session $state"
				;;
			*)
				warn "unexpected session state: $state"
				sleep "$POLL_INTERVAL"
				;;
			esac
			;;
		410)
			die "datacore bootstrap session expired"
			;;
		404)
			die "datacore bootstrap session missing"
			;;
		*)
			warn "unexpected HTTP status from datacore: $status"
			sleep "$POLL_INTERVAL"
			;;
		esac
	done
}

install_ssh_trust_bundle() {
	[[ -n "$SSH_TRUST_BUNDLE" ]] || return 0
	local ssh_user known_hosts ssh_config_snippet ssh_config_block datacore_host default_snippet
	ssh_user="$(printf '%s' "$SSH_TRUST_BUNDLE" | json_get_optional ssh_trust_bundle.ssh_user || true)"
	known_hosts="$(printf '%s' "$SSH_TRUST_BUNDLE" | json_get_optional ssh_trust_bundle.known_hosts || true)"
	ssh_config_snippet="$(printf '%s' "$SSH_TRUST_BUNDLE" | json_get_optional ssh_trust_bundle.ssh_config_snippet || true)"
	if [[ -n "$known_hosts" ]]; then
		mkdir -p "$HOME/.ssh"
		chmod 700 "$HOME/.ssh"
		printf '%s\n' "$known_hosts" >"$DATACORE_SSH_KNOWN_HOSTS_FILE"
		chmod 600 "$DATACORE_SSH_KNOWN_HOSTS_FILE"
		msg "installed datacore known_hosts trust"
	fi
	if [[ -z "$ssh_config_snippet" && -n "$ssh_user" ]]; then
		datacore_host="$(python3 -c 'from urllib.parse import urlparse; import sys
url = sys.argv[1]
parsed = urlparse(url)
print(parsed.hostname or url)' "$DATACORE_URL")"
		default_snippet=$(
			cat <<EOF
Host datacore
  HostName $datacore_host
  User $ssh_user
  IdentityFile $MACHINE_SSH_KEY_PATH
  UserKnownHostsFile $DATACORE_SSH_KNOWN_HOSTS_FILE
  IdentitiesOnly yes
  HostKeyAlias datacore
EOF
		)
		ssh_config_snippet="$default_snippet"
	fi
	if [[ -n "$ssh_config_snippet" ]]; then
		mkdir -p "$HOME/.ssh"
		chmod 700 "$HOME/.ssh"
		ssh_config_block="$HOME/.ssh/config"
		if ! grep -qF '# BEGIN datacore bootstrap' "$ssh_config_block" 2>/dev/null; then
			printf '%s\n%s\n%s\n' '# BEGIN datacore bootstrap' "$ssh_config_snippet" '# END datacore bootstrap' >>"$ssh_config_block"
		else
			warn "datacore SSH config block already present"
		fi
		chmod 600 "$ssh_config_block"
		msg "installed datacore SSH config"
	fi
	if [[ -z "$known_hosts" && -z "$ssh_config_snippet" && -n "$ssh_user" ]]; then
		warn "datacore approved session returned ssh user but no trust material"
	fi
}

set_hostname() {
	local desired="$1"
	local current
	current="$(hostname -s 2>/dev/null || true)"
	[[ "$current" == "$desired" ]] && return 0
	if have hostnamectl; then
		sudo hostnamectl set-hostname "$desired"
	else
		warn "hostnamectl missing; leaving system hostname unchanged"
	fi
}

join_headscale_datacore() {
	[[ "$NO_HEADSCALE" -eq 0 ]] || {
		warn "Skipping Headscale join (--no-headscale)"
		return 0
	}
	[[ -n "$HEADSCALE_LOGIN_SERVER" ]] || die "datacore session did not return headscale_login_server"
	[[ -n "$BOOTSTRAP_TOKEN" ]] || die "bootstrap token missing"
	ensure_tailscale
	msg "Joining Headscale as $APPROVED_HOSTNAME"
	sudo tailscale up --reset \
		--login-server="$HEADSCALE_LOGIN_SERVER" \
		--authkey="$BOOTSTRAP_TOKEN" \
		--hostname="$APPROVED_HOSTNAME"
}

join_headscale_legacy() {
	[[ "$NO_HEADSCALE" -eq 0 ]] || {
		warn "Skipping Headscale join (--no-headscale)"
		return 0
	}
	if [[ -z "$LEGACY_LOGIN_SERVER" ]]; then
		LEGACY_LOGIN_SERVER="$(prompt_default 'Headscale login server URL' 'https://headscale')"
	fi
	if [[ -z "$LEGACY_HEADSCALE_AUTHKEY" ]]; then
		read -rsp 'Headscale auth key: ' LEGACY_HEADSCALE_AUTHKEY
		echo
	fi
	[[ -n "$LEGACY_LOGIN_SERVER" ]] || die "Headscale login server required"
	[[ -n "$LEGACY_HEADSCALE_AUTHKEY" ]] || die "Headscale auth key required"
	ensure_tailscale
	set_hostname "$APPROVED_HOSTNAME"
	msg "Joining Headscale as $APPROVED_HOSTNAME (legacy fallback)"
	sudo tailscale up --reset \
		--login-server="$LEGACY_LOGIN_SERVER" \
		--authkey="$LEGACY_HEADSCALE_AUTHKEY" \
		--hostname="$APPROVED_HOSTNAME"
}

prepare_target_dir() {
	if [[ -d "$TARGET_DIR/.git" ]]; then
		msg "dotfiles already present at $TARGET_DIR"
		return 1
	fi
	if [[ -e "$TARGET_DIR" ]]; then
		local backup="$TARGET_DIR.pre-ventoy.$(date +%Y%m%d%H%M%S)"
		warn "existing $TARGET_DIR is not a git repo; moving aside to $(basename "$backup")"
		mv "$TARGET_DIR" "$backup"
	fi
	mkdir -p "$(dirname "$TARGET_DIR")"
	return 0
}

extract_archive_tree() {
	local url="$1"
	local archive="$2"
	local dest="$3"
	case "$url" in
	*.zip)
		if python3 -m zipfile -e "$archive" "$dest"; then
			return 0
		fi
		return 1
		;;
	*.tar.gz | *.tgz)
		if tar -xzf "$archive" -C "$dest"; then
			return 0
		fi
		return 1
		;;
	*.tar)
		if tar -xf "$archive" -C "$dest"; then
			return 0
		fi
		return 1
		;;
	*)
		if python3 -m zipfile -e "$archive" "$dest"; then
			return 0
		fi
		if tar -xzf "$archive" -C "$dest" 2>/dev/null; then
			return 0
		fi
		if tar -xf "$archive" -C "$dest" 2>/dev/null; then
			return 0
		fi
		return 1
		;;
	esac
}

acquire_from_archive() {
	local url="$1"
	local tmpdir archive extract_root single_entry
	tmpdir="$(mktemp -d)"
	archive="$tmpdir/dotfiles-archive"
	extract_root="$tmpdir/extract"
	mkdir -p "$extract_root"
	msg "Downloading dotfiles archive from datacore"
	if ! curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
		"$url" -o "$archive"; then
		rm -rf "$tmpdir"
		return 1
	fi
	if ! extract_archive_tree "$url" "$archive" "$extract_root"; then
		rm -rf "$tmpdir"
		return 1
	fi

	rm -rf "$TARGET_DIR"
	mkdir -p "$TARGET_DIR"
	if [[ -x "$extract_root/bootstrap.sh" ]]; then
		cp -a "$extract_root"/. "$TARGET_DIR"/
	elif [[ "$(find "$extract_root" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" -eq 1 ]]; then
		single_entry="$(find "$extract_root" -mindepth 1 -maxdepth 1 -print -quit)"
		if [[ -d "$single_entry" && -x "$single_entry/bootstrap.sh" ]]; then
			cp -a "$single_entry"/. "$TARGET_DIR"/
		else
			rm -rf "$tmpdir"
			return 1
		fi
	else
		rm -rf "$tmpdir"
		return 1
	fi
	rm -rf "$tmpdir"
	return 0
}

acquire_from_git() {
	local url="$1"
	ensure_git
	msg "Cloning dotfiles from datacore"
	if git clone "$url" "$TARGET_DIR"; then
		return 0
	fi
	return 1
}

acquire_from_local_mirror() {
	[[ -d "$LOCAL_SOURCE" && -f "$LOCAL_SOURCE/bootstrap.sh" ]] || return 1
	msg "Copying dotfiles from USB mirror at $LOCAL_SOURCE"
	rm -rf "$TARGET_DIR"
	mkdir -p "$TARGET_DIR"
	cp -a "$LOCAL_SOURCE"/. "$TARGET_DIR"/
}

acquire_dotfiles() {
	if [[ -d "$TARGET_DIR/.git" ]]; then
		return 0
	fi

	prepare_target_dir

	if [[ -n "$DOTFILES_ARCHIVE_URL" ]]; then
		if acquire_from_archive "$DOTFILES_ARCHIVE_URL"; then
			return 0
		fi
		warn "datacore archive fetch failed; trying other datacore source"
	fi

	if [[ -n "$DOTFILES_GIT_URL" ]]; then
		if acquire_from_git "$DOTFILES_GIT_URL"; then
			return 0
		fi
		warn "datacore git fetch failed; trying USB mirror"
	fi

	if acquire_from_local_mirror; then
		return 0
	fi

	die "could not acquire dotfiles from datacore or USB mirror"
}

run_dotfiles_bootstrap() {
	[[ -f "$TARGET_DIR/bootstrap.sh" ]] || die "bootstrap.sh missing in $TARGET_DIR"
	chmod +x "$TARGET_DIR/bootstrap.sh"
	msg "Bootstrapping dotfiles in $TARGET_DIR"
	cd "$TARGET_DIR"
	./bootstrap.sh
}

complete_bootstrap_session() {
	[[ -n "$SESSION_ID" ]] || return 0
	local response
	response="$(api_post "/api/bootstrap/sessions/$SESSION_ID/complete" "$(build_completion_payload)")" || {
		warn "datacore completion callback failed"
		return 0
	}
	if [[ -n "$response" ]]; then
		msg "datacore completion acknowledged"
	fi
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--datacore-url)
		DATACORE_URL="$2"
		shift 2
		;;
	--device-name)
		DEVICE_NAME="$2"
		shift 2
		;;
	--role)
		ROLE="$2"
		shift 2
		;;
	--target)
		TARGET_DIR="$2"
		shift 2
		;;
	--source)
		LOCAL_SOURCE="$2"
		shift 2
		;;
	--no-browser)
		NO_BROWSER=1
		shift
		;;
	--no-headscale)
		NO_HEADSCALE=1
		shift
		;;
	--legacy-login-server)
		LEGACY_LOGIN_SERVER="$2"
		FLOW_MODE="legacy"
		shift 2
		;;
	--legacy-headscale-authkey)
		LEGACY_HEADSCALE_AUTHKEY="$2"
		FLOW_MODE="legacy"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		die "unknown arg: $1"
		;;
	esac
done

msg "Ventoy bootstrap starting"
ensure_packages

if [[ "$FLOW_MODE" == "legacy" ]]; then
	prompt_device_fields
	APPROVED_HOSTNAME="$DEVICE_NAME"
	join_headscale_legacy
	acquire_dotfiles
	run_dotfiles_bootstrap
	msg "Ventoy bootstrap complete (legacy mode)"
	exit 0
fi

prompt_datacore_url
prompt_device_fields
ensure_machine_ssh_keypair
start_bootstrap_session
print_enrollment_instructions
wait_for_bootstrap_approval
install_ssh_trust_bundle
set_hostname "$APPROVED_HOSTNAME"
join_headscale_datacore
acquire_dotfiles
run_dotfiles_bootstrap
complete_bootstrap_session
msg "Ventoy bootstrap complete"
