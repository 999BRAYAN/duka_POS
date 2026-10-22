"""Shared pieces for the assistant: the question's context, answer shapes,
name matching and date-range reading."""

import difflib
import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from .. import authz, dates
from ..db import Db

STOP = {
    "the", "a", "an", "of", "for", "is", "are", "do", "we", "have", "how", "many", "much", "what", "whats", "in",
    "stock", "left", "price", "cost", "sell", "sold", "selling", "sales", "me", "my", "our", "show", "tell", "about",
    "and", "to", "on", "at", "any", "there", "i", "you", "today", "week", "month", "year", "this", "will",
    "next", "predict", "forecast", "does", "did", "can", "us", "give", "list", "all", "with", "who", "which",
    "owe", "owes", "balance", "credit", "customer", "supplier", "last", "has", "much", "been", "from", "total",
}


def money(v: float) -> str:
    return dates.fmt_amount(v or 0)


def qty(v: float) -> str:
    return f"{(v or 0):,.2f}".rstrip("0").rstrip(".")


def has(text: str, *patterns: str) -> bool:
    return any(re.search(p, text) for p in patterns)


def tokens(text: str) -> list[str]:
    out = []
    for t in re.findall(r"[a-z0-9]+", text.lower()):
        if len(t) > 3 and t.endswith("s"):
            t = t[:-1]
        out.append(t)
    return out


def table(columns: list[str], rows: list[list]) -> dict:
    return {"columns": columns, "rows": [["-" if c is None else str(c) for c in r] for r in rows]}


def answer(reply: str, tbl: dict | None = None, suggestions: list[str] | None = None) -> dict:
    return {"reply": reply, "table": tbl, "suggestions": suggestions or []}


def manager_only(label: str) -> dict:
    return answer(f"Only a manager can see {label}. Ask them, or sign in as a manager.", suggestions=["What's running low?"])


def pct(part: float, whole: float) -> str:
    return f"{part / whole * 100:.0f}%" if whole else "0%"


def when(d: datetime | None) -> str:
    return dates.fmt_date(d) if d else "never"


# --- who is asking, and what they asked -----------------------------------

@dataclass
class Ctx:
    db: Db
    user: dict
    text: str
    q: str
    now: datetime = field(default_factory=datetime.now)
    _cache: dict = field(default_factory=dict)

    @property
    def manager(self) -> bool:
        return authz.can(self.user, authz.MANAGE_PRODUCTS)

    @property
    def can_see_staff(self) -> bool:
        return authz.can(self.user, authz.MANAGE_STAFF)

    def _memo(self, key, fn):
        if key not in self._cache:
            self._cache[key] = fn()
        return self._cache[key]

    @property
    def products(self) -> list[dict]:
        return self._memo("products", lambda: self.db.all(
            "SELECT p.*, c.name AS category_name FROM products p LEFT JOIN categories c ON c.id = p.category_id WHERE p.is_active = 1"))

    @property
    def customers(self) -> list[dict]:
        return self._memo("customers", lambda: self.db.all("SELECT * FROM customers WHERE is_walk_in = 0"))

    @property
    def suppliers(self) -> list[dict]:
        return self._memo("suppliers", lambda: self.db.all("SELECT * FROM suppliers"))

    @property
    def categories(self) -> list[dict]:
        return self._memo("categories", lambda: self.db.all("SELECT * FROM categories"))

    @property
    def period(self) -> "Period":
        return self._memo("period", lambda: read_period(self.q, self.now))


# --- finding the product / customer / supplier a question names ------------

def find_named(question: str, rows: list[dict], *, min_score: float = 0.6, key: str = "name") -> list[dict]:
    """Rows whose name the question points at, best matches first (all of
    those that tie for the top score). Empty when nothing clearly matches."""
    q = question.lower()
    q_tokens = set(tokens(q))
    scored: list[tuple[float, dict]] = []
    for row in rows:
        name = str(row[key] or "").lower().strip()
        if not name:
            continue
        if len(name) > 2 and re.search(rf"\b{re.escape(name)}\b", q):
            score = 1.0 + len(name) / 100  # a longer exact name beats a shorter one inside it
        else:
            name_tokens = [t for t in tokens(name) if t not in STOP and len(t) > 1]
            if not name_tokens:
                continue
            hits = 0.0
            for t in name_tokens:
                if t in q_tokens:
                    hits += 1
                elif len(t) > 4 and difflib.get_close_matches(t, q_tokens, n=1, cutoff=0.85):
                    hits += 0.9
            score = hits / len(name_tokens)
        if score >= min_score:
            scored.append((score, row))
    if not scored:
        return []
    top = max(s for s, _ in scored)
    return [r for s, r in scored if s == top]


# --- dates -----------------------------------------------------------------

MONTHS = ("january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december")
_MONTH_RE = "|".join(m[:3] + ("(?:" + m[3:] + ")?" if len(m) > 3 else "") for m in MONTHS)


@dataclass
class Period:
    start: datetime
    end: datetime
    label: str
    kind: str                       # today, yesterday, week, month, year, days, month_name
    previous: "Period | None" = None  # the period just before, for comparisons

    @property
    def days(self) -> int:
        return max((self.end - self.start).days + 1, 1)


def _end(d: datetime) -> datetime:
    return datetime(d.year, d.month, d.day, 23, 59, 59, 999000)


def _start(d: datetime) -> datetime:
    return datetime(d.year, d.month, d.day)


def read_period(q: str, now: datetime | None = None) -> Period:
    """The date range a question talks about; "today" when it names none."""
    now = now or datetime.now()

    m = re.search(r"\b(?:last|past|previous)\s+(\d{1,3})\s+days?\b", q)
    if m:
        n = max(1, min(int(m.group(1)), 366))
        start = _start(now - timedelta(days=n - 1))
        prev_end = start - timedelta(milliseconds=1)
        prev = Period(_start(prev_end - timedelta(days=n - 1)), prev_end, f"the {n} days before", "days")
        return Period(start, _end(now), f"the last {n} days", "days", prev)

    if re.search(r"\byesterday\b", q):
        d = now - timedelta(days=1)
        return Period(_start(d), _end(d), "yesterday", "yesterday",
                      Period(_start(d - timedelta(days=1)), _end(d - timedelta(days=1)), "the day before", "yesterday"))

    if re.search(r"\blast week\b|\bprevious week\b", q):
        s, e = dates.for_period("week", now - timedelta(days=7))
        ps, pe = dates.for_period("week", now - timedelta(days=14))
        return Period(s, e, "last week", "week", Period(ps, pe, "the week before", "week"))

    if re.search(r"\blast month\b|\bprevious month\b", q):
        first = now.replace(day=1)
        s, e = dates.for_period("month", first - timedelta(days=1))
        ps, pe = dates.for_period("month", s - timedelta(days=1))
        return Period(s, e, "last month", "month", Period(ps, pe, "the month before", "month"))

    if re.search(r"\blast year\b|\bprevious year\b", q):
        s, e = dates.for_period("year", now.replace(year=now.year - 1, day=min(now.day, 28)))
        ps, pe = dates.for_period("year", now.replace(year=now.year - 2, day=min(now.day, 28)))
        return Period(s, e, "last year", "year", Period(ps, pe, "the year before", "year"))

    m = re.search(rf"\b(?:in|for|during|of)\s+({_MONTH_RE})\b", q)
    if m:
        idx = next(i for i, name in enumerate(MONTHS) if name.startswith(m.group(1)[:3]))
        year = now.year if idx + 1 <= now.month else now.year - 1
        s, e = dates.for_period("month", datetime(year, idx + 1, 1))
        return Period(s, e, f"{MONTHS[idx].capitalize()} {year}", "month_name")

    for kind, pattern, label in (
        ("year", r"\byear\b|\bannual", "this year"),
        ("month", r"\bmonth", "this month"),
        ("week", r"\bweek", "this week"),
    ):
        if re.search(pattern, q):
            s, e = dates.for_period(kind, now)
            if kind == "week":
                ps, pe = dates.for_period("week", now - timedelta(days=7))
                prev = Period(ps, pe, "last week", "week")
            elif kind == "month":
                ps, pe = dates.for_period("month", now.replace(day=1) - timedelta(days=1))
                prev = Period(ps, pe, "last month", "month")
            else:
                ps, pe = dates.for_period("year", now.replace(year=now.year - 1, day=min(now.day, 28)))
                prev = Period(ps, pe, "last year", "year")
            return Period(s, e, label, kind, prev)

    s, e = dates.for_period("today", now)
    y = now - timedelta(days=1)
    return Period(s, e, "today", "today", Period(_start(y), _end(y), "yesterday", "yesterday"))


_EXPLICIT = re.compile(
    r"\b(today|yesterday|week|month|year|(?:last|past|previous)\s+\d{1,3}\s+days?|(?:in|for|during|of)\s+(?:" + _MONTH_RE + r"))\b")


def read_two_periods(q: str, now: datetime | None = None) -> tuple[Period, Period] | None:
    """"this week vs last week", "today with yesterday": both sides named."""
    parts = re.split(r"\b(?:with|vs\.?|versus|and|to|against|than|compared\s+(?:to|with)|from)\b", q, maxsplit=1)
    if len(parts) == 2 and _EXPLICIT.search(parts[0]) and _EXPLICIT.search(parts[1]):
        a, b = read_period(parts[0], now), read_period(parts[1], now)
        if (a.start, a.end) != (b.start, b.end):
            return a, b
    return None
