"""Retention sweep — delete published, unpinned, old shoots from staging."""
from __future__ import annotations

import shutil
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

from photo_import.ledger import Ledger, Status


@dataclass
class SweepReport:
    removed: int = 0
    kept: int = 0


def sweep_staging(
    staging_root: Path,
    ledger: Ledger,
    retention_days: int,
) -> SweepReport:
    report = SweepReport()
    if not staging_root.is_dir():
        return report

    for shoot_dir in sorted(staging_root.iterdir()):
        if not shoot_dir.is_dir():
            continue
        try:
            from datetime import date as _date
            shoot_date = _date.fromisoformat(shoot_dir.name)
        except ValueError:
            continue

        if ledger.is_pinned(shoot_date):
            report.kept += 1
            continue

        rows = ledger.files_for_shoot(shoot_date)
        if not rows:
            report.kept += 1
            continue
        if not all(r.status == Status.PUBLISHED for r in rows):
            report.kept += 1
            continue

        # Use newest published_at from ledger rows (not file mtime — files copied from
        # SD card preserve their original capture mtime, which is irrelevant here).
        publish_times = [r.published_at for r in rows if r.published_at is not None]
        if not publish_times:
            # Defensive: all rows are PUBLISHED (we checked above) so at least one
            # should have published_at set. If none do, treat as too-new to be safe.
            report.kept += 1
            continue
        newest_published = max(publish_times)
        # published_at is stored UTC; compare with a UTC cutoff
        cutoff_utc = datetime.now(timezone.utc) - timedelta(days=retention_days)
        if newest_published > cutoff_utc:
            report.kept += 1
            continue

        ledger.begin_immediate()
        try:
            shutil.rmtree(shoot_dir)
            for r in rows:
                ledger.clear_inbox_path(r.sha256)
                ledger.mark_archived_only(r.sha256, r.archive_path or "")
            ledger.commit()
            report.removed += 1
        except Exception:
            ledger.rollback()
            raise
    return report
