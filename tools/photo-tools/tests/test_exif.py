import os
import shutil
from datetime import date, datetime

import pytest

from photo_import.exif import shoot_date_for


# `exiftool` is a runtime dependency that may not be installed in the dev
# environment. The EXIF-positive test depends on it; skip when missing.
exiftool_available = shutil.which("exiftool") is not None
requires_exiftool = pytest.mark.skipif(
    not exiftool_available,
    reason="exiftool not installed (will be installed during Task 18 commissioning)",
)


@requires_exiftool
def test_uses_exif_when_present(make_jpg):
    p = make_jpg(exif_dt=datetime(2026, 5, 8, 14, 30, 0))
    assert shoot_date_for(p) == date(2026, 5, 8)


def test_falls_back_to_mtime_when_no_exif(make_jpg, tmp_path):
    p = make_jpg(name="NOEXIF.JPG", exif_dt=None)
    target_ts = datetime(2025, 12, 25, 10, 0, 0).timestamp()
    os.utime(p, (target_ts, target_ts))
    assert shoot_date_for(p) == date(2025, 12, 25)


def test_falls_back_to_today_when_mtime_in_future(make_jpg, tmp_path):
    p = make_jpg(name="WEIRD.JPG", exif_dt=None)
    future_ts = datetime(2099, 1, 1).timestamp()
    os.utime(p, (future_ts, future_ts))
    today = date.today()
    assert shoot_date_for(p) == today


def test_recognized_extensions(make_jpg):
    from photo_import.exif import is_photo_file
    p = make_jpg(name="X.JPG")
    assert is_photo_file(p) is True
    cr3 = p.parent / "X.CR3"
    cr3.write_bytes(b"\x00")
    assert is_photo_file(cr3) is True
    junk = p.parent / "X.txt"
    junk.write_bytes(b"")
    assert is_photo_file(junk) is False


def test_skipped_paths(tmp_path):
    from photo_import.exif import should_skip
    assert should_skip(tmp_path / "DCIM" / "MISC" / "X.JPG") is True
    assert should_skip(tmp_path / "DCIM" / ".tmp.driveupload" / "X.JPG") is True
    assert should_skip(tmp_path / "DCIM" / "100CANON" / "X.JPG") is False
