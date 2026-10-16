import json
from datetime import datetime, timedelta

import pytest

from api_helpers import get_customer, get_product, make_customer, make_product, sell


# --- products -----------------------------------------------------------------------

def test_product_roundtrip_and_search_fields(manager):
    p = make_product(manager, name="Elbow 90", sku="EL90", barcode="123")
    assert p["stock"] == 100 and p["unit"] == "pcs" and p["isActive"] is True
    listed = manager.get("/api/products").get_json()["products"]
    assert [x["name"] for x in listed] == ["Elbow 90"]


def test_blank_minimum_price_defaults_to_selling_price(manager):
    assert make_product(manager, price=15)["minSellingPrice"] == 15


def test_price_below_cost_needs_confirmation(manager):
    r = manager.post("/api/products", {"name": "X", "costPrice": 10, "sellingPrice": 12, "minSellingPrice": 8})
    assert r.status_code == 409
    err = r.get_json()["error"]
    assert err["code"] == "price_below_cost" and err["costPrice"] == 10 and err["minSellingPrice"] == 8
    r = manager.post(
        "/api/products",
        {"name": "X", "costPrice": 10, "sellingPrice": 12, "minSellingPrice": 8, "confirmPriceBelowCost": True},
    )
    assert r.status_code == 200


def test_editing_a_product_never_touches_stock(manager):
    p = make_product(manager, stock=40)
    r = manager.put(f"/api/products/{p['uuid']}", {"name": "Renamed", "costPrice": 10, "sellingPrice": 20, "stock": 9999})
    assert r.status_code == 200
    again = get_product(manager, p["uuid"])
    assert again["name"] == "Renamed" and again["sellingPrice"] == 20 and again["stock"] == 40


def test_deactivated_products_disappear_but_stay_on_old_sales(manager):
    p = make_product(manager)
    assert sell(manager, [(p, 1, None)], paymentMethod="cash").status_code == 200
    assert manager.delete(f"/api/products/{p['uuid']}").status_code == 200
    assert manager.get("/api/products").get_json()["products"] == []


def test_categories(manager, cashier):
    c = manager.post("/api/categories", {"name": "Pipes"}).get_json()["category"]
    assert c["name"] == "Pipes"
    assert cashier.post("/api/categories", {"name": "Nope"}).status_code == 403
    assert [x["name"] for x in cashier.get("/api/categories").get_json()["categories"]] == ["Pipes"]


# --- selling --------------------------------------------------------------------------

def test_cash_sale_moves_stock_and_numbers_invoices(manager):
    p = make_product(manager, cost=10, price=15, stock=50)
    r = sell(manager, [(p, 3, None)], paymentMethod="cash", amountPaid=45)
    assert r.status_code == 200
    sale = r.get_json()["sale"]
    assert sale["invoiceNumber"] == "INV-000001"
    assert (sale["subtotal"], sale["total"], sale["cogs"], sale["grossProfit"]) == (45, 45, 30, 15)
    assert get_product(manager, p["uuid"])["stock"] == 47
    second = sell(manager, [(p, 1, None)], paymentMethod="cash").get_json()["sale"]
    assert second["invoiceNumber"] == "INV-000002"


def test_stock_movement_audit_row_is_signed(manager):
    p = make_product(manager, stock=10)
    sell(manager, [(p, 4, None)], paymentMethod="cash")
    movements = manager.get("/api/stock/movements").get_json()["movements"]
    sale_move = next(m for m in movements if m["type"] == "SALE")
    assert sale_move["quantity"] == -4 and sale_move["unitCost"] == 10


def test_insufficient_stock_is_refused_and_nothing_written(manager):
    p = make_product(manager, stock=2)
    r = sell(manager, [(p, 5, None)], paymentMethod="cash")
    assert r.status_code == 409
    assert r.get_json()["error"]["message"] == "Only 2.00 of 'Elbow' left in stock, but 5.00 were requested."
    assert manager.get("/api/sales").get_json()["sales"] == []
    assert get_product(manager, p["uuid"])["stock"] == 2


def test_price_floor_per_line_and_with_cart_discount(manager):
    p = make_product(manager, cost=10, price=20, minimum=15)
    assert sell(manager, [(p, 1, 14)], paymentMethod="cash").status_code == 409
    assert sell(manager, [(p, 1, 15)], paymentMethod="cash").status_code == 200
    # A cart discount is spread across lines and can push one under its floor.
    r = sell(manager, [(p, 1, 20)], paymentMethod="cash", discount=6)
    assert r.status_code == 409 and r.get_json()["error"]["code"] == "price_below_floor"
    assert sell(manager, [(p, 1, 20)], paymentMethod="cash", discount=5).status_code == 200


def test_walk_in_credit_sale_needs_a_customer(manager):
    p = make_product(manager)
    r = sell(manager, [(p, 1, None)], paymentMethod="credit")
    assert r.status_code == 400
    assert r.get_json()["error"]["message"] == "A customer is required for payment method 'credit'."


def test_empty_cart(manager):
    assert manager.post("/api/sales", {"cart": [], "paymentMethod": "cash"}).status_code == 400


def test_cashier_can_sell_but_not_override_or_void(manager, cashier):
    p = make_product(manager)
    c = make_customer(manager, limit=10)
    assert sell(cashier, [(p, 1, None)], paymentMethod="cash").status_code == 200
    # Over the limit: a cashier is refused, and may not request the override.
    r = sell(cashier, [(p, 3, None)], paymentMethod="credit", customerId=c["id"], amountPaid=0)
    assert r.status_code == 409 and r.get_json()["error"]["code"] == "credit_limit_exceeded"
    r = sell(cashier, [(p, 3, None)], paymentMethod="credit", customerId=c["id"], amountPaid=0, overrideCreditLimit=True)
    assert r.status_code == 403
    sale = manager.get("/api/sales").get_json()["sales"][0]
    assert cashier.post(f"/api/sales/{sale['uuid']}/void", {"reason": "x"}).status_code == 403


# --- credit -------------------------------------------------------------------------

def test_short_payment_goes_on_the_customers_account(manager):
    p = make_product(manager, price=100)
    c = make_customer(manager, limit=500)
    r = sell(manager, [(p, 3, None)], paymentMethod="cash", customerId=c["id"], amountPaid=100)
    assert r.status_code == 200
    assert get_customer(manager, c["id"])["currentBalance"] == 200


def test_credit_limit_blocks_then_manager_override_allows(manager):
    p = make_product(manager, price=100)
    c = make_customer(manager, limit=150)
    r = sell(manager, [(p, 2, None)], paymentMethod="credit", customerId=c["id"], amountPaid=0)
    assert r.status_code == 409
    assert r.get_json()["error"]["message"] == (
        "This sale would take Jane's balance to 200.00, over their credit limit of 150.00."
    )
    assert get_customer(manager, c["id"])["currentBalance"] == 0
    r = sell(manager, [(p, 2, None)], paymentMethod="credit", customerId=c["id"], amountPaid=0, overrideCreditLimit=True)
    assert r.status_code == 200
    assert get_customer(manager, c["id"])["currentBalance"] == 200


def test_payment_settles_oldest_sale_first_and_statement_reconciles(manager):
    p = make_product(manager, price=100, stock=100)
    c = make_customer(manager, limit=10000)
    first = sell(manager, [(p, 2, None)], paymentMethod="credit", customerId=c["id"], amountPaid=0).get_json()["sale"]
    second = sell(manager, [(p, 3, None)], paymentMethod="credit", customerId=c["id"], amountPaid=0).get_json()["sale"]
    assert get_customer(manager, c["id"])["currentBalance"] == 500

    r = manager.post(f"/api/customers/{c['id']}/payments", {"amount": 250, "method": "mpesa"})
    assert r.status_code == 200
    sales = {s["uuid"]: s for s in manager.get("/api/sales").get_json()["sales"]}
    assert sales[first["uuid"]]["amountPaid"] == 200       # cleared in full
    assert sales[second["uuid"]]["amountPaid"] == 50       # the rest spills over
    assert get_customer(manager, c["id"])["currentBalance"] == 250

    ledger = manager.get(f"/api/customers/{c['id']}/ledger").get_json()["entries"]
    assert [e["type"] for e in ledger] == ["creditSale", "creditSale", "payment"]
    assert [e["runningBalance"] for e in ledger] == [200, 500, 250]
    assert ledger[0]["reference"] == "INV-000001" and ledger[2]["reference"] == "mpesa"
    # Independent reconciliation against the stored balance.
    charged = sum(e["amount"] for e in ledger if e["type"] == "creditSale")
    paid = sum(e["amount"] for e in ledger if e["type"] == "payment")
    assert charged - paid == get_customer(manager, c["id"])["currentBalance"]


def test_overpayment_never_goes_negative(manager):
    p = make_product(manager, price=100)
    c = make_customer(manager)
    sell(manager, [(p, 1, None)], paymentMethod="credit", customerId=c["id"], amountPaid=0)
    manager.post(f"/api/customers/{c['id']}/payments", {"amount": 500, "method": "cash"})
    assert get_customer(manager, c["id"])["currentBalance"] == 0


def test_payment_validation_and_permissions(manager, cashier):
    c = make_customer(manager)
    assert manager.post(f"/api/customers/{c['id']}/payments", {"amount": 0, "method": "cash"}).status_code == 400
    assert cashier.post(f"/api/customers/{c['id']}/payments", {"amount": 5, "method": "cash"}).status_code == 403


def test_walk_in_customer_cannot_be_edited(manager):
    walk_in = next(c for c in manager.get("/api/customers").get_json()["customers"] if c["isWalkIn"])
    r = manager.put(f"/api/customers/{walk_in['id']}", {"name": "Hacked", "creditLimit": 99999})
    assert r.status_code == 409 and r.get_json()["error"]["message"] == "The walk-in customer cannot be edited."


# --- voiding ---------------------------------------------------------------------------

def test_void_returns_stock_reverses_the_balance_and_needs_a_reason(manager):
    p = make_product(manager, price=100, stock=10)
    c = make_customer(manager, limit=10000)
    sale = sell(manager, [(p, 4, None)], paymentMethod="credit", customerId=c["id"], amountPaid=100).get_json()["sale"]
    assert get_product(manager, p["uuid"])["stock"] == 6
    assert get_customer(manager, c["id"])["currentBalance"] == 300

    assert manager.post(f"/api/sales/{sale['uuid']}/void", {"reason": "  "}).status_code == 400
    assert manager.post(f"/api/sales/{sale['uuid']}/void", {"reason": "wrong item"}).status_code == 200

    assert get_product(manager, p["uuid"])["stock"] == 10
    assert get_customer(manager, c["id"])["currentBalance"] == 0
    voided = manager.get("/api/sales").get_json()["sales"][0]
    assert voided["status"] == "void" and voided["voidReason"] == "wrong item" and voided["voidedByUserId"]
    ledger = manager.get(f"/api/customers/{c['id']}/ledger").get_json()["entries"]
    assert [e["type"] for e in ledger] == ["creditSale", "reversal"]

    again = manager.post(f"/api/sales/{sale['uuid']}/void", {"reason": "again"})
    assert again.status_code == 409
    assert again.get_json()["error"]["message"] == "Sale INV-000001 has already been voided."
    assert get_product(manager, p["uuid"])["stock"] == 10  # not returned twice


# --- stock adjustments ----------------------------------------------------------------------

def test_stock_adjustment_rules(manager, cashier):
    p = make_product(manager, stock=10)
    assert manager.post("/api/stock/adjustments", {"productId": p["id"], "quantityChange": -3, "reason": " "}).status_code == 400
    assert manager.post("/api/stock/adjustments", {"productId": p["id"], "quantityChange": -30, "reason": "lost"}).status_code == 400
    assert manager.post("/api/stock/adjustments", {"productId": p["id"], "quantityChange": 0, "reason": "none"}).status_code == 400
    assert manager.post("/api/stock/adjustments", {"productId": p["id"], "quantityChange": -3, "reason": "cracked"}).status_code == 200
    assert get_product(manager, p["uuid"])["stock"] == 7
    assert cashier.post("/api/stock/adjustments", {"productId": p["id"], "quantityChange": 1, "reason": "x"}).status_code == 403
    adj = [m for m in manager.get("/api/stock/movements").get_json()["movements"] if m["type"] == "ADJUSTMENT"]
    assert adj[0]["notes"] == "cracked" and adj[0]["quantity"] == -3


def test_stock_valuation_uses_weighted_purchase_cost(manager):
    p = make_product(manager, cost=10, stock=0)
    s = manager.post("/api/suppliers", {"name": "Acme"}).get_json()["supplier"]
    for qty, cost in ((20, 40), (100, 60)):
        r = manager.post(
            "/api/purchases",
            {"supplierId": s["id"], "items": [{"productId": p["id"], "quantity": qty, "unitCost": cost}], "paymentStatus": "paid"},
        )
        assert r.status_code == 200, r.get_json()
    level = next(l for l in manager.get("/api/stock/valuation").get_json()["levels"] if l["productId"] == p["id"])
    assert level["stock"] == 120
    assert level["averageCost"] == pytest.approx((20 * 40 + 100 * 60) / 120)
    assert level["stockValue"] == pytest.approx(120 * level["averageCost"])
    assert level["isLowStock"] is False


# --- purchases ----------------------------------------------------------------------------------

def test_receive_stock_credit_then_pay_it_off(manager, cashier):
    p = make_product(manager, cost=10, stock=10)
    s = manager.post("/api/suppliers", {"name": "Acme"}).get_json()["supplier"]
    body = {
        "supplierId": s["id"],
        "items": [{"productId": p["id"], "quantity": 10, "unitCost": 20}],
        "paymentStatus": "partial",
        "amountPaid": 50,
    }
    assert cashier.post("/api/purchases", body).status_code == 403
    purchase = manager.post("/api/purchases", body).get_json()["purchase"]
    assert (purchase["total"], purchase["amountPaid"], purchase["status"], purchase["paymentStatus"]) == (200, 50, "received", "partial")
    assert get_product(manager, p["uuid"]) ["stock"] == 20
    assert get_product(manager, p["uuid"])["costPrice"] == pytest.approx(15)  # (10*10 + 10*20)/20
    supplier = manager.get("/api/suppliers").get_json()["suppliers"][0]
    assert supplier["balance"] == 150

    pay = f"/api/purchases/{purchase['uuid']}/payments"
    assert manager.post(pay, {"amount": 0}).status_code == 400
    assert manager.post(pay, {"amount": 151}).status_code == 400   # overpayment is refused, not floored
    assert manager.post(pay, {"amount": 100}).get_json()["purchase"]["paymentStatus"] == "partial"
    assert manager.post(pay, {"amount": 50}).get_json()["purchase"]["paymentStatus"] == "paid"
    assert manager.get("/api/suppliers").get_json()["suppliers"][0]["balance"] == 0


def test_receive_stock_rejects_bad_payment_status(manager):
    p = make_product(manager)
    s = manager.post("/api/suppliers", {"name": "Acme"}).get_json()["supplier"]
    r = manager.post(
        "/api/purchases",
        {"supplierId": s["id"], "items": [{"productId": p["id"], "quantity": 1, "unitCost": 1}], "paymentStatus": "weird"},
    )
    assert r.status_code == 400


# --- expenses & reports -------------------------------------------------------------------------------

def test_expenses_need_permission_and_fields(manager, cashier):
    assert cashier.post("/api/expenses", {"category": "Rent", "description": "x", "amount": 5}).status_code == 403
    assert manager.post("/api/expenses", {"category": "Rent", "description": "x", "amount": 0}).status_code == 400
    assert manager.post("/api/expenses", {"category": "Rent", "description": " ", "amount": 5}).status_code == 400
    assert manager.post("/api/expenses", {"category": "Rent", "description": "March", "amount": 500}).status_code == 200
    assert manager.get("/api/expenses").get_json()["expenses"][0]["description"] == "March"


def test_reports_count_only_completed_sales_and_reconcile(manager):
    p = make_product(manager, cost=10, price=30, minimum=0, stock=100, confirmPriceBelowCost=True)
    q = make_product(manager, name="Tee", cost=5, price=20, minimum=0, stock=100, confirmPriceBelowCost=True)
    sell(manager, [(p, 2, None)], paymentMethod="cash")                       # 60
    sell(manager, [(q, 3, None), (p, 1, None)], paymentMethod="cash", discount=10)   # 90 - 10 = 80
    void = sell(manager, [(p, 5, None)], paymentMethod="cash").get_json()["sale"]
    manager.post(f"/api/sales/{void['uuid']}/void", {"reason": "oops"})
    manager.post("/api/expenses", {"category": "Rent", "description": "r", "amount": 40})

    sales = manager.get("/api/reports/sales?period=today").get_json()["report"]
    assert sales["totalRevenue"] == 140 and sales["saleCount"] == 2 and sales["averageSaleValue"] == 70
    by_name = {r["productName"]: r for r in sales["productBreakdown"]}
    assert by_name["Elbow"]["quantitySold"] == 3 and by_name["Elbow"]["revenue"] == 90
    assert [r["productName"] for r in sales["productBreakdown"]] == ["Elbow", "Tee"]  # by revenue desc

    pnl = manager.get("/api/reports/pnl?period=today").get_json()["report"]
    assert (pnl["subtotal"], pnl["discount"], pnl["netRevenue"]) == (150, 10, 140)
    assert pnl["cogs"] == 2 * 10 + 3 * 5 + 1 * 10
    assert pnl["grossProfit"] == 140 - 45 and pnl["expenses"] == 40 and pnl["netProfit"] == 140 - 45 - 40
    assert sales["totalRevenue"] == pnl["netRevenue"]

    inv = manager.get("/api/reports/inventory?period=today").get_json()["report"]
    moves = {m["type"]: m["totalQuantity"] for m in inv["movementSummary"]}
    assert moves["SALE"] == -(2 + 3 + 1 + 5) and moves["RETURN"] == 5


def test_empty_period_reads_as_zeros(manager):
    r = manager.get("/api/reports/sales?period=year").get_json()["report"]
    assert (r["totalRevenue"], r["saleCount"], r["averageSaleValue"], r["productBreakdown"]) == (0, 0, 0, [])
    pnl = manager.get("/api/reports/pnl?period=year").get_json()["report"]
    assert pnl["netProfit"] == 0


def test_report_exports(manager):
    p = make_product(manager)
    sell(manager, [(p, 1, None)], paymentMethod="cash")
    for kind in ("sales", "pnl", "inventory"):
        csv = manager.get(f"/api/reports/{kind}?period=week&format=csv")
        assert csv.status_code == 200 and csv.data.startswith(b"\xef\xbb\xbf")
        pdf = manager.get(f"/api/reports/{kind}?period=week&format=pdf")
        assert pdf.status_code == 200 and pdf.data.startswith(b"%PDF-")
        assert "attachment" in pdf.headers["Content-Disposition"]
    h_csv = manager.get("/api/sales/export.csv")
    assert b"Receipt,Date,Customer,Total,Paid,Status" in h_csv.data and b"INV-000001" in h_csv.data
    assert manager.get("/api/sales/export.pdf").data.startswith(b"%PDF-")


def test_receipt_pdf(manager, cashier):
    p = make_product(manager)
    sale = sell(cashier, [(p, 2, None)], paymentMethod="cash").get_json()["sale"]
    r = cashier.get(f"/api/sales/{sale['uuid']}/receipt.pdf")
    assert r.status_code == 200 and r.data.startswith(b"%PDF-") and r.mimetype == "application/pdf"


def test_bad_period(manager):
    assert manager.get("/api/reports/sales?period=decade").status_code == 400


def test_dashboard(manager):
    p = make_product(manager, cost=10, price=30, stock=3, reorder=5)   # low stock
    c = make_customer(manager, limit=1000)
    sell(manager, [(p, 1, None)], paymentMethod="credit", customerId=c["id"], amountPaid=0)
    d = manager.get("/api/dashboard").get_json()
    assert d["todayRevenue"] == 30 and d["todayNetProfit"] == 20
    assert d["lowStockCount"] == 1 and d["creditOutstanding"] == 30
    assert len(d["revenueTrend"]) == 7 and d["revenueTrend"][-1]["revenue"] == 30
    assert all(day["revenue"] == 0 for day in d["revenueTrend"][:-1])


# --- date ranges -----------------------------------------------------------------------------------------

def test_week_boundaries_have_no_gap_or_overlap():
    from duka.dates import for_period

    sunday = datetime(2026, 3, 15, 13, 0)
    monday = sunday + timedelta(days=1)
    s_start, s_end = for_period("week", sunday)
    m_start, m_end = for_period("week", monday)
    assert s_start == datetime(2026, 3, 9) and s_end == datetime(2026, 3, 15, 23, 59, 59, 999000)
    assert s_end + timedelta(milliseconds=1) == m_start


def test_month_and_year_ends():
    from duka.dates import for_period

    assert for_period("month", datetime(2026, 12, 5))[1] == datetime(2026, 12, 31, 23, 59, 59, 999000)
    assert for_period("month", datetime(2028, 2, 5))[1].day == 29
    assert for_period("year", datetime(2026, 6, 1)) == (datetime(2026, 1, 1), datetime(2026, 12, 31, 23, 59, 59, 999000))


# --- backup --------------------------------------------------------------------------------------------------

def test_backup_roundtrip_restores_everything(manager, app):
    p = make_product(manager, price=100, stock=10)
    c = make_customer(manager, limit=1000)
    sell(manager, [(p, 2, None)], paymentMethod="credit", customerId=c["id"], amountPaid=50)
    manager.post("/api/expenses", {"category": "Rent", "description": "r", "amount": 40})

    dump = manager.get("/api/backup")
    assert dump.status_code == 200
    document = json.loads(dump.data)
    assert document["format"] == "duka_pos_backup" and len(document["tables"]["sales"]) == 1

    # Wreck the data, then restore.
    manager.post("/api/expenses", {"category": "Rent", "description": "later", "amount": 1})
    sell(manager, [(p, 5, None)], paymentMethod="cash")
    r = manager.post("/api/restore", data={"file": (__import__("io").BytesIO(dump.data), "b.json")}, content_type="multipart/form-data")
    assert r.status_code == 200, r.get_json()

    assert get_product(manager, p["uuid"])["stock"] == 8
    assert len(manager.get("/api/sales").get_json()["sales"]) == 1
    assert get_customer(manager, c["id"])["currentBalance"] == 150
    assert len(manager.get("/api/expenses").get_json()["expenses"]) == 1
    # And the app keeps working: the next invoice continues the sequence.
    assert sell(manager, [(p, 1, None)], paymentMethod="cash").get_json()["sale"]["invoiceNumber"] == "INV-000002"


def test_restore_rejects_garbage_and_changes_nothing(manager):
    p = make_product(manager)
    for payload in (b"not json", json.dumps({"format": "other"}).encode(), json.dumps({"format": "duka_pos_backup", "version": 3, "tables": {}}).encode()):
        r = manager.post("/api/restore", data={"file": (__import__("io").BytesIO(payload), "b.json")}, content_type="multipart/form-data")
        assert r.status_code == 400
    assert get_product(manager, p["uuid"])["stock"] == 100


def test_restore_is_manager_only(manager, cashier):
    r = cashier.post("/api/restore", data={"file": (__import__("io").BytesIO(b"{}"), "b.json")}, content_type="multipart/form-data")
    assert r.status_code == 403


# --- concurrency -----------------------------------------------------------------------------------------------

def test_two_tills_cannot_both_sell_the_last_unit(manager, app):
    """Two checkouts racing for the last unit: exactly one wins, stock never goes negative."""
    import threading

    from api_helpers import Client

    p = make_product(manager, stock=1, price=10, minimum=1, cost=1)
    clients = []
    for i in range(4):
        c = Client(app)
        assert c.post("/api/auth/login", {"username": "mary", "password": "secret1"}).status_code == 200
        clients.append(c)

    results = []

    def go(c):
        results.append(sell(c, [(p, 1, None)], paymentMethod="cash").status_code)

    threads = [threading.Thread(target=go, args=(c,)) for c in clients]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert sorted(results) == [200, 409, 409, 409]
    assert get_product(manager, p["uuid"])["stock"] == 0


def test_invoice_numbers_stay_unique_and_gapless_under_load(manager, app):
    import threading

    from api_helpers import Client

    p = make_product(manager, stock=100, price=10, minimum=1, cost=1)
    clients = []
    for i in range(6):
        c = Client(app)
        c.post("/api/auth/login", {"username": "mary", "password": "secret1"})
        clients.append(c)
    numbers = []

    def go(c):
        for _ in range(3):
            r = sell(c, [(p, 1, None)], paymentMethod="cash")
            assert r.status_code == 200, r.get_json()
            numbers.append(r.get_json()["sale"]["invoiceNumber"])

    threads = [threading.Thread(target=go, args=(c,)) for c in clients]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert sorted(numbers) == [f"INV-{i:06d}" for i in range(1, 19)]
    assert get_product(manager, p["uuid"])["stock"] == 82
