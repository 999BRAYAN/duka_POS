import re

import pytest

from ui_helpers import Ui, first_run

playwright_sync = pytest.importorskip("playwright.sync_api")
expect = playwright_sync.expect


def seed(ui):
    """A few products, a customer and a supplier, through the API."""
    pipes = ui.post("/api/categories", {"name": "Pipes"})["category"]
    ui.post("/api/categories", {"name": "Taps"})
    ids = {}
    for name, cost, price, stock, minimum in [
        ("Elbow", 20, 35, 40, 30),
        ("Socket", 15, 28, 3, 28),
        ("Brass tap", 120, 220, 15, 200),
        ("PTFE tape", 8, 15, 0, 15),
    ]:
        ids[name] = ui.post(
            "/api/products",
            {
                "name": name, "costPrice": cost, "sellingPrice": price, "minSellingPrice": minimum, "stock": stock,
                "reorderLevel": 5, "sku": name[:3].upper(), "categoryId": pipes["id"] if name != "Brass tap" else None,
            },
        )["product"]
    jane = ui.post("/api/customers", {"name": "Jane Wanjiru", "phone": "0712", "creditLimit": 500})["customer"]
    ui.post("/api/suppliers", {"name": "Mabati Wholesale"})
    return ids, jane


def card(ui, name):
    return ui.page.locator(".product-card", has_text=name)


# --- first run / auth -----------------------------------------------------------------------------------

def test_first_run_then_sign_in_and_out(manager_ui):
    ui = manager_ui
    expect(ui.page.locator(".appbar .title")).to_have_text("Products")
    expect(ui.page.locator(".drawer-head .name").first).to_have_text("Mary Manager")
    ui.btn("Sign out").click()
    expect(ui.page.locator(".auth-card h1")).to_have_text("Duka POS")
    ui.page.locator(".auth-card input").nth(0).fill("mary")
    ui.page.locator(".auth-card input").nth(1).fill("nope")
    ui.page.locator(".auth-card .btn-filled").click()
    expect(ui.page.locator(".auth-card .error-text")).to_contain_text("don't match")
    ui.page.locator(".auth-card input").nth(1).fill("secret1")
    ui.page.locator(".auth-card .btn-filled").click()
    expect(ui.page.locator(".appbar .title")).to_have_text("Products")


def test_setup_validation(ui):
    ui.page.goto(ui.base)
    ui.page.wait_for_selector(".auth-card")
    inputs = ui.page.locator(".auth-card input")
    ui.page.get_by_role("button", name="Create account").click()
    expect(ui.page.locator(".auth-card .error-text")).to_have_text("Enter your name and a username.")
    for i, v in enumerate(["M", "m", "abcdef", "abcdeX"]):
        inputs.nth(i).fill(v)
    ui.page.get_by_role("button", name="Create account").click()
    expect(ui.page.locator(".auth-card .error-text")).to_have_text("Those passwords don't match.")
    inputs.nth(2).fill("abc")
    inputs.nth(3).fill("abc")
    ui.page.get_by_role("button", name="Create account").click()
    expect(ui.page.locator(".auth-card .error-text")).to_have_text("Password too short. Use at least 6 characters.")


def test_cashier_sees_locked_navigation_and_switch_user(manager_ui):
    ui = manager_ui
    ui.post("/api/users", {"fullName": "Carl Cashier", "username": "carl", "password": "cashpw1", "role": "cashier"})
    ui.btn("Switch user").click()
    expect(ui.page.locator(".dialog h2")).to_have_text("Switch user")
    ui.page.locator(".list-tile", has_text="Carl Cashier").click()
    ui.page.locator(".dialog input").fill("bad")
    ui.btn("Switch").click()
    expect(ui.page.locator(".dialog .error-text")).to_contain_text("don't match")
    ui.page.locator(".dialog input").fill("cashpw1")
    ui.btn("Switch").click()
    expect(ui.page.locator(".drawer-head .name").first).to_have_text("Carl Cashier")
    assert ui.page.locator(".rail .nav-item", has_text="Reports").is_disabled()
    assert ui.page.locator(".rail .nav-item", has_text="New sale").is_enabled()
    # No add-product button for a cashier on the product list.
    expect(ui.page.locator("button[title='Add product']")).to_have_count(0)
    ui.shot("cashier")


# --- products ---------------------------------------------------------------------------------------------

def test_add_edit_product_with_below_cost_confirmation_and_new_category(manager_ui):
    ui = manager_ui
    ui.page.locator("button[title='Add product']").click()
    expect(ui.page.locator(".appbar .title")).to_have_text("Add product")
    ui.field("Product name").fill("Gate valve")
    ui.field("SKU (optional)").fill("GV1")
    # A new category without leaving the form.
    ui.select("Category").select_option(label="New category…")
    ui.page.locator(".dialog input").fill("Valves")
    ui.btn("Create").click()
    expect(ui.select("Category").locator("option:checked")).to_have_text("Valves")
    ui.field("Cost price").fill("300")
    ui.field("Selling price").fill("480")
    ui.field("Lowest price you will accept").fill("250")   # below cost
    ui.field("Opening stock").fill("6")
    ui.btn("Add product").click()
    expect(ui.page.locator(".dialog h2")).to_have_text("Selling below cost")
    ui.btn("Cancel").click()
    expect(ui.page.locator(".appbar .title")).to_have_text("Add product")   # still on the form, values intact
    assert ui.field("Product name").input_value() == "Gate valve"
    ui.btn("Add product").click()
    ui.btn("Save anyway").click()
    expect(ui.page.locator(".appbar .title")).to_have_text("Products")
    row = ui.page.locator("tr", has_text="Gate valve")
    expect(row).to_contain_text("6.00")
    expect(row).to_contain_text("Valves")

    row.get_by_role("button", name="Edit").click()
    expect(ui.page.locator(".appbar .title")).to_have_text("Edit product")
    assert ui.page.locator("label:text-is('Opening stock')").count() == 0   # stock is never edited here
    ui.field("Selling price").fill("500")
    ui.field("Lowest price you will accept").fill("300")
    ui.btn("Save changes").click()
    expect(ui.page.locator("tr", has_text="Gate valve")).to_contain_text("500.00")
    assert ui.get("/api/products")["products"][0]["stock"] == 6


def test_product_filters_and_low_stock(manager_ui):
    ui = manager_ui
    seed(ui)
    ui.goto("/products")
    expect(ui.page.locator("tbody tr")).to_have_count(4)
    ui.page.locator("input[placeholder='Search by name, SKU or barcode']").fill("tap")
    expect(ui.page.locator("tbody tr")).to_have_count(2)   # Brass tap, PTFE tape
    ui.page.locator("input[placeholder='Search by name, SKU or barcode']").fill("")
    ui.btn("Low stock only").click()
    expect(ui.page.locator("tbody tr")).to_have_count(2)   # Socket (3), PTFE (0)
    ui.btn("Low stock only").click()
    ui.page.locator(".field select").first.select_option(label="Pipes")
    expect(ui.page.locator("tbody tr")).to_have_count(3)
    ui.shot("products")


# --- the sale -----------------------------------------------------------------------------------------------

def test_cash_sale_end_to_end(manager_ui):
    ui = manager_ui
    seed(ui)
    ui.goto("/sell")
    expect(card(ui, "PTFE tape")).to_be_disabled()
    expect(card(ui, "Socket")).to_contain_text("low")
    card(ui, "Elbow").click()
    card(ui, "Elbow").click()
    card(ui, "Brass tap").click()
    expect(ui.page.locator(".order-line")).to_have_count(2)
    expect(ui.page.locator(".order-total .v")).to_have_text("290.00")   # 2*35 + 220
    # Haggle the tap below its floor: the box shows the minimum in red, and checkout refuses.
    price = ui.page.locator(".order-line", has_text="Brass tap").locator("input")
    price.fill("150")
    expect(ui.page.locator(".order-line", has_text="Brass tap").locator(".err")).to_have_text("Min 200.00")
    expect(ui.page.locator(".order-total .v")).to_have_text("220.00")
    ui.shot("order_below_floor")
    ui.btn("Review order").click()
    expect(ui.page.locator(".appbar .title")).to_have_text("Confirm & pay")
    ui.btn("Complete sale · 220.00").click()
    expect(ui.page.locator(".notice-bad")).to_contain_text(
        "'Brass tap' would sell at 150.00 after discount, below its minimum selling price of 200.00."
    )
    ui.shot("floor_refused")
    # Back, fix the price, pay.
    ui.btn("Back to the order").click()
    expect(ui.page.locator(".appbar .title")).to_have_text("New sale")
    price = ui.page.locator(".order-line", has_text="Brass tap").locator("input")
    assert price.input_value() == "150.00"           # the order survived the round trip
    price.fill("210")
    ui.btn("Review order").click()
    ui.btn("Complete sale · 280.00").click()
    expect(ui.page.locator(".dialog h2")).to_have_text("Sale complete")
    expect(ui.page.locator(".dialog .d-body")).to_contain_text("INV-000001 · 280.00")
    ui.shot("sale_complete")
    with ui.ctx.expect_page() as popup:
        ui.btn("Print receipt").click()
    receipt = popup.value
    receipt.wait_for_load_state()
    assert "/receipt.pdf" in receipt.url
    receipt.close()
    ui.btn("Done").click()
    expect(ui.page.locator(".appbar .title")).to_have_text("New sale")
    expect(ui.page.locator(".order-line")).to_have_count(0)    # a fresh order
    stock = {p["name"]: p["stock"] for p in ui.get("/api/products")["products"]}
    assert stock["Elbow"] == 38 and stock["Brass tap"] == 14


def test_credit_sale_limit_override_and_void(manager_ui):
    ui = manager_ui
    seed(ui)
    ui.goto("/sell")
    card(ui, "Brass tap").click()
    card(ui, "Brass tap").click()      # 440
    ui.btn("Review order").click()
    ui.choose("Customer", "Jane Wanjiru")
    # A customer defaults to paying in full…
    assert ui.field("Amount paid now").input_value() == "440.00"
    # …choosing Credit takes nothing now and hides the field.
    ui.select("Payment method").select_option(label="Credit")
    expect(ui.page.locator("label:text-is('Amount paid now')")).to_have_count(0)
    expect(ui.page.locator(".notice-warn")).to_contain_text(
        "Remaining 440.00 goes on Jane Wanjiru's account — now 0.00 of 500.00."
    )
    ui.btn("Back to the order").click()
    card(ui, "Brass tap").click()      # 660 > 500
    ui.btn("Review order").click()
    ui.btn("Complete sale · 660.00").click()
    expect(ui.page.locator(".notice-bad")).to_contain_text(
        "This sale would take Jane Wanjiru's balance to 660.00, over their credit limit of 500.00."
    )
    ui.shot("credit_limit")
    ui.btn("Override and complete").click()     # a manager may
    expect(ui.page.locator(".dialog h2")).to_have_text("Sale complete")
    ui.btn("Done").click()
    assert ui.get("/api/customers")["customers"][0]["currentBalance"] == 660

    # Void it from Sales history: stock and the balance come back.
    ui.goto("/sales")
    row = ui.page.locator("tr", has_text="INV-000001")
    expect(row).to_contain_text("On account")
    row.get_by_role("button", name="Void").click()
    ui.btn("Void sale").click()
    expect(ui.page.locator(".dialog .err")).to_have_text("Say why this sale is being voided.")
    ui.field("Reason").fill("wrong customer")
    ui.btn("Void sale").click()
    expect(ui.snack()).to_contain_text("INV-000001 voided. Stock and balance reversed.")
    expect(ui.page.locator("tr", has_text="INV-000001")).to_contain_text("Void")
    cust = next(c for c in ui.get("/api/customers")["customers"] if c["name"].startswith("Jane"))
    assert cust["currentBalance"] == 0
    assert next(p for p in ui.get("/api/products")["products"] if p["name"] == "Brass tap")["stock"] == 15
    ui.shot("history_voided")


def test_cashier_cannot_override_a_credit_limit(manager_ui):
    ui = manager_ui
    seed(ui)
    ui.post("/api/users", {"fullName": "Carl", "username": "carl", "password": "cashpw1", "role": "cashier"})
    ui.post("/api/auth/login", {"username": "carl", "password": "cashpw1"})
    ui.page.reload()          # the page was loaded as the manager
    ui.goto("/sell")
    for _ in range(3):
        card(ui, "Brass tap").click()
    ui.btn("Review order").click()
    ui.choose("Customer", "Jane")
    ui.select("Payment method").select_option(label="Credit")
    ui.btn("Complete sale · 660.00").click()
    expect(ui.page.locator(".notice-bad")).to_contain_text("over their credit limit")
    expect(ui.page.locator(".notice-bad")).to_contain_text("A manager can approve this.")
    expect(ui.page.get_by_role("button", name="Override and complete")).to_have_count(0)


def test_hold_and_resume_an_order(manager_ui):
    ui = manager_ui
    seed(ui)
    ui.goto("/sell")
    card(ui, "Elbow").click()
    ui.field("Discount on the whole order").fill("5")
    expect(ui.page.locator(".order-total .v")).to_have_text("30.00")
    ui.btn("Hold order").click()
    expect(ui.snack()).to_have_text("Order held.")
    expect(ui.page.locator(".order-line")).to_have_count(0)
    expect(ui.page.locator("button[title='Held orders'] .badge")).to_have_text("1")
    ui.page.locator("button[title='Held orders']").click()
    expect(ui.page.locator(".dialog .list-tile")).to_contain_text("Walk-in customer")
    expect(ui.page.locator(".dialog .list-tile")).to_contain_text("1 item(s) · 35.00")
    ui.btn("Resume").click()
    expect(ui.page.locator(".order-line")).to_have_count(1)
    expect(ui.page.locator(".order-total .v")).to_have_text("30.00")
    assert ui.field("Discount on the whole order").input_value() == "5"


def test_the_order_survives_navigating_away(manager_ui):
    ui = manager_ui
    seed(ui)
    ui.goto("/sell")
    card(ui, "Elbow").click()
    ui.page.locator(".rail .nav-item", has_text="Products").click()
    expect(ui.page.locator(".appbar .title")).to_have_text("Products")
    ui.btn("New sale").click()
    expect(ui.page.locator(".order-line")).to_have_count(1)


# --- stock in, customers, money -----------------------------------------------------------------------------

def test_receive_stock_on_credit_then_pay_supplier(manager_ui):
    ui = manager_ui
    seed(ui)
    ui.goto("/purchases/receive")
    ui.select("Supplier").select_option(label="Mabati Wholesale")
    ui.page.locator(".ac input").first.fill("elb")
    ui.page.locator(".ac-item", has_text="Elbow").click()
    assert ui.field("Unit cost").input_value() == "20"          # prefilled from the product, editable
    ui.field("Qty").fill("10")
    ui.field("Unit cost").fill("30")
    expect(ui.page.get_by_text("Total: 300.00")).to_be_visible()
    ui.select("Payment status").select_option(label="Partially paid")
    ui.field("Amount paid").fill("100")
    ui.shot("receive")
    ui.btn("Receive stock").click()
    expect(ui.page.locator(".appbar .title")).to_have_text("Purchases")
    row = ui.page.locator("tr", has_text="Mabati")
    expect(row).to_contain_text("Partially paid")
    assert next(p for p in ui.get("/api/products")["products"] if p["name"] == "Elbow")["stock"] == 50
    row.get_by_role("button", name="Record payment").click()
    assert ui.field("Amount paid").input_value() == "200.00"      # defaults to the full balance
    ui.field("Amount paid").fill("250")
    ui.page.locator(".dialog").get_by_role("button", name="Record payment").click()
    expect(ui.page.locator(".dialog .error-text")).to_have_text("Only 200.00 is owed on this purchase.")
    ui.field("Amount paid").fill("200")
    ui.page.locator(".dialog").get_by_role("button", name="Record payment").click()
    expect(ui.page.locator("tr", has_text="Mabati")).to_contain_text("Paid")
    expect(ui.page.locator("tr", has_text="Mabati").get_by_role("button", name="Record payment")).to_have_count(0)


def test_customer_payment_and_statement(manager_ui):
    ui = manager_ui
    ids, jane = seed(ui)
    ui.post(
        "/api/sales",
        {
            "cart": [{"productId": ids["Brass tap"]["id"], "price": 220, "quantity": 2}],
            "customerId": jane["id"], "paymentMethod": "credit", "amountPaid": 0, "overrideCreditLimit": True,
        },
    )
    ui.goto("/customers")
    row = ui.page.locator("tr", has_text="Jane Wanjiru")
    expect(row).to_contain_text("440.00")
    # The walk-in customer can't take a payment.
    expect(ui.page.locator("tr", has_text="Walk-in Customer").locator("button[title^='The walk-in']")).to_be_disabled()
    row.locator("button[title='Receive payment']").click()
    expect(ui.page.get_by_text("Current balance: 440.00")).to_be_visible()
    ui.btn("Record payment").click()
    expect(ui.page.locator(".error-text")).to_have_text("Enter an amount greater than zero.")
    ui.field("Amount").fill("140")
    ui.select("Payment method").select_option(label="M-Pesa")
    ui.btn("Record payment").click()
    expect(ui.page.locator(".appbar .title")).to_have_text("Customers")
    expect(ui.page.locator("tr", has_text="Jane Wanjiru")).to_contain_text("300.00")
    ui.page.locator("tr", has_text="Jane Wanjiru").locator("button[title='Statement']").click()
    expect(ui.page.locator(".appbar .title")).to_have_text("Jane Wanjiru — statement")
    rows = ui.page.locator("tbody tr")
    expect(rows).to_have_count(2)
    expect(rows.nth(0)).to_contain_text("Credit sale")
    expect(rows.nth(0)).to_contain_text("+440.00")
    expect(rows.nth(1)).to_contain_text("Payment")
    expect(rows.nth(1)).to_contain_text("mpesa")
    expect(rows.nth(1)).to_contain_text("-140.00")
    expect(rows.nth(1)).to_contain_text("300.00")
    ui.shot("statement")


def test_add_customer_supplier_and_staff(manager_ui):
    ui = manager_ui
    ui.goto("/customers")
    ui.btn("Add customer").click()
    ui.btn("Add customer").click()      # the form's own button, still empty
    expect(ui.page.locator(".error-text")).to_have_text("Enter a name.")
    ui.field("Name").fill("Otieno Hardware")
    ui.field("Credit limit").fill("20000")
    ui.btn("Add customer").click()
    expect(ui.page.locator("tr", has_text="Otieno Hardware")).to_contain_text("20,000.00")

    ui.goto("/suppliers")
    expect(ui.page.locator(".empty")).to_have_text("No suppliers yet. Add the shops you buy stock from.")
    ui.btn("Add supplier").click()
    ui.field("Supplier name").fill("Mabati")
    ui.btn("Add supplier").click()
    expect(ui.page.locator("tr", has_text="Mabati")).to_be_visible()

    ui.goto("/staff")
    ui.btn("Add staff").click()
    ui.field("Full name").fill("Carl Cashier")
    ui.field("Username").fill("carl")
    ui.field("Password").fill("abc")
    ui.btn("Create login").click()
    expect(ui.page.locator(".error-text")).to_have_text("Password too short. Use at least 6 characters.")
    ui.field("Password").fill("cashpw1")
    ui.btn("Create login").click()
    row = ui.page.locator("tr", has_text="Carl Cashier")
    expect(row).to_contain_text("Active")
    row.get_by_role("button", name="Disable").click()
    ui.page.locator(".dialog").get_by_role("button", name="Disable").click()
    expect(ui.page.locator("tr", has_text="Carl Cashier")).to_contain_text("Disabled")
    # You can't disable yourself.
    expect(ui.page.locator("tr", has_text="Mary Manager").get_by_role("button", name="Disable")).to_have_count(0)


def test_expenses_adjustments_dashboard_and_reports(manager_ui):
    ui = manager_ui
    ids, _ = seed(ui)
    ui.post(
        "/api/sales",
        {"cart": [{"productId": ids["Elbow"]["id"], "price": 35, "quantity": 4}], "paymentMethod": "cash", "amountPaid": 140},
    )

    ui.goto("/expenses")
    ui.btn("Record expense").click()
    expect(ui.page.locator(".error-text")).to_have_text("Enter how much was spent.")
    ui.field("Amount").fill("40")
    ui.btn("Record expense").click()
    expect(ui.page.locator(".error-text")).to_have_text("Say what the money was for.")
    ui.field("What was it for?").fill("Matatu fare")
    ui.btn("Record expense").click()
    expect(ui.page.locator("tr", has_text="Matatu fare")).to_contain_text("40.00")

    ui.goto("/adjust")
    ui.choose("Product", "Socket")
    ui.field("Change").fill("-10")
    ui.field("Reason").fill("cracked")
    ui.btn("Record correction").click()
    expect(ui.page.locator(".error-text")).to_contain_text("below zero")
    ui.field("Change").fill("-2")
    ui.field("Reason").fill("")
    ui.btn("Record correction").click()
    expect(ui.page.locator(".error-text")).to_have_text("A reason is required for a manual stock adjustment.")
    ui.field("Reason").fill("cracked")
    ui.btn("Record correction").click()
    expect(ui.page.locator("tr", has_text="cracked")).to_contain_text("-2")

    ui.goto("/dashboard")
    kpis = ui.page.locator(".kpi")
    expect(kpis.nth(0)).to_contain_text("140.00")
    expect(kpis.nth(1)).to_contain_text("20.00")      # 140 revenue - 80 cost - 40 expense
    ui.shot("dashboard")
    ui.goto("/reports")
    expect(ui.page.locator("tr", has_text="Elbow")).to_contain_text("140.00")
    ui.page.get_by_role("tab", name="Profit & loss").click()
    expect(ui.page.locator(".pnl-card")).to_contain_text("Net profit")
    expect(ui.page.locator(".pnl-card .pnl-row").last).to_contain_text("20.00")
    ui.shot("pnl")
    with ui.page.expect_download() as d:
        ui.btn("PDF").click()
    assert d.value.suggested_filename.startswith("profit_and_loss_") and d.value.suggested_filename.endswith(".pdf")
    ui.page.get_by_role("tab", name="Inventory").click()
    expect(ui.page.locator(".report-split svg")).to_be_visible()
    ui.shot("inventory")
    ui.btn("This year").click()
    ui.page.get_by_role("tab", name="Sales").click()
    expect(ui.page.locator(".kpi").first).to_contain_text("140.00")


def test_backup_and_restore_through_the_dashboard(manager_ui, tmp_path):
    ui = manager_ui
    seed(ui)
    ui.goto("/dashboard")
    with ui.page.expect_download() as d:
        ui.page.locator("button[title='Backup now']").click()
    backup = tmp_path / d.value.suggested_filename
    d.value.save_as(backup)
    expect(ui.snack()).to_have_text("Backup downloaded.")
    expect(ui.page.locator(".banner")).to_contain_text("Backed up today.")

    ui.post("/api/expenses", {"category": "Rent", "description": "after the backup", "amount": 9})
    ui.page.locator("button[title='Restore from backup']").click()
    with ui.page.expect_file_chooser() as chooser:
        ui.btn("Choose backup file").click()
    with ui.page.expect_download():           # the safety copy of what's there now
        chooser.value.set_files(str(backup))
    ui.page.wait_for_timeout(2000)            # upload, then reload
    assert ui.get("/api/expenses")["expenses"] == []
    assert len(ui.get("/api/products")["products"]) == 4


# --- look & feel -----------------------------------------------------------------------------------------------------

def test_dark_theme_and_narrow_window(browser, server):
    ui = Ui(browser, server, width=900, height=800)
    first_run(ui)
    seed(ui)
    ui.goto("/products")
    # Below 1100px the rail collapses into a hamburger + slide-over drawer.
    assert not ui.page.locator(".rail").is_visible()
    ui.page.locator("button[title='Open navigation']").click()
    ui.shot("narrow_drawer")
    ui.page.locator(".drawer-wrap .nav-item", has_text="Customers").click()
    expect(ui.page.locator(".appbar .title")).to_have_text("Customers")
    ui.page.locator("button[title='Open navigation']").click()
    ui.page.locator(".drawer-wrap button[title='Dark']").click()
    assert ui.page.evaluate("document.documentElement.dataset.theme") == "dark"
    ui.page.locator(".drawer-scrim").click(position={"x": 700, "y": 400})
    ui.goto("/products")
    ui.shot("dark_products")
    ui.goto("/sell")
    ui.shot("dark_sell")
    problems = list(ui.problems)
    ui.close()
    assert not problems, problems
