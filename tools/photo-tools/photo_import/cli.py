"""argparse dispatcher for photo-import."""
from __future__ import annotations

import argparse
import sys
from datetime import date
from pathlib import Path

from photo_import import __version__
from photo_import.commands.index import run_index
from photo_import.commands.publish import PublishError, run_publish
from photo_import.commands.retention import sweep_staging
from photo_import.commands.sd import find_sd_card, run_sd_import
from photo_import.commands.status import build_status, format_status
from photo_import.config import Config, load_config
from photo_import.immich import ImmichClient
from photo_import.ledger import Ledger
from photo_import.transport import Transport


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="photo-import",
        description="Import camera photos into datacore archive + Immich.",
    )
    p.add_argument("--version", action="version", version=__version__)
    sub = p.add_subparsers(dest="command", required=True)

    sd = sub.add_parser("sd", help="Copy from SD card to laptop staging.")
    sd.add_argument("--source", help="Override SD card path (default: auto-detect).", default=None)

    pub = sub.add_parser("publish", help="Push a staged shoot to datacore + Immich.")
    pub.add_argument("shoot_date", nargs="?", default=None,
                     help="Shoot date YYYY-MM-DD; default: every staged shoot.")

    sub.add_parser("index", help="Bootstrap ledger from datacore archive.")
    sub.add_parser("status", help="Show staged/published shoots and reachability.")
    pin = sub.add_parser("pin", help="Pin a shoot to skip retention sweep.")
    pin.add_argument("shoot_date")
    unpin = sub.add_parser("unpin", help="Unpin a previously-pinned shoot.")
    unpin.add_argument("shoot_date")
    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    cfg = load_config()
    transport = Transport(cfg.ssh_target)
    immich = ImmichClient(cfg.immich_url, cfg.immich_api_key)

    if args.command == "sd":
        return _cmd_sd(args, cfg)
    if args.command == "publish":
        return _cmd_publish(args, cfg, transport, immich)
    if args.command == "index":
        return _cmd_index(cfg, transport)
    if args.command == "status":
        return _cmd_status(cfg, transport, immich)
    if args.command in ("pin", "unpin"):
        return _cmd_pin(args, cfg)
    parser.error(f"unknown command {args.command}")
    return 2


def _cmd_sd(args, cfg: Config) -> int:
    if args.source:
        sd_root = Path(args.source).expanduser()
    else:
        try:
            sd_root = find_sd_card()
        except RuntimeError as e:
            print(f"error: {e}", file=sys.stderr)
            return 1
        if sd_root is None:
            print("no SD card found under /run/media/$USER/. Pass --source <path> if mounted elsewhere.", file=sys.stderr)
            return 1
    print(f"importing from {sd_root}")
    with Ledger.open(cfg.ledger_path) as ledger:
        report = run_sd_import(
            source_root=sd_root,
            staging_root=cfg.staging_root,
            ledger=ledger,
        )
    print(f"copied: {report.copied}, skipped (already known): {report.skipped_existing}, "
          f"flagged corrupt: {report.flagged_corrupt}, collisions: {report.collisions}")
    if report.errors:
        print("errors:")
        for e in report.errors:
            print(f"  {e}")
    return 0


def _cmd_publish(args, cfg: Config, transport: Transport, immich: ImmichClient) -> int:
    with Ledger.open(cfg.ledger_path) as ledger:
        if args.shoot_date:
            dates = [date.fromisoformat(args.shoot_date)]
        else:
            dates = [s.shoot_date for s in ledger.list_shoots()
                     if any(r.status.value == "staged" for r in ledger.files_for_shoot(s.shoot_date))]
        if not dates:
            print("no staged shoots to publish")
            return 0
        any_failure = False
        for d in dates:
            print(f"publishing {d.isoformat()}")
            try:
                report = run_publish(
                    shoot_date=d,
                    staging_root=cfg.staging_root,
                    archive_root=cfg.archive_root,
                    transport=transport,
                    immich=immich,
                    ledger=ledger,
                )
            except PublishError as e:
                print(f"  FAILED: {e}", file=sys.stderr)
                any_failure = True
                continue
            print(f"  archived: {report.archived}, uploaded: {report.uploaded}")
            if report.errors:
                any_failure = True
                for err in report.errors:
                    print(f"  warn: {err}")
        # Retention sweep at the end
        sw = sweep_staging(cfg.staging_root, ledger, cfg.retention_days)
        print(f"retention sweep: removed {sw.removed} shoot folder(s), kept {sw.kept}")
    return 1 if any_failure else 0


def _cmd_index(cfg: Config, transport: Transport) -> int:
    print(f"indexing {cfg.archive_root} via {cfg.ssh_target} (this can take a while)")
    with Ledger.open(cfg.ledger_path) as ledger:
        report = run_index(transport=transport, archive_root=cfg.archive_root, ledger=ledger)
    print(f"indexed: {report.indexed}, already known: {report.already_known}")
    if report.errors:
        for e in report.errors:
            print(f"  warn: {e}")
    return 0


def _cmd_status(cfg: Config, transport: Transport, immich: ImmichClient) -> int:
    with Ledger.open(cfg.ledger_path) as ledger:
        rpt = build_status(
            staging_root=cfg.staging_root,
            ledger=ledger,
            transport=transport,
            immich=immich,
            ssh_target=cfg.ssh_target,
            immich_url=cfg.immich_url,
            retention_days=cfg.retention_days,
        )
    print(format_status(rpt))
    return 0


def _cmd_pin(args, cfg: Config) -> int:
    d = date.fromisoformat(args.shoot_date)
    with Ledger.open(cfg.ledger_path) as ledger:
        if args.command == "pin":
            ledger.pin(d)
            print(f"pinned {d.isoformat()}")
        else:
            ledger.unpin(d)
            print(f"unpinned {d.isoformat()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
