"""Customers, their credit account, and their statement."""

from .. import authz
from ..db import Db, new_uuid, now, r4
from ..errors import NotFound, ValidationError, WalkInCustomerNotEditable


def _blank_to_none(value):
    if value is None:
        return None
    value = str(value).strip()
    return value or None


def list_customers(db: Db) -> list[dict]:
    return db.all("SELECT * FROM customers ORDER BY name")


def get_customer(db: Db, customer_id: int) -> dict:
    customer = db.one("SELECT * FROM customers WHERE id = %s", (customer_id,))
    if customer is None:
        raise NotFound("That customer")
    return customer


def _fields(data: dict) -> dict:
    name = (data.get("name") or "").strip()
    if not name:
        raise ValidationError("Enter a name.")
    try:
        credit_limit = float(data.get("creditLimit") or 0)
    except (TypeError, ValueError):
        credit_limit = 0.0
    return {
        "name": name,
        "phone": _blank_to_none(data.get("phone")),
        "email": _blank_to_none(data.get("email")),
        "address": _blank_to_none(data.get("address")),
        "credit_limit": max(credit_limit, 0.0),
    }


def add_customer(db: Db, actor: dict, data: dict) -> dict:
    authz.require(actor, authz.MANAGE_CUSTOMERS)
    customer_id = db.insert("customers", {"uuid": new_uuid(), **_fields(data), "created_at": now()})
    return get_customer(db, customer_id)


def update_customer(db: Db, actor: dict, customer_id: int, data: dict) -> dict:
    authz.require(actor, authz.MANAGE_CUSTOMERS)
    existing = get_customer(db, customer_id)
    # Checked after the permission check (auth is always the outer gate), so
    # even a manager cannot edit the seeded walk-in row.
    if existing["is_walk_in"]:
        raise WalkInCustomerNotEditable()
    db.update("customers", {**_fields(data), "updated_at": now()}, "id = %s", (customer_id,))
    return get_customer(db, customer_id)


# --- credit account ---------------------------------------------------------
#
# `customers.current_balance` is never written anywhere else. Every change
# goes through here, so each one leaves a `credit_transactions` row behind it
# and a customer's statement can be derived from that table alone.

def _apply_transaction(
    db: Db,
    *,
    customer_id: int,
    sale_id: int | None,
    type: str,
    amount: float,
    compute_balance_after,
    method: str | None = None,
    notes: str | None = None,
) -> dict:
    with db.tx():
        customer = db.one("SELECT current_balance FROM customers WHERE id = %s FOR UPDATE", (customer_id,))
        if customer is None:
            raise NotFound("That customer")
        stamp = now()
        balance_after = r4(compute_balance_after(customer["current_balance"]))
        transaction_id = db.insert(
            "credit_transactions",
            {
                "uuid": new_uuid(),
                "customer_id": customer_id,
                "sale_id": sale_id,
                "type": type,
                "amount": amount,
                "balance_after": balance_after,
                "method": method,
                "notes": notes,
                "created_at": stamp,
            },
        )
        db.update("customers", {"current_balance": balance_after, "updated_at": stamp}, "id = %s", (customer_id,))
        return db.one("SELECT * FROM credit_transactions WHERE id = %s", (transaction_id,))


def charge_customer(db: Db, *, customer_id: int, sale_id: int | None, amount: float, notes: str | None = None) -> dict:
    return _apply_transaction(
        db,
        customer_id=customer_id,
        sale_id=sale_id,
        type="CHARGE",
        amount=amount,
        compute_balance_after=lambda balance: balance + amount,
        notes=notes,
    )


def record_payment(db: Db, *, customer_id: int, amount: float, method: str, notes: str | None = None) -> dict:
    # Floored at zero: an overpayment (or a payment recorded against a stale
    # balance) should never leave the customer showing a negative balance.
    return _apply_transaction(
        db,
        customer_id=customer_id,
        sale_id=None,
        type="PAYMENT",
        amount=amount,
        compute_balance_after=lambda balance: max(balance - amount, 0),
        method=method,
        notes=notes,
    )


def reverse_sale_charge(db: Db, *, customer_id: int, sale_id: int, amount: float, notes: str | None = None) -> dict:
    # Same floor as record_payment, for the same reason: the debt may already
    # have been settled before anyone noticed the sale was wrong.
    return _apply_transaction(
        db,
        customer_id=customer_id,
        sale_id=sale_id,
        type="REVERSAL",
        amount=amount,
        compute_balance_after=lambda balance: max(balance - amount, 0),
        notes=notes,
    )


def receive_payment(db: Db, actor: dict, customer_id: int, amount, method: str, notes: str | None = None) -> dict:
    """Records money collected against a customer's tab, and settles their
    oldest unpaid sales with it."""
    authz.require(actor, authz.MANAGE_CUSTOMERS)
    try:
        amount = float(amount)
    except (TypeError, ValueError):
        amount = 0.0
    if amount <= 0:
        raise ValidationError("Enter an amount greater than zero.")
    if method not in ("cash", "mpesa", "card"):
        raise ValidationError("Choose how the payment was taken.")

    with db.tx():
        get_customer(db, customer_id)
        transaction = record_payment(db, customer_id=customer_id, amount=amount, method=method, notes=_blank_to_none(notes))

        # Oldest first — the same chronological order the statement reads in —
        # so paying "the tab" settles the longest-outstanding sale first, as
        # real bookkeeping does. Void sales are excluded: their charge was
        # already reversed, so they carry no real debt.
        sales = db.all(
            "SELECT id, total, amount_paid FROM sales WHERE customer_id = %s AND status = 'completed' "
            "ORDER BY created_at ASC, id ASC FOR UPDATE",
            (customer_id,),
        )
        remaining = amount
        for sale in sales:
            if remaining <= 0:
                break
            due = r4(sale["total"] - sale["amount_paid"])
            if due <= 0:
                continue
            applied = min(remaining, due)
            db.update("sales", {"amount_paid": r4(sale["amount_paid"] + applied)}, "id = %s", (sale["id"],))
            remaining = r4(remaining - applied)
        return transaction


def ledger(db: Db, customer_id: int) -> list[dict]:
    """The customer's statement: every credit sale, payment and void that
    moved their balance, oldest first, with a running balance."""
    get_customer(db, customer_id)
    transactions = db.all(
        "SELECT * FROM credit_transactions WHERE customer_id = %s ORDER BY created_at ASC, id ASC",
        (customer_id,),
    )
    sale_ids = {t["sale_id"] for t in transactions if t["sale_id"] is not None}
    invoice_numbers: dict[int, str] = {}
    if sale_ids:
        marks = ", ".join(["%s"] * len(sale_ids))
        for sale in db.all(f"SELECT id, invoice_number FROM sales WHERE id IN ({marks})", tuple(sale_ids)):
            invoice_numbers[sale["id"]] = sale["invoice_number"]

    entries = []
    running = 0.0
    for t in transactions:
        kind = {"CHARGE": "creditSale", "REVERSAL": "reversal"}.get(t["type"], "payment")
        running += t["amount"] if kind == "creditSale" else -t["amount"]
        if running < 0:
            running = 0.0
        entries.append(
            {
                "date": t["created_at"].isoformat(timespec="milliseconds"),
                "type": kind,
                "reference": (t["method"] or "unspecified")
                if kind == "payment"
                else invoice_numbers.get(t["sale_id"], "adjustment"),
                "amount": t["amount"],
                "runningBalance": r4(running),
            }
        )
    return entries
