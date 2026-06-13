from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

from photo_import.transport import (
    Transport,
    TransportError,
)


def _completed(returncode=0, stdout="", stderr=""):
    m = MagicMock()
    m.returncode = returncode
    m.stdout = stdout
    m.stderr = stderr
    return m


def test_ssh_probe_returns_true_on_success():
    t = Transport(ssh_target="datacore")
    with patch("photo_import.transport.subprocess.run") as run:
        run.return_value = _completed(returncode=0)
        assert t.ssh_probe() is True
        args = run.call_args.args[0]
        assert args[:2] == ["ssh", "-o"]  # uses options
        assert "datacore" in args


def test_ssh_probe_returns_false_on_failure():
    t = Transport(ssh_target="datacore")
    with patch("photo_import.transport.subprocess.run") as run:
        run.return_value = _completed(returncode=255)
        assert t.ssh_probe() is False


def test_rsync_pushes_directory(tmp_path):
    t = Transport(ssh_target="datacore")
    src = tmp_path / "2026-05-08"
    src.mkdir()
    (src / "x.jpg").write_bytes(b"x")
    with patch("photo_import.transport.subprocess.run") as run:
        run.return_value = _completed(returncode=0)
        t.rsync_push(src, "/srv/data/photo-archive/Pictures/2026/2026-05-08")
        cmd = run.call_args.args[0]
        assert cmd[0] == "rsync"
        assert "--partial" in cmd
        assert "--append-verify" in cmd
        assert str(src) + "/" in cmd  # trailing slash
        assert "datacore:/srv/data/photo-archive/Pictures/2026/2026-05-08/" in cmd


def test_rsync_raises_on_nonzero():
    t = Transport(ssh_target="datacore")
    with patch("photo_import.transport.subprocess.run") as run:
        run.return_value = _completed(returncode=23, stderr="permission denied")
        with pytest.raises(TransportError, match="rsync"):
            t.rsync_push(Path("/no/such"), "/srv/data/photo-archive/Pictures/2026/2026-05-08")


def test_remote_sha256_parses_output():
    t = Transport(ssh_target="datacore")
    fake_out = (
        "abc123  /srv/data/photo-archive/Pictures/2026/2026-05-08/IMG_0001.JPG\n"
        "def456  /srv/data/photo-archive/Pictures/2026/2026-05-08/IMG_0002.JPG\n"
    )
    with patch("photo_import.transport.subprocess.run") as run:
        run.return_value = _completed(returncode=0, stdout=fake_out)
        result = t.remote_sha256("/srv/data/photo-archive/Pictures/2026/2026-05-08")
        assert result == {
            "IMG_0001.JPG": "abc123",
            "IMG_0002.JPG": "def456",
        }


def test_remote_mkdir_runs_ssh_mkdir():
    t = Transport(ssh_target="datacore")
    with patch("photo_import.transport.subprocess.run") as run:
        run.return_value = _completed(returncode=0)
        t.remote_mkdir("/srv/data/photo-archive/Pictures/2026/2026-05-08")
        cmd = run.call_args.args[0]
        assert cmd[0] == "ssh"
        assert "datacore" in cmd
        assert "mkdir -p '/srv/data/photo-archive/Pictures/2026/2026-05-08'" in " ".join(cmd)


def test_remote_walk_parses_output():
    t = Transport(ssh_target="datacore")
    fake_out = (
        "/srv/data/photo-archive/Pictures/2026/2026-05-08/IMG_0001.JPG\n"
        "/srv/data/photo-archive/Pictures/2026/2026-05-08/IMG_0002.JPG\n"
        "\n"  # trailing blank line should be filtered
        "/srv/data/photo-archive/Pictures/2025/IMG_OLD.JPG\n"
    )
    with patch("photo_import.transport.subprocess.run") as run:
        run.return_value = _completed(returncode=0, stdout=fake_out)
        result = t.remote_walk("/srv/data/photo-archive/Pictures")
        assert result == [
            "/srv/data/photo-archive/Pictures/2026/2026-05-08/IMG_0001.JPG",
            "/srv/data/photo-archive/Pictures/2026/2026-05-08/IMG_0002.JPG",
            "/srv/data/photo-archive/Pictures/2025/IMG_OLD.JPG",
        ]


def test_remote_walk_raises_on_nonzero():
    t = Transport(ssh_target="datacore")
    with patch("photo_import.transport.subprocess.run") as run:
        run.return_value = _completed(returncode=1, stderr="not found")
        with pytest.raises(TransportError, match="remote walk"):
            t.remote_walk("/no/such/path")


def test_remote_sha256_one_returns_digest():
    t = Transport(ssh_target="datacore")
    with patch("photo_import.transport.subprocess.run") as run:
        run.return_value = _completed(
            returncode=0,
            stdout="abc123def456  /srv/data/photo-archive/Pictures/2026/2026-05-08/IMG_0001.JPG\n",
        )
        digest = t.remote_sha256_one("/srv/data/photo-archive/Pictures/2026/2026-05-08/IMG_0001.JPG")
        assert digest == "abc123def456"


def test_remote_sha256_one_raises_on_empty_output():
    t = Transport(ssh_target="datacore")
    with patch("photo_import.transport.subprocess.run") as run:
        run.return_value = _completed(returncode=0, stdout="")
        with pytest.raises(TransportError, match="empty output"):
            t.remote_sha256_one("/srv/data/photo-archive/Pictures/2026/2026-05-08/IMG_0001.JPG")


def test_remote_sha256_one_raises_on_nonzero():
    t = Transport(ssh_target="datacore")
    with patch("photo_import.transport.subprocess.run") as run:
        run.return_value = _completed(returncode=1, stderr="No such file")
        with pytest.raises(TransportError, match="remote sha256"):
            t.remote_sha256_one("/no/such/path")
