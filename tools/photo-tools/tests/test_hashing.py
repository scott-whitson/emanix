import hashlib
from pathlib import Path

import pytest

from photo_import.hashing import sha256_file, validate_jpg


def test_sha256_file_matches_hashlib(tmp_path):
    p = tmp_path / "f.bin"
    data = b"hello world" * 1000
    p.write_bytes(data)
    expected = hashlib.sha256(data).hexdigest()
    assert sha256_file(p) == expected


def test_sha256_file_streams_large_file(tmp_path):
    p = tmp_path / "big.bin"
    chunk = b"x" * 65536
    with open(p, "wb") as f:
        for _ in range(50):
            f.write(chunk)
    expected = hashlib.sha256(chunk * 50).hexdigest()
    assert sha256_file(p) == expected


def test_validate_jpg_accepts_well_formed(tmp_path):
    p = tmp_path / "ok.jpg"
    p.write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 100 + b"\xff\xd9")
    assert validate_jpg(p) is True


def test_validate_jpg_rejects_missing_start_marker(tmp_path):
    p = tmp_path / "bad.jpg"
    p.write_bytes(b"\x00\x00\x00\x00" + b"\xff\xd9")
    assert validate_jpg(p) is False


def test_validate_jpg_rejects_truncated_no_end_marker(tmp_path):
    p = tmp_path / "trunc.jpg"
    p.write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 100)
    assert validate_jpg(p) is False


def test_validate_jpg_rejects_empty(tmp_path):
    p = tmp_path / "empty.jpg"
    p.write_bytes(b"")
    assert validate_jpg(p) is False
