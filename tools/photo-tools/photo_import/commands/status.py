"""`photo-import status` — show staged/published shoots, reachability, and disk."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path

from photo_import.ledger import Ledger, Status


@dataclass
class ShootStatus:
    shoot_date: date
    file_count: int
    status_summary: str
    pinned: bool
    retention_days_left: int | None


@dataclass
class StatusReport:
    shoots: list[ShootStatus]
    datacore_reachable: bool
    immich_reachable: bool
    staged_missing: int
    ssh_target: str
    immich_url: str
    staging_root: Path
    staging_size_bytes: int


def build_status(
    staging_root: Path,
    ledger: Ledger,
    transport,
    immich,
    ssh_target: str,
    immich_url: str,
    retention_days: int = 30,
) -> StatusReport:
    shoots: list[ShootStatus] = []
    staged_missing = 0
    for summary in ledger.list_shoots():
        rows = ledger.files_for_shoot(summary.shoot_date)
        statuses = sorted({r.status.value for r in rows})
        # Detect staged-but-missing
        for r in rows:
            if r.status == Status.STAGED and r.inbox_path and not Path(r.inbox_path).exists():
                staged_missing += 1
        retention_left = None
        if all(r.status == Status.PUBLISHED for r in rows) and not summary.pinned:
            shoot_dir = staging_root / summary.shoot_date.isoformat()
            if shoot_dir.is_dir():
                newest = max(
                    (f.stat().st_mtime for f in shoot_dir.rglob("*") if f.is_file()),
                    default=0.0,
                )
                if newest > 0:
                    age_days = (datetime.now().timestamp() - newest) / 86400
                    retention_left = max(0, retention_days - int(age_days))
        shoots.append(
            ShootStatus(
                shoot_date=summary.shoot_date,
                file_count=summary.file_count,
                status_summary=", ".join(statuses),
                pinned=summary.pinned,
                retention_days_left=retention_left,
            )
        )

    staging_bytes = 0
    if staging_root.is_dir():
        for f in staging_root.rglob("*"):
            if f.is_file():
                staging_bytes += f.stat().st_size

    return StatusReport(
        shoots=shoots,
        datacore_reachable=transport.ssh_probe(),
        immich_reachable=immich.probe(),
        staged_missing=staged_missing,
        ssh_target=ssh_target,
        immich_url=immich_url,
        staging_root=staging_root,
        staging_size_bytes=staging_bytes,
    )


def format_status(rpt: StatusReport) -> str:
    lines = []
    lines.append(f"Staging:  {rpt.staging_root}  ({_fmt_bytes(rpt.staging_size_bytes)})")
    lines.append(f"Datacore reachable: {'yes' if rpt.datacore_reachable else 'no'}  ({rpt.ssh_target})")
    lines.append(f"Immich reachable:   {'yes' if rpt.immich_reachable else 'no'}   ({rpt.immich_url})")
    if rpt.staged_missing:
        lines.append(f"WARNING: {rpt.staged_missing} ledger rows reference inbox files that no longer exist.")
    lines.append("")
    if not rpt.shoots:
        lines.append("(no shoots tracked)")
        return "\n".join(lines)
    lines.append(f"{'Shoot date':<12} {'Files':>6} {'Status':<35} {'Retention':<14} Pin")
    for s in rpt.shoots:
        retention = "-" if s.retention_days_left is None else f"{s.retention_days_left}d left"
        lines.append(
            f"{s.shoot_date.isoformat():<12} {s.file_count:>6} {s.status_summary:<35} {retention:<14} {'yes' if s.pinned else 'no'}"
        )
    return "\n".join(lines)


def _fmt_bytes(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} PB"
