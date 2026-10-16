"""Report date ranges.

Every report and dashboard query takes its boundaries from `for_period` so a
boundary day (a Sunday, say) can never land in two adjacent periods when
different call sites compute their own start/end.
"""

from datetime import date, datetime, timedelta

PERIODS = ("today", "week", "month", "year")

_MONTHS = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")


def _end_of_day(day: date) -> datetime:
    return datetime(day.year, day.month, day.day, 23, 59, 59, 999000)


def _start_of_day(day: date) -> datetime:
    return datetime(day.year, day.month, day.day)


def for_period(period: str, reference: datetime | None = None) -> tuple[datetime, datetime]:
    """`(start, end)` — start at 00:00:00.000, end at 23:59:59.999.

    Weeks run Monday–Sunday. Month-end uses "day zero of next month"."""
    now = reference or datetime.now()
    today = date(now.year, now.month, now.day)

    if period == "today":
        return _start_of_day(today), _end_of_day(today)
    if period == "week":
        start = today - timedelta(days=today.weekday())
        return _start_of_day(start), _end_of_day(start + timedelta(days=6))
    if period == "month":
        start = today.replace(day=1)
        next_month = date(today.year + (today.month == 12), today.month % 12 + 1, 1)
        return _start_of_day(start), _end_of_day(next_month - timedelta(days=1))
    if period == "year":
        return _start_of_day(date(today.year, 1, 1)), _end_of_day(date(today.year, 12, 31))
    raise ValueError(f"Unknown period {period!r}")


# --- formatting (the shapes Version 1's intl formats produced) -------------

def fmt_amount(value: float) -> str:
    """`#,##0.00`"""
    return f"{value:,.2f}"


def fmt_date(d: datetime) -> str:
    """`d MMM yyyy`"""
    return f"{d.day} {_MONTHS[d.month - 1]} {d.year}"


def fmt_datetime(d: datetime) -> str:
    """`d MMM yyyy, HH:mm`"""
    return f"{d.day} {_MONTHS[d.month - 1]} {d.year}, {d:%H:%M}"
