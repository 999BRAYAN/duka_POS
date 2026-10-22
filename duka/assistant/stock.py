"""Answers about products and stock."""

from ..repos import insights, stock as stock_repo
from .common import Ctx, answer, has, manager_only, money, pct, qty, table, when

HELP_STOCK = "stock levels, prices, what to reorder, slow movers, best sellers, margins, stock value"


def note(data: dict) -> str:
    if not any(i["sold"] for i in data["products"]):
        return "There are no completed sales yet, so there is nothing to judge from."
    if not data["enoughHistory"]:
        return f"Note: only {data['historyDays']:.0f} days of sales so far - slow/overstock calls get reliable after about {insights.MIN_HISTORY_DAYS} days."
    return ""


def _tail(data: dict) -> str:
    n = note(data)
    return f" {n}" if n else ""


# --- one product -----------------------------------------------------------

def stock_of(p: dict) -> dict:
    status = "out of stock" if p["stock"] <= 0 else ("at or below its reorder level" if p["stock"] <= p["reorder_level"] else "in stock")
    return answer(
        f"{p['name']}: {qty(p['stock'])} {p['unit']} in stock ({status}). Sells at {money(p['selling_price'])}.",
        suggestions=[f"Tell me about {p['name']}", f"How fast is {p['name']} selling?"],
    )


def price_of(p: dict, can_see_cost: bool) -> dict:
    text = f"{p['name']} sells at {money(p['selling_price'])} per {p['unit']} (lowest allowed price {money(p['min_selling_price'])})."
    if can_see_cost:
        margin = (p["selling_price"] - p["cost_price"]) / p["selling_price"] * 100 if p["selling_price"] else 0
        text += f" It costs {money(p['cost_price'])}, a margin of {margin:.0f}%."
    return answer(text)


def product_speed(p: dict, data: dict) -> dict:
    row = next((i for i in data["products"] if i["id"] == p["id"]), None)
    if row is None or not data["historyDays"]:
        return answer(f"There are no sales on record yet, so I can't say how {p['name']} is doing.")
    if row["sold"] <= 0:
        return answer(
            f"{p['name']} has not sold in the last {data['windowDays']} days. You hold {qty(row['stock'])} {row['unit']} "
            f"worth {money(row['stockValue'])} at cost."
        )
    cover = f"{row['coverDays']:.0f} days" if row["coverDays"] is not None else "n/a"
    text = (
        f"{p['name']} sold {qty(row['sold'])} {row['unit']} in the last {data['historyDays']:.0f} days "
        f"(about {row['dailyRate']:.1f} a day, {money(row['revenue'])} revenue, {money(row['profit'])} profit). "
        f"Stock of {qty(row['stock'])} lasts about {cover}. "
        f"Expected next 7 days: ~{qty(round(row['forecastNext7']))}."
    )
    if row["suggestedOrder"]:
        text += f" I'd order about {qty(row['suggestedOrder'])}."
    return answer(text)


def product_details(c: Ctx, p: dict) -> dict:
    db = c.db
    last_sold = db.scalar(
        "SELECT MAX(s.created_at) FROM sale_items si JOIN sales s ON s.id = si.sale_id "
        "WHERE si.product_id = %s AND s.status = 'completed'", (p["id"],))
    last_in = db.one(
        "SELECT created_at, quantity, unit_cost FROM stock_movements WHERE product_id = %s AND type = 'PURCHASE' "
        "ORDER BY created_at DESC, id DESC LIMIT 1", (p["id"],))
    rows = [
        ["Category", p["category_name"] or "none"],
        ["SKU / barcode", f"{p['sku'] or '-'} / {p['barcode'] or '-'}"],
        ["In stock", f"{qty(p['stock'])} {p['unit']} (reorder at {qty(p['reorder_level'])})"],
        ["Selling price", f"{money(p['selling_price'])} (lowest {money(p['min_selling_price'])})"],
    ]
    if c.manager:
        margin = pct(p["selling_price"] - p["cost_price"], p["selling_price"])
        rows.append(["Cost price", f"{money(p['cost_price'])} (margin {margin})"])
        rows.append(["Stock value at cost", money(p["stock"] * p["cost_price"])])
    rows.append(["Last sold", when(last_sold)])
    if last_in:
        rows.append(["Last restocked", f"{when(last_in['created_at'])}: {qty(last_in['quantity'])}" +
                     (f" at {money(last_in['unit_cost'])}" if c.manager and last_in["unit_cost"] is not None else "")])
    return answer(f"Here is {p['name']}:", table(["", ""], rows),
                  [f"Show stock movements for {p['name']}", f"How fast is {p['name']} selling?"] if c.manager else [])


def product_history(c: Ctx, p: dict) -> dict:
    if not c.manager:
        return manager_only("the stock movements")
    rows = c.db.all(
        "SELECT m.created_at, m.type, m.quantity, m.unit_cost, m.reference, m.notes, u.full_name "
        "FROM stock_movements m LEFT JOIN users u ON u.id = m.user_id WHERE m.product_id = %s "
        "ORDER BY m.created_at DESC, m.id DESC LIMIT 15", (p["id"],))
    if not rows:
        return answer(f"{p['name']} has no stock movements yet.")
    return answer(
        f"The last {len(rows)} stock movements for {p['name']} (now {qty(p['stock'])} {p['unit']}):",
        table(["When", "Type", "Qty", "Who", "Note"],
              [[when(r["created_at"]), r["type"], qty(r["quantity"]), r["full_name"] or "-", r["notes"] or r["reference"] or ""] for r in rows]))


# --- lists of products -------------------------------------------------------

def low_stock(c: Ctx) -> dict:
    levels = [l for l in stock_repo.stock_valuation(c.db) if l["isLowStock"]]
    if not levels:
        return answer("Nothing is at or below its reorder level right now.")
    rows = [[l["name"], qty(l["stock"]), qty(l["reorderLevel"])] for l in levels]
    return answer(
        f"{len(levels)} product{'s are' if len(levels) != 1 else ' is'} at or below the reorder level.",
        table(["Product", "In stock", "Reorder level"], rows[:30]),
        ["What should I reorder?"],
    )


def out_of_stock(c: Ctx) -> dict:
    rows = c.db.all("SELECT name, unit FROM products WHERE is_active = 1 AND stock <= 0 ORDER BY name LIMIT 50")
    if not rows:
        return answer("Nothing is out of stock.")
    return answer(f"{len(rows)} product{'s are' if len(rows) != 1 else ' is'} out of stock.", table(["Product"], [[r["name"]] for r in rows]), ["What should I reorder?"])


def reorder(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("buying advice")
    data = insights.product_insights(c.db)
    items = [i for i in data["products"] if i["status"] in ("reorder", "out") and i["dailyRate"] > 0]
    items.sort(key=lambda i: (i["coverDays"] if i["coverDays"] is not None else 0))
    if not items:
        return answer("Nothing needs buying right now - everything that sells has more than a week of stock." + _tail(data))
    rows = [
        [i["name"], qty(i["stock"]), "-" if i["coverDays"] is None else f"{i['coverDays']:.1f}", qty(i["suggestedOrder"]) or "0"]
        for i in items[:30]
    ]
    return answer(
        f"{len(items)} product{'s' if len(items) != 1 else ''} will run out within a week or already have. "
        f"The order amounts bring each up to {insights.TARGET_COVER_DAYS} days of stock at the recent selling pace." + _tail(data),
        table(["Product", "In stock", "Days left", "Suggested order"], rows),
        ["Which products are not selling?"],
    )


def movers(c: Ctx, *, best: bool) -> dict:
    if not c.manager:
        return manager_only("sales rankings")
    data = insights.product_insights(c.db)
    sold = [i for i in data["products"] if i["sold"] > 0]
    if not sold:
        return answer("No product has sold yet in this period." + _tail(data))
    sold.sort(key=lambda i: i["revenue"], reverse=best)
    rows = [[n + 1, i["name"], qty(i["sold"]), money(i["revenue"]), i["abc"]] for n, i in enumerate(sold[:10])]
    head = f"{'Best' if best else 'Weakest'} sellers over the last {data['historyDays']:.0f} days (by revenue)."
    return answer(head + _tail(data), table(["#", "Product", "Sold", "Revenue", "Class"], rows),
                  ["Which products are not selling?" if best else "What are my best sellers this month?"])


def most_profitable(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("profit by product")
    data = insights.product_insights(c.db)
    sold = sorted((i for i in data["products"] if i["sold"] > 0), key=lambda i: i["profit"], reverse=True)
    if not sold:
        return answer("No product has sold yet." + _tail(data))
    rows = [[n + 1, i["name"], money(i["profit"]), pct(i["profit"], i["revenue"]), money(i["revenue"])] for n, i in enumerate(sold[:10])]
    return answer(f"Most profitable products over the last {data['historyDays']:.0f} days:" + _tail(data),
                  table(["#", "Product", "Profit", "Margin", "Revenue"], rows), ["Which products are not selling?"])


def lagging(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("which products are lagging")
    data = insights.product_insights(c.db)
    items = [i for i in data["products"] if i["status"] in ("dead", "slow", "overstocked")]
    if not items:
        return answer("No product is lagging - nothing is dead or over-stocked." + _tail(data))
    order = {"dead": 0, "overstocked": 1, "slow": 2}
    items.sort(key=lambda i: (order[i["status"]], -i["excessValue"] - i["stockValue"] * 0.001))
    label = {"dead": "Not selling", "overstocked": "Too much stock", "slow": "Slow"}
    rows = [
        [i["name"], label[i["status"]], qty(i["stock"]), "-" if i["coverDays"] is None else f"{i['coverDays']:.0f}", money(i["excessValue"] or i["stockValue"])]
        for i in items[:30]
    ]
    dead = sum(1 for i in items if i["status"] == "dead")
    over = sum(1 for i in items if i["status"] == "overstocked")
    text = f"{dead} product{'s' if dead != 1 else ''} not selling at all and {over} over-stocked. Consider pausing purchases, promoting them, or discounting before they spoil."
    return answer(text + _tail(data), table(["Product", "Problem", "In stock", "Days of cover", "Money tied up"], rows),
                  ["Where is my money tied up in stock?"])


def money_tied(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("the stock value")
    data = insights.product_insights(c.db)
    s = insights.summary(data)
    items = sorted((i for i in data["products"] if i["excessValue"] > 0), key=lambda i: i["excessValue"], reverse=True)[:10]
    retail = c.db.scalar("SELECT SUM(stock * selling_price) FROM products WHERE is_active = 1 AND stock > 0") or 0
    text = (f"Your stock is worth {money(s['stockValue'])} at cost (about {money(retail)} if it all sold at the shelf price). "
            f"About {money(s['excessValue'])} of it is more than you need for {insights.TARGET_COVER_DAYS} days of selling (dead or over-stocked items).")
    tbl = table(["Product", "Excess money tied up"], [[i["name"], money(i["excessValue"])] for i in items]) if items else None
    return answer(text + _tail(data), tbl, ["Which products are not selling?"])


def product_count(c: Ctx) -> dict:
    total = len(c.products)
    out = sum(1 for p in c.products if p["stock"] <= 0)
    low = sum(1 for p in c.products if 0 < p["stock"] <= p["reorder_level"])
    cats = len(c.categories)
    return answer(f"You have {total} active product{'s' if total != 1 else ''} in {cats} categor{'ies' if cats != 1 else 'y'}: "
                  f"{out} out of stock and {low} running low.", suggestions=["Show my categories", "What's running low?"])


def categories(c: Ctx) -> dict:
    rows = c.db.all(
        "SELECT COALESCE(c.name, 'No category') AS name, COUNT(p.id) AS n, SUM(p.stock * p.cost_price) AS value "
        "FROM products p LEFT JOIN categories c ON c.id = p.category_id WHERE p.is_active = 1 "
        "GROUP BY c.id, c.name ORDER BY n DESC")
    if not rows:
        return answer("There are no products yet.")
    cols = ["Category", "Products"] + (["Stock value (cost)"] if c.manager else [])
    return answer(f"{len(rows)} categor{'ies' if len(rows) != 1 else 'y'}:",
                  table(cols, [[r["name"], r["n"]] + ([money(r["value"])] if c.manager else []) for r in rows]))


def category_products(c: Ctx, category: dict) -> dict:
    rows = [p for p in c.products if p["category_id"] == category["id"]]
    if not rows:
        return answer(f"There are no products in {category['name']}.")
    rows.sort(key=lambda p: p["name"].lower())
    return answer(f"{len(rows)} product{'s' if len(rows) != 1 else ''} in {category['name']}:",
                  table(["Product", "In stock", "Price"], [[p["name"], f"{qty(p['stock'])} {p['unit']}", money(p["selling_price"])] for p in rows[:40]]))


def stock_value(c: Ctx) -> dict:
    return money_tied(c)


def below_cost(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("cost prices")
    rows = [p for p in c.products if p["selling_price"] < p["cost_price"] or p["min_selling_price"] < p["cost_price"]]
    if not rows:
        return answer("Every product sells above its cost price, and no price floor is below cost.")
    return answer(f"{len(rows)} product{'s' if len(rows) != 1 else ''} with a selling price or price floor below cost:",
                  table(["Product", "Cost", "Price", "Lowest price"], [[p["name"], money(p["cost_price"]), money(p["selling_price"]), money(p["min_selling_price"])] for p in rows[:30]]))


def recent_adjustments(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("stock adjustments")
    rows = c.db.all(
        "SELECT m.created_at, p.name, m.quantity, m.notes, u.full_name FROM stock_movements m "
        "JOIN products p ON p.id = m.product_id LEFT JOIN users u ON u.id = m.user_id "
        "WHERE m.type = 'ADJUSTMENT' ORDER BY m.created_at DESC, m.id DESC LIMIT 15")
    if not rows:
        return answer("No manual stock adjustments have been made.")
    return answer(f"The last {len(rows)} manual stock adjustments:",
                  table(["When", "Product", "Change", "By", "Reason"], [[when(r["created_at"]), r["name"], qty(r["quantity"]), r["full_name"] or "-", r["notes"] or ""] for r in rows]))
