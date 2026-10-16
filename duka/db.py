"""MySQL access.

One `Db` per request. Statements autocommit unless wrapped in `tx()`, and
`tx()` nests: a repository function called from inside another's transaction
simply joins it, the same way calling one Version 1 repository from another's
`db.transaction()` did. Only the outermost block commits or rolls back.
"""

import uuid as _uuid
from contextlib import contextmanager
from datetime import datetime

import pymysql
from pymysql.constants import FIELD_TYPE
from pymysql.converters import conversions

from .config import settings

# DECIMAL columns come back as plain floats: the business rules do ordinary
# arithmetic on them, and the DECIMAL(15,4) storage is what keeps the values
# from picking up floating-point noise between requests.
_conv = conversions.copy()
_conv[FIELD_TYPE.NEWDECIMAL] = float
_conv[FIELD_TYPE.DECIMAL] = float


def now() -> datetime:
    """Local wall-clock time to the millisecond — what the DATETIME(3)
    columns hold."""
    n = datetime.now()
    return n.replace(microsecond=(n.microsecond // 1000) * 1000)


def new_uuid() -> str:
    return str(_uuid.uuid4())


def r4(value: float) -> float:
    """Round to the 4 decimal places the columns store, so comparisons made in
    Python agree with what the database will hold."""
    return round(value + 0.0, 4)


def connect(database: str | None = None) -> pymysql.connections.Connection:
    return pymysql.connect(
        host=settings.db_host,
        port=settings.db_port,
        user=settings.db_user,
        password=settings.db_password,
        database=database if database is not None else settings.db_name,
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True,
        conv=_conv,
    )


class Db:
    def __init__(self, raw: pymysql.connections.Connection | None = None):
        self.raw = raw or connect()
        self._depth = 0

    # --- queries -------------------------------------------------------
    def all(self, sql: str, args=None) -> list[dict]:
        with self.raw.cursor() as cur:
            cur.execute(sql, args)
            return list(cur.fetchall())

    def one(self, sql: str, args=None) -> dict | None:
        with self.raw.cursor() as cur:
            cur.execute(sql, args)
            return cur.fetchone()

    def scalar(self, sql: str, args=None):
        row = self.one(sql, args)
        return None if row is None else next(iter(row.values()))

    def execute(self, sql: str, args=None) -> int:
        """Runs a write; returns the new AUTO_INCREMENT id for an INSERT."""
        with self.raw.cursor() as cur:
            cur.execute(sql, args)
            return cur.lastrowid

    def insert(self, table: str, values: dict) -> int:
        cols = ", ".join(f"`{c}`" for c in values)
        marks = ", ".join(["%s"] * len(values))
        return self.execute(f"INSERT INTO `{table}` ({cols}) VALUES ({marks})", list(values.values()))

    def update(self, table: str, values: dict, where: str, where_args) -> None:
        sets = ", ".join(f"`{c}` = %s" for c in values)
        self.execute(f"UPDATE `{table}` SET {sets} WHERE {where}", [*values.values(), *where_args])

    # --- transactions --------------------------------------------------
    @contextmanager
    def tx(self):
        if self._depth == 0:
            self.raw.begin()
        self._depth += 1
        try:
            yield
        except BaseException:
            self._depth -= 1
            if self._depth == 0:
                self.raw.rollback()
            raise
        else:
            self._depth -= 1
            if self._depth == 0:
                self.raw.commit()

    @contextmanager
    def named_lock(self, name: str, timeout: int = 15):
        """A server-wide mutex, for the few places (invoice numbering) where
        row locks can't express "only one of these at a time"."""
        got = self.scalar("SELECT GET_LOCK(%s, %s)", (name, timeout))
        if got != 1:
            raise RuntimeError("The till is busy finishing another sale. Try again in a moment.")
        try:
            yield
        finally:
            self.scalar("SELECT RELEASE_LOCK(%s)", (name,))

    def close(self) -> None:
        try:
            self.raw.close()
        except Exception:
            pass


def connect_server() -> pymysql.connections.Connection:
    """A connection with no database selected, for creating it."""
    return connect(database="")
