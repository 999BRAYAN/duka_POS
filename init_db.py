"""Creates the database and its tables, and seeds the walk-in customer.

Safe to run again: every statement is `IF NOT EXISTS`, and the seed is
idempotent. Settings come from the environment / `.env` (see config.py).

    python init_db.py
"""

import re
import sys

from duka.config import SCHEMA_FILE, settings
from duka.db import Db, connect, connect_server
from duka.repos.backup import seed_walk_in_customer


def split_statements(sql: str) -> list[str]:
    sql = re.sub(r"--[^\n]*", "", sql)
    return [s.strip() for s in sql.split(";") if s.strip()]


def init_database() -> None:
    server = connect_server()
    try:
        with server.cursor() as cur:
            cur.execute(
                f"CREATE DATABASE IF NOT EXISTS `{settings.db_name}` "
                "CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
            )
    finally:
        server.close()

    db = Db(connect())
    try:
        for statement in split_statements(SCHEMA_FILE.read_text(encoding="utf-8")):
            db.execute(statement)
        seed_walk_in_customer(db)
    finally:
        db.close()


if __name__ == "__main__":
    try:
        init_database()
    except Exception as e:  # noqa: BLE001 — a friendly message beats a traceback here
        print(f"Could not set up the database '{settings.db_name}' on {settings.db_host}:{settings.db_port}: {e}")
        print("Is MySQL running, and are DUKA_DB_USER / DUKA_DB_PASSWORD right? See .env.example.")
        sys.exit(1)
    print(f"Database '{settings.db_name}' is ready.")
