#!/usr/bin/env bash
# install/12-ibgateway.sh — install IB Gateway (stable) + IBC into /opt.
#
# Idempotent: skips if either is already installed. Run with sudo available
# (script invokes `sudo` for /opt writes).
#
# Layout after this:
#   /opt/ibgateway/                       binary install (root-owned, world-readable)
#   /opt/ibc/                             IBC install
#   ~/.local/share/Jts/                   per-user state (sessions, jts.ini, hashes)
#   ~/.config/ibc/config.{live,paper}.ini per-user IBC config (creds, mode 600 — you fill in)

set -euo pipefail

# Allow standalone execution: set the env _common.sh requires when not invoked
# by install.sh (orchestrator). Falls through cleanly when env IS set.
export DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"

# This script must run as the user (sudo is invoked internally for /opt writes).
# Running the whole script with `sudo bash …` would put HOME=/root and write
# ~/.config/ibc to the wrong place.
if [[ $EUID -eq 0 ]]; then
	echo "Run as your user, not root. The script calls 'sudo' itself for /opt writes." >&2
	echo "Re-run:  bash $0" >&2
	exit 1
fi

source "$(dirname "$0")/_common.sh"

GW_ROOT="/opt/ibgateway"
IBC_ROOT="/opt/ibc"
GW_INSTALLER_URL="https://download2.interactivebrokers.com/installers/ibgateway/stable-standalone/ibgateway-stable-standalone-linux-x64.sh"
IBC_API_URL="https://api.github.com/repos/IbcAlpha/IBC/releases/latest"

# --- Debian deps for headless run ---
need_pkg xvfb unzip curl

# --- IB Gateway ---
if [[ -d "$GW_ROOT/ibgateway" ]] && compgen -G "$GW_ROOT/ibgateway/[0-9]*" >/dev/null; then
	log "IB Gateway already at $GW_ROOT (versions: $(ls "$GW_ROOT/ibgateway" | tr '\n' ' '))"
else
	log "downloading IB Gateway stable installer (~150 MB)"
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	curl -fL "$GW_INSTALLER_URL" -o "$tmp/install.sh"
	chmod +x "$tmp/install.sh"

	log "installing IB Gateway to $GW_ROOT (sudo required)"
	# install4j unattended: -q quiet, -dir installs to specified path, -overwrite for re-runs
	sudo "$tmp/install.sh" -q -overwrite -dir "$GW_ROOT"
	sudo chmod -R o+rX "$GW_ROOT"
fi

# --- IBC compat shim ---
# Modern "stable-standalone" installer puts files flat at $GW_ROOT, but IBC
# (3.23) hard-constructs $tws_path/ibgateway/$version/jars and has no flag to
# override. We can't build that path inside $GW_ROOT (file already named
# `ibgateway` — the launcher script). Solution: a separate shim dir whose
# only purpose is to bridge IBC's expectation to the flat install.
GW_SHIM="/opt/ibc-shim"
desktop=$(compgen -G "$GW_ROOT/IB Gateway *.desktop" 2>/dev/null | head -1 || true)
if [[ -n "$desktop" ]]; then
	gw_version=$(basename "$desktop" | grep -oE '[0-9]+\.[0-9]+' | tr -d '.')
	if [[ -n "$gw_version" ]]; then
		compat_link="$GW_SHIM/ibgateway/$gw_version"
		if [[ ! -L "$compat_link" ]] || [[ "$(readlink "$compat_link")" != "$GW_ROOT" ]]; then
			log "creating IBC compat shim: $compat_link -> $GW_ROOT"
			sudo mkdir -p "$GW_SHIM/ibgateway"
			sudo ln -sfn "$GW_ROOT" "$compat_link"
		fi
	fi
fi

# --- IBC ---
if [[ -x "$IBC_ROOT/scripts/ibcstart.sh" ]]; then
	log "IBC already at $IBC_ROOT"
else
	log "fetching latest IBC release URL from GitHub"
	ibc_url=$(curl -fsSL "$IBC_API_URL" |
		grep '"browser_download_url".*[Ll]inux.*\.zip"' |
		head -1 |
		sed -E 's/.*"(https[^"]+)".*/\1/')
	[[ -n "$ibc_url" ]] || die "could not parse IBC linux zip URL from $IBC_API_URL"
	log "downloading IBC: $ibc_url"

	tmp_ibc=$(mktemp -d)
	trap 'rm -rf "$tmp_ibc"' EXIT
	curl -fL "$ibc_url" -o "$tmp_ibc/ibc.zip"

	log "installing IBC to $IBC_ROOT (sudo required)"
	sudo mkdir -p "$IBC_ROOT"
	sudo unzip -o "$tmp_ibc/ibc.zip" -d "$IBC_ROOT" >/dev/null
	sudo find "$IBC_ROOT" -maxdepth 2 -name '*.sh' -exec chmod +x {} \;
	sudo chmod -R o+rX "$IBC_ROOT"
fi

# --- Per-user IBC config dir + templates (kept outside dotfiles since real .ini holds creds) ---
mkdir -p "$HOME/.config/ibc"
chmod 700 "$HOME/.config/ibc"

for mode in live paper; do
	template="$HOME/.config/ibc/config.${mode}.ini.template"
	[[ -f "$template" ]] && continue
	log "writing $(basename "$template")"
	port=$([[ "$mode" == live ]] && echo 4001 || echo 4002)
	cat >"$template" <<EOF
; IBC config — ${mode^^} mode (port $port)
; Copy to config.${mode}.ini, fill in credentials, then chmod 600.
;
;   cp config.${mode}.ini.template config.${mode}.ini
;   chmod 600 config.${mode}.ini
;   \$EDITOR config.${mode}.ini

IbLoginId=
IbPassword=

TradingMode=${mode}
FIX=no

; IBKR Mobile push 2FA — leave SecondFactorDevice blank → push to phone, you tap.
; Debian laptop policy: no auto-relogin, no auto-restart, no auto-logoff.
SecondFactorDevice=
ReloginAfterSecondFactorAuthenticationTimeout=no
ExitAfterSecondFactorAuthenticationTimeout=no
SecondFactorAuthenticationExitInterval=60

OverrideTwsApiPort=${port}
ReadOnlyApi=no
AcceptIncomingConnectionAction=accept
AcceptNonBrokerageAccountWarning=yes
AllowBlindTrading=no
DismissPasswordExpiryWarning=no
DismissNSEComplianceNotice=yes

; Keep all auto-restart fields blank.
AutoRestartTime=
ClosedownAt=
AutoLogoffTime=

LogComponents=never
EOF
done

log ""
log "Install complete."
log "Next steps (you):"
log "  1. cp ~/.config/ibc/config.paper.ini.template ~/.config/ibc/config.paper.ini"
log "  2. chmod 600 ~/.config/ibc/config.paper.ini && \$EDITOR ~/.config/ibc/config.paper.ini"
log "  3. (cd ~/dotfiles && stow -d base -t \"\$HOME\" --no-folding -R systemd ib)"
log "  4. rm -f ~/.config/systemd/user/ib-gateway@.service.bak  # (in case stow refused)"
log "  5. systemctl --user daemon-reload"
log "  6. ib up paper       # invisible Xvfb start; ~30s; check 'ib status'"
log "  7. once paper good: rm -rf ~/.local/share/Jts/ibgateway  # old binary tree"
log "  8. fill config.live.ini same way → ib up live  (manual login only; no auto-relogin)"
