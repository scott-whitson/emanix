"""Shoot date extraction (EXIF → mtime → today) and source-file filtering."""
from __future__ import annotations

import json
import re
import subprocess
from datetime import date, datetime
from pathlib import Path

PHOTO_EXTENSIONS = {
    ".jpg", ".jpeg", ".png",
    ".heic", ".heif",
    ".cr2", ".cr3", ".nef", ".arw", ".dng", ".orf", ".rw2", ".raf",
    ".mp4", ".mov", ".m4v", ".mts", ".mkv",
}

SKIP_DIR_NAMES = {"MISC", "CANONMSC", "System Volume Information"}
SKIP_DIR_PREFIXES = (".tmp.",)

_EXIFTOOL_DATE_TAGS = ("DateTimeOriginal", "CreateDate", "MediaCreateDate")
_EXIFTOOL_DATE_RE = re.compile(r"(\d{4})[:\-](\d{2})[:\-](\d{2})")


def is_photo_file(path: Path) -> bool:
    return path.suffix.lower() in PHOTO_EXTENSIONS


def should_skip(path: Path) -> bool:
    for part in path.parts:
        if part in SKIP_DIR_NAMES:
            return True
        for pref in SKIP_DIR_PREFIXES:
            if part.startswith(pref):
                return True
    return False


def shoot_date_for(path: Path) -> date:
    """Determine the shoot date for a file via EXIF → mtime → today."""
    exif_date = _read_exif_date(path)
    if exif_date:
        return exif_date

    try:
        mtime = datetime.fromtimestamp(path.stat().st_mtime).date()
    except OSError:
        mtime = None

    today = date.today()
    if mtime and mtime <= today:
        return mtime
    return today


def _read_exif_date(path: Path) -> date | None:
    """Use exiftool to extract a creation date. Returns None on any failure."""
    try:
        result = subprocess.run(
            ["exiftool", "-j", "-d", "%Y-%m-%d", *(f"-{tag}" for tag in _EXIFTOOL_DATE_TAGS), str(path)],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None

    if result.returncode != 0 or not result.stdout.strip():
        return None

    try:
        records = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None

    if not records:
        return None
    rec = records[0]
    for tag in _EXIFTOOL_DATE_TAGS:
        value = rec.get(tag)
        if not value:
            continue
        m = _EXIFTOOL_DATE_RE.search(value)
        if m:
            try:
                return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
            except ValueError:
                continue
    return None
