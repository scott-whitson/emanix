from pathlib import Path

import pytest

from photo_import.config import Config, load_config


def test_load_with_defaults(tmp_path):
    cfg_path = tmp_path / "config.toml"
    cfg_path.write_text(
        """
ssh_target = "datacore"
archive_root = "/srv/data/photo-archive/Pictures"
immich_url = "http://datacore:2283"
"""
    )
    secrets_path = tmp_path / "secrets.toml"
    secrets_path.write_text('immich_api_key = "key-abc"\n')
    secrets_path.chmod(0o600)

    cfg = load_config(cfg_path, secrets_path)
    assert cfg.ssh_target == "datacore"
    assert cfg.archive_root == "/srv/data/photo-archive/Pictures"
    assert cfg.immich_url == "http://datacore:2283"
    assert cfg.immich_api_key == "key-abc"
    assert cfg.retention_days == 30  # default
    assert cfg.staging_root == Path.home() / "downloads/camera"  # default
    assert cfg.ledger_path == Path.home() / ".local/share/photo-import/imports.sqlite"


def test_overrides_defaults(tmp_path):
    cfg_path = tmp_path / "config.toml"
    cfg_path.write_text(
        """
ssh_target = "datacore"
archive_root = "/srv/data/photo-archive/Pictures"
immich_url = "http://datacore:2283"
retention_days = 7
staging_root = "/tmp/cam"
"""
    )
    secrets_path = tmp_path / "secrets.toml"
    secrets_path.write_text('immich_api_key = "k"\n')
    secrets_path.chmod(0o600)

    cfg = load_config(cfg_path, secrets_path)
    assert cfg.retention_days == 7
    assert cfg.staging_root == Path("/tmp/cam")


def test_warns_on_loose_secrets_perms(tmp_path):
    cfg_path = tmp_path / "config.toml"
    cfg_path.write_text(
        """
ssh_target = "datacore"
archive_root = "/srv/data/photo-archive/Pictures"
immich_url = "http://datacore:2283"
"""
    )
    secrets_path = tmp_path / "secrets.toml"
    secrets_path.write_text('immich_api_key = "k"\n')
    secrets_path.chmod(0o644)

    with pytest.warns(UserWarning, match="secrets file"):
        load_config(cfg_path, secrets_path)


def test_missing_required_field_raises(tmp_path):
    cfg_path = tmp_path / "config.toml"
    cfg_path.write_text('ssh_target = "datacore"\n')  # missing fields
    secrets_path = tmp_path / "secrets.toml"
    secrets_path.write_text('immich_api_key = "k"\n')
    secrets_path.chmod(0o600)

    with pytest.raises(KeyError, match="archive_root"):
        load_config(cfg_path, secrets_path)
