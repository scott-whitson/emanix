"""SQLite-backed dedup ledger and shoot-state tracker."""
from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import date, datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Iterator


class Status(str, Enum):
    STAGED = "staged"
    PUBLISHED = "published"
    ARCHIVE_FAILED = "archive-failed"
    IMMICH_FAILED = "immich-failed"
    ARCHIVED_ONLY = "archived-only"


@dataclass(frozen=True)
class LedgerRow:
    sha256: str
    src_path: str
    inbox_path: str | None
    shoot_date: date
    status: Status
    archive_path: str | None
    immich_asset_id: str | None
    last_error: str | None
    imported_at: datetime
    published_at: datetime | None


@dataclass(frozen=True)
class ShootSummary:
    shoot_date: date
    file_count: int
    statuses: tuple[Status, ...]
    pinned: bool


_SCHEMA = """
CREATE TABLE IF NOT EXISTS files (
    sha256 TEXT PRIMARY KEY,
    src_path TEXT NOT NULL,
    inbox_path TEXT,
    shoot_date TEXT NOT NULL,
    status TEXT NOT NULL,
    archive_path TEXT,
    immich_asset_id TEXT,
    last_error TEXT,
    imported_at TEXT NOT NULL,
    published_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_files_shoot_date ON files(shoot_date);
CREATE INDEX IF NOT EXISTS idx_files_status ON files(status);

CREATE TABLE IF NOT EXISTS pinned_shoots (
    shoot_date TEXT PRIMARY KEY,
    pinned_at TEXT NOT NULL
);
"""


class Ledger:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self._conn = conn

    @classmethod
    def open(cls, db_path: Path) -> "Ledger":
        db_path.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(db_path, detect_types=sqlite3.PARSE_DECLTYPES, isolation_level=None)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA foreign_keys=ON")
        conn.executescript(_SCHEMA)
        return cls(conn)

    def __enter__(self) -> "Ledger":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def close(self) -> None:
        self._conn.close()

    # --- transactions --------------------------------------------------

    def begin_immediate(self, timeout_ms: int = 5000) -> None:
        self._conn.execute(f"PRAGMA busy_timeout = {timeout_ms}")
        self._conn.execute("BEGIN IMMEDIATE")

    def commit(self) -> None:
        self._conn.execute("COMMIT")

    def rollback(self) -> None:
        try:
            self._conn.execute("ROLLBACK")
        except sqlite3.OperationalError:
            pass

    # --- inserts/updates -----------------------------------------------

    def insert_staged(
        self,
        sha256: str,
        src_path: str,
        inbox_path: str,
        shoot_date: date,
    ) -> None:
        self._conn.execute(
            """
            INSERT INTO files (sha256, src_path, inbox_path, shoot_date, status, imported_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                sha256,
                src_path,
                inbox_path,
                shoot_date.isoformat(),
                Status.STAGED.value,
                datetime.now(timezone.utc).isoformat(),
            ),
        )

    def mark_published(
        self,
        sha256: str,
        archive_path: str,
        immich_asset_id: str | None,
    ) -> None:
        self._conn.execute(
            """
            UPDATE files
            SET status = ?, archive_path = ?, immich_asset_id = ?,
                published_at = ?, last_error = NULL
            WHERE sha256 = ?
            """,
            (
                Status.PUBLISHED.value,
                archive_path,
                immich_asset_id,
                datetime.now(timezone.utc).isoformat(),
                sha256,
            ),
        )

    def mark_archived_only(self, sha256: str, archive_path: str) -> None:
        self._conn.execute(
            """
            UPDATE files
            SET status = ?, archive_path = ?, last_error = NULL
            WHERE sha256 = ?
            """,
            (Status.ARCHIVED_ONLY.value, archive_path, sha256),
        )

    def mark_archive_failed(self, sha256: str, error: str) -> None:
        self._conn.execute(
            "UPDATE files SET status = ?, last_error = ? WHERE sha256 = ?",
            (Status.ARCHIVE_FAILED.value, error, sha256),
        )

    def mark_immich_failed(self, sha256: str, archive_path: str, error: str) -> None:
        """Archive succeeded but Immich upload failed. Records archive_path so
        retention/status know the file is durable on datacore."""
        self._conn.execute(
            "UPDATE files SET status = ?, archive_path = ?, last_error = ? WHERE sha256 = ?",
            (Status.IMMICH_FAILED.value, archive_path, error, sha256),
        )

    def clear_inbox_path(self, sha256: str) -> None:
        """Called after retention sweep removes the local file."""
        self._conn.execute(
            "UPDATE files SET inbox_path = NULL WHERE sha256 = ?",
            (sha256,),
        )

    # --- lookups -------------------------------------------------------

    def lookup_hash(self, sha256: str) -> LedgerRow | None:
        row = self._conn.execute(
            "SELECT * FROM files WHERE sha256 = ?", (sha256,)
        ).fetchone()
        return _row_to_ledger_row(row) if row else None

    def list_shoots(self) -> list[ShootSummary]:
        rows = self._conn.execute(
            """
            SELECT shoot_date,
                   COUNT(*) AS file_count,
                   GROUP_CONCAT(DISTINCT status) AS statuses
            FROM files
            GROUP BY shoot_date
            ORDER BY shoot_date DESC
            """
        ).fetchall()
        pinned_dates = self._all_pinned_dates()
        return [
            ShootSummary(
                shoot_date=date.fromisoformat(r[0]),
                file_count=r[1],
                statuses=tuple(Status(s) for s in (r[2] or "").split(",") if s),
                pinned=date.fromisoformat(r[0]) in pinned_dates,
            )
            for r in rows
        ]

    def files_for_shoot(self, shoot_date: date) -> list[LedgerRow]:
        rows = self._conn.execute(
            "SELECT * FROM files WHERE shoot_date = ? ORDER BY src_path",
            (shoot_date.isoformat(),),
        ).fetchall()
        return [_row_to_ledger_row(r) for r in rows]

    # --- pinning -------------------------------------------------------

    def pin(self, shoot_date: date) -> None:
        self._conn.execute(
            "INSERT OR REPLACE INTO pinned_shoots (shoot_date, pinned_at) VALUES (?, ?)",
            (shoot_date.isoformat(), datetime.now(timezone.utc).isoformat()),
        )

    def unpin(self, shoot_date: date) -> None:
        self._conn.execute(
            "DELETE FROM pinned_shoots WHERE shoot_date = ?",
            (shoot_date.isoformat(),),
        )

    def is_pinned(self, shoot_date: date) -> bool:
        row = self._conn.execute(
            "SELECT 1 FROM pinned_shoots WHERE shoot_date = ?",
            (shoot_date.isoformat(),),
        ).fetchone()
        return row is not None

    def _all_pinned_dates(self) -> set[date]:
        rows = self._conn.execute("SELECT shoot_date FROM pinned_shoots").fetchall()
        return {date.fromisoformat(r[0]) for r in rows}


def _row_to_ledger_row(row: tuple) -> LedgerRow:
    (
        sha256,
        src_path,
        inbox_path,
        shoot_date_s,
        status_s,
        archive_path,
        immich_asset_id,
        last_error,
        imported_at_s,
        published_at_s,
    ) = row
    return LedgerRow(
        sha256=sha256,
        src_path=src_path,
        inbox_path=inbox_path,
        shoot_date=date.fromisoformat(shoot_date_s),
        status=Status(status_s),
        archive_path=archive_path,
        immich_asset_id=immich_asset_id,
        last_error=last_error,
        imported_at=datetime.fromisoformat(imported_at_s),
        published_at=datetime.fromisoformat(published_at_s) if published_at_s else None,
    )
