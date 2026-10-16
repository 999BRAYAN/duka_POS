"""Settings, read from the environment (and a `.env` file beside run.py).

Defaults match a stock XAMPP / local MySQL install: root, no password,
127.0.0.1:3306, a database called `duka_pos`.
"""

import os
import secrets
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB_DIR = ROOT / "web"
SCHEMA_FILE = ROOT / "schema.sql"
_ENV_FILE = ROOT / ".env"
_SECRET_FILE = ROOT / ".secret_key"


def _load_env_file() -> None:
    if not _ENV_FILE.exists():
        return
    for line in _ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


_load_env_file()


def _secret_key() -> str:
    """A signing key for session cookies — from the environment, or generated
    once and kept beside the app so sessions survive a restart."""
    from_env = os.environ.get("DUKA_SECRET_KEY")
    if from_env:
        return from_env
    if _SECRET_FILE.exists():
        return _SECRET_FILE.read_text(encoding="utf-8").strip()
    key = secrets.token_hex(32)
    _SECRET_FILE.write_text(key, encoding="utf-8")
    return key


class Settings:
    db_host = os.environ.get("DUKA_DB_HOST", "127.0.0.1")
    db_port = int(os.environ.get("DUKA_DB_PORT", "3306"))
    db_user = os.environ.get("DUKA_DB_USER", "root")
    db_password = os.environ.get("DUKA_DB_PASSWORD", "")
    db_name = os.environ.get("DUKA_DB_NAME", "duka_pos")

    host = os.environ.get("DUKA_HOST", "127.0.0.1")
    port = int(os.environ.get("DUKA_PORT", "8080"))

    @property
    def secret_key(self) -> str:
        return _secret_key()


settings = Settings()
