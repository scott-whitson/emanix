from datetime import date

import pytest

from photo_import.ledger import Ledger, LedgerRow, Status


def test_open_creates_schema(tmp_path):
    db_path = tmp_path / "ledger.sqlite"
    with Ledger.open(db_path) as ledger:
        assert ledger.lookup_hash("doesnotexist") is None


def test_insert_then_lookup(tmp_path):
    db_path = tmp_path / "ledger.sqlite"
    with Ledger.open(db_path) as ledger:
        ledger.insert_staged(
            sha256="a" * 64,
            src_path="/run/media/scott/SD/DCIM/100CANON/IMG_0017.JPG",
            inbox_path="/home/scott/downloads/camera/2026-05-08/IMG_0017.JPG",
            shoot_date=date(2026, 5, 8),
        )
        row = ledger.lookup_hash("a" * 64)
        assert row is not None
        assert row.sha256 == "a" * 64
        assert row.shoot_date == date(2026, 5, 8)
        assert row.status == Status.STAGED
        assert row.archive_path is None


def test_mark_published(tmp_path):
    db_path = tmp_path / "ledger.sqlite"
    with Ledger.open(db_path) as ledger:
        ledger.insert_staged(
            sha256="b" * 64,
            src_path="/sd/IMG_0018.JPG",
            inbox_path="/home/scott/downloads/camera/2026-05-08/IMG_0018.JPG",
            shoot_date=date(2026, 5, 8),
        )
        ledger.mark_published(
            sha256="b" * 64,
            archive_path="/srv/data/photo-archive/Pictures/2026/2026-05-08/IMG_0018.JPG",
            immich_asset_id="asset-uuid-1",
        )
        row = ledger.lookup_hash("b" * 64)
        assert row.status == Status.PUBLISHED
        assert row.archive_path == "/srv/data/photo-archive/Pictures/2026/2026-05-08/IMG_0018.JPG"
        assert row.immich_asset_id == "asset-uuid-1"


def test_mark_archive_failed(tmp_path):
    db_path = tmp_path / "ledger.sqlite"
    with Ledger.open(db_path) as ledger:
        ledger.insert_staged("c" * 64, "/sd/X.JPG", "/inbox/X.JPG", date(2026, 5, 8))
        ledger.mark_archive_failed("c" * 64, error="rsync exit 23")
        row = ledger.lookup_hash("c" * 64)
        assert row.status == Status.ARCHIVE_FAILED
        assert row.last_error == "rsync exit 23"


def test_pin_and_unpin(tmp_path):
    db_path = tmp_path / "ledger.sqlite"
    with Ledger.open(db_path) as ledger:
        ledger.insert_staged("d" * 64, "/sd/Y.JPG", "/inbox/2026-05-08/Y.JPG", date(2026, 5, 8))
        assert ledger.is_pinned(date(2026, 5, 8)) is False
        ledger.pin(date(2026, 5, 8))
        assert ledger.is_pinned(date(2026, 5, 8)) is True
        ledger.unpin(date(2026, 5, 8))
        assert ledger.is_pinned(date(2026, 5, 8)) is False


def test_list_shoots_groups_by_date(tmp_path):
    db_path = tmp_path / "ledger.sqlite"
    with Ledger.open(db_path) as ledger:
        ledger.insert_staged("e" * 64, "/sd/A.JPG", "/inbox/2026-05-08/A.JPG", date(2026, 5, 8))
        ledger.insert_staged("f" * 64, "/sd/B.JPG", "/inbox/2026-05-08/B.JPG", date(2026, 5, 8))
        ledger.insert_staged("g" * 64, "/sd/C.JPG", "/inbox/2026-05-09/C.JPG", date(2026, 5, 9))
        shoots = ledger.list_shoots()
        by_date = {s.shoot_date: s for s in shoots}
        assert by_date[date(2026, 5, 8)].file_count == 2
        assert by_date[date(2026, 5, 9)].file_count == 1


def test_concurrent_writers_fail_fast(tmp_path):
    db_path = tmp_path / "ledger.sqlite"
    ledger_a = Ledger.open(db_path)
    ledger_b = Ledger.open(db_path)
    try:
        ledger_a.begin_immediate()
        with pytest.raises(Exception):
            ledger_b.begin_immediate(timeout_ms=200)
    finally:
        ledger_a.rollback()
        ledger_a.close()
        ledger_b.close()
