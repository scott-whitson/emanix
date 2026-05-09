from datetime import date
from pathlib import Path
from unittest.mock import MagicMock

import pytest

from photo_import.commands.publish import (
    PublishError,
    PublishReport,
    archive_path_for,
    run_publish,
)
from photo_import.hashing import sha256_file
from photo_import.ledger import Ledger, Status


def test_archive_path_for():
    assert archive_path_for(
        "/srv/data/photo-archive/Pictures",
        date(2026, 5, 8),
    ) == "/srv/data/photo-archive/Pictures/2026/2026-05-08"


def _make_shoot(staging: Path, files: dict[str, bytes]) -> Path:
    out = staging / "2026-05-08"
    out.mkdir(parents=True)
    for name, data in files.items():
        (out / name).write_bytes(data)
    return out


def _seed_ledger(ledger: Ledger, shoot_dir: Path):
    for f in shoot_dir.iterdir():
        digest = sha256_file(f)
        ledger.insert_staged(
            sha256=digest,
            src_path=f"/sd/{f.name}",
            inbox_path=str(f),
            shoot_date=date(2026, 5, 8),
        )


def test_publish_archives_and_uploads(tmp_path):
    staging = tmp_path / "staging"
    shoot = _make_shoot(
        staging,
        {
            "IMG_0001.JPG": b"\xff\xd8\xff\xe0AAA\xff\xd9",
            "IMG_0002.JPG": b"\xff\xd8\xff\xe0BBB\xff\xd9",
        },
    )
    ledger_path = tmp_path / "l.sqlite"
    with Ledger.open(ledger_path) as ledger:
        _seed_ledger(ledger, shoot)

    transport = MagicMock()
    transport.ssh_probe.return_value = True
    # Pretend remote sha256 matches what we have locally
    expected_remote = {f.name: sha256_file(f) for f in shoot.iterdir()}
    transport.remote_sha256.return_value = expected_remote

    immich = MagicMock()
    immich.probe.return_value = True

    with Ledger.open(ledger_path) as ledger:
        report = run_publish(
            shoot_date=date(2026, 5, 8),
            staging_root=staging,
            archive_root="/srv/data/photo-archive/Pictures",
            transport=transport,
            immich=immich,
            ledger=ledger,
        )

    assert report.archived == 2
    assert report.uploaded == 2
    assert report.errors == []
    transport.remote_mkdir.assert_called_once()
    transport.rsync_push.assert_called_once()
    immich.upload_directory.assert_called_once_with(shoot)

    with Ledger.open(ledger_path) as ledger:
        for f in shoot.iterdir():
            row = ledger.lookup_hash(sha256_file(f))
            assert row.status == Status.PUBLISHED


def test_publish_aborts_when_ssh_unreachable(tmp_path):
    staging = tmp_path / "staging"
    shoot = _make_shoot(staging, {"IMG_0001.JPG": b"\xff\xd8\xff\xe0X\xff\xd9"})
    ledger_path = tmp_path / "l.sqlite"
    with Ledger.open(ledger_path) as ledger:
        _seed_ledger(ledger, shoot)

    transport = MagicMock()
    transport.ssh_probe.return_value = False
    immich = MagicMock()
    immich.probe.return_value = True

    with Ledger.open(ledger_path) as ledger:
        with pytest.raises(PublishError, match="ssh"):
            run_publish(
                shoot_date=date(2026, 5, 8),
                staging_root=staging,
                archive_root="/srv/data/photo-archive/Pictures",
                transport=transport,
                immich=immich,
                ledger=ledger,
            )
    transport.rsync_push.assert_not_called()
    immich.upload_directory.assert_not_called()


def test_publish_marks_archive_failed_on_hash_mismatch(tmp_path):
    staging = tmp_path / "staging"
    shoot = _make_shoot(staging, {"IMG_0001.JPG": b"\xff\xd8\xff\xe0X\xff\xd9"})
    ledger_path = tmp_path / "l.sqlite"
    with Ledger.open(ledger_path) as ledger:
        _seed_ledger(ledger, shoot)

    transport = MagicMock()
    transport.ssh_probe.return_value = True
    transport.remote_sha256.return_value = {"IMG_0001.JPG": "WRONG"}
    immich = MagicMock()
    immich.probe.return_value = True

    with Ledger.open(ledger_path) as ledger:
        with pytest.raises(PublishError, match="hash mismatch"):
            run_publish(
                shoot_date=date(2026, 5, 8),
                staging_root=staging,
                archive_root="/srv/data/photo-archive/Pictures",
                transport=transport,
                immich=immich,
                ledger=ledger,
            )
    immich.upload_directory.assert_not_called()
    with Ledger.open(ledger_path) as ledger:
        row = ledger.lookup_hash(sha256_file(shoot / "IMG_0001.JPG"))
        assert row.status == Status.ARCHIVE_FAILED


def test_publish_marks_immich_failed_when_immich_errors_after_archive(tmp_path):
    from photo_import.immich import ImmichError
    staging = tmp_path / "staging"
    shoot = _make_shoot(staging, {"IMG_0001.JPG": b"\xff\xd8\xff\xe0X\xff\xd9"})
    ledger_path = tmp_path / "l.sqlite"
    with Ledger.open(ledger_path) as ledger:
        _seed_ledger(ledger, shoot)

    transport = MagicMock()
    transport.ssh_probe.return_value = True
    expected_remote = {f.name: sha256_file(f) for f in shoot.iterdir()}
    transport.remote_sha256.return_value = expected_remote

    immich = MagicMock()
    immich.probe.return_value = True
    immich.upload_directory.side_effect = ImmichError("503")

    with Ledger.open(ledger_path) as ledger:
        report = run_publish(
            shoot_date=date(2026, 5, 8),
            staging_root=staging,
            archive_root="/srv/data/photo-archive/Pictures",
            transport=transport,
            immich=immich,
            ledger=ledger,
        )
    assert report.archived == 1
    assert report.uploaded == 0
    assert any("immich" in e.lower() for e in report.errors)

    with Ledger.open(ledger_path) as ledger:
        row = ledger.lookup_hash(sha256_file(shoot / "IMG_0001.JPG"))
        assert row.status == Status.IMMICH_FAILED
