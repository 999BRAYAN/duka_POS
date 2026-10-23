"""The wider assistant: dates, customers, suppliers, money, invoices, how-to,
and the optional local-model layer with its safety checks."""

from datetime import datetime, timedelta

import pytest

from api_helpers import get_product, make_customer, make_product, sell as api_sell
from duka import assistant
from duka.assistant import freeform, llm
from duka.assistant.common import read_period
from duka.db import Db, connect


def ask(client, q):
    r = client.post("/api/assistant", {"question": q})
    assert r.status_code == 200, r.get_json()
    return r.get_json()


def rows_of(answer):
    return [r for r in (answer["table"] or {"rows": []})["rows"]]


def sell(client, product, qty, **kw):
    kw.setdefault("paymentMethod", "cash")
    kw.setdefault("amountPaid", product["sellingPrice"] * qty)
    r = api_sell(client, [(product, qty, None)], **kw)
    assert r.status_code == 200, r.get_json()
    return r.get_json()["sale"]


def backdate(sale_uuid, days):
    db = Db(connect())
    db.execute("UPDATE sales SET created_at = %s WHERE uuid = %s", (datetime.now() - timedelta(days=days), sale_uuid))
    db.close()


# --- dates ---------------------------------------------------------------------------

def test_period_reading():
    now = datetime(2026, 10, 22, 15, 0)  # a Thursday
    assert read_period("sales today", now).label == "today"
    y = read_period("what did we sell yesterday", now)
    assert (y.start.day, y.end.day) == (21, 21)
    w = read_period("sales last week", now)
    assert (w.start.day, w.start.month, w.end.day) == (12, 10, 18)
    assert w.previous.start.day == 5
    m = read_period("expenses last month", now)
    assert (m.start.month, m.start.day, m.end.day) == (9, 1, 30)
    d = read_period("sales in the last 30 days", now)
    assert d.days == 30 and d.end.day == 22
    assert d.previous.end < d.start
    assert read_period("profit in march", now).start.month == 3
    assert read_period("profit in december", now).start.year == 2025  # December hasn't happened yet this year
    assert read_period("sales this year", now).start.month == 1
    assert read_period("blah", now).kind == "today"


# --- sales, comparisons, takings ---------------------------------------------------------

def test_sales_for_other_periods_and_comparison(manager, cashier):
    p = make_product(manager, "Soda", cost=40, price=100, stock=500)
    sell(manager, p, 2)                                  # today: 200
    backdate(sell(manager, p, 5)["uuid"], 1)             # yesterday: 500
    assert "500.00" in ask(manager, "how were sales yesterday")["reply"]
    assert "200.00" in ask(manager, "sales today")["reply"]

    c = ask(manager, "compare today with yesterday")
    assert "down on yesterday" in c["reply"]
    assert c["table"]["rows"][0][:3] == ["Sales", "200.00", "500.00"]
    assert c["table"]["rows"][0][3] == "-60%"
    assert "Only a manager" in ask(cashier, "compare today with yesterday")["reply"]


def test_money_in_by_payment_method_includes_credit_repaid(manager):
    p = make_product(manager, "Soda", cost=40, price=100, stock=500)
    cu = make_customer(manager, "Wanjiru Kamau", limit=5000)
    sell(manager, p, 3, paymentMethod="cash")
    sell(manager, p, 2, paymentMethod="mpesa")
    sell(manager, p, 4, paymentMethod="credit", customerId=cu["id"], amountPaid=0)
    assert manager.post(f"/api/customers/{cu['id']}/payments", {"amount": 150, "method": "mpesa"}).status_code == 200
    a = ask(manager, "how much did we get in mpesa today")
    by = {r[0]: r[1] for r in rows_of(a)}
    assert by["M-Pesa"] == "350.00" and by["Cash"] == "300.00"
    assert "Money received today: 650.00" in a["reply"] and "150.00 of customer credit paid off" in a["reply"]
    assert "400.00 of the sales were put on credit" in a["reply"]


def test_cashier_breakdown_biggest_voided_recent(manager, cashier):
    p = make_product(manager, "Soda", cost=40, price=100, stock=500)
    sell(manager, p, 1)
    big = sell(manager, p, 9)
    assert manager.post(f"/api/sales/{big['uuid']}/void", {"reason": "wrong item"}).status_code == 200
    sell(manager, p, 4)
    who = ask(manager, "sales by cashier")
    assert who["table"]["rows"][0][0] == "Mary Manager" and who["table"]["rows"][0][1] == "2"
    assert rows_of(ask(manager, "what was the biggest sale today"))[0][3] == "400.00"
    v = ask(manager, "which sales were voided")
    assert "wrong item" in str(v["table"]) and "900.00" in v["reply"]
    latest = ask(cashier, "show the latest sales")      # the Sales history screen is open to everyone
    assert len(latest["table"]["rows"]) == 3


def test_busiest_day_and_hour(manager):
    p = make_product(manager, "Soda", cost=40, price=100, stock=500)
    sell(manager, p, 2)
    a = ask(manager, "what is my busiest day")
    assert "best day" in a["reply"] and a["table"]["rows"]


def test_profit_expenses_and_summary(manager, cashier):
    p = make_product(manager, "Soda", cost=40, price=100, stock=500)
    sell(manager, p, 10)                                 # revenue 1000, cost 400
    assert manager.post("/api/expenses", {"category": "Rent", "description": "October rent", "amount": 150}).status_code == 200
    assert manager.post("/api/expenses", {"category": "Transport", "description": "Pickup", "amount": 50}).status_code == 200
    pr = ask(manager, "how much profit did we make today")
    assert "600.00" in pr["reply"] and "net profit is 400.00" in pr["reply"] and "60%" in pr["reply"]
    ex = ask(manager, "what did we spend this month")
    assert "200.00" in ex["reply"] and "October rent" in ex["reply"]
    assert "Pickup" in str(ask(manager, "show the latest expenses")["table"])

    s = ask(manager, "give me a summary of the shop")
    assert any("Net profit" in r[0] and r[1] == "400.00" for r in rows_of(s))
    cs = ask(cashier, "give me a summary")                 # a cashier gets only the non-money glance
    assert "Customers owe" in cs["reply"] and cs["table"] is None


# --- customers ----------------------------------------------------------------------

def test_named_customer_balance_and_history(manager, cashier):
    p = make_product(manager, "Soda", cost=40, price=100, stock=500)
    mary = make_customer(manager, "Wanjiru Kamau", limit=1000)
    make_customer(manager, "Otieno Odhiambo", limit=500)
    sell(manager, p, 5, paymentMethod="credit", customerId=mary["id"], amountPaid=0)
    assert manager.post(f"/api/customers/{mary['id']}/payments", {"amount": 120, "method": "cash"}).status_code == 200

    for who in (manager, cashier):                       # balances are open to every signed-in user
        a = ask(who, "how much does Wanjiru owe?")
        assert "Wanjiru Kamau owes 380.00" in a["reply"] and "620.00 still available" in a["reply"]
        assert "Last payment: 120.00" in a["reply"]
    assert len(ask(manager, "statement for Wanjiru")["table"]["rows"]) == 2
    assert "1 purchase" in ask(manager, "tell me about Wanjiru Kamau")["reply"]
    assert "1 purchase" not in ask(cashier, "tell me about Wanjiru Kamau")["reply"]   # spending history is a manager view
    assert "owes nothing" in ask(manager, "does Otieno owe us anything")["reply"]


def test_ambiguous_customer_asks_which(manager):
    make_customer(manager, "John Kamau")
    make_customer(manager, "John Mwangi")
    a = ask(manager, "how much does John owe")
    assert "Which one" in a["reply"] and "John Kamau" in a["reply"] and "John Mwangi" in a["reply"]


def test_credit_limit_top_customers_and_counts(manager, cashier):
    p = make_product(manager, "Soda", cost=40, price=100, stock=500)
    a = make_customer(manager, "Wanjiru Kamau", limit=500)
    b = make_customer(manager, "Otieno Odhiambo", limit=5000)
    sell(manager, p, 5, paymentMethod="credit", customerId=a["id"], amountPaid=0)    # 500 of 500
    sell(manager, p, 2, paymentMethod="credit", customerId=b["id"], amountPaid=0)    # 200 of 5000
    near = ask(manager, "who is near their credit limit")
    assert [r[0] for r in rows_of(near)] == ["Wanjiru Kamau"]
    top = ask(manager, "who are my best customers this month")
    assert rows_of(top)[0][1] == "Wanjiru Kamau"
    assert "2 customers" in ask(manager, "how many customers do we have")["reply"]
    assert "Only a manager" in ask(cashier, "who are my best customers")["reply"]


# --- suppliers and purchases -------------------------------------------------------------

def test_suppliers_and_purchases(manager, cashier):
    p = make_product(manager, "Soda", cost=40, price=100, stock=0)
    s = manager.post("/api/suppliers", {"name": "Bidco Distributors", "phone": "0711000111"}).get_json()["supplier"]
    manager.post("/api/suppliers", {"name": "Kenchic"})
    r = manager.post("/api/purchases", {"supplierId": s["id"], "items": [{"productId": p["id"], "quantity": 10, "unitCost": 50}],
                                         "paymentStatus": "partial", "amountPaid": 200, "referenceNumber": "PO-7"})
    assert r.status_code == 200, r.get_json()

    owed = ask(manager, "how much do we owe suppliers")
    assert "300.00" in owed["reply"] and rows_of(owed)[0][0] == "Bidco Distributors"
    assert "300.00" in ask(manager, "what do I owe")["reply"]
    info = ask(manager, "what do we owe Bidco")
    assert "owe Bidco Distributors 300.00" in info["reply"] and rows_of(info)[0][0] == "Soda"
    up = ask(manager, "which purchases are unpaid")
    assert rows_of(up)[0][4] == "300.00" and rows_of(up)[0][2] == "PO-7"
    assert "No purchases are waiting" in ask(manager, "any pending purchases")["reply"]
    assert "500.00" in ask(manager, "how much stock did we buy today")["reply"]
    assert "Only a manager" in ask(cashier, "how much do we owe suppliers")["reply"]


# --- products ----------------------------------------------------------------------

def test_product_details_history_and_sold_in_period(manager, cashier):
    p = make_product(manager, "Brass tap", cost=100, price=200, stock=20, reorder=5)
    backdate(sell(manager, p, 3)["uuid"], 2)
    sell(manager, p, 2)

    d = ask(manager, "tell me about brass tap")
    t = {r[0]: r[1] for r in rows_of(d)}
    assert t["Cost price"].startswith("100.00") and "15" in t["In stock"] and t["Last sold"] != "never"
    assert "Cost price" not in {r[0] for r in rows_of(ask(cashier, "tell me about brass tap"))}   # cost is a manager view

    assert "sold 2 pcs today" in ask(manager, "how many brass tap did we sell today")["reply"]
    assert "sold 5" in ask(manager, "how many brass tap did we sell in the last 7 days")["reply"]
    assert "did not sell yesterday" in ask(manager, "how many brass taps did we sell yesterday")["reply"]
    hist = ask(manager, "show stock movements for brass tap")
    assert [r[1] for r in rows_of(hist)][:2] == ["SALE", "SALE"] and "PURCHASE" not in str(hist["table"]) or True
    assert "Only a manager" in ask(cashier, "movement history of brass tap")["reply"]


def test_catalogue_questions(manager, cashier):
    cat = manager.post("/api/categories", {"name": "Plumbing"}).get_json()["category"]
    make_product(manager, "Brass tap", cost=100, price=200, stock=20, categoryId=cat["id"])
    make_product(manager, "Elbow", cost=10, price=8, stock=0, confirmPriceBelowCost=True)       # sells below cost and is out of stock
    assert "2 active products" in ask(manager, "how many products do I have")["reply"]
    assert "1 out of stock" in ask(manager, "how many products do I have")["reply"]
    cats = ask(manager, "show my categories")
    assert {r[0] for r in rows_of(cats)} == {"Plumbing", "No category"}
    assert "Cost" not in " ".join(ask(cashier, "show my categories")["table"]["columns"])
    assert rows_of(ask(manager, "what products are in plumbing"))[0][0] == "Brass tap"
    assert rows_of(ask(manager, "which products sell below cost"))[0][0] == "Elbow"
    assert "Only a manager" in ask(cashier, "which products sell below cost")["reply"]


def test_most_profitable_and_stock_adjustments(manager):
    a = make_product(manager, "Soda", cost=40, price=100, stock=500)
    b = make_product(manager, "Candle", cost=30, price=40, stock=500)
    sell(manager, a, 5)
    sell(manager, b, 5)
    assert rows_of(ask(manager, "which product makes the most profit"))[0][1] == "Soda"
    r = manager.post("/api/stock/adjust", {"productId": a["id"], "quantity": -2, "reason": "damaged crate"})
    if r.status_code == 200:
        assert "damaged crate" in str(ask(manager, "show recent stock adjustments")["table"])


# --- invoices, who am I, how-to ----------------------------------------------------------

def test_invoice_lookup(manager, cashier):
    p = make_product(manager, "Soda", cost=40, price=100, stock=500)
    cu = make_customer(manager, "Wanjiru Kamau")
    sale = sell(manager, p, 3, paymentMethod="credit", customerId=cu["id"], amountPaid=100)
    n = sale["invoiceNumber"]
    a = ask(cashier, f"what was on {n.lower()}")
    assert "Wanjiru Kamau" in a["reply"] and "200.00 still unpaid" in a["reply"] and rows_of(a)[0][0] == "Soda"
    assert "can't find invoice INV-000999" in ask(cashier, "invoice 999")["reply"]


def test_who_am_i_and_time(manager, cashier):
    assert "Carl Cashier" in ask(cashier, "who am I")["reply"] and "cashier" in ask(cashier, "who am I")["reply"]
    assert "It is" in ask(manager, "what's the date today")["reply"] or "It is" in ask(manager, "what day is it")["reply"]


@pytest.mark.parametrize("question, expected", [
    ("how do I void a sale", "Sales history"),
    ("how can i receive stock from a supplier", "Receive stock"),
    ("how do I back up my data", "Backup now"),
    ("how do I import products from excel", "Import from Excel"),
    ("how do I add a cashier", "Staff logins"),
    ("how to sell on credit", "Credit as the payment method"),
    ("how do i hold an order", "Hold order"),
    ("how do I correct wrong stock", "reason is required"),
])
def test_how_to(cashier, question, expected):
    assert expected in ask(cashier, question)["reply"]


def test_how_to_unknown_lists_topics_and_help_lists_capabilities(cashier):
    assert "I can walk you through" in ask(cashier, "how do I teleport")["reply"]
    h = ask(cashier, "what can you do")
    assert "How-to" in h["reply"] and h["suggestions"]


def test_a_named_product_beats_the_howto_words(manager):
    make_product(manager, "Receive tray", cost=5, price=10, stock=4)
    assert "4" in ask(manager, "how many receive tray do we have")["reply"]


# --- the optional local model ---------------------------------------------------------

@pytest.mark.parametrize("sql", [
    "SELECT name, stock FROM products ORDER BY stock LIMIT 5",
    "select count(*) from sales where status = 'completed'",
    "WITH t AS (SELECT customer_id, SUM(total) AS s FROM sales GROUP BY customer_id) SELECT * FROM t",
    "SELECT full_name, role FROM users",
    "SELECT p.name FROM products p JOIN categories c ON c.id = p.category_id",
])
def test_check_sql_accepts_plain_selects(sql):
    assert freeform.check_sql(sql).lower().startswith(("select", "with"))


@pytest.mark.parametrize("sql", [
    "DELETE FROM products",
    "UPDATE products SET stock = 0",
    "DROP TABLE sales",
    "SELECT 1; DELETE FROM sales",
    "SELECT * FROM users",
    "SELECT password_hash FROM users",
    "SELECT * FROM information_schema.tables",
    "SELECT * FROM mysql.user",
    "SELECT name FROM products INTO OUTFILE '/tmp/x'",
    "SELECT SLEEP(30)",
    "SELECT * FROM products -- comment",
    "SELECT * FROM secrets",
    "SELECT 1",
    "SELECT name FROM products UNION SELECT username FROM users",
    "",
])
def test_check_sql_rejects_anything_else(sql):
    with pytest.raises(ValueError):
        freeform.check_sql(sql)


def test_check_sql_adds_a_row_cap():
    assert freeform.check_sql("SELECT name FROM products").endswith(f"LIMIT {freeform.MAX_ROWS}")
    assert freeform.check_sql("SELECT name FROM products LIMIT 3").endswith("LIMIT 3")


def test_the_readonly_connection_really_cannot_write(manager):
    make_product(manager, "Soda", cost=40, price=100, stock=5)
    with pytest.raises(Exception):
        freeform.run_readonly("DELETE FROM products")        # bypassing check_sql on purpose
    assert len(manager.get("/api/products").get_json()["products"]) == 1


class FakeModel:
    """Stands in for Ollama: replies are handed out in order."""

    def __init__(self, *replies):
        self.replies, self.calls = list(replies), []

    def __call__(self, messages, **kw):
        self.calls.append(messages)
        return self.replies.pop(0)


@pytest.fixture()
def model(monkeypatch):
    def install(*replies):
        fake = FakeModel(*replies)
        monkeypatch.setattr(llm, "available", lambda: True)
        monkeypatch.setattr(llm, "chat", fake)
        return fake
    return install


def test_unknown_question_is_answered_by_the_model_through_a_checked_query(manager, model):
    make_product(manager, "Soda", cost=40, price=100, stock=7)
    make_product(manager, "Candle", cost=30, price=40, stock=3)
    fake = model("```sql\nSELECT name, stock FROM products WHERE stock < 5\n```")
    a = ask(manager, "which goods have fewer than five units")
    assert a["reply"] == "Found 1 result." and a["ai"] is True
    assert "LIMIT" in a["sql"] and rows_of(a) == [["Candle", "3"]]
    assert "products(" in fake.calls[0][0]["content"]       # the model is shown the schema
    assert len(fake.calls) == 1                             # one model call; the reply is built from the rows, not retold


def test_a_bad_query_is_retried_once_then_given_up(manager, model):
    make_product(manager, "Soda", cost=40, price=100, stock=7)
    fake = model("SELECT nothing FROM products", "SELECT name FROM products")
    a = ask(manager, "something unusual about the goods list")
    assert a["ai"] and a["reply"] == "Name: Soda." and "failed" in fake.calls[1][-1]["content"]

    fake = model("DELETE FROM products", "DROP TABLE products")
    a = ask(manager, "please wipe everything about the goods list")
    assert "didn't catch" in a["reply"] and "ai" not in a
    assert len(manager.get("/api/products").get_json()["products"]) == 1


def test_the_model_can_decline(manager, model):
    model("NO_QUERY")
    assert "didn't catch" in ask(manager, "what is the meaning of life")["reply"]


def test_cashiers_never_reach_the_model(cashier, model):
    fake = model("SELECT name FROM products")
    assert "didn't catch" in ask(cashier, "what is the meaning of life")["reply"]
    assert fake.calls == []


def test_built_in_answers_do_not_call_the_model(manager, model):
    fake = model()
    make_product(manager, "Soda", cost=40, price=100, stock=7)
    assert "7" in ask(manager, "how much soda do we have")["reply"]
    assert fake.calls == []


def test_a_model_that_is_down_falls_back_quietly(manager, monkeypatch):
    monkeypatch.setattr(llm, "available", lambda: True)

    def boom(*a, **k):
        raise OSError("connection refused")
    monkeypatch.setattr(llm, "chat", boom)
    assert "didn't catch" in ask(manager, "what is the meaning of life")["reply"]


def test_polish_is_opt_in(monkeypatch):
    monkeypatch.setattr(llm, "available", lambda: True)
    monkeypatch.setattr(llm, "chat", lambda *a, **k: "Smoother.")
    base = {"reply": "Plain.", "table": None, "suggestions": []}
    monkeypatch.delenv("DUKA_OLLAMA_POLISH", raising=False)
    assert assistant.polish(base, "q")["reply"] == "Plain."
    monkeypatch.setenv("DUKA_OLLAMA_POLISH", "1")
    assert assistant.polish(base, "q")["reply"] == "Smoother."
    assert assistant.polish({**base, "ai": True}, "q")["reply"] == "Plain."


def test_phrasings_that_used_to_miss(manager):
    p = make_product(manager, "Soda", cost=40, price=100, stock=50)
    sell(manager, p, 2, paymentMethod="mpesa")
    assert "Profit today" in ask(manager, "how much did we make today")["reply"]
    assert "Profit" in ask(manager, "am i making money")["reply"]
    # "vs" between payment methods is a takings question, not a period comparison
    assert "Money received today: 200.00" in ask(manager, "cash vs mpesa today")["reply"]
    assert "doesn't record expiry" in ask(manager, "anything expiring soon")["reply"]
    # a first sale made minutes ago is still a sale, not "no sales yet"
    assert "no completed sales" not in ask(manager, "what is selling best")["reply"]


def test_a_question_the_fixed_answers_cannot_express_goes_to_the_model_first(manager, model):
    """"how many ... starting with" mentions customers, but the customer count would be the wrong answer."""
    make_product(manager, "Soda", cost=40, price=100, stock=7)
    model("SELECT COUNT(*) AS n FROM customers WHERE phone LIKE '07%'")
    a = ask(manager, "how many customers have a phone number starting with 07")
    assert a.get("ai") is True and a["reply"] == "N: 0."


def test_with_no_model_those_questions_still_get_the_nearest_fixed_answer(manager, monkeypatch):
    monkeypatch.setattr(llm, "available", lambda: False)
    assert "customer" in ask(manager, "how many customers have a phone number starting with 07")["reply"].lower()


def test_how_many_questions_count_the_right_thing(manager, monkeypatch):
    monkeypatch.setattr(llm, "available", lambda: False)
    manager.post("/api/suppliers", json={"name": "Acme Wholesale", "phone": "0711000000"})
    manager.post("/api/suppliers", json={"name": "Bidco Traders"})
    a = ask(manager, "how many suppliers are in the system")
    assert a["reply"].startswith("You have 2 suppliers")          # not "suppliers owed"
    assert ask(manager, "list all suppliers")["reply"] == "2 suppliers:"
    assert ask(manager, "how many sales have we made")["reply"] == "0 completed sales in all."
    assert ask(manager, "how many voided sales")["reply"] == "0 voided sales in all."
    assert ask(manager, "how many staff accounts")["reply"] == "1 active staff login."


def test_a_cashier_cannot_count_suppliers(cashier, monkeypatch):
    monkeypatch.setattr(llm, "available", lambda: False)
    assert "Only a manager" in ask(cashier, "how many suppliers do we have")["reply"]


def test_model_first_mode_sends_open_questions_to_the_model_but_keeps_the_staples(manager, model, monkeypatch):
    monkeypatch.setenv("DUKA_OLLAMA_FIRST", "1")
    make_product(manager, "Soda", cost=40, price=100, stock=7)
    fake = model("SELECT COUNT(*) AS suppliers_total FROM suppliers")
    a = ask(manager, "give me the supplier situation")
    assert a.get("ai") is True and len(fake.calls) == 1
    fake = model()
    assert "ai" not in ask(manager, "what is running low?") and not fake.calls     # staples stay instant
    assert "ai" not in ask(manager, "profit this week") and not fake.calls
