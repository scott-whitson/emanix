"""Load configuration and secrets from XDG-correct TOML files."""
from __future__ import annotations

import os
import stat
import tomllib
import warnings
from dataclasses import dataclass
from pathlib import Path

DEFAULT_CONFIG_PATH = Path.home() / ".config/photo-import/config.toml"
DEFAULT_SECRETS_PATH = Path.home() / ".config/photo-import/secrets.toml"
DEFAULT_STAGING_ROOT = Path.home() / "downloads/camera"
DEFAULT_LEDGER_PATH = Path.home() / ".local/share/photo-import/imports.sqlite"
DEFAULT_LOG_PATH = Path.home() / ".local/share/photo-import/photo-import.log"
DEFAULT_RETENTION_DAYS = 30


@dataclass(frozen=True)
class Config:
    ssh_target: str
    archive_root: str
    immich_url: str
    immich_api_key: str
    staging_root: Path
    ledger_path: Path
    log_path: Path
    retention_days: int


def load_config(
    config_path: Path = DEFAULT_CONFIG_PATH,
    secrets_path: Path = DEFAULT_SECRETS_PATH,
) -> Config:
    if not config_path.is_file():
        raise FileNotFoundError(f"config file not found: {config_path}")
    if not secrets_path.is_file():
        raise FileNotFoundError(f"secrets file not found: {secrets_path}")

    _check_secrets_permissions(secrets_path)

    with open(config_path, "rb") as f:
        cfg = tomllib.load(f)
    with open(secrets_path, "rb") as f:
        secrets = tomllib.load(f)

    required = ("ssh_target", "archive_root", "immich_url")
    for k in required:
        if k not in cfg:
            raise KeyError(f"config missing required field: {k}")
    if "immich_api_key" not in secrets:
        raise KeyError("secrets missing required field: immich_api_key")

    staging_root = Path(cfg.get("staging_root", DEFAULT_STAGING_ROOT)).expanduser()
    ledger_path = Path(cfg.get("ledger_path", DEFAULT_LEDGER_PATH)).expanduser()
    log_path = Path(cfg.get("log_path", DEFAULT_LOG_PATH)).expanduser()

    return Config(
        ssh_target=cfg["ssh_target"],
        archive_root=cfg["archive_root"],
        immich_url=cfg["immich_url"],
        immich_api_key=secrets["immich_api_key"],
        staging_root=staging_root,
        ledger_path=ledger_path,
        log_path=log_path,
        retention_days=int(cfg.get("retention_days", DEFAULT_RETENTION_DAYS)),
    )


def _check_secrets_permissions(path: Path) -> None:
    mode = path.stat().st_mode
    other_or_group_readable = mode & (stat.S_IRGRP | stat.S_IROTH | stat.S_IWGRP | stat.S_IWOTH)
    if other_or_group_readable:
        warnings.warn(
            f"secrets file {path} is group/world readable (mode {oct(mode & 0o777)}); "
            "should be 0600. Run: chmod 600 " + str(path),
            UserWarning,
            stacklevel=3,
        )
