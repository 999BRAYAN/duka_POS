"""Answers about customers, suppliers, staff, purchases and single invoices."""

import re

from .common import Ctx, answer, manager_only, money, pct, qty, table, when

HELP_PEOPLE = "who owes you, any customer's balance or history, suppliers and what you owe them, invoices, staff"


# --- customers ---------------------------------------------------------------

def owed_by_customers(c: Ctx) -> dict:
    rows = c.db.all("SELECT name, phone, current_balance, credit_limit FROM customers WHERE current_balance > 0 ORDER BY current_balance DESC LIMIT 20")
    if not rows:
        return answer("No customer owes anything right now.")
    total = c.db.scalar("SELECT SUM(current_balance) FROM customers WHERE current_balance > 0")
    return answer(f"Customers owe {money(total)} in total.",
                  table(["Customer", "Phone", "Owes", "Limit"], [[r["name"], r["phone"] or "-", money(r["current_balance"]), money(r["credit_limit"])] for r in rows]),
                  ["Who is near their credit limit?"])


def near_limit(c: Ctx) -> dict:
    rows = c.db.all(
        "SELECT name, phone, current_balance, credit_limit FROM customers WHERE is_walk_in = 0 AND credit_limit > 0 "
        "AND current_balance >= credit_limit * 0.8 ORDER BY current_balance / credit_limit DESC LIMIT 20")
    if not rows:
        return answer("Nobody is within 80% of their credit limit.")
    return answer(f"{len(rows)} customer{'s are' if len(rows) != 1 else ' is'} at or near their credit limit:",
                  table(["Customer", "Owes", "Limit", "Used"], [[r["name"], money(r["current_balance"]), money(r["credit_limit"]), pct(r["current_balance"], r["credit_limit"])] for r in rows]))


def customer_info(c: Ctx, cu: dict) -> dict:
    last_pay = c.db.one("SELECT created_at, amount, method FROM credit_transactions WHERE customer_id = %s AND type = 'PAYMENT' ORDER BY created_at DESC, id DESC LIMIT 1", (cu["id"],))
    ledger = c.db.all("SELECT created_at, type, amount, balance_after, method FROM credit_transactions WHERE customer_id = %s ORDER BY created_at DESC, id DESC LIMIT 8", (cu["id"],))
    room = cu["credit_limit"] - cu["current_balance"]
    text = f"{cu['name']} owes {money(cu['current_balance'])}" if cu["current_balance"] > 0 else f"{cu['name']} owes nothing"
    text += f" (credit limit {money(cu['credit_limit'])}, {money(max(room, 0))} still available)."
    if last_pay:
        text += f" Last payment: {money(last_pay['amount'])} on {when(last_pay['created_at'])}."
    if cu["phone"]:
        text += f" Phone {cu['phone']}."
    if c.manager:
        s = c.db.one("SELECT COUNT(*) AS n, SUM(total) AS total, MAX(created_at) AS last FROM sales WHERE customer_id = %s AND status = 'completed'", (cu["id"],))
        if s["n"]:
            text += f" They have made {s['n']} purchase{'s' if s['n'] != 1 else ''} worth {money(s['total'])}, the last on {when(s['last'])}."
    tbl = table(["When", "What", "Amount", "Balance after"],
                [[when(r["created_at"]), {"CHARGE": "Left on credit", "PAYMENT": f"Paid ({r['method'] or 'cash'})", "REVERSAL": "Sale voided"}.get(r["type"], r["type"]),
                  money(r["amount"]), money(r["balance_after"])] for r in ledger]) if ledger else None
    return answer(text, tbl)


def top_customers(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("customer spending")
    p = c.period
    rows = c.db.all(
        "SELECT cu.name, COUNT(*) AS n, SUM(s.total) AS total FROM sales s JOIN customers cu ON cu.id = s.customer_id "
        "WHERE s.status = 'completed' AND cu.is_walk_in = 0 AND s.created_at BETWEEN %s AND %s GROUP BY cu.id, cu.name ORDER BY total DESC LIMIT 10",
        (p.start, p.end))
    if not rows:
        return answer(f"No named customer bought anything {p.label}.")
    return answer(f"Your best customers {p.label}:", table(["#", "Customer", "Purchases", "Spent"], [[n + 1, r["name"], r["n"], money(r["total"])] for n, r in enumerate(rows)]))


def customer_count(c: Ctx) -> dict:
    n = len(c.customers)
    owing = sum(1 for cu in c.customers if cu["current_balance"] > 0)
    return answer(f"You have {n} customer{'s' if n != 1 else ''}; {owing} of them owe money.", suggestions=["Who owes us money?"])


def pick_one(kind: str, matches: list[dict]) -> dict:
    names = ", ".join(m["name"] for m in matches[:6])
    return answer(f"More than one {kind} fits that: {names}. Which one do you mean? Use the full name.")


# --- suppliers and purchases -------------------------------------------------

def owed_to_suppliers(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("what is owed to suppliers")
    rows = c.db.all("SELECT name, phone, balance FROM suppliers WHERE balance > 0 ORDER BY balance DESC LIMIT 20")
    if not rows:
        return answer("You don't owe any supplier right now.")
    total = c.db.scalar("SELECT SUM(balance) FROM suppliers WHERE balance > 0")
    return answer(f"You owe suppliers {money(total)} in total.", table(["Supplier", "Phone", "You owe"], [[r["name"], r["phone"] or "-", money(r["balance"])] for r in rows]),
                  ["Which purchases are unpaid?"])


def supplier_info(c: Ctx, s: dict) -> dict:
    if not c.manager:
        return manager_only("supplier details")
    last = c.db.one("SELECT created_at, total, payment_status, status FROM purchases WHERE supplier_id = %s ORDER BY created_at DESC, id DESC LIMIT 1", (s["id"],))
    items = c.db.all(
        "SELECT p.name, SUM(pi.quantity) AS q, SUM(pi.total) AS total FROM purchase_items pi JOIN purchases pu ON pu.id = pi.purchase_id "
        "JOIN products p ON p.id = pi.product_id WHERE pu.supplier_id = %s AND pu.status = 'received' GROUP BY p.id, p.name ORDER BY total DESC LIMIT 8", (s["id"],))
    text = f"You owe {s['name']} {money(s['balance'])}." if s["balance"] > 0 else f"You owe {s['name']} nothing."
    if s["phone"]:
        text += f" Phone {s['phone']}."
    if last:
        text += f" The latest purchase was {money(last['total'])} on {when(last['created_at'])} ({last['status']}, {last['payment_status']})."
    return answer(text, table(["Bought from them", "Quantity", "Spent"], [[r["name"], qty(r["q"]), money(r["total"])] for r in items]) if items else None)


def supplier_count(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("supplier details")
    n = len(c.suppliers)
    owed = sum(1 for s in c.suppliers if s["balance"] > 0)
    return answer(f"You have {n} supplier{'s' if n != 1 else ''}; you owe money to {owed} of them.", suggestions=["Show all suppliers", "What do I owe suppliers?"])


def supplier_list(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("supplier details")
    rows = c.db.all("SELECT name, phone, balance FROM suppliers ORDER BY name LIMIT 100")
    if not rows:
        return answer("You have no suppliers yet.")
    return answer(f"{len(rows)} supplier{'s' if len(rows) != 1 else ''}:",
                  table(["Supplier", "Phone", "You owe"], [[r["name"], r["phone"] or "-", money(r["balance"])] for r in rows]))


def unpaid_purchases(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("purchases")
    rows = c.db.all(
        "SELECT pu.created_at, pu.reference_number, s.name, pu.total, pu.amount_paid FROM purchases pu JOIN suppliers s ON s.id = pu.supplier_id "
        "WHERE pu.status = 'received' AND pu.payment_status <> 'paid' ORDER BY pu.created_at LIMIT 20")
    if not rows:
        return answer("Every received purchase is paid for.")
    return answer(f"{len(rows)} received purchase{'s' if len(rows) != 1 else ''} not fully paid, {money(sum(r['total'] - r['amount_paid'] for r in rows))} outstanding:",
                  table(["Date", "Supplier", "Ref", "Total", "Still owed"], [[when(r["created_at"]), r["name"], r["reference_number"] or "-", money(r["total"]), money(r["total"] - r["amount_paid"])] for r in rows]))


def pending_purchases(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("purchases")
    rows = c.db.all(
        "SELECT pu.created_at, pu.reference_number, s.name, pu.total FROM purchases pu JOIN suppliers s ON s.id = pu.supplier_id "
        "WHERE pu.status = 'pending' ORDER BY pu.created_at LIMIT 20")
    if not rows:
        return answer("No purchases are waiting to be received.")
    return answer(f"{len(rows)} purchase{'s are' if len(rows) != 1 else ' is'} still waiting to be received:",
                  table(["Date", "Supplier", "Ref", "Total"], [[when(r["created_at"]), r["name"], r["reference_number"] or "-", money(r["total"])] for r in rows]))


def recent_purchases(c: Ctx) -> dict:
    if not c.manager:
        return manager_only("purchases")
    p = c.period
    rows = c.db.all(
        "SELECT pu.created_at, s.name, pu.total, pu.status, pu.payment_status FROM purchases pu JOIN suppliers s ON s.id = pu.supplier_id "
        "WHERE pu.status <> 'cancelled' AND pu.created_at BETWEEN %s AND %s ORDER BY pu.created_at DESC LIMIT 15", (p.start, p.end))
    if not rows:
        return answer(f"No stock was bought {p.label}.")
    return answer(f"Stock bought {p.label}: {money(sum(r['total'] for r in rows))} in {len(rows)} purchase{'s' if len(rows) != 1 else ''}.",
                  table(["Date", "Supplier", "Total", "Status", "Payment"], [[when(r["created_at"]), r["name"], money(r["total"]), r["status"], r["payment_status"]] for r in rows]))


# --- staff -------------------------------------------------------------------

def staff(c: Ctx) -> dict:
    if not c.can_see_staff:
        return manager_only("the staff list")
    rows = c.db.all("SELECT full_name, username, role, is_active FROM users ORDER BY FIELD(role, 'manager', 'admin', 'cashier'), full_name")
    return answer(f"{len(rows)} login{'s' if len(rows) != 1 else ''}:",
                  table(["Name", "Username", "Role", "Active"], [[r["full_name"], r["username"], r["role"], "yes" if r["is_active"] else "no"] for r in rows]))


def who_am_i(c: Ctx) -> dict:
    perms = "everything" if c.manager else "ringing up sales and looking up stock and prices"
    return answer(f"You are signed in as {c.user['full_name']} ({c.user['username']}), role {c.user['role']}. You can do {perms}.")


# --- a single invoice --------------------------------------------------------

_INVOICE = re.compile(r"\b(?:inv[-\s]?|invoice\s+(?:no\.?\s*|number\s*|#\s*)?)0*(\d{1,9})\b")


def invoice_number_in(q: str) -> str | None:
    m = _INVOICE.search(q)
    return f"INV-{int(m.group(1)):06d}" if m else None


def invoice(c: Ctx, number: str) -> dict:
    sale = c.db.one(
        "SELECT s.*, COALESCE(cu.name, 'Walk-in') AS customer, u.full_name AS cashier FROM sales s "
        "LEFT JOIN customers cu ON cu.id = s.customer_id LEFT JOIN users u ON u.id = s.user_id WHERE s.invoice_number = %s", (number,))
    if not sale:
        return answer(f"I can't find invoice {number}.")
    items = c.db.all("SELECT p.name, si.quantity, si.unit_price, si.total FROM sale_items si JOIN products p ON p.id = si.product_id WHERE si.sale_id = %s", (sale["id"],))
    text = (f"{number} on {when(sale['created_at'])} for {sale['customer']}, rung up by {sale['cashier']}: total {money(sale['total'])}, "
            f"paid {money(sale['amount_paid'])} by {sale['payment_method']}")
    if sale["total"] > sale["amount_paid"]:
        text += f", {money(sale['total'] - sale['amount_paid'])} still unpaid"
    text += f". Status: {sale['status']}"
    if sale["status"] != "completed" and sale["void_reason"]:
        text += f" ({sale['void_reason']})"
    return answer(text + ".", table(["Item", "Qty", "Price", "Total"], [[i["name"], qty(i["quantity"]), money(i["unit_price"]), money(i["total"])] for i in items]))
