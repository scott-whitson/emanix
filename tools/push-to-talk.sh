#!/usr/bin/env bash
# Push-to-talk voice transcription for Sway/Wayland
# Usage: push-to-talk.sh toggle  (toggle recording on/off)

set -euo pipefail

PIDFILE="/tmp/ptt-recording.pid"
WAVFILE="/tmp/ptt-recording.wav"
PYTHON="$HOME/.local/pipx/venvs/vosk/bin/python"
MODEL="$HOME/tools/vosk-models/vosk-model-small-en-us-0.15"
TRANSCRIBE_SCRIPT="$HOME/tools/ptt-transcribe.py"

notify() {
    # Dismiss previous PTT notifications, then show new one
    makoctl dismiss -g "Push-to-Talk" 2>/dev/null || true
    notify-send -t "${2:-2000}" -a "Push-to-Talk" "PTT" "$1" 2>/dev/null || true
}

start_recording() {
    rm -f "$WAVFILE"

    # Record from default ALSA capture device, 16kHz mono (what VOSK expects)
    arecord -f S16_LE -r 16000 -c 1 -t wav "$WAVFILE" &
    echo $! > "$PIDFILE"

    notify "Recording..." 10000
}

stop_recording() {
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"

    sleep 0.1

    if [[ ! -f "$WAVFILE" ]] || [[ ! -s "$WAVFILE" ]]; then
        notify "No audio captured" 1500
        exit 0
    fi

    notify "Transcribing..." 5000

    TEXT=$("$PYTHON" "$TRANSCRIBE_SCRIPT" "$MODEL" "$WAVFILE" 2>/dev/null)

    if [[ -n "$TEXT" ]]; then
        if command -v wtype &>/dev/null; then
            wtype -- "$TEXT"
        else
            echo -n "$TEXT" | wl-copy
            notify "Copied to clipboard (install wtype for auto-type)" 3000
        fi
    else
        notify "No speech detected" 1500
    fi

    rm -f "$WAVFILE"
}

toggle() {
    if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        stop_recording
    else
        # Clean up stale pidfile if process is dead
        rm -f "$PIDFILE"
        start_recording
    fi
}

case "${1:-}" in
    toggle) toggle ;;
    start)  start_recording ;;
    stop)   stop_recording ;;
    *)      echo "Usage: $0 {toggle|start|stop}" >&2; exit 1 ;;
esac
