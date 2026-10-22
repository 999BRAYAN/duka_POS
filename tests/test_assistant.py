"""The assistant and the stock-health figures."""

from datetime import datetime, timedelta

from api_helpers import make_product, sell as api_sell
from duka.db import Db, connect


def ask(client, q):
    r = client.post("/api/assistant", {"question": q})
    assert r.status_code == 200, r.get_json()
    return r.get_json()


def backdate_sales(days_ago):
    """Move every sale so the shop looks like it has `days_ago` days of history."""
    db = Db(connect())
    db.execute("UPDATE sales SET created_at = %s", (datetime.now() - timedelta(days=days_ago),))
    db.close()


def sell(client, product, qty):
    r = api_sell(client, [(product, qty, None)], paymentMethod="cash", amountPaid=product["sellingPrice"] * qty)
    assert r.status_code == 200, r.get_json()


def test_stock_and_price_questions_work_for_a_cashier(manager, cashier):
    make_product(manager, "Brass tap", cost=100, price=200, stock=7)
    a = ask(cashier, "how many brass taps do we have?")
    assert "7" in a["reply"] and "Brass tap" in a["reply"]
    assert "200" in ask(cashier, "price of brass tap")["reply"]
    assert "Only a manager" in ask(cashier, "how much profit today")["reply"]
    assert "Only a manager" in ask(cashier, "which products are not selling")["reply"]


def test_fast_slow_dead_and_reorder(manager):
    fast = make_product(manager, "Soda", cost=40, price=70, stock=30, reorder=5)
    slow = make_product(manager, "Candle", cost=20, price=40, stock=500, reorder=5)
    dead = make_product(manager, "Old calendar", cost=10, price=25, stock=40, reorder=5)
    sell(manager, fast, 24)
    sell(manager, slow, 1)
    backdate_sales(20)          # ~20 days of history: soda ~1.2/day, 25 left lasts ~20d

    data = manager.get("/api/insights").get_json()
    by = {p["name"]: p for p in data["products"]}
    assert by["Soda"]["abc"] == "A"
    assert by["Old calendar"]["status"] == "dead"
    assert by["Candle"]["status"] == "overstocked"

    reply = ask(manager, "which products are not selling?")
    names = [r[0] for r in reply["table"]["rows"]]
    assert "Old calendar" in names and "Candle" in names and "Soda" not in names
    assert "worth" in ask(manager, "where is my money tied up")["reply"]

    top = ask(manager, "what are my best sellers")
    assert top["table"]["rows"][0][1] == "Soda"

    # 6 Soda left selling ~1.2 a day: about 5 days of cover, so it needs buying.
    assert by["Soda"]["status"] == "reorder" and by["Soda"]["suggestedOrder"] > 0
    assert "Soda" in [r[0] for r in ask(manager, "what should I reorder")["table"]["rows"]]
    assert "a day" in ask(manager, "how fast is soda selling")["reply"]


def test_little_history_does_not_call_things_slow(manager):
    p = make_product(manager, "Biscuits", stock=10)
    make_product(manager, "Sugar", stock=10)
    sell(manager, p, 1)
    data = manager.get("/api/insights").get_json()
    assert not data["enoughHistory"]
    assert {i["status"] for i in data["products"]} <= {"new", "out", "reorder"}


def test_unknown_and_empty_questions(manager):
    assert ask(manager, "")["suggestions"]
    assert "didn't catch" in ask(manager, "purple monkey dishwasher")["reply"]
    assert "No completed sales" in ask(manager, "sales today")["reply"]
    assert "Nothing is out of stock" in ask(manager, "anything out of stock?")["reply"]
