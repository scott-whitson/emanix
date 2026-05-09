"""Thin wrappers around ssh/rsync to keep subprocess concerns isolated and mockable."""
from __future__ import annotations

import shlex
import subprocess
from pathlib import Path


class TransportError(RuntimeError):
    pass


_SSH_OPTS = (
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=8",
    "-o", "StrictHostKeyChecking=accept-new",
)


class Transport:
    def __init__(self, ssh_target: str) -> None:
        self.ssh_target = ssh_target

    def ssh_probe(self, timeout: int = 10) -> bool:
        """Return True iff ssh to ssh_target succeeds with a no-op command."""
        cmd = ["ssh", *_SSH_OPTS, self.ssh_target, "true"]
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            return False
        return r.returncode == 0

    def remote_mkdir(self, remote_path: str) -> None:
        # Force single-quoting so the remote shell receives the path safely
        quoted = "'" + remote_path.replace("'", "'\\''") + "'"
        cmd = ["ssh", *_SSH_OPTS, self.ssh_target, f"mkdir -p {quoted}"]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            raise TransportError(f"remote mkdir failed: {r.stderr.strip()}")

    def rsync_push(self, local_dir: Path, remote_dir: str) -> None:
        """Push the contents of local_dir/ to ssh_target:remote_dir/. Idempotent."""
        # Trailing slashes matter: src/ → contents go INTO remote_dir/
        cmd = [
            "rsync",
            "-av",
            "--partial",
            "--append-verify",
            "-e", " ".join(["ssh", *_SSH_OPTS]),
            f"{local_dir}/",
            f"{self.ssh_target}:{remote_dir}/",
        ]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            raise TransportError(f"rsync exit {r.returncode}: {r.stderr.strip()}")

    def remote_sha256(self, remote_dir: str) -> dict[str, str]:
        """Return {filename: sha256} for every regular file directly in remote_dir."""
        cmd = [
            "ssh", *_SSH_OPTS, self.ssh_target,
            f"cd {shlex.quote(remote_dir)} && find . -maxdepth 1 -type f -print0 "
            f"| xargs -0 sha256sum",
        ]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            raise TransportError(f"remote sha256 failed: {r.stderr.strip()}")
        result: dict[str, str] = {}
        for line in r.stdout.splitlines():
            parts = line.strip().split(None, 1)
            if len(parts) != 2:
                continue
            digest, path = parts
            name = Path(path).name
            result[name] = digest
        return result

    def remote_walk(self, remote_dir: str) -> list[str]:
        """List every regular file path (recursive) under remote_dir."""
        cmd = [
            "ssh", *_SSH_OPTS, self.ssh_target,
            f"find {shlex.quote(remote_dir)} -type f -print",
        ]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            raise TransportError(f"remote walk failed: {r.stderr.strip()}")
        return [line for line in r.stdout.splitlines() if line]

    def remote_sha256_one(self, remote_path: str) -> str:
        """Return the SHA256 hex digest of a single file on the remote."""
        cmd = [
            "ssh", *_SSH_OPTS, self.ssh_target,
            f"sha256sum {shlex.quote(remote_path)}",
        ]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            raise TransportError(f"remote sha256 of {remote_path} failed: {r.stderr.strip()}")
        return r.stdout.split(None, 1)[0]
