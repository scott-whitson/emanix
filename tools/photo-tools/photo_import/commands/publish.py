"""`photo-import publish` — push a staged shoot to datacore + Immich."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from pathlib import Path

from photo_import.hashing import sha256_file
from photo_import.immich import ImmichClient, ImmichError
from photo_import.ledger import Ledger
from photo_import.transport import Transport, TransportError


class PublishError(RuntimeError):
    pass


@dataclass
class PublishReport:
    archived: int = 0
    uploaded: int = 0
    errors: list[str] = field(default_factory=list)


def archive_path_for(archive_root: str, shoot_date: date) -> str:
    """Compute /srv/data/photo-archive/Pictures/<year>/<YYYY-MM-DD>."""
    return f"{archive_root.rstrip('/')}/{shoot_date.year}/{shoot_date.isoformat()}"


def run_publish(
    shoot_date: date,
    staging_root: Path,
    archive_root: str,
    transport: Transport,
    immich: ImmichClient,
    ledger: Ledger,
) -> PublishReport:
    report = PublishReport()
    shoot_dir = staging_root / shoot_date.isoformat()
    if not shoot_dir.is_dir():
        raise PublishError(f"no staged shoot at {shoot_dir}")

    # ── Pre-flight ─────────────────────────────────────────────────────
    if not transport.ssh_probe():
        raise PublishError(f"ssh to {transport.ssh_target} unreachable")
    if not immich.probe():
        raise PublishError(f"immich at {immich.url} unreachable")

    # ── Compute local hashes (used for verification + ledger keys) ─────
    local_hashes: dict[str, str] = {}
    for f in sorted(shoot_dir.iterdir()):
        if not f.is_file():
            continue
        local_hashes[f.name] = sha256_file(f)
    if not local_hashes:
        raise PublishError(f"shoot directory is empty: {shoot_dir}")

    # ── Archive push ───────────────────────────────────────────────────
    remote_dir = archive_path_for(archive_root, shoot_date)
    try:
        transport.remote_mkdir(remote_dir)
        transport.rsync_push(shoot_dir, remote_dir)
    except TransportError as e:
        ledger.begin_immediate()
        try:
            for digest in local_hashes.values():
                ledger.mark_archive_failed(digest, error=str(e))
            ledger.commit()
        except Exception:
            ledger.rollback()
            raise
        raise PublishError(f"rsync push failed: {e}") from e

    # ── Verify remote hashes match local ───────────────────────────────
    try:
        remote_hashes = transport.remote_sha256(remote_dir)
    except TransportError as e:
        ledger.begin_immediate()
        try:
            for digest in local_hashes.values():
                ledger.mark_archive_failed(digest, error=f"remote sha256: {e}")
            ledger.commit()
        except Exception:
            ledger.rollback()
            raise
        raise PublishError(f"remote sha256 failed: {e}") from e

    mismatches = []
    for name, local_hash in local_hashes.items():
        if remote_hashes.get(name) != local_hash:
            mismatches.append(name)
    if mismatches:
        ledger.begin_immediate()
        try:
            for name in mismatches:
                ledger.mark_archive_failed(local_hashes[name], error="hash mismatch after rsync")
            ledger.commit()
        except Exception:
            ledger.rollback()
            raise
        raise PublishError(f"hash mismatch on datacore for: {', '.join(mismatches)}")

    # Archive verified — record archive_path in ledger
    archive_paths = {name: f"{remote_dir}/{name}" for name in local_hashes}
    report.archived = len(local_hashes)

    # ── Immich upload ──────────────────────────────────────────────────
    try:
        immich.upload_directory(shoot_dir)
    except ImmichError as e:
        # Archive succeeded; mark immich-failed and record archive_path in the same update.
        ledger.begin_immediate()
        try:
            for name, digest in local_hashes.items():
                ledger.mark_immich_failed(digest, archive_path=archive_paths[name], error=str(e))
            ledger.commit()
        except Exception:
            ledger.rollback()
            raise
        report.errors.append(f"immich upload failed: {e}")
        return report

    # ── All-good ledger update ─────────────────────────────────────────
    ledger.begin_immediate()
    try:
        for name, digest in local_hashes.items():
            # immich-go does not currently surface per-asset IDs; pass None.
            ledger.mark_published(
                sha256=digest,
                archive_path=archive_paths[name],
                immich_asset_id=None,
            )
        ledger.commit()
    except Exception:
        ledger.rollback()
        raise
    report.uploaded = len(local_hashes)
    return report
