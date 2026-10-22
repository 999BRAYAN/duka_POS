"""The shop assistant: ask a question in plain words, get an answer from the books.

This is not an AI service. It recognises what is being asked from keywords
(and which product is meant by matching names), then answers from the same
queries the screens use, so every number is the real one. It runs free, offline
and instantly.

If the free local program Ollama is installed, set DUKA_OLLAMA_MODEL (for
example `llama3.2`) and the answer's wording is passed through it to read more
naturally; the numbers still come from the database, and any failure simply
falls back to the plain answer.

Who may ask what follows the screens: stock and price questions are open to
every signed-in user; sales, profit, expenses and the buying advice need the
same permission as Dashboard and Reports.
"""

import difflib
import json
import os
import re
import urllib.request
from datetime import datetime

from . import authz, dates
from .db import Db
from .repos import insights, reports, stock

_STOP = {
    "the", "a", "an", "of", "for", "is", "are", "do", "we", "have", "how", "many", "much", "what", "whats", "in",
    "stock", "left", "price", "cost", "sell", "sold", "selling", "sales", "me", "my", "our", "show", "tell", "about",
    "and", "to", "on", "at", "any", "there", "i", "you", "much", "today", "week", "month", "year", "this", "will",
    "next", "predict", "forecast", "many", "does", "did", "can", "us", "give", "list", "all", "with", "much",
}

HELP = [
    "What's running low?",
    "What should I reorder?",
    "Which products are not selling?",
    "What are my best sellers this month?",
    "Where is my money tied up in stock?",
    "How are sales today?",
    "Who owes us money?",
]


def _money(v: float) -> str:
    return dates.fmt_amount(v)


def _qty(v: float) -> str:
    return f"{v:,.2f}".rstrip("0").rstrip(".")


def _has(text: str, *patterns: str) -> bool:
    return any(re.search(p, text) for p in patterns)


def _tokens(text: str) -> list[str]:
    out = []
    for t in re.findall(r"[a-z0-9]+", text.lower()):
        if len(t) > 3 and t.endswith("s"):
            t = t[:-1]
        out.append(t)
    return out


def _find_product(question: str, products: list[dict]) -> dict | None:
    """The product the question is about, if the words clearly point at one."""
    q = question.lower()
    q_tokens = set(_tokens(q))
    best, best_score = None, 0.0
    for p in products:
        name = p["name"].lower()
        if len(name) > 2 and re.search(rf"\b{re.escape(name)}\b", q):
            score = 1.0 + len(name) / 100  # a longer exact name beats a shorter one inside it
        else:
            name_tokens = [t for t in _tokens(name) if t not in _STOP and len(t) > 1]
            if not name_tokens:
                continue
            hits = 0.0
            for t in name_tokens:
                if t in q_tokens:
                    hits += 1
                elif len(t) > 4 and difflib.get_close_matches(t, q_tokens, n=1, cutoff=0.85):
                    hits += 0.9
            score = hits / len(name_tokens)
        if score > best_score:
            best, best_score = p, score
    return best if best_score >= 0.6 else None


def _period(q: str) -> tuple[str, str]:
    if _has(q, r"\byear\b", r"\bannual"):
        return "year", "this year"
    if _has(q, r"\bmonth"):
        return "month", "this month"
    if _has(q, r"\bweek"):
        return "week", "this week"
    return "today", "today"


def _table(columns: list[str], rows: list[list]) -> dict:
    return {"columns": columns, "rows": [[str(c) for c in r] for r in rows]}


def _answer(reply: str, table: dict | None = None, suggestions: list[str] | None = None) -> dict:
    return {"reply": reply, "table": table, "suggestions": suggestions or []}


def _manager_only(label: str) -> dict:
    return _answer(f"Only a manager can see {label}. Ask them, or sign in as a manager.", suggestions=["What's running low?"])


# --- the answers -----------------------------------------------------------

def _stock_of(p: dict) -> dict:
    status = "out of stock" if p["stock"] <= 0 else ("at or below its reorder level" if p["stock"] <= p["reorder_level"] else "in stock")
    return _answer(
        f"{p['name']}: {_qty(p['stock'])} {p['unit']} in stock ({status}). Sells at {_money(p['selling_price'])}.",
        suggestions=[f"How fast is {p['name']} selling?", "What's running low?"],
    )


def _price_of(p: dict, can_see_cost: bool) -> dict:
    text = f"{p['name']} sells at {_money(p['selling_price'])} per {p['unit']} (lowest allowed price {_money(p['min_selling_price'])})."
    if can_see_cost:
        margin = (p["selling_price"] - p["cost_price"]) / p["selling_price"] * 100 if p["selling_price"] else 0
        text += f" It costs {_money(p['cost_price'])}, a margin of {margin:.0f}%."
    return _answer(text)


def _product_speed(p: dict, data: dict) -> dict:
    row = next((i for i in data["products"] if i["id"] == p["id"]), None)
    if row is None or not data["historyDays"]:
        return _answer(f"There are no sales on record yet, so I can't say how {p['name']} is doing.")
    if row["sold"] <= 0:
        return _answer(
            f"{p['name']} has not sold in the last {data['windowDays']} days. You hold {_qty(row['stock'])} {row['unit']} "
            f"worth {_money(row['stockValue'])} at cost."
        )
    cover = f"{row['coverDays']:.0f} days" if row["coverDays"] is not None else "n/a"
    text = (
        f"{p['name']} sold {_qty(row['sold'])} {row['unit']} in the last {data['historyDays']:.0f} days "
        f"(about {row['dailyRate']:.1f} a day, {_money(row['revenue'])} revenue). "
        f"Stock of {_qty(row['stock'])} lasts about {cover}. "
        f"Expected next 7 days: ~{_qty(round(row['forecastNext7']))}."
    )
    if row["suggestedOrder"]:
        text += f" I'd order about {_qty(row['suggestedOrder'])}."
    return _answer(text)


def _note(data: dict) -> str:
    if not data["historyDays"]:
        return "There are no completed sales yet, so there is nothing to judge from."
    if not data["enoughHistory"]:
        return f"Note: only {data['historyDays']:.0f} days of sales so far - slow/overstock calls get reliable after about {insights.MIN_HISTORY_DAYS} days."
    return ""


def _low_stock(db: Db) -> dict:
    levels = [l for l in stock.stock_valuation(db) if l["isLowStock"]]
    if not levels:
        return _answer("Nothing is at or below its reorder level right now.")
    rows = [[l["name"], _qty(l["stock"]), _qty(l["reorderLevel"])] for l in levels]
    return _answer(
        f"{len(levels)} product{'s are' if len(levels) != 1 else ' is'} at or below the reorder level.",
        _table(["Product", "In stock", "Reorder level"], rows[:30]),
        ["What should I reorder?"],
    )


def _reorder(data: dict) -> dict:
    items = [i for i in data["products"] if i["status"] in ("reorder", "out") and i["dailyRate"] > 0]
    items.sort(key=lambda i: (i["coverDays"] if i["coverDays"] is not None else 0))
    note = _note(data)
    if not items:
        return _answer("Nothing needs buying right now - everything that sells has more than a week of stock." + (f" {note}" if note else ""))
    rows = [
        [i["name"], _qty(i["stock"]), "-" if i["coverDays"] is None else f"{i['coverDays']:.1f}", _qty(i["suggestedOrder"]) or "0"]
        for i in items[:30]
    ]
    return _answer(
        f"{len(items)} product{'s' if len(items) != 1 else ''} will run out within a week or already have. "
        f"The order amounts bring each up to {insights.TARGET_COVER_DAYS} days of stock at the recent selling pace." + (f" {note}" if note else ""),
        _table(["Product", "In stock", "Days left", "Suggested order"], rows),
        ["Which products are not selling?"],
    )


def _movers(data: dict, *, best: bool, label: str) -> dict:
    sold = [i for i in data["products"] if i["sold"] > 0]
    note = _note(data)
    if not sold:
        return _answer("No product has sold yet in this period." + (f" {note}" if note else ""))
    sold.sort(key=lambda i: i["revenue"], reverse=best)
    top = sold[:10]
    rows = [[n + 1, i["name"], _qty(i["sold"]), _money(i["revenue"]), i["abc"]] for n, i in enumerate(top)]
    head = f"{'Best' if best else 'Weakest'} sellers over the last {data['historyDays']:.0f} days (by revenue)."
    return _answer(head + (f" {note}" if note else ""), _table(["#", "Product", "Sold", "Revenue", "Class"], rows),
                   ["Which products are not selling?" if best else "What are my best sellers this month?"])


def _lagging(data: dict) -> dict:
    items = [i for i in data["products"] if i["status"] in ("dead", "slow", "overstocked")]
    note = _note(data)
    if not items:
        return _answer("No product is lagging - nothing is dead or over-stocked." + (f" {note}" if note else ""))
    order = {"dead": 0, "overstocked": 1, "slow": 2}
    items.sort(key=lambda i: (order[i["status"]], -i["excessValue"] - i["stockValue"] * 0.001))
    label = {"dead": "Not selling", "overstocked": "Too much stock", "slow": "Slow"}
    rows = [
        [i["name"], label[i["status"]], _qty(i["stock"]), "-" if i["coverDays"] is None else f"{i['coverDays']:.0f}", _money(i["excessValue"] or i["stockValue"])]
        for i in items[:30]
    ]
    dead = sum(1 for i in items if i["status"] == "dead")
    over = sum(1 for i in items if i["status"] == "overstocked")
    text = f"{dead} product{'s' if dead != 1 else ''} not selling at all and {over} over-stocked. Consider pausing purchases, promoting them, or discounting before they spoil."
    return _answer(text + (f" {note}" if note else ""), _table(["Product", "Problem", "In stock", "Days of cover", "Money tied up"], rows),
                   ["Where is my money tied up in stock?"])


def _money_tied(data: dict) -> dict:
    s = insights.summary(data)
    items = sorted(data["products"], key=lambda i: i["excessValue"], reverse=True)
    items = [i for i in items if i["excessValue"] > 0][:10]
    text = f"Your stock is worth {_money(s['stockValue'])} at cost. About {_money(s['excessValue'])} of it is more than you need for {insights.TARGET_COVER_DAYS} days of selling (dead or over-stocked items)."
    note = _note(data)
    table = _table(["Product", "Excess money tied up"], [[i["name"], _money(i["excessValue"])] for i in items]) if items else None
    return _answer(text + (f" {note}" if note else ""), table, ["Which products are not selling?"])


def _sales(db: Db, period: str, label: str) -> dict:
    start, end = dates.for_period(period)
    r = reports.sales_report(db, start, end)
    if r["saleCount"] == 0:
        return _answer(f"No completed sales {label}.")
    top = r["productBreakdown"][:5]
    return _answer(
        f"Sales {label}: {_money(r['totalRevenue'])} from {r['saleCount']} sale{'s' if r['saleCount'] != 1 else ''} "
        f"(average {_money(r['averageSaleValue'])}).",
        _table(["Top products", "Sold", "Revenue"], [[t["productName"], _qty(t["quantitySold"]), _money(t["revenue"])] for t in top]),
        ["How much profit did we make?", "What are my best sellers this month?"],
    )


def _profit(db: Db, period: str, label: str) -> dict:
    start, end = dates.for_period(period)
    r = reports.profit_and_loss_report(db, start, end)
    return _answer(
        f"Profit {label}: net revenue {_money(r['netRevenue'])}, minus cost of goods {_money(r['cogs'])} gives gross profit "
        f"{_money(r['grossProfit'])}. After expenses of {_money(r['expenses'])}, net profit is {_money(r['netProfit'])}.",
        suggestions=["What did we spend this month?"],
    )


def _expenses(db: Db, period: str, label: str) -> dict:
    start, end = dates.for_period(period)
    rows = db.all(
        "SELECT category, SUM(amount) AS total FROM expenses WHERE created_at BETWEEN %s AND %s GROUP BY category ORDER BY total DESC",
        (start, end),
    )
    if not rows:
        return _answer(f"No expenses recorded {label}.")
    total = sum(r["total"] for r in rows)
    return _answer(f"Expenses {label}: {_money(total)}.", _table(["Category", "Amount"], [[r["category"], _money(r["total"])] for r in rows]))


def _owed_by_customers(db: Db) -> dict:
    rows = db.all("SELECT name, phone, current_balance FROM customers WHERE current_balance > 0 ORDER BY current_balance DESC LIMIT 20")
    if not rows:
        return _answer("No customer owes anything right now.")
    total = db.scalar("SELECT SUM(current_balance) FROM customers WHERE current_balance > 0")
    return _answer(f"Customers owe {_money(total)} in total.", _table(["Customer", "Phone", "Owes"], [[r["name"], r["phone"] or "-", _money(r["current_balance"])] for r in rows]))


def _owed_to_suppliers(db: Db) -> dict:
    rows = db.all("SELECT name, phone, balance FROM suppliers WHERE balance > 0 ORDER BY balance DESC LIMIT 20")
    if not rows:
        return _answer("You don't owe any supplier right now.")
    total = db.scalar("SELECT SUM(balance) FROM suppliers WHERE balance > 0")
    return _answer(f"You owe suppliers {_money(total)} in total.", _table(["Supplier", "Phone", "You owe"], [[r["name"], r["phone"] or "-", _money(r["balance"])] for r in rows]))


def _out_of_stock(db: Db) -> dict:
    rows = db.all("SELECT name, unit FROM products WHERE is_active = 1 AND stock <= 0 ORDER BY name LIMIT 50")
    if not rows:
        return _answer("Nothing is out of stock.")
    return _answer(f"{len(rows)} product{'s are' if len(rows) != 1 else ' is'} out of stock.", _table(["Product"], [[r["name"]] for r in rows]), ["What should I reorder?"])


# --- routing ---------------------------------------------------------------

def ask(db: Db, user: dict, question: str) -> dict:
    question = (question or "").strip()
    if not question:
        return _answer("Ask me about stock, sales, what to reorder or which products aren't selling.", suggestions=HELP)
    q = question.lower()
    manager = authz.can(user, authz.MANAGE_PRODUCTS)
    products = db.all("SELECT * FROM products WHERE is_active = 1")
    product = _find_product(question, products)
    period, label = _period(q)

    def analytics():
        return insights.product_insights(db)

    # Questions about one named product.
    if product:
        if _has(q, r"\b(predict|forecast|expect|next week|how fast|selling|sold|sell|demand|moving)\b") and not _has(q, r"\bprice\b"):
            return _product_speed(product, analytics()) if manager else _manager_only("how products are selling")
        if _has(q, r"\b(price|cost|how much is|worth)\b"):
            return _price_of(product, manager)
        return _stock_of(product)

    if _has(q, r"^(hi|hello|hey|help)\b", r"what can you", r"\bhelp\b"):
        return _answer("Hello! I answer from your shop's own records. Try one of these:", suggestions=HELP)
    if _has(q, r"\bout of stock\b", r"\bsold out\b", r"\bfinished\b", r"\bzero stock\b", r"\bno stock\b"):
        return _out_of_stock(db)
    if _has(q, r"\b(reorder|restock|re-stock|replenish)\b", r"\bwhat (should|do|must) i (buy|order)\b", r"\bneed to (buy|order)\b", r"\bpurchase suggestion"):
        return _reorder(analytics()) if manager else _manager_only("buying advice")
    if _has(q, r"\b(low|running low|almost|nearly|shortage|running out|run out|reorder level)\b"):
        return _low_stock(db)
    if _has(q, r"\b(slow|not selling|isn't selling|lagging|dead|dormant|stagnant|worst|weakest|least|waste|wastage|spoil|expir|overstock|over-stock|excess|too much|bulk|gather dust|unsold)\b"):
        return _lagging(analytics()) if manager else _manager_only("which products are lagging")
    if _has(q, r"\b(tied up|capital|stock value|inventory value|worth of stock|value of (my )?stock)\b"):
        return _money_tied(analytics()) if manager else _manager_only("the stock value")
    if _has(q, r"\b(best|top|fast|popular|bestsell|best-sell|most sold|selling well|selling most|moving fast|favou?rite)\b"):
        return _movers(analytics(), best=True, label=label) if manager else _manager_only("sales rankings")
    if _has(q, r"\b(profit|margin|earn|earned|net)\b"):
        return _profit(db, period, label) if manager else _manager_only("profit")
    if _has(q, r"\b(expense|expenses|spent|spend|spending)\b"):
        return _expenses(db, period, label) if manager else _manager_only("expenses")
    if _has(q, r"\bsupplier"):
        return _owed_to_suppliers(db) if manager else _manager_only("what is owed to suppliers")
    if _has(q, r"\b(owe|owes|owed|debt|debtor|debtors|credit|balance|balances|arrears)\b"):
        return _owed_by_customers(db)
    if _has(q, r"\b(sales|revenue|sold|takings|turnover|income|sell)\b"):
        return _sales(db, period, label) if manager else _manager_only("sales figures")
    if _has(q, r"\b(stock|inventory)\b"):
        return _low_stock(db)

    return _answer("I didn't catch that. I can answer questions about stock, prices, sales, profit, expenses, customer credit and what to reorder.", suggestions=HELP)


# --- optional: free local wording via Ollama -------------------------------

def polish(answer: dict, question: str) -> dict:
    model = os.environ.get("DUKA_OLLAMA_MODEL")
    if not model:
        return answer
    try:
        body = json.dumps({
            "model": model, "stream": False,
            "messages": [
                {"role": "system", "content": "You are a friendly shop assistant. Rewrite the given answer in one or two natural sentences. Keep every number exactly as given. Do not add facts."},
                {"role": "user", "content": f"Question: {question}\nAnswer: {answer['reply']}"},
            ],
        }).encode()
        req = urllib.request.Request("http://127.0.0.1:11434/api/chat", body, {"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=20) as r:
            text = json.load(r)["message"]["content"].strip()
        if text:
            return {**answer, "reply": text}
    except Exception:
        pass
    return answer
