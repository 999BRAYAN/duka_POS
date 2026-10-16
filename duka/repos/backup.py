"""Backup and restore.

Version 1 downloaded the browser's SQLite file. The data now lives in MySQL,
so a backup is a single JSON file holding every row of every table — portable,
readable, and independent of the MySQL version. Restore replaces the whole
database with it, in one transaction: either it all goes in or nothing changes.
"""

import json
from datetime import date, datetime

from ..db import Db, new_uuid, now
from ..errors import InvalidBackup

FORMAT = "duka_pos_backup"
VERSION = 3

# Parents before children, so a restore can insert in this order and delete in
# the reverse one.
TABLES = (
    "users",
    "categories",
    "products",
    "customers",
    "suppliers",
    "sales",
    "sale_items",
    "purchases",
    "purchase_items",
    "stock_movements",
    "credit_transactions",
    "expenses",
)


def _columns(db: Db, table: str) -> list[str]:
    """Every column a restore may write — the generated ones are computed by
    MySQL and can't be."""
    return [
        c["Field"]
        for c in db.all(f"SHOW COLUMNS FROM `{table}`")
        if "GENERATED" not in (c["Extra"] or "").upper() and "PERSISTENT" not in (c["Extra"] or "").upper()
    ]


def _plain(value):
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    return value


def export_all(db: Db) -> bytes:
    tables = {}
    # One consistent snapshot: a sale ringing up mid-export can't leave the
    # sales and their lines out of step.
    with db.tx():
        for table in TABLES:
            columns = _columns(db, table)
            order = "id"
            tables[table] = [
                {c: _plain(row[c]) for c in columns}
                for row in db.all(f"SELECT {', '.join(f'`{c}`' for c in columns)} FROM `{table}` ORDER BY {order}")
            ]
    document = {
        "format": FORMAT,
        "version": VERSION,
        "createdAt": now().isoformat(timespec="milliseconds"),
        "tables": tables,
    }
    return json.dumps(document, ensure_ascii=False).encode("utf-8")


def _parse(raw: bytes) -> dict:
    try:
        document = json.loads(raw.decode("utf-8-sig"))
    except (UnicodeDecodeError, ValueError):
        raise InvalidBackup("That file is not a duka_pos backup — nothing was restored.") from None
    if not isinstance(document, dict) or document.get("format") != FORMAT:
        raise InvalidBackup("That file is not a duka_pos backup — nothing was restored.")
    if document.get("version", 0) > VERSION:
        raise InvalidBackup("That backup was made by a newer version of duka_pos — nothing was restored.")
    tables = document.get("tables")
    if not isinstance(tables, dict) or any(not isinstance(tables.get(t), list) for t in TABLES):
        raise InvalidBackup("That backup is incomplete — nothing was restored.")
    return tables


def restore_all(db: Db, raw: bytes) -> dict:
    tables = _parse(raw)
    known = {t: _columns(db, t) for t in TABLES}

    # Validate every row's columns before touching anything.
    for table in TABLES:
        for row in tables[table]:
            if not isinstance(row, dict) or not set(row) <= set(known[table]):
                raise InvalidBackup(f"The '{table}' section of that backup has columns this version doesn't know.")

    db.execute("SET FOREIGN_KEY_CHECKS = 0")
    try:
        with db.tx():
            for table in reversed(TABLES):
                db.execute(f"DELETE FROM `{table}`")
            for table in TABLES:
                for row in tables[table]:
                    db.insert(table, row)
            seed_walk_in_customer(db)
    finally:
        db.execute("SET FOREIGN_KEY_CHECKS = 1")
    return {t: len(tables[t]) for t in TABLES}


def seed_walk_in_customer(db: Db) -> None:
    """Creates the one walk-in customer, idempotently."""
    if db.scalar("SELECT COUNT(*) FROM customers WHERE is_walk_in = 1"):
        return
    db.insert(
        "customers",
        {
            "uuid": new_uuid(),
            "name": "Walk-in Customer",
            "credit_limit": 0,
            "is_walk_in": 1,
            "created_at": now(),
        },
    )
