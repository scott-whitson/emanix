from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import pytest

from photo_import.commands.retention import sweep_staging
from photo_import.hashing import sha256_file
from photo_import.ledger import Ledger


def _staged_and_published(tmp_path, shoot_date_str: str, names: list[str]) -> Path:
    staging = tmp_path / "staging"
    out = staging / shoot_date_str
    out.mkdir(parents=True)
    for n in names:
        (out / n).write_bytes(b"\xff\xd8\xff\xe0" + n.encode() + b"\xff\xd9")
    return staging


def test_sweep_deletes_old_published_shoots(tmp_path):
    staging = _staged_and_published(tmp_path, "2026-04-01", ["A.JPG"])
    shoot = staging / "2026-04-01"
    digest = sha256_file(shoot / "A.JPG")

    ledger_path = tmp_path / "l.sqlite"
    with Ledger.open(ledger_path) as ledger:
        ledger.insert_staged(digest, "/sd/A.JPG", str(shoot / "A.JPG"), date(2026, 4, 1))
        ledger.mark_published(digest, "/srv/data/photo-archive/Pictures/2026/2026-04-01/A.JPG", None)
        # Backdate published_at in the ledger directly (file mtime is irrelevant now)
        old_iso = (datetime.now(timezone.utc) - timedelta(days=40)).isoformat()
        ledger._conn.execute(
            "UPDATE files SET published_at = ? WHERE sha256 = ?",
            (old_iso, digest),
        )
        report = sweep_staging(staging_root=staging, ledger=ledger, retention_days=30)
    assert report.removed == 1
    assert not shoot.exists()


def test_sweep_keeps_pinned_shoots(tmp_path):
    staging = _staged_and_published(tmp_path, "2026-04-01", ["A.JPG"])
    shoot = staging / "2026-04-01"
    digest = sha256_file(shoot / "A.JPG")

    ledger_path = tmp_path / "l.sqlite"
    with Ledger.open(ledger_path) as ledger:
        ledger.insert_staged(digest, "/sd/A.JPG", str(shoot / "A.JPG"), date(2026, 4, 1))
        ledger.mark_published(digest, "/srv/data/photo-archive/Pictures/2026/2026-04-01/A.JPG", None)
        # Backdate published_at in the ledger directly (file mtime is irrelevant now)
        old_iso = (datetime.now(timezone.utc) - timedelta(days=40)).isoformat()
        ledger._conn.execute(
            "UPDATE files SET published_at = ? WHERE sha256 = ?",
            (old_iso, digest),
        )
        ledger.pin(date(2026, 4, 1))
        report = sweep_staging(staging_root=staging, ledger=ledger, retention_days=30)
    assert report.removed == 0
    assert (shoot / "A.JPG").exists()


def test_sweep_keeps_unpublished_shoots(tmp_path):
    staging = _staged_and_published(tmp_path, "2026-04-01", ["A.JPG"])
    shoot = staging / "2026-04-01"
    digest = sha256_file(shoot / "A.JPG")

    ledger_path = tmp_path / "l.sqlite"
    with Ledger.open(ledger_path) as ledger:
        ledger.insert_staged(digest, "/sd/A.JPG", str(shoot / "A.JPG"), date(2026, 4, 1))
        # Not marked published — still 'staged'
        report = sweep_staging(staging_root=staging, ledger=ledger, retention_days=30)
    assert report.removed == 0
    assert (shoot / "A.JPG").exists()


def test_sweep_keeps_recent_shoots(tmp_path):
    staging = _staged_and_published(tmp_path, "2026-05-01", ["A.JPG"])
    shoot = staging / "2026-05-01"
    digest = sha256_file(shoot / "A.JPG")

    ledger_path = tmp_path / "l.sqlite"
    with Ledger.open(ledger_path) as ledger:
        ledger.insert_staged(digest, "/sd/A.JPG", str(shoot / "A.JPG"), date(2026, 5, 1))
        ledger.mark_published(digest, "/srv/data/photo-archive/Pictures/2026/2026-05-01/A.JPG", None)
        report = sweep_staging(staging_root=staging, ledger=ledger, retention_days=30)
    assert report.removed == 0
    assert (shoot / "A.JPG").exists()
