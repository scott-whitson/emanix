from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

from photo_import.immich import ImmichClient, ImmichError


def _completed(returncode=0, stdout="", stderr=""):
    m = MagicMock()
    m.returncode = returncode
    m.stdout = stdout
    m.stderr = stderr
    return m


def test_probe_returns_true_when_reachable():
    c = ImmichClient(url="http://datacore:2283", api_key="k")
    with patch("photo_import.immich.urllib.request.urlopen") as urlopen:
        urlopen.return_value.__enter__.return_value.status = 200
        assert c.probe() is True


def test_probe_uses_server_ping_url():
    c = ImmichClient(url="http://datacore:2283", api_key="k")
    with patch("photo_import.immich.urllib.request.urlopen") as urlopen:
        urlopen.return_value.__enter__.return_value.status = 200
        c.probe()
        # urlopen was called with a Request whose full_url ends in /api/server/ping
        req = urlopen.call_args.args[0]
        assert req.full_url == "http://datacore:2283/api/server/ping"
        assert req.get_method() == "GET"


def test_probe_returns_false_on_connection_error():
    c = ImmichClient(url="http://datacore:2283", api_key="k")
    with patch("photo_import.immich.urllib.request.urlopen", side_effect=ConnectionError("nope")):
        assert c.probe() is False


def test_upload_directory_calls_immich_go(tmp_path):
    c = ImmichClient(url="http://datacore:2283", api_key="k")
    src = tmp_path / "2026-05-08"
    src.mkdir()
    with patch("photo_import.immich.subprocess.run") as run:
        run.return_value = _completed(returncode=0, stdout="uploaded 5\n")
        c.upload_directory(src)
        cmd = run.call_args.args[0]
        assert cmd[0] == "immich-go"
        assert "--server" in cmd
        assert "http://datacore:2283" in cmd
        assert "--api-key" in cmd
        assert "k" in cmd
        assert str(src) in cmd


def test_upload_raises_on_nonzero():
    c = ImmichClient(url="http://datacore:2283", api_key="k")
    with patch("photo_import.immich.subprocess.run") as run:
        run.return_value = _completed(returncode=2, stderr="401 unauthorized")
        with pytest.raises(ImmichError, match="401"):
            c.upload_directory(Path("/no"))


def test_upload_raises_with_helpful_message_on_401():
    c = ImmichClient(url="http://datacore:2283", api_key="k")
    with patch("photo_import.immich.subprocess.run") as run:
        run.return_value = _completed(returncode=2, stderr="HTTP 401 unauthorized")
        with pytest.raises(ImmichError, match="API key"):
            c.upload_directory(Path("/x"))
