"""Content hashing and lightweight JPG integrity checks."""
from __future__ import annotations

import hashlib
from pathlib import Path

_HASH_BUF = 1 << 16  # 64 KB read chunks
_JPG_START = b"\xff\xd8\xff"
_JPG_END = b"\xff\xd9"


def sha256_file(path: Path) -> str:
    """Stream a file through SHA256 and return its hex digest."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(_HASH_BUF):
            h.update(chunk)
    return h.hexdigest()


def validate_jpg(path: Path) -> bool:
    """Return True iff the file starts with FF D8 FF and ends with FF D9.

    This is a fast structural check — it does NOT decode the image. It catches
    truncated SD-card writes (camera buffer overflow) without decoding cost.
    """
    try:
        size = path.stat().st_size
        if size < 4:
            return False
        with open(path, "rb") as f:
            head = f.read(3)
            if head != _JPG_START:
                return False
            f.seek(-2, 2)  # 2 bytes from end
            tail = f.read(2)
            return tail == _JPG_END
    except OSError:
        return False
