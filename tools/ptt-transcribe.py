#!/usr/bin/env python3
"""Transcribe a WAV file using VOSK and print the result."""
import json
import sys
import wave

from vosk import Model, KaldiRecognizer, SetLogLevel

SetLogLevel(-1)  # suppress vosk logs

def transcribe(model_path: str, wav_path: str) -> str:
    model = Model(model_path)
    wf = wave.open(wav_path, "rb")
    rec = KaldiRecognizer(model, wf.getframerate())
    rec.SetWords(False)

    while True:
        data = wf.readframes(4000)
        if len(data) == 0:
            break
        rec.AcceptWaveform(data)

    result = json.loads(rec.FinalResult())
    return result.get("text", "").strip()

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: ptt-transcribe.py <model_path> <wav_path>", file=sys.stderr)
        sys.exit(1)
    text = transcribe(sys.argv[1], sys.argv[2])
    if text:
        print(text)
