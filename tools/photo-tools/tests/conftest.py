"""Shared pytest fixtures."""
from __future__ import annotations

from datetime import datetime
from pathlib import Path

import pytest
from PIL import Image
from PIL.ExifTags import Base


@pytest.fixture
def make_jpg(tmp_path):
    """Factory that writes a tiny JPG with optional EXIF DateTimeOriginal."""
    counter = {"n": 0}

    def _make(name: str | None = None, exif_dt: datetime | None = None) -> Path:
        counter["n"] += 1
        name = name or f"IMG_{counter['n']:04d}.JPG"
        out = tmp_path / name
        img = Image.new("RGB", (8, 8), color=(255, 0, 0))
        if exif_dt is not None:
            exif = img.getexif()
            # Tag 36867 = DateTimeOriginal, format "YYYY:MM:DD HH:MM:SS"
            exif[Base.DateTimeOriginal.value] = exif_dt.strftime("%Y:%m:%d %H:%M:%S")
            img.save(out, "JPEG", exif=exif)
        else:
            img.save(out, "JPEG")
        return out

    return _make
