""""How many ...?" - plain counts of the things the shop keeps records of."""

import re

from .common import Ctx, answer, has, manager_only, money

_ASKS_COUNT = (r"\bhow many\b", r"\bnumber of\b", r"\bcount of\b", r"\btotal number\b", r"\b(count|tally)\b.*\b(of|the)\b")


def asks_count(q: str) -> bool:
    return has(q, *_ASKS_COUNT)


def _scope(c: Ctx):
    """(start, end, label) when the question names a period, else None for all time."""
    p = c.period
    if p.kind == "today" and not re.search(r"\btoday\b", c.q):
        return None
    return p.start, p.end, p.label


def _counted(c: Ctx, noun: str, table: str, where: str) -> dict:
    scope = _scope(c)
    sql, args = f"SELECT COUNT(*) AS n FROM {table} WHERE {where}", ()
    if scope:
        sql += " AND created_at BETWEEN %s AND %s"
        args = (scope[0], scope[1])
    n = c.db.scalar(sql, args) or 0
    when = f" {scope[2]}" if scope else " in all"
    return answer(f"{n} {noun if n != 1 else noun.rstrip('s')}{when}.")


def how_many(c: Ctx) -> dict | None:
    """The answer, or None when the question isn't a count of something known."""
    q = c.q
    if has(q, r"\bvoid(ed)?\b") and has(q, r"\bsales?\b"):
        return _counted(c, "voided sales", "sales", "status <> 'completed'")
    if has(q, r"\b(sales|sale|transactions|invoices|receipts|orders)\b") and not has(q, r"\b(items?|units|products?)\b"):
        return _counted(c, "completed sales", "sales", "status = 'completed'")
    if has(q, r"\bpurchases?\b|\bdeliver(y|ies)\b"):
        return _counted(c, "purchases", "purchases", "status <> 'cancelled'") if c.manager else manager_only("purchases")
    if has(q, r"\bexpenses?\b"):
        return _counted(c, "expenses", "expenses", "1 = 1") if c.manager else manager_only("expenses")
    if has(q, r"\b(staff|employees?|cashiers?|users?|logins?)\b") and not has(q, r"\bcustomers?\b"):
        if not c.can_see_staff:
            return manager_only("the staff list")
        n = c.db.scalar("SELECT COUNT(*) FROM users WHERE is_active = 1") or 0
        return answer(f"{n} active staff login{'s' if n != 1 else ''}.", suggestions=["Show the staff list"])
    return None
