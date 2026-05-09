import os
from datetime import datetime
from pathlib import Path

import pytest

from photo_import.commands.sd import find_sd_card, run_sd_import
from photo_import.ledger import Ledger, Status


@pytest.fixture
def sd_card(tmp_path, make_jpg):
    """Build a fake SD card structure with a few photos and one skipped dir."""
    sd = tmp_path / "SD" / "DCIM"
    canon = sd / "100CANON"
    canon.mkdir(parents=True)
    misc = sd / "MISC"
    misc.mkdir()

    # 3 valid JPGs (one with EXIF, one without, one with a paired CR3)
    a = make_jpg(name="IMG_0001.JPG", exif_dt=datetime(2026, 5, 8, 12, 0, 0))
    b = make_jpg(name="IMG_0002.JPG", exif_dt=None)
    c = make_jpg(name="IMG_0003.JPG", exif_dt=datetime(2026, 5, 8, 13, 0, 0))
    for p in (a, b, c):
        target = canon / p.name
        target.write_bytes(p.read_bytes())
    # paired CR3
    (canon / "IMG_0003.CR3").write_bytes(b"\x00CR3-RAW-DATA-FAKE")
    # truncated JPG
    (canon / "IMG_BAD.JPG").write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 50)
    # something to skip
    (misc / "thumb.jpg").write_bytes(b"\xff\xd8\xff\xe0\x00\x00\xff\xd9")
    # backdate IMG_0002 mtime so its shoot_date is deterministic
    target = canon / "IMG_0002.JPG"
    ts = datetime(2026, 5, 7, 9, 0, 0).timestamp()
    os.utime(target, (ts, ts))

    # Set explicit mtimes for all JPGs so tests are deterministic without exiftool
    for name, dt in [
        ("IMG_0001.JPG", datetime(2026, 5, 8, 12, 0, 0)),
        ("IMG_0003.JPG", datetime(2026, 5, 8, 13, 0, 0)),
        ("IMG_0003.CR3", datetime(2026, 5, 8, 13, 0, 0)),
        ("IMG_BAD.JPG", datetime(2026, 5, 8, 14, 0, 0)),
    ]:
        ts = dt.timestamp()
        os.utime(canon / name, (ts, ts))

    return sd.parent  # return the directory CONTAINING DCIM/, i.e. tmp_path/SD


def test_find_sd_card_via_dcim(tmp_path):
    candidate = tmp_path / "SD"
    (candidate / "DCIM" / "100CANON").mkdir(parents=True)
    found = find_sd_card(search_root=tmp_path)
    assert found == candidate


def test_find_sd_card_returns_none_when_no_dcim(tmp_path):
    (tmp_path / "SOMEDIR").mkdir()
    assert find_sd_card(search_root=tmp_path) is None


def test_run_sd_import_copies_and_deduplicates(tmp_path, sd_card):
    staging = tmp_path / "staging"
    ledger_path = tmp_path / "ledger.sqlite"

    with Ledger.open(ledger_path) as ledger:
        report = run_sd_import(
            source_root=sd_card,
            staging_root=staging,
            ledger=ledger,
        )

    # 3 valid JPGs + 1 CR3 should be copied; 1 truncated flagged; 1 skipped
    assert report.copied == 4
    assert report.flagged_corrupt == 1
    assert report.skipped_existing == 0
    # Re-run is a no-op on dedup
    with Ledger.open(ledger_path) as ledger:
        report2 = run_sd_import(
            source_root=sd_card,
            staging_root=staging,
            ledger=ledger,
        )
    assert report2.copied == 0
    assert report2.skipped_existing == 4

    # Files landed in correct date folders
    may8 = staging / "2026-05-08"
    may7 = staging / "2026-05-07"
    assert (may8 / "IMG_0001.JPG").exists()
    assert (may8 / "IMG_0003.JPG").exists()
    assert (may8 / "IMG_0003.CR3").exists()
    assert (may7 / "IMG_0002.JPG").exists()
    # MISC was skipped
    assert not any("thumb.jpg" in str(p) for p in staging.rglob("*"))


def test_run_sd_import_handles_filename_collision(tmp_path, sd_card):
    staging = tmp_path / "staging"
    ledger_path = tmp_path / "ledger.sqlite"

    # Pre-populate staging with a different file under the same target name
    pre_target = staging / "2026-05-08"
    pre_target.mkdir(parents=True)
    (pre_target / "IMG_0001.JPG").write_bytes(b"\xff\xd8\xff\xe0DIFFERENT\xff\xd9")

    with Ledger.open(ledger_path) as ledger:
        report = run_sd_import(
            source_root=sd_card,
            staging_root=staging,
            ledger=ledger,
        )
    # Collision resolved with -1 suffix
    assert (pre_target / "IMG_0001-1.JPG").exists()
    assert report.collisions == 1
