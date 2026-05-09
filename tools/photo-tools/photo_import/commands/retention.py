"""Retention sweep — delete published, unpinned, old shoots from staging."""
from __future__ import annotations

import shutil
import time
from dataclasses import dataclass
from datetime import datetime, timedelta
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

    cutoff = datetime.now() - timedelta(days=retention_days)
    cutoff_ts = cutoff.timestamp()

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

        # Newest mtime among files in the dir
        newest = max(
            (f.stat().st_mtime for f in shoot_dir.rglob("*") if f.is_file()),
            default=0.0,
        )
        if newest > cutoff_ts:
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
