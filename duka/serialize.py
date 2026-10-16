"""Rows -> JSON-ready dicts (camelCase keys, ISO timestamps, real booleans)."""

from datetime import date, datetime


def _camel(name: str) -> str:
    head, *rest = name.split("_")
    return head + "".join(part.capitalize() for part in rest)


def _value(key: str, value):
    if isinstance(value, datetime):
        return value.isoformat(timespec="milliseconds")
    if isinstance(value, date):
        return value.isoformat()
    if key.startswith("is_"):
        return bool(value)
    return value


def row(r: dict | None, *, drop: tuple = ()) -> dict | None:
    if r is None:
        return None
    return {_camel(k): _value(k, v) for k, v in r.items() if k not in drop}


def rows(rs: list[dict], *, drop: tuple = ()) -> list[dict]:
    return [row(r, drop=drop) for r in rs]


# Never let a password hash (or the generated manager slot) reach the browser.
USER_DROP = ("password_hash", "manager_slot")


def user(r: dict | None) -> dict | None:
    return row(r, drop=USER_DROP)
