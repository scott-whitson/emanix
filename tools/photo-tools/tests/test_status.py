from datetime import date
from pathlib import Path
from unittest.mock import MagicMock

import pytest

from photo_import.commands.status import build_status, format_status
from photo_import.ledger import Ledger


def test_build_status_lists_shoots(tmp_path):
    staging = tmp_path / "staging"
    (staging / "2026-05-08").mkdir(parents=True)
    (staging / "2026-05-08" / "A.JPG").write_bytes(b"\xff\xd8\xff\xe0X\xff\xd9")
    ledger_path = tmp_path / "l.sqlite"

    with Ledger.open(ledger_path) as ledger:
        ledger.insert_staged("a" * 64, "/sd/A.JPG", str(staging / "2026-05-08" / "A.JPG"), date(2026, 5, 8))
        s = build_status(
            staging_root=staging,
            ledger=ledger,
            transport=MagicMock(ssh_probe=MagicMock(return_value=True)),
            immich=MagicMock(probe=MagicMock(return_value=True)),
            ssh_target="datacore",
            immich_url="http://datacore:2283",
        )

    assert any(sh.shoot_date == date(2026, 5, 8) for sh in s.shoots)
    assert s.datacore_reachable is True
    assert s.immich_reachable is True


def test_build_status_detects_staged_missing(tmp_path):
    staging = tmp_path / "staging"
    ledger_path = tmp_path / "l.sqlite"
    with Ledger.open(ledger_path) as ledger:
        ledger.insert_staged("a" * 64, "/sd/A.JPG", str(staging / "2026-05-08" / "A.JPG"), date(2026, 5, 8))
        # do not actually create the file
        s = build_status(
            staging_root=staging,
            ledger=ledger,
            transport=MagicMock(ssh_probe=MagicMock(return_value=True)),
            immich=MagicMock(probe=MagicMock(return_value=True)),
            ssh_target="datacore",
            immich_url="http://datacore:2283",
        )
    assert s.staged_missing == 1


def test_format_status_includes_summary(tmp_path):
    from photo_import.commands.status import StatusReport, ShootStatus
    rpt = StatusReport(
        shoots=[
            ShootStatus(
                shoot_date=date(2026, 5, 8),
                file_count=2,
                status_summary="staged",
                pinned=False,
                retention_days_left=None,
            )
        ],
        datacore_reachable=True,
        immich_reachable=False,
        staged_missing=0,
        ssh_target="datacore",
        immich_url="http://datacore:2283",
        staging_root=Path("/tmp/stage"),
        staging_size_bytes=1024,
    )
    out = format_status(rpt)
    assert "2026-05-08" in out
    assert "staged" in out
    assert "datacore" in out
    assert "Immich reachable" in out and "no" in out.lower()
