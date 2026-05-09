"""`photo-import sd` — copy from SD card to laptop staging."""
from __future__ import annotations

import os
import shutil
from dataclasses import dataclass, field
from pathlib import Path

from photo_import.exif import is_photo_file, should_skip, shoot_date_for
from photo_import.hashing import sha256_file, validate_jpg
from photo_import.ledger import Ledger


@dataclass
class SdReport:
    copied: int = 0
    skipped_existing: int = 0
    flagged_corrupt: int = 0
    collisions: int = 0
    errors: list[str] = field(default_factory=list)


def find_sd_card(
    search_root: Path = Path("/run/media") / os.environ.get("USER", "scott"),
) -> Path | None:
    """Return the path of the first mounted volume containing a DCIM directory, or None."""
    if not search_root.is_dir():
        return None
    candidates = [
        d for d in search_root.iterdir()
        if d.is_dir() and (d / "DCIM").is_dir()
    ]
    if len(candidates) == 1:
        return candidates[0]
    if not candidates:
        return None
    # Multiple candidates → caller must choose.
    raise RuntimeError(
        f"multiple SD cards detected at {search_root}: " + ", ".join(str(c) for c in candidates)
    )


def run_sd_import(
    source_root: Path,
    staging_root: Path,
    ledger: Ledger,
) -> SdReport:
    """Walk source_root/DCIM, copy new files into staging_root/<shoot_date>/."""
    report = SdReport()
    dcim = source_root / "DCIM"
    if not dcim.is_dir():
        # Some cards drop DCIM at root; allow source_root itself.
        dcim = source_root

    ledger.begin_immediate()
    try:
        for src in sorted(dcim.rglob("*")):
            if not src.is_file():
                continue
            if should_skip(src.relative_to(source_root)):
                continue
            if not is_photo_file(src):
                continue

            try:
                digest = sha256_file(src)
            except OSError as e:
                report.errors.append(f"hash failed for {src}: {e}")
                continue

            if ledger.lookup_hash(digest) is not None:
                report.skipped_existing += 1
                continue

            shoot_date = shoot_date_for(src)
            target_dir = staging_root / shoot_date.isoformat()
            target_dir.mkdir(parents=True, exist_ok=True)
            target = target_dir / src.name

            # Filename collision (different content, same name) → append -N
            if target.exists():
                stem, suffix = target.stem, target.suffix
                n = 1
                while True:
                    candidate = target_dir / f"{stem}-{n}{suffix}"
                    if not candidate.exists():
                        target = candidate
                        report.collisions += 1
                        break
                    n += 1

            # JPG marker check before copy — flag and skip corrupt files
            if src.suffix.lower() in (".jpg", ".jpeg"):
                if not validate_jpg(src):
                    report.flagged_corrupt += 1
                    continue

            shutil.copy2(src, target)

            # Verify by re-hashing the destination
            try:
                dest_digest = sha256_file(target)
            except OSError as e:
                report.errors.append(f"verify hash failed for {target}: {e}")
                target.unlink(missing_ok=True)
                continue
            if dest_digest != digest:
                report.errors.append(f"hash mismatch after copy: {src} -> {target}")
                target.unlink(missing_ok=True)
                continue

            ledger.insert_staged(
                sha256=digest,
                src_path=str(src),
                inbox_path=str(target),
                shoot_date=shoot_date,
            )
            report.copied += 1

        ledger.commit()
    except Exception:
        ledger.rollback()
        raise

    return report
