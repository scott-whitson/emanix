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


def test_run_sd_import_stages_xmp_sidecars(tmp_path, make_jpg):
    """XMP sidecars are staged alongside their parent photo in the correct shoot folder."""
    sd = tmp_path / "SD" / "DCIM" / "100CANON"
    sd.mkdir(parents=True)
    staging = tmp_path / "staging"
    ledger_path = tmp_path / "ledger.sqlite"

    # Create a JPG with a known shoot date and drop it on the fake SD card
    jpg_src = make_jpg(name="IMG_0001.JPG", exif_dt=datetime(2026, 5, 8, 12, 0, 0))
    (sd / "IMG_0001.JPG").write_bytes(jpg_src.read_bytes())

    # Create a matching XMP sidecar on the fake SD card
    xmp_content = b'<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?></xpacket>'
    (sd / "IMG_0001.JPG.xmp").write_bytes(xmp_content)

    source_root = sd.parent.parent  # directory containing DCIM/

    # First run: imports the JPG (and XMP, because the JPG is now in the ledger
    # after the first pass processes it, and the XMP second pass runs right after)
    with Ledger.open(ledger_path) as ledger:
        report = run_sd_import(
            source_root=source_root,
            staging_root=staging,
            ledger=ledger,
        )

    # JPG + XMP both copied
    assert report.copied == 2
    assert report.skipped_existing == 0
    assert report.errors == []

    may8 = staging / "2026-05-08"
    assert (may8 / "IMG_0001.JPG").exists()
    assert (may8 / "IMG_0001.JPG.xmp").exists()

    # Second run: both are already in ledger — all skipped
    with Ledger.open(ledger_path) as ledger:
        report2 = run_sd_import(
            source_root=source_root,
            staging_root=staging,
            ledger=ledger,
        )
    assert report2.copied == 0
    assert report2.skipped_existing == 2


def test_run_sd_import_picks_up_xmp_sidecars(tmp_path, sd_card):
    """XMP sidecars should be staged alongside their parent photos."""
    # Add an XMP sidecar for IMG_0001.JPG (which has EXIF date 2026-05-08)
    canon = sd_card / "DCIM" / "100CANON"
    xmp = canon / "IMG_0001.JPG.xmp"
    xmp.write_text('<xml>rating-data</xml>')

    staging = tmp_path / "staging"
    ledger_path = tmp_path / "ledger.sqlite"
    with Ledger.open(ledger_path) as ledger:
        report = run_sd_import(
            source_root=sd_card,
            staging_root=staging,
            ledger=ledger,
        )
    # 4 photos + 1 XMP = 5 copied
    assert report.copied == 5
    # XMP lands in same date folder as its parent (parent has EXIF date 2026-05-08)
    assert (staging / "2026-05-08" / "IMG_0001.JPG.xmp").exists()


def test_run_sd_import_skips_orphan_xmp(tmp_path, sd_card):
    """An XMP with no parent on the card should be flagged as an error, not crash."""
    canon = sd_card / "DCIM" / "100CANON"
    (canon / "NONEXISTENT.JPG.xmp").write_text('<xml/>')

    staging = tmp_path / "staging"
    ledger_path = tmp_path / "ledger.sqlite"
    with Ledger.open(ledger_path) as ledger:
        report = run_sd_import(
            source_root=sd_card,
            staging_root=staging,
            ledger=ledger,
        )
    # No XMPs staged (orphan), but no crash
    assert any("orphan XMP" in e for e in report.errors)


def test_run_sd_import_xmp_dedup_on_rerun(tmp_path, sd_card):
    """XMP rerun is a no-op via ledger dedup."""
    canon = sd_card / "DCIM" / "100CANON"
    (canon / "IMG_0001.JPG.xmp").write_text('<xml>rating-data</xml>')

    staging = tmp_path / "staging"
    ledger_path = tmp_path / "ledger.sqlite"
    with Ledger.open(ledger_path) as ledger:
        run_sd_import(source_root=sd_card, staging_root=staging, ledger=ledger)
    with Ledger.open(ledger_path) as ledger:
        report = run_sd_import(source_root=sd_card, staging_root=staging, ledger=ledger)
    # XMP would have been deduped against ledger
    assert report.copied == 0
    assert report.skipped_existing >= 5  # 4 photos + 1 XMP


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
