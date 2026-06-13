"""Thin wrapper around the immich-go CLI for batch uploads."""
from __future__ import annotations

import subprocess
import urllib.error
import urllib.request
from pathlib import Path


class ImmichError(RuntimeError):
    pass


class ImmichClient:
    def __init__(self, url: str, api_key: str) -> None:
        self.url = url.rstrip("/")
        self.api_key = api_key

    def probe(self, timeout: int = 5) -> bool:
        """Return True iff Immich responds to /api/server/ping (200 {"res":"pong"})."""
        req = urllib.request.Request(f"{self.url}/api/server/ping", method="GET")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return 200 <= resp.status < 400
        except (urllib.error.URLError, ConnectionError, OSError, TimeoutError):
            return False

    def upload_directory(self, local_dir: Path) -> None:
        """Run immich-go upload <dir>. Re-uploads of known hashes are no-ops on the server."""
        cmd = [
            "immich-go", "upload",
            "--server", self.url,
            "--api-key", self.api_key,
            str(local_dir),
        ]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            stderr = (r.stderr or "").strip()
            if "401" in stderr or "unauthorized" in stderr.lower():
                raise ImmichError(
                    "Immich rejected the API key. Regenerate one in "
                    "Immich → Account Settings → API Keys, then update "
                    "~/.config/photo-import/secrets.toml. Underlying: " + stderr
                )
            raise ImmichError(f"immich-go exit {r.returncode}: {stderr}")
