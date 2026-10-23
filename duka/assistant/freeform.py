"""Questions the built-in answers don't know: let the local model write a
database query, check it hard, run it read-only, and explain the result.

Only a manager gets this. The model never touches the database itself - it only
suggests one SELECT, and nothing runs until `check_sql` accepts it. The query
then runs on its own connection that is set read-only, with a time limit and a
row cap, so even a query that slipped past the checks could not change data.
Answers from here are marked as machine-made so they are double-checked.
"""

import os
import re

from .. import dates
from ..db import connect
from . import llm
from .common import Ctx, answer, table

ALLOWED_TABLES = {
    "products", "categories", "customers", "suppliers", "sales", "sale_items", "purchases",
    "purchase_items", "stock_movements", "credit_transactions", "expenses", "users",
}
MAX_ROWS = 200
SHOWN_ROWS = 25

SCHEMA = """\
products(id, sku, barcode, name, category_id, unit, cost_price, selling_price, min_selling_price, stock, reorder_level, is_active, created_at)
categories(id, name)
customers(id, name, phone, email, address, credit_limit, current_balance, is_walk_in, created_at)   -- current_balance = what they owe us
suppliers(id, name, phone, email, address, balance, created_at)                                      -- balance = what we owe them
sales(id, invoice_number, customer_id, user_id, subtotal, discount, tax, total, amount_paid, payment_method, cogs, gross_profit, status, void_reason, created_at)
   -- payment_method: cash, mpesa, card, credit. status: completed, void, refunded. total - amount_paid = left on credit.
sale_items(id, sale_id, product_id, quantity, unit_price, discount, total)
purchases(id, reference_number, supplier_id, user_id, subtotal, discount, tax, total, amount_paid, status, payment_status, created_at)
   -- status: pending, received, cancelled. payment_status: paid, partial, unpaid.
purchase_items(id, purchase_id, product_id, quantity, unit_cost, total)
stock_movements(id, product_id, type, quantity, unit_cost, reference, notes, user_id, created_at)
   -- type: SALE (negative quantity), PURCHASE, RETURN, ADJUSTMENT. quantity is the signed change to stock.
credit_transactions(id, customer_id, sale_id, type, amount, balance_after, method, notes, created_at)
   -- type: CHARGE (sale left on credit), PAYMENT (customer paid), REVERSAL (sale voided).
expenses(id, category, description, amount, user_id, created_at)
users(id, username, full_name, role, is_active, created_at)   -- role: admin, manager, cashier. Never select *.
"""

EXAMPLES = """\
Q: which category earns the most?
SELECT c.name, SUM(si.total) AS revenue FROM sale_items si JOIN sales s ON s.id = si.sale_id JOIN products p ON p.id = si.product_id JOIN categories c ON c.id = p.category_id WHERE s.status = 'completed' GROUP BY c.id, c.name ORDER BY revenue DESC LIMIT 10
Q: how many units of sugar did we sell last week?
SELECT SUM(si.quantity) AS units FROM sale_items si JOIN sales s ON s.id = si.sale_id JOIN products p ON p.id = si.product_id WHERE s.status = 'completed' AND p.name LIKE '%sugar%' AND s.created_at >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
Q: which customers have not bought anything in 30 days?
SELECT c.name, MAX(s.created_at) AS last_purchase FROM customers c LEFT JOIN sales s ON s.customer_id = c.id AND s.status = 'completed' WHERE c.is_walk_in = 0 GROUP BY c.id, c.name HAVING last_purchase IS NULL OR last_purchase < DATE_SUB(NOW(), INTERVAL 30 DAY) ORDER BY last_purchase LIMIT 50
Q: which products have never sold? (the 5 dearest)
SELECT p.name, p.selling_price FROM products p WHERE p.is_active = 1 AND NOT EXISTS (SELECT 1 FROM sale_items si JOIN sales s ON s.id = si.sale_id WHERE si.product_id = p.id AND s.status = 'completed') ORDER BY p.selling_price DESC LIMIT 5
Q: how many customers have a phone number starting with 07?
SELECT COUNT(*) AS customers FROM customers WHERE is_walk_in = 0 AND phone LIKE '07%'
Q: what is the average sale per weekday?
SELECT DAYNAME(created_at) AS weekday, AVG(total) AS average_sale, COUNT(*) AS sales FROM sales WHERE status = 'completed' GROUP BY DAYOFWEEK(created_at), DAYNAME(created_at) ORDER BY DAYOFWEEK(created_at)
"""

_FORBIDDEN = re.compile(
    r"\b(insert|update|delete|drop|alter|create|truncate|replace|grant|revoke|call|set|lock|unlock|handler|load|"
    r"outfile|dumpfile|into|sleep|benchmark|get_lock|release_lock|information_schema|performance_schema|mysql|sys|"
    r"password_hash|manager_slot|uuid|show|describe|explain|prepare|execute|union)\b"
)


def check_sql(sql: str) -> str:
    """The query, tidied, if it is safe to run - otherwise ValueError."""
    sql = sql.strip().rstrip(";").strip()
    low = sql.lower()
    if not low:
        raise ValueError("empty query")
    if not re.match(r"(select|with)\b", low):
        raise ValueError("only a SELECT is allowed")
    if ";" in sql or "--" in sql or "/*" in sql or "#" in sql or "`" in sql:
        raise ValueError("one plain statement only")
    bad = _FORBIDDEN.search(low)
    if bad:
        raise ValueError(f"'{bad.group(0)}' is not allowed")
    tables = re.findall(r"\b(?:from|join)\s+([a-z_][a-z0-9_]*)", low)
    if not tables:
        raise ValueError("no table")
    unknown = [t for t in tables if t not in ALLOWED_TABLES and t not in _ctes(low)]
    if unknown:
        raise ValueError(f"unknown table {unknown[0]}")
    if re.search(r"\busers\b", low) and "*" in re.sub(r"count\(\s*\*\s*\)", "", low):
        raise ValueError("do not select * from users")
    if not re.search(r"\blimit\s+\d+\s*$", low):
        sql += f" LIMIT {MAX_ROWS}"
    return sql


def _ctes(low: str) -> set[str]:
    return set(re.findall(r"\b([a-z_][a-z0-9_]*)\s+as\s*\(", low)) if low.startswith("with") else set()


def extract_sql(text: str) -> str:
    text = re.sub(r"```(?:sql)?", "", text, flags=re.I)
    m = re.search(r"\b(select|with)\b", text, re.I)
    return text[m.start():].split(";")[0].strip() if m else ""


def run_readonly(sql: str) -> tuple[list[str], list[dict]]:
    """Runs on its own read-only connection and returns (columns, rows)."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute("SET SESSION TRANSACTION READ ONLY")
            for stmt in ("SET SESSION max_statement_time = 10", "SET SESSION MAX_EXECUTION_TIME = 10000"):
                try:
                    cur.execute(stmt)   # MariaDB / MySQL name it differently; one of them applies
                except Exception:
                    pass
            cur.execute(sql)
            rows = list(cur.fetchmany(MAX_ROWS))
            cols = [d[0] for d in cur.description or []]
        return cols, rows
    finally:
        conn.close()


def _cell(v) -> str:
    if v is None:
        return "-"
    if isinstance(v, float):
        return dates.fmt_amount(v) if abs(v) >= 1000 or v != int(v) else str(int(v))
    if hasattr(v, "year") and hasattr(v, "month"):
        return dates.fmt_datetime(v) if hasattr(v, "hour") else dates.fmt_date(v)
    return str(v)


def _generate(question: str, today: str, problem: str | None = None, previous: str | None = None) -> str:
    system = (
        "You write one MySQL SELECT query that answers a shopkeeper's question from this database. "
        "Reply with ONLY the SQL, nothing else. Always try: pick the closest tables and columns. "
        "Reply NO_QUERY only if the question has nothing to do with a shop's records.\n"
        "Rules: read-only; one statement; completed sales only (sales.status = 'completed') unless asked about voids; "
        f"keep results small (LIMIT 50 or less); today is {today}; use CURDATE()/NOW() for relative dates; "
        "name columns clearly with AS.\n\nTables:\n" + SCHEMA
    )
    messages = [{"role": "system", "content": system}]
    for block in EXAMPLES.split("Q: ")[1:]:      # worked examples go in as earlier turns
        ask, _, sql = block.partition("\n")
        messages += [{"role": "user", "content": ask.strip()}, {"role": "assistant", "content": sql.strip()}]
    messages.append({"role": "user", "content": question})
    if problem and previous:
        messages += [{"role": "assistant", "content": previous},
                     {"role": "user", "content": f"That failed: {problem}. Write a corrected query. Reply with only the SQL."}]
    return llm.chat(messages)


def _describe(cols: list[str], rows: list[dict]) -> str:
    if len(rows) == 1 and len(cols) == 1:
        return f"{cols[0].replace('_', ' ').capitalize()}: {_cell(rows[0][cols[0]])}."
    more = f" Showing the first {SHOWN_ROWS}." if len(rows) > SHOWN_ROWS else ""
    return f"Found {len(rows)} result{'s' if len(rows) != 1 else ''}.{more}"


def _explain(question: str, cols: list[str], rows: list[dict]) -> str:
    shown = [{c: _cell(r[c]) for c in cols} for r in rows[:30]]
    reply = llm.chat([
        {"role": "system", "content": "You are a friendly shop assistant. Answer the shopkeeper's question in one to three short sentences "
                                      "using ONLY the result rows given. Keep every number exactly as given. Do not invent anything."},
        {"role": "user", "content": f"Question: {question}\nResult rows ({len(rows)} in all): {shown}"},
    ])
    return reply or f"I found {len(rows)} result{'s' if len(rows) != 1 else ''}."


def try_answer(c: Ctx) -> dict | None:
    """An answer from the model, or None when it can't help (not a manager, no
    model running, or it never produced a usable query)."""
    if not c.manager or not llm.available():
        return None
    try:
        today = dates.fmt_date(c.now)
        raw = _generate(c.text, today)
        sql, error = "", None
        for attempt in range(2):
            if "NO_QUERY" in raw.upper() and not extract_sql(raw):
                return None
            candidate = extract_sql(raw)
            try:
                sql = check_sql(candidate)
                cols, rows = run_readonly(sql)
                error = None
                break
            except Exception as e:  # a bad query: tell the model once and let it try again
                error = str(e)
                if attempt == 0:
                    raw = _generate(c.text, today, error, candidate)
        if error is not None:
            return None
        if not rows:
            reply = "I looked, and found nothing matching that."
        else:
            # A small model retelling the rows can get them wrong, so by default the
            # reply is plain and the table carries the detail (DUKA_OLLAMA_EXPLAIN=1
            # asks the model to put it in words, at the cost of a second, slower call).
            reply = _explain(c.text, cols, rows) if os.environ.get("DUKA_OLLAMA_EXPLAIN") == "1" else _describe(cols, rows)
        tbl = table(cols, [[_cell(r[col]) for col in cols] for r in rows[:SHOWN_ROWS]]) if rows and len(cols) > 0 and not (len(rows) == 1 and len(cols) == 1) else None
        out = answer(reply, tbl)
        out.update(ai=True, sql=sql)
        return out
    except Exception:
        return None
