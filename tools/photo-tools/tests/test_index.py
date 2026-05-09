from datetime import date
from pathlib import Path
from unittest.mock import MagicMock

import pytest

from photo_import.commands.index import run_index
from photo_import.ledger import Ledger, Status


def test_index_inserts_archived_only_rows(tmp_path):
    ledger_path = tmp_path / "l.sqlite"
    transport = MagicMock()
    transport.remote_walk.return_value = [
        "/srv/data/photo-archive/Pictures/2026/2026-05-08/IMG_0001.JPG",
        "/srv/data/photo-archive/Pictures/2026/2026-05-08/IMG_0002.JPG",
        "/srv/data/photo-archive/Pictures/2025/2025-12-25/IMG_X.JPG",
    ]
    transport.remote_sha256_one.side_effect = lambda p: f"hash-of-{Path(p).name}"

    with Ledger.open(ledger_path) as ledger:
        report = run_index(
            transport=transport,
            archive_root="/srv/data/photo-archive/Pictures",
            ledger=ledger,
        )

    assert report.indexed == 3
    with Ledger.open(ledger_path) as ledger:
        row = ledger.lookup_hash("hash-of-IMG_0001.JPG")
        assert row is not None
        assert row.status == Status.ARCHIVED_ONLY
        assert row.archive_path == "/srv/data/photo-archive/Pictures/2026/2026-05-08/IMG_0001.JPG"
        assert row.shoot_date == date(2026, 5, 8)


def test_index_skips_already_known_hashes(tmp_path):
    ledger_path = tmp_path / "l.sqlite"
    transport = MagicMock()
    transport.remote_walk.return_value = [
        "/srv/data/photo-archive/Pictures/2026/2026-05-08/IMG_0001.JPG",
    ]
    transport.remote_sha256_one.return_value = "hash1"

    with Ledger.open(ledger_path) as ledger:
        ledger.insert_staged(
            sha256="hash1",
            src_path="/somewhere/local",
            inbox_path="/somewhere/local",
            shoot_date=date(2026, 5, 8),
        )
        report = run_index(
            transport=transport,
            archive_root="/srv/data/photo-archive/Pictures",
            ledger=ledger,
        )

    assert report.indexed == 0
    assert report.already_known == 1


def test_index_extracts_shoot_date_from_path(tmp_path):
    """Paths like .../<year>/<YYYY-MM-DD>/<file> use the date subdir."""
    from photo_import.commands.index import shoot_date_from_archive_path
    p = "/srv/data/photo-archive/Pictures/2026/2026-05-08/IMG_0001.JPG"
    assert shoot_date_from_archive_path(p) == date(2026, 5, 8)


def test_index_extracts_shoot_date_year_only_for_legacy(tmp_path):
    """Legacy flat-in-year paths (no per-shoot subfolder) date to Jan 1 of that year."""
    from photo_import.commands.index import shoot_date_from_archive_path
    p = "/srv/data/photo-archive/Pictures/2024/IMG_OLD.JPG"
    assert shoot_date_from_archive_path(p) == date(2024, 1, 1)
