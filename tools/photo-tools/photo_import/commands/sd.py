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

    # Second pass: XMP sidecars (e.g., IMG_0017.JPG.xmp). Each XMP belongs to a
    # parent photo (same dir, name minus the .xmp suffix). We stage the XMP in
    # the parent's shoot_date folder so it travels with its parent when publish
    # runs. We insert a ledger row for the XMP itself with status=staged so
    # publish picks up the shoot folder even when the parent is already
    # published.
    ledger.begin_immediate()
    try:
        for src in sorted(dcim.rglob("*")):
            if not src.is_file():
                continue
            if should_skip(src.relative_to(source_root)):
                continue
            if src.suffix.lower() != ".xmp":
                continue

            parent_name = src.name[:-len(".xmp")]  # IMG_0017.JPG.xmp -> IMG_0017.JPG
            parent_src = src.parent / parent_name
            if not parent_src.is_file():
                report.errors.append(f"orphan XMP (no parent on card): {src}")
                continue

            # Hash the XMP itself for dedup; if we've imported this exact XMP before,
            # skip. (XMP edits change the hash, so a different ledger row would be
            # created for an updated XMP.)
            try:
                xmp_digest = sha256_file(src)
            except OSError as e:
                report.errors.append(f"hash failed for {src}: {e}")
                continue
            if ledger.lookup_hash(xmp_digest) is not None:
                report.skipped_existing += 1
                continue

            # Look up the parent's shoot_date so we know which staging folder
            try:
                parent_digest = sha256_file(parent_src)
            except OSError as e:
                report.errors.append(f"hash failed for parent {parent_src}: {e}")
                continue
            parent_row = ledger.lookup_hash(parent_digest)
            if parent_row is None:
                report.errors.append(f"XMP parent not in ledger; skipping: {src}")
                continue
            shoot_date = parent_row.shoot_date

            target_dir = staging_root / shoot_date.isoformat()
            target_dir.mkdir(parents=True, exist_ok=True)
            target = target_dir / src.name

            if target.exists():
                # Filename collision: existing XMP in staging. Compare hashes.
                try:
                    existing_digest = sha256_file(target)
                except OSError:
                    existing_digest = None
                if existing_digest == xmp_digest:
                    report.skipped_existing += 1
                    continue
                # Different content — append -N suffix
                stem, suffix = target.stem, target.suffix
                n = 1
                while True:
                    candidate = target_dir / f"{stem}-{n}{suffix}"
                    if not candidate.exists():
                        target = candidate
                        report.collisions += 1
                        break
                    n += 1

            shutil.copy2(src, target)
            try:
                dest_digest = sha256_file(target)
            except OSError as e:
                report.errors.append(f"verify hash failed for {target}: {e}")
                target.unlink(missing_ok=True)
                continue
            if dest_digest != xmp_digest:
                report.errors.append(f"hash mismatch after copy: {src} -> {target}")
                target.unlink(missing_ok=True)
                continue

            ledger.insert_staged(
                sha256=xmp_digest,
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
