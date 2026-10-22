"""Which products sell, which lag, and what that means for buying.

Plain arithmetic over the sales the till has recorded - no outside service.
Everything is derived from completed sales and current stock, so it gets
better as history builds up and says so when there isn't enough of it yet.

For each active product:

* sales rate  - units sold per day over the look-back window (the window is
  cut short if the shop has fewer days of history than that, so a new shop
  isn't made to look slow)
* days of cover - stock / sales rate: how long today's stock lasts
* class (A/B/C) - A products bring in the first 80% of revenue, B the next
  15%, C the tail
* status - out, reorder (cover below the lead time), fast, steady, slow,
  overstocked (cover well past the target) or dead (stock but no sales)
"""

import math
from datetime import datetime, timedelta

from ..db import Db

TARGET_COVER_DAYS = 14      # how much stock a reorder should bring you up to
REORDER_COVER_DAYS = 7      # at or below this many days of cover: time to buy
OVERSTOCK_COVER_DAYS = 60   # above this many days of cover: over-bought
MIN_HISTORY_DAYS = 7        # below this, rates are too noisy to judge "slow"


def _history_days(db: Db, now: datetime, window: int) -> float:
    first = db.scalar("SELECT MIN(created_at) FROM sales WHERE status = 'completed'")
    if first is None:
        return 0.0
    days = (now - first).total_seconds() / 86400
    return max(min(days, float(window)), 0.0)


def product_insights(db: Db, *, window: int = 30, now: datetime | None = None) -> dict:
    now = now or datetime.now()
    since = now - timedelta(days=window)
    week_ago = now - timedelta(days=7)
    history = _history_days(db, now, window)
    days = max(history, 1.0)
    days7 = max(min(history, 7.0), 1.0)

    sold = {
        r["product_id"]: r
        for r in db.all(
            """
            SELECT si.product_id,
                   SUM(si.quantity) AS qty, SUM(si.total) AS revenue,
                   SUM(CASE WHEN s.created_at >= %s THEN si.quantity ELSE 0 END) AS qty7,
                   MAX(s.created_at) AS last_sale
            FROM sale_items si JOIN sales s ON s.id = si.sale_id
            WHERE s.status = 'completed' AND s.created_at >= %s
            GROUP BY si.product_id
            """,
            (week_ago, since),
        )
    }
    last_sale_ever = {
        r["product_id"]: r["last_sale"]
        for r in db.all(
            "SELECT si.product_id, MAX(s.created_at) AS last_sale FROM sale_items si "
            "JOIN sales s ON s.id = si.sale_id WHERE s.status = 'completed' GROUP BY si.product_id"
        )
    }
    products = db.all(
        "SELECT p.*, c.name AS category_name FROM products p "
        "LEFT JOIN categories c ON c.id = p.category_id WHERE p.is_active = 1"
    )

    items = []
    for p in products:
        s = sold.get(p["id"])
        qty = float(s["qty"]) if s else 0.0
        revenue = float(s["revenue"]) if s else 0.0
        rate = qty / days
        rate7 = (float(s["qty7"]) if s else 0.0) / days7
        # Next week's demand: lean on the last week, but keep the longer
        # average in the mix so one odd week doesn't swing the number.
        forecast_rate = 0.6 * rate7 + 0.4 * rate if history >= 14 else rate
        stock_qty = float(p["stock"])
        cover = stock_qty / rate if rate > 0 else None
        last = last_sale_ever.get(p["id"])
        items.append({
            "id": p["id"], "uuid": p["uuid"], "name": p["name"], "sku": p["sku"],
            "category": p["category_name"], "unit": p["unit"],
            "stock": stock_qty, "reorderLevel": float(p["reorder_level"]),
            "costPrice": float(p["cost_price"]), "sellingPrice": float(p["selling_price"]),
            "sold": qty, "revenue": revenue,
            "profit": revenue - qty * float(p["cost_price"]),
            "dailyRate": rate, "forecastNext7": forecast_rate * 7,
            "coverDays": cover,
            "daysSinceSale": (now - last).days if last else None,
            "stockValue": stock_qty * float(p["cost_price"]),
        })

    # ABC class by share of revenue.
    total_revenue = sum(i["revenue"] for i in items)
    running = 0.0
    for item in sorted(items, key=lambda i: i["revenue"], reverse=True):
        if item["revenue"] <= 0:
            item["abc"] = "-"
            continue
        prior = running / total_revenue
        running += item["revenue"]
        item["abc"] = "A" if prior < 0.80 else ("B" if prior < 0.95 else "C")

    enough = history >= MIN_HISTORY_DAYS
    for i in items:
        i["status"] = _status(i, enough)
        i["suggestedOrder"] = _suggested_order(i)
        i["excessValue"] = _excess_value(i)
    return {
        "windowDays": window,
        "historyDays": round(history, 1),
        "enoughHistory": enough,
        "products": items,
    }


def _status(i: dict, enough: bool) -> str:
    sold_any = i["sold"] > 0
    if i["sellingPrice"] <= 0 and not sold_any:
        return "supply"       # an ingredient or consumable, not sold at the till
    if i["stock"] <= 0:
        return "out"
    if not enough:
        return "new"          # not enough history to call anything slow
    if not sold_any:
        return "dead"
    if i["coverDays"] <= REORDER_COVER_DAYS:
        return "reorder"
    if i["coverDays"] > OVERSTOCK_COVER_DAYS:
        return "overstocked"
    if i["abc"] == "A":
        return "fast"
    if i["abc"] == "C":
        return "slow"
    return "steady"


def _suggested_order(i: dict) -> float:
    if i["dailyRate"] <= 0:
        return 0.0
    need = i["forecastNext7"] / 7 * TARGET_COVER_DAYS - i["stock"]
    if i["status"] not in ("reorder", "out"):
        return 0.0
    return float(math.ceil(need)) if need > 0 else 0.0


def _excess_value(i: dict) -> float:
    """Cost of the stock beyond what the target cover calls for."""
    if i["status"] == "dead":
        return i["stockValue"]
    if i["status"] == "overstocked":
        keep = i["dailyRate"] * TARGET_COVER_DAYS
        return max(i["stock"] - keep, 0.0) * i["costPrice"]
    return 0.0


def summary(data: dict) -> dict:
    items = data["products"]
    by = lambda status: [i for i in items if i["status"] == status]  # noqa: E731
    return {
        "stockValue": sum(i["stockValue"] for i in items),
        "excessValue": sum(i["excessValue"] for i in items),
        "counts": {s: len(by(s)) for s in ("fast", "steady", "slow", "overstocked", "dead", "reorder", "out", "new", "supply")},
    }
