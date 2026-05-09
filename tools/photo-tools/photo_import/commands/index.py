"""`photo-import index` — bootstrap ledger from datacore filesystem archive."""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import date
from pathlib import PurePosixPath

from photo_import.ledger import Ledger


@dataclass
class IndexReport:
    indexed: int = 0
    already_known: int = 0
    errors: list[str] = field(default_factory=list)


_DATE_DIR_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_YEAR_DIR_RE = re.compile(r"^\d{4}$")


def shoot_date_from_archive_path(path: str) -> date:
    """Extract a shoot_date from an archive path.

    For paths like .../Pictures/<year>/<YYYY-MM-DD>/<file>, use the dated subdir.
    For legacy paths .../Pictures/<year>/<file>, fall back to <year>-01-01.
    """
    parts = PurePosixPath(path).parts
    for part in reversed(parts[:-1]):
        if _DATE_DIR_RE.match(part):
            return date.fromisoformat(part)
        if _YEAR_DIR_RE.match(part):
            return date(int(part), 1, 1)
    return date.today()


def run_index(transport, archive_root: str, ledger: Ledger) -> IndexReport:
    """Walk archive_root via transport, hash each file, insert ledger rows.

    Skips hashes that already exist in the ledger (preserves their status).
    """
    report = IndexReport()
    files = transport.remote_walk(archive_root)

    ledger.begin_immediate()
    try:
        for remote_path in files:
            try:
                digest = transport.remote_sha256_one(remote_path)
            except Exception as e:
                report.errors.append(f"sha256 failed for {remote_path}: {e}")
                continue

            if ledger.lookup_hash(digest) is not None:
                report.already_known += 1
                continue

            shoot_date = shoot_date_from_archive_path(remote_path)
            ledger.insert_staged(
                sha256=digest,
                src_path=remote_path,
                inbox_path=remote_path,  # placeholder; cleared below
                shoot_date=shoot_date,
            )
            ledger.mark_archived_only(digest, archive_path=remote_path)
            ledger.clear_inbox_path(digest)
            report.indexed += 1
        ledger.commit()
    except Exception:
        ledger.rollback()
        raise

    return report
