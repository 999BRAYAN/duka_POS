"""The shop assistant: ask a question in plain words, get an answer from the books.

This is not an AI service. It recognises what is being asked from keywords
(and which product, customer, supplier or category is meant by matching
names), then answers from the same queries the screens use, so every number is
the real one. It runs free, offline and instantly.

Two optional extras use Ollama, a free program that runs a language model on
this computer (see llm.py). With it running:

* a manager's question the built-in answers don't recognise is turned into a
  read-only database query, run safely, and explained (see freeform.py);
* with DUKA_OLLAMA_POLISH=1, every answer's wording is also smoothed by the
  model. The numbers always come from the database.

Who may ask what follows the screens: stock and price questions, customer
balances and how-to help are open to every signed-in user; sales, profit,
expenses, suppliers and the buying advice need the same permission as
Dashboard and Reports.
"""

import os
import re

from . import freeform, howto, llm, money as money_a, people, stock as stock_a
from .common import Ctx, answer, find_named, has, qty, read_two_periods
from .. import dates
from ..db import Db
from ..repos import insights

HELP = [
    "Give me a summary of the shop",
    "What's running low?",
    "What should I reorder?",
    "Which products are not selling?",
    "How are sales today?",
    "Compare this week with last week",
    "Who owes us money?",
]


def _help(c: Ctx) -> dict:
    lines = [
        "Stock: " + stock_a.HELP_STOCK + ".",
        "Money: " + money_a.HELP_MONEY + ".",
        "People: " + people.HELP_PEOPLE + ".",
        "How-to: ask \"how do I ...\" about any screen (receive stock, void a sale, back up, import...).",
        "Name a product, customer or supplier to get its details, e.g. \"tell me about Sugar\" or \"how much does Mary owe?\".",
        "Add a time: today, yesterday, this/last week, this/last month, last 30 days, in March.",
    ]
    if llm.available():
        lines.append("A local language model is connected, so managers can also ask anything else about the shop's data.")
    return answer("Hello! I answer from your shop's own records. " + " ".join(lines), suggestions=HELP)


def _explicit_period(c: Ctx) -> bool:
    return c.period.kind != "today" or bool(re.search(r"\btoday\b", c.q))


def _product_question(c: Ctx, p: dict) -> dict:
    q = c.q
    if has(q, r"\b(history|movements?|moved|audit|adjustments?)\b"):
        return stock_a.product_history(c, p)
    if has(q, r"\b(tell me about|details?|info|about|profile|everything)\b") and not has(q, r"\b(price|cost)\b"):
        return stock_a.product_details(c, p)
    if has(q, r"\b(predict|forecast|expect|next week|how fast|selling|sold|sell|sales|demand|moving|revenue)\b") and not has(q, r"\bprice\b"):
        if not c.manager:
            return answer("Only a manager can see how products are selling. Ask them, or sign in as a manager.")
        if _explicit_period(c) and not has(q, r"\b(predict|forecast|expect|next week|how fast)\b"):
            p_ = c.period
            row = c.db.one(
                "SELECT SUM(si.quantity) AS q, SUM(si.total) AS rev FROM sale_items si JOIN sales s ON s.id = si.sale_id "
                "WHERE si.product_id = %s AND s.status = 'completed' AND s.created_at BETWEEN %s AND %s", (p["id"], p_.start, p_.end))
            sold = row["q"] or 0
            if not sold:
                return answer(f"{p['name']} did not sell {p_.label}.")
            return answer(f"{p['name']} sold {qty(sold)} {p['unit']} {p_.label}, bringing in {money_a.money(row['rev'])}.")
        return stock_a.product_speed(p, insights.product_insights(c.db))
    if has(q, r"\b(price|cost|how much is|worth|margin)\b"):
        return stock_a.price_of(p, c.manager)
    return stock_a.stock_of(p)


_NEEDS_QUERY = (r"\b(per|each|every|never|ever|starting|starts?|ending|ends?|contains?|containing|without|except)\b",
                r"\b(more|less|fewer|greater|higher|lower) than\b", r"\bat (least|most)\b", r"\bbetween\b",
                r"\b(average|avg|median|ratio|percent|percentage)\b", r"\b(group|grouped|sorted|ordered) by\b",
                r"categor.{0,30}(most|least|best|worst|sold|earn|revenue|profit)",
                r"\b(which|what|how many) .{0,40}\b(that|who|with)\b")


def ask(db: Db, user: dict, question: str) -> dict:
    question = (question or "").strip()
    if not question:
        return answer("Ask me about stock, sales, what to reorder, customers or how to do something.", suggestions=HELP)
    c = Ctx(db=db, user=user, text=question, q=question.lower().replace("’", "'"))
    q = c.q

    invoice = people.invoice_number_in(q)
    if invoice:
        return people.invoice(c, invoice)
    if has(q, r"^(hi|hello|hey|help|hallo|habari|sasa)\b", r"what can you", r"\bwhat do you know\b", r"^help$"):
        return _help(c)
    if has(q, r"\bwho am i\b", r"\bmy (role|permissions?|login|account)\b"):
        return people.who_am_i(c)
    if has(q, r"\bwhat (time|day|date) is it\b", r"\btoday'?s date\b", r"\bwhat'?s the date\b"):
        return answer(f"It is {c.now:%A}, {dates.fmt_date(c.now)}, {c.now:%H:%M}.")
    if howto.is_howto(q):
        found = howto.lookup(q)
        if found:
            return found

    # Which product / customer / supplier / category does the question name?
    customer_words = has(q, r"\b(owe|owes|owed|balance|credit|statement|paid|pays|payment|customer|debt|bought|buys|spent|phone|limit)\b")
    supplier_words = has(q, r"\b(supplier|suppliers|supplied|supplies|vendor|wholesaler|distributor|purchases?|bought from)\b")
    products, customers, suppliers = c.products, c.customers, c.suppliers
    product = (find_named(question, products) or [None])[0]
    cust = find_named(question, customers, min_score=0.5)
    sup = find_named(question, suppliers, min_score=0.5)

    # A question the fixed answers can't express ("per cashier", "never sold",
    # "starting with") would only get a loosely related answer from them, so
    # a manager's goes to the local model first when one is running.
    if not (product or cust or sup) and c.manager and has(q, *_NEEDS_QUERY):
        found = freeform.try_answer(c)
        if found:
            return found

    if cust and customer_words:
        return people.customer_info(c, cust[0]) if len(cust) == 1 else people.pick_one("customer", cust)
    if sup and supplier_words:
        return people.supplier_info(c, sup[0]) if len(sup) == 1 else people.pick_one("supplier", sup)
    if product:
        return _product_question(c, product)
    if cust:
        return people.customer_info(c, cust[0]) if len(cust) == 1 else people.pick_one("customer", cust)
    if sup:
        return people.supplier_info(c, sup[0]) if len(sup) == 1 else people.pick_one("supplier", sup)
    cat = find_named(question, c.categories)
    if cat and has(q, r"\b(products?|items?|stock|list|show|what|which)\b"):
        return stock_a.category_products(c, cat[0])

    # Stock.
    if has(q, r"\bout of stock\b", r"\bsold out\b", r"\bfinished\b", r"\bzero stock\b", r"\bno stock\b", r"\bunavailable\b"):
        return stock_a.out_of_stock(c)
    if has(q, r"\b(reorder|restock|re-stock|replenish)\b", r"\bwhat (should|do|must|shall) (i|we) (buy|order|get)\b", r"\bneed to (buy|order)\b", r"\bpurchase suggestion", r"\bshopping list\b"):
        return stock_a.reorder(c)
    if has(q, r"\b(low|running low|almost|nearly|shortage|running out|run out|reorder level)\b"):
        return stock_a.low_stock(c)
    if has(q, r"\b(slow|not selling|isn't selling|lagging|dead|dormant|stagnant|worst|weakest|least|waste|wastage|spoil|expir|overstock|over-stock|excess|too much|gather dust|unsold)\b"):
        return stock_a.lagging(c)
    if has(q, r"\b(most profitable|highest margin|best margin|biggest margin|makes? the most (profit|money)|profit by product|profit per product)\b"):
        return stock_a.most_profitable(c)
    if has(q, r"\b(tied up|capital|stock value|inventory value|worth of stock|value of (my |the )?(stock|inventory)|stock worth)\b"):
        return stock_a.stock_value(c)
    if has(q, r"\b(selling below|below cost|loss[- ]making|negative margin)\b"):
        return stock_a.below_cost(c)
    if has(q, r"\b(adjustments?|written off|write[- ]off|stock corrections?)\b"):
        return stock_a.recent_adjustments(c)
    if has(q, r"\bhow many (products|items)\b", r"\bnumber of (products|items)\b", r"\bproduct count\b"):
        return stock_a.product_count(c)
    if has(q, r"\bcategor(y|ies)\b", r"\bsections?\b"):
        return stock_a.categories(c)

    # People.
    if has(q, r"\b(best|top|biggest|loyal|regular)\b.*\bcustomers?\b", r"\bcustomers?\b.*\b(spent|spend|buy)\b.*\bmost\b", r"\bwho (buys|spends) (the )?most\b"):
        return people.top_customers(c)
    if has(q, r"\b(near|close to|over|exceed\w*|reach\w*|at)\b.*\bcredit limit\b", r"\bover (their )?limit\b"):
        return people.near_limit(c)
    if has(q, r"\bhow many customers\b", r"\bnumber of customers\b"):
        return people.customer_count(c)
    if has(q, r"\b(unpaid|owing|outstanding|not (fully )?paid|payable)\b.*\b(purchases?|invoices?|deliver\w*|bills?)\b", r"\bwhich purchases\b.*\bunpaid\b"):
        return people.unpaid_purchases(c)
    if has(q, r"\b(pending|waiting|not yet received|incoming|on order|expected)\b.*\b(purchases?|orders?|stock|deliver\w*)\b"):
        return people.pending_purchases(c)
    if has(q, r"\b(supplier|suppliers)\b.*\b(owe|owed|balance|payable)\b", r"\b(owe|owed)\b.*\bsuppliers?\b", r"\bwhat (do|did) (i|we) owe\b", r"\b(i|we) owe\b", r"\bpayables?\b"):
        return people.owed_to_suppliers(c)
    if has(q, r"\bsuppliers?\b") and not has(q, r"\bpurchases?\b"):
        return people.owed_to_suppliers(c)
    if has(q, r"\b(staff|employees?|logins?|cashiers?|users?|accounts?)\b") and has(q, r"\b(list|show|who|how many|which|all|my)\b") and not has(q, r"\b(sold|sales|sell|best|most|top)\b"):
        return people.staff(c)

    # Money.
    paid_by_words = has(q, r"\b(m-?pesa|mpesa|cash|card|payment methods?|paid by|takings|collected|received|money in|came in|collections?)\b") and has(q, r"\b(how much|total|take|took|taken|got|get|receive\w*|collect\w*|takings|by|methods?|money|came in|breakdown|vs\.?|versus)\b") and not has(q, r"\b(profit|expense)")
    if paid_by_words and not read_two_periods(q, c.now):
        return money_a.collections(c)
    if has(q, r"\b(compare|compared|comparison|versus|vs\.?|than (last|the previous|yesterday)|up or down|better than|worse than|growth|trend)\b"):
        return money_a.compare(c)
    if has(q, r"\b(busiest|slowest|peak|rush|best day|worst day|which day|what time|busy)\b"):
        return money_a.busiest(c)
    if paid_by_words:
        return money_a.collections(c)
    if has(q, r"\b(expir\w*|best before|use by|shelf life|sell[- ]by)\b"):
        return answer("The shop software doesn't record expiry dates, so I can't tell what is about to expire. The closest help is "
                      "products that aren't selling or that you hold too much of - those are the ones most likely to spoil.",
                      suggestions=["Which products are not selling?"])
    if has(q, r"\b(cashier|cashiers|attendant|who sold|each (person|staff|user)|per (person|staff|cashier)|by (person|staff|cashier)|staff sales|employee sales|who made)\b"):
        return money_a.by_cashier(c)
    if has(q, r"\b(void|voided|cancelled|canceled|refunded|refunds)\b"):
        return money_a.voided(c)
    if has(q, r"\b(biggest|largest|highest|top)\b.*\b(sale|sales|transaction|order|invoice|receipt)\b"):
        return money_a.biggest_sales(c)
    if has(q, r"\b(recent|latest|last|newest)\b.*\b(sales?|transactions?|invoices?|receipts?)\b"):
        return money_a.recent_sales(c)
    if has(q, r"\b(recent|latest|last)\b.*\b(expenses?|spending)\b"):
        return money_a.recent_expenses(c)
    if has(q, r"\b(recent|latest|last)\b.*\b(purchases?|deliver\w*|restock\w*)\b", r"\b(stock|goods) (we )?(bought|purchased)\b", r"\bhow much (stock )?did (i|we) (buy|purchase|spend on stock)\b"):
        return people.recent_purchases(c)
    if has(q, r"\b(profit|margin|earn|earned|net|gross|loss|made|make|making)\b") and not has(q, r"\b(best|top)\b"):
        return money_a.profit(c)
    if has(q, r"\b(expense|expenses|spent|spend|spending|costs?|bills?|rent|salary|salaries|wages)\b"):
        return money_a.expenses(c)
    if has(q, r"\b(best|top|fast|popular|bestsell\w*|best-sell\w*|most sold|selling well|selling most|moving fast|favou?rite)\b"):
        return stock_a.movers(c, best=True)
    if has(q, r"\b(summary|overview|snapshot|brief\w*|at a glance|status|how (is|are) (we|the (business|shop|store)|business)( doing)?|how'?s (the )?(business|shop|store)|how are things|update me|catch me up)\b"):
        return money_a.briefing(c)
    if has(q, r"\b(owe|owes|owed|debt|debtor|debtors|credit|balance|balances|arrears)\b"):
        return people.owed_by_customers(c)
    if has(q, r"\b(sales|revenue|sold|takings|turnover|income|sell|transactions|sale)\b"):
        return money_a.sales(c)
    if has(q, r"\b(stock|inventory)\b"):
        return stock_a.low_stock(c)
    if howto.is_howto(q):
        return howto.topic_list()

    # Nothing built in fits: let the local model try (managers, if it is running).
    found = freeform.try_answer(c)
    if found:
        return found
    extra = "" if llm.available() else " (Install the free Ollama program and a small model to let managers ask anything else - see the README.)"
    return answer("I didn't catch that. I can answer questions about stock, prices, sales, profit, expenses, customers, suppliers, "
                  "invoices and what to reorder, and explain how to use the screens." + extra, suggestions=HELP)


# --- optional: smoother wording via Ollama ---------------------------------

def polish(result: dict, question: str) -> dict:
    if os.environ.get("DUKA_OLLAMA_POLISH") != "1" or result.get("ai") or not llm.available():
        return result
    try:
        text = llm.chat([
            {"role": "system", "content": "You are a friendly shop assistant. Rewrite the given answer in one or two natural sentences. Keep every number exactly as given. Do not add facts."},
            {"role": "user", "content": f"Question: {question}\nAnswer: {result['reply']}"},
        ], timeout=20)
        if text:
            return {**result, "reply": text}
    except Exception:
        pass
    return result
