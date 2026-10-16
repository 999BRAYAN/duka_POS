"""Sales, profit & loss, inventory and dashboard figures.

Every query takes its date range from `dates.for_period`, and every sales
figure counts completed sales only — a void sale contributes to nothing.
SUM and AVG are NULL over an empty group, so each is coalesced to 0: a period
with no activity reads as all zeros rather than blank.
"""

from datetime import datetime, timedelta

from ..db import Db
from . import customers, stock

MOVEMENT_TYPE_ORDER = ("PURCHASE", "SALE", "RETURN", "ADJUSTMENT")


def sales_report(db: Db, start: datetime, end: datetime) -> dict:
    summary = db.one(
        "SELECT SUM(total) AS total_revenue, COUNT(*) AS sale_count, AVG(total) AS average_sale "
        "FROM sales WHERE status = 'completed' AND created_at BETWEEN %s AND %s",
        (start, end),
    )
    breakdown = db.all(
        """
        SELECT p.id AS product_id, p.name AS product_name,
               SUM(si.quantity) AS quantity_sold, SUM(si.total) AS revenue
        FROM sale_items si
        JOIN sales s ON s.id = si.sale_id
        JOIN products p ON p.id = si.product_id
        WHERE s.status = 'completed' AND s.created_at BETWEEN %s AND %s
        GROUP BY p.id, p.name
        ORDER BY revenue DESC
        """,
        (start, end),
    )
    return {
        "totalRevenue": summary["total_revenue"] or 0.0,
        "saleCount": int(summary["sale_count"] or 0),
        "averageSaleValue": summary["average_sale"] or 0.0,
        "productBreakdown": [
            {
                "productId": r["product_id"],
                "productName": r["product_name"],
                "quantitySold": r["quantity_sold"],
                "revenue": r["revenue"],
            }
            for r in breakdown
        ],
    }


def profit_and_loss_report(db: Db, start: datetime, end: datetime) -> dict:
    sales = db.one(
        "SELECT SUM(subtotal) AS subtotal, SUM(discount) AS discount, SUM(cogs) AS cogs "
        "FROM sales WHERE status = 'completed' AND created_at BETWEEN %s AND %s",
        (start, end),
    )
    expenses = db.scalar("SELECT SUM(amount) FROM expenses WHERE created_at BETWEEN %s AND %s", (start, end))

    subtotal = sales["subtotal"] or 0.0
    discount = sales["discount"] or 0.0
    cogs = sales["cogs"] or 0.0
    expenses = expenses or 0.0
    net_revenue = subtotal - discount
    gross_profit = net_revenue - cogs
    return {
        "subtotal": subtotal,
        "discount": discount,
        "cogs": cogs,
        "expenses": expenses,
        "netRevenue": net_revenue,
        "grossProfit": gross_profit,
        "netProfit": gross_profit - expenses,
    }


def inventory_report(db: Db, start: datetime, end: datetime) -> dict:
    # stockLevels is a snapshot of stock right now, not scoped to the range —
    # it reuses the stock valuation view verbatim.
    rows = db.all(
        "SELECT type, SUM(quantity) AS total_quantity FROM stock_movements "
        "WHERE created_at BETWEEN %s AND %s GROUP BY type",
        (start, end),
    )
    return {
        "stockLevels": stock.stock_valuation(db),
        "movementSummary": [{"type": r["type"], "totalQuantity": r["total_quantity"] or 0.0} for r in rows],
    }


def dashboard(db: Db, today: datetime | None = None) -> dict:
    """Today's headline numbers plus revenue for each of the last 7 days."""
    from ..dates import for_period

    today = today or datetime.now()
    start, end = for_period("today", today)
    sales = sales_report(db, start, end)
    pnl = profit_and_loss_report(db, start, end)

    low_stock = sum(1 for level in stock.stock_valuation(db) if level["isLowStock"])
    credit_outstanding = db.scalar("SELECT SUM(current_balance) FROM customers WHERE current_balance > 0") or 0.0

    first_day = (today - timedelta(days=6)).date()
    window_start = datetime(first_day.year, first_day.month, first_day.day)
    per_day = {
        r["day"]: r["revenue"]
        for r in db.all(
            "SELECT DATE(created_at) AS day, SUM(total) AS revenue FROM sales "
            "WHERE status = 'completed' AND created_at BETWEEN %s AND %s GROUP BY DATE(created_at)",
            (window_start, end),
        )
    }
    trend = []
    for days_ago in range(6, -1, -1):
        day = (today - timedelta(days=days_ago)).date()
        trend.append({"date": day.isoformat(), "revenue": per_day.get(day, 0.0) or 0.0})

    return {
        "todayRevenue": sales["totalRevenue"],
        "todayNetProfit": pnl["netProfit"],
        "lowStockCount": low_stock,
        "creditOutstanding": credit_outstanding,
        "revenueTrend": trend,
    }
