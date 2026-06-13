import pytest

from photo_import.cli import build_parser


def test_parser_has_subcommands():
    p = build_parser()
    args = p.parse_args(["sd"])
    assert args.command == "sd"
    args = p.parse_args(["publish"])
    assert args.command == "publish"
    assert args.shoot_date is None
    args = p.parse_args(["publish", "2026-05-08"])
    assert args.command == "publish"
    assert args.shoot_date == "2026-05-08"
    args = p.parse_args(["index"])
    assert args.command == "index"
    args = p.parse_args(["status"])
    assert args.command == "status"
    args = p.parse_args(["pin", "2026-05-08"])
    assert args.command == "pin"
    assert args.shoot_date == "2026-05-08"
    args = p.parse_args(["unpin", "2026-05-08"])
    assert args.command == "unpin"


def test_sd_accepts_source_override():
    p = build_parser()
    args = p.parse_args(["sd", "--source", "/mnt/foo"])
    assert args.source == "/mnt/foo"
