"""Answers about sales, takings, profit and expenses. All of these are manager
questions, the same people who may open Dashboard and Reports."""

from datetime import timedelta

from ..repos import insights, reports
from .common import Ctx, answer, has, manager_only, money, pct, qty, read_two_periods, table, when

HELP_MONEY = "sales for any day/week/month, comparisons, takings by cash/M-Pesa/card, profit, expenses, busiest times"


def _sales_row(c: Ctx, start, end) -> dict:
    return reports.sales_report(c.db, start, end)


def sales(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("sales figures")
    p = c.period
    r = _sales_row(c, p.start, p.end)
    if r["saleCount"] == 0:
        return answer(f"No completed sales {p.label}.", suggestions=["How are sales this week?"])
    top = r["productBreakdown"][:5]
    return answer(
        f"Sales {p.label}: {money(r['totalRevenue'])} from {r['saleCount']} sale{'s' if r['saleCount'] != 1 else ''} "
        f"(average {money(r['averageSaleValue'])}).",
        table(["Top products", "Sold", "Revenue"], [[t["productName"], qty(t["quantitySold"]), money(t["revenue"])] for t in top]),
        ["How much profit did we make?", "Compare with the previous period", "How much did we take in cash, M-Pesa and card?"],
    )


def compare(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("sales figures")
    two = read_two_periods(c.q, c.now)
    p, prev = two if two else (c.period, c.period.previous)
    if prev is None:
        return answer("Say which period to compare, for example \"compare this week with last week\".")
    now = _sales_row(c, p.start, p.end)
    before = _sales_row(c, prev.start, prev.end)
    pnl_now = reports.profit_and_loss_report(c.db, p.start, p.end)
    pnl_before = reports.profit_and_loss_report(c.db, prev.start, prev.end)

    def change(a: float, b: float) -> str:
        if not b:
            return "new" if a else "-"
        d = (a - b) / b * 100
        return f"{'+' if d >= 0 else ''}{d:.0f}%"

    rows = [
        ["Sales", money(now["totalRevenue"]), money(before["totalRevenue"]), change(now["totalRevenue"], before["totalRevenue"])],
        ["Number of sales", now["saleCount"], before["saleCount"], change(now["saleCount"], before["saleCount"])],
        ["Gross profit", money(pnl_now["grossProfit"]), money(pnl_before["grossProfit"]), change(pnl_now["grossProfit"], pnl_before["grossProfit"])],
        ["Expenses", money(pnl_now["expenses"]), money(pnl_before["expenses"]), change(pnl_now["expenses"], pnl_before["expenses"])],
        ["Net profit", money(pnl_now["netProfit"]), money(pnl_before["netProfit"]), change(pnl_now["netProfit"], pnl_before["netProfit"])],
    ]
    direction = "up" if now["totalRevenue"] > before["totalRevenue"] else ("down" if now["totalRevenue"] < before["totalRevenue"] else "level")
    tail = "" if p.kind in ("week", "month", "year", "days") else " (a part-finished period is naturally lower)"
    return answer(f"Sales {p.label} are {direction} on {prev.label}{tail}.",
                  table(["", p.label.capitalize(), prev.label.capitalize(), "Change"], rows))


def collections(c: Ctx) -> dict:
    """Money actually taken in, by how it was paid - including credit paid off."""
    if not c.manager:
        return manager_only("takings")
    p = c.period
    # A later customer payment also raises sales.amount_paid, so what was paid
    # at the till is the sale's total less the credit charge it left behind.
    sold = c.db.all(
        "SELECT s.payment_method AS m, SUM(s.total - COALESCE(ch.amt, 0)) AS paid, SUM(COALESCE(ch.amt, 0)) AS owed "
        "FROM sales s LEFT JOIN (SELECT sale_id, SUM(amount) AS amt FROM credit_transactions WHERE type = 'CHARGE' GROUP BY sale_id) ch "
        "ON ch.sale_id = s.id WHERE s.status = 'completed' AND s.created_at BETWEEN %s AND %s GROUP BY s.payment_method",
        (p.start, p.end))
    repaid = c.db.all(
        "SELECT COALESCE(method, 'other') AS m, SUM(amount) AS paid FROM credit_transactions "
        "WHERE type = 'PAYMENT' AND created_at BETWEEN %s AND %s GROUP BY method", (p.start, p.end))
    by: dict[str, float] = {}
    for r in sold:
        by[r["m"]] = by.get(r["m"], 0) + (r["paid"] or 0)
    repaid_total = 0.0
    for r in repaid:
        by[r["m"]] = by.get(r["m"], 0) + (r["paid"] or 0)
        repaid_total += r["paid"] or 0
    left_on_credit = sum(r["owed"] or 0 for r in sold)
    by = {k: v for k, v in by.items() if v}
    if not by and not left_on_credit:
        return answer(f"No money came in {p.label}.")
    total = sum(by.values())
    rows = [[k.capitalize() if k != "mpesa" else "M-Pesa", money(v), pct(v, total)] for k, v in sorted(by.items(), key=lambda kv: -kv[1])]
    text = f"Money received {p.label}: {money(total)}"
    if repaid_total:
        text += f" (including {money(repaid_total)} of customer credit paid off)"
    text += f". {money(left_on_credit)} of the sales were put on credit." if left_on_credit else "."
    return answer(text, table(["Paid by", "Amount", "Share"], rows), ["Who owes us money?"])


def by_cashier(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("sales by cashier")
    p = c.period
    rows = c.db.all(
        "SELECT u.full_name, COUNT(*) AS n, SUM(s.total) AS total FROM sales s JOIN users u ON u.id = s.user_id "
        "WHERE s.status = 'completed' AND s.created_at BETWEEN %s AND %s GROUP BY u.id, u.full_name ORDER BY total DESC", (p.start, p.end))
    if not rows:
        return answer(f"No completed sales {p.label}.")
    return answer(f"Sales by person {p.label}:", table(["Who", "Sales", "Total"], [[r["full_name"], r["n"], money(r["total"])] for r in rows]))


def biggest_sales(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("sales figures")
    p = c.period
    rows = c.db.all(
        "SELECT s.invoice_number, s.created_at, s.total, s.payment_method, COALESCE(cu.name, 'Walk-in') AS customer FROM sales s "
        "LEFT JOIN customers cu ON cu.id = s.customer_id WHERE s.status = 'completed' AND s.created_at BETWEEN %s AND %s "
        "ORDER BY s.total DESC LIMIT 5", (p.start, p.end))
    if not rows:
        return answer(f"No completed sales {p.label}.")
    return answer(f"Biggest sales {p.label}:", table(["Invoice", "When", "Customer", "Total"],
                  [[r["invoice_number"], when(r["created_at"]), r["customer"], money(r["total"])] for r in rows]))


def recent_sales(c: Ctx) -> dict:
    rows = c.db.all(
        "SELECT s.invoice_number, s.created_at, s.total, s.status, COALESCE(cu.name, 'Walk-in') AS customer FROM sales s "
        "LEFT JOIN customers cu ON cu.id = s.customer_id ORDER BY s.created_at DESC, s.id DESC LIMIT 10")
    if not rows:
        return answer("There are no sales yet.")
    return answer("The latest sales:", table(["Invoice", "When", "Customer", "Total", "Status"],
                  [[r["invoice_number"], when(r["created_at"]), r["customer"], money(r["total"]), r["status"]] for r in rows]),
                  ["Which sales were voided?"])


def voided(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("voided sales")
    p = c.period
    rows = c.db.all(
        "SELECT s.invoice_number, s.created_at, s.total, s.void_reason, u.full_name FROM sales s "
        "LEFT JOIN users u ON u.id = s.voided_by_user_id WHERE s.status <> 'completed' AND s.created_at BETWEEN %s AND %s "
        "ORDER BY s.created_at DESC LIMIT 20", (p.start, p.end))
    if not rows:
        return answer(f"No sales were voided {p.label}.")
    return answer(f"{len(rows)} voided sale{'s' if len(rows) != 1 else ''} {p.label}, worth {money(sum(r['total'] for r in rows))}:",
                  table(["Invoice", "When", "Total", "Voided by", "Reason"], [[r["invoice_number"], when(r["created_at"]), money(r["total"]), r["full_name"] or "-", r["void_reason"] or ""] for r in rows]))


def busiest(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("sales patterns")
    since = c.now.replace(hour=0, minute=0, second=0, microsecond=0)
    since -= timedelta(days=90)
    days = c.db.all(
        "SELECT DAYOFWEEK(created_at) AS d, COUNT(*) AS n, SUM(total) AS total FROM sales "
        "WHERE status = 'completed' AND created_at >= %s GROUP BY d", (since,))
    hours = c.db.all(
        "SELECT HOUR(created_at) AS h, COUNT(*) AS n FROM sales WHERE status = 'completed' AND created_at >= %s GROUP BY h ORDER BY n DESC LIMIT 3", (since,))
    if not days:
        return answer("There are no sales in the last 90 days to learn from.")
    names = {1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday", 5: "Thursday", 6: "Friday", 7: "Saturday"}
    days.sort(key=lambda r: r["total"] or 0, reverse=True)
    busy_hours = ", ".join(f"{r['h']:02d}:00-{(r['h'] + 1) % 24:02d}:00" for r in hours)
    return answer(f"Over the last 90 days your best day is {names[days[0]['d']]}. The busiest hours are {busy_hours}.",
                  table(["Day", "Sales", "Takings"], [[names[r["d"]], r["n"], money(r["total"])] for r in days]))


def profit(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("profit")
    p = c.period
    r = reports.profit_and_loss_report(c.db, p.start, p.end)
    margin = pct(r["grossProfit"], r["netRevenue"])
    return answer(
        f"Profit {p.label}: net revenue {money(r['netRevenue'])}, minus cost of goods {money(r['cogs'])} gives gross profit "
        f"{money(r['grossProfit'])} ({margin} margin). After expenses of {money(r['expenses'])}, net profit is {money(r['netProfit'])}.",
        suggestions=["What did we spend this month?", "Compare with the previous period"],
    )


def expenses(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("expenses")
    p = c.period
    rows = c.db.all(
        "SELECT category, SUM(amount) AS total, COUNT(*) AS n FROM expenses WHERE created_at BETWEEN %s AND %s GROUP BY category ORDER BY total DESC",
        (p.start, p.end))
    if not rows:
        return answer(f"No expenses recorded {p.label}.")
    total = sum(r["total"] for r in rows)
    biggest = c.db.one("SELECT category, description, amount FROM expenses WHERE created_at BETWEEN %s AND %s ORDER BY amount DESC LIMIT 1", (p.start, p.end))
    text = f"Expenses {p.label}: {money(total)}. Biggest single expense: {biggest['description']} ({biggest['category']}) at {money(biggest['amount'])}."
    return answer(text, table(["Category", "Amount", "Share"], [[r["category"], money(r["total"]), pct(r["total"], total)] for r in rows]),
                  ["How much profit did we make?"])


def recent_expenses(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("expenses")
    rows = c.db.all("SELECT created_at, category, description, amount FROM expenses ORDER BY created_at DESC, id DESC LIMIT 10")
    if not rows:
        return answer("No expenses recorded yet.")
    return answer("The latest expenses:", table(["When", "Category", "What", "Amount"],
                  [[when(r["created_at"]), r["category"], r["description"], money(r["amount"])] for r in rows]))


def briefing(c: Ctx) -> dict:
    """A one-glance summary of the shop right now."""
    owed = c.db.scalar("SELECT SUM(current_balance) FROM customers WHERE current_balance > 0") or 0
    levels = c.db.all("SELECT stock, reorder_level FROM products WHERE is_active = 1")
    low = sum(1 for l in levels if 0 < l["stock"] <= l["reorder_level"])
    out = sum(1 for l in levels if l["stock"] <= 0)
    if not c.manager:
        return answer(f"Right now {out} product{'s are' if out != 1 else ' is'} out of stock and {low} running low. Customers owe {money(owed)} in total.",
                      suggestions=["What's running low?", "Who owes us money?"])
    p = c.period
    r = _sales_row(c, p.start, p.end)
    pnl = reports.profit_and_loss_report(c.db, p.start, p.end)
    owe_sup = c.db.scalar("SELECT SUM(balance) FROM suppliers WHERE balance > 0") or 0
    data = insights.product_insights(c.db)
    s = insights.summary(data)
    rows = [
        [f"Sales {p.label}", f"{money(r['totalRevenue'])} from {r['saleCount']} sale(s)"],
        ["Gross profit", money(pnl["grossProfit"])],
        ["Expenses", money(pnl["expenses"])],
        ["Net profit", money(pnl["netProfit"])],
        ["Out of stock / running low", f"{out} / {low}"],
        ["Stock value at cost", money(s["stockValue"])],
        ["Customers owe you", money(owed)],
        ["You owe suppliers", money(owe_sup)],
    ]
    return answer(f"Here is the shop at a glance ({p.label}):", table(["", ""], rows),
                  ["What should I reorder?", "Which products are not selling?", "Who owes us money?"])
