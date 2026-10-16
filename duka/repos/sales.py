"""Checkout, voiding, and the sales ledger."""

from .. import authz
from ..db import Db, new_uuid, now, r4
from ..errors import (
    CreditLimitExceeded,
    CustomerRequiredForCredit,
    InsufficientStock,
    MissingVoidReason,
    NotFound,
    PriceBelowFloor,
    SaleAlreadyVoid,
    ValidationError,
)
from . import customers, stock

PAYMENT_METHODS = ("cash", "mpesa", "card", "credit")

# Held for the length of a checkout. The invoice number is a straight count of
# every sale ever created plus one, which only stays gapless and collision-free
# if two checkouts can't read the same count at once.
_SALE_LOCK = "duka_pos_sale"


def list_sales(db: Db) -> list[dict]:
    return db.all("SELECT * FROM sales ORDER BY created_at DESC, id DESC")


def get_sale(db: Db, uuid: str) -> dict:
    sale = db.one("SELECT * FROM sales WHERE uuid = %s", (uuid,))
    if sale is None:
        raise NotFound("That sale")
    return sale


def items_for_sale(db: Db, sale_id: int) -> list[dict]:
    return db.all("SELECT * FROM sale_items WHERE sale_id = %s ORDER BY id", (sale_id,))


def _clean_cart(raw_cart) -> list[dict]:
    if not raw_cart:
        raise ValidationError("Cannot complete a sale with an empty cart.")
    cart = []
    for line in raw_cart:
        try:
            product_id = int(line["productId"])
            price = float(line["price"])
            quantity = float(line["quantity"])
        except (KeyError, TypeError, ValueError):
            raise ValidationError("That order has a line the till can't read. Rebuild it and try again.") from None
        if quantity <= 0 or price < 0:
            raise ValidationError("Every line needs a quantity above zero and a price of zero or more.")
        cart.append({"productId": product_id, "price": price, "quantity": quantity, "lineTotal": price * quantity})
    return cart


def _assert_no_line_below_floor(lines: list[dict], subtotal: float, cart_discount: float, products: dict) -> None:
    """A line's total is net of any item-level discount, so the only further
    deduction is the cart-level discount, allocated across lines in
    proportion to their share of the subtotal."""
    for line in lines:
        if line["quantity"] <= 0:
            continue
        allocated = cart_discount * (line["lineTotal"] / subtotal) if subtotal > 0 else 0.0
        effective_price = (line["lineTotal"] - allocated) / line["quantity"]
        product = products[line["productId"]]
        if r4(effective_price) < product["min_selling_price"]:
            raise PriceBelowFloor(product["name"], effective_price, product["min_selling_price"])


def complete_sale(
    db: Db,
    actor: dict,
    *,
    cart,
    customer_id: int | None,
    payment_method: str,
    amount_paid: float = 0,
    discount: float = 0,
    override_credit_limit: bool = False,
) -> dict:
    """Rings up a sale: checks stock and the price floors, writes the sale and
    its lines, moves the stock, and puts any unpaid balance on the customer's
    account — all in one transaction, so a failure anywhere leaves nothing
    behind."""
    authz.require(actor, authz.PROCESS_SALE)
    if override_credit_limit:
        authz.require(actor, authz.OVERRIDE_CREDIT_LIMIT)

    lines = _clean_cart(cart)
    if payment_method not in PAYMENT_METHODS:
        raise ValidationError("Choose how the sale is being paid.")
    if payment_method == "credit" and customer_id is None:
        raise CustomerRequiredForCredit()
    try:
        amount_paid = float(amount_paid or 0)
        discount = float(discount or 0)
    except (TypeError, ValueError):
        raise ValidationError("The discount and amount paid must be numbers.") from None
    if amount_paid < 0 or discount < 0:
        raise ValidationError("The discount and amount paid can't be negative.")

    with db.named_lock(_SALE_LOCK), db.tx():
        stamp = now()
        subtotal = r4(sum(line["lineTotal"] for line in lines))
        total = r4(subtotal - discount)

        # Fetched fresh, once, right here — never the cart's own snapshot —
        # since both stock and cost may have moved since a line was added.
        # Locked in id order so two checkouts can't deadlock each other.
        products: dict[int, dict] = {}
        for product_id in sorted({line["productId"] for line in lines}):
            product = db.one("SELECT * FROM products WHERE id = %s FOR UPDATE", (product_id,))
            if product is None:
                raise NotFound("A product in this order")
            products[product_id] = product

        # The same product on two lines is one demand on its stock.
        wanted: dict[int, float] = {}
        for line in lines:
            wanted[line["productId"]] = wanted.get(line["productId"], 0.0) + line["quantity"]
        for line in lines:
            product = products[line["productId"]]
            if product["stock"] < wanted[line["productId"]]:
                raise InsufficientStock(product["name"], wanted[line["productId"]], product["stock"])

        _assert_no_line_below_floor(lines, subtotal, discount, products)

        customer = None
        if customer_id is not None:
            customer = db.one("SELECT * FROM customers WHERE id = %s FOR UPDATE", (customer_id,))
            if customer is None:
                raise NotFound("That customer")

        # Any unpaid balance extends credit, whatever the payment method is
        # labeled — a "cash" sale that's short still leaves the customer
        # owing the shop, so it's checked against the same limit a 'credit'
        # sale would be. With no customer at all there's no one to check (and
        # no one to charge the shortfall to).
        balance_due = r4(total - amount_paid)
        if balance_due > 0 and customer is not None and not override_credit_limit:
            would_be = r4(customer["current_balance"] + balance_due)
            if would_be > customer["credit_limit"]:
                raise CreditLimitExceeded(customer["name"], would_be, customer["credit_limit"])

        cogs = r4(sum(line["quantity"] * products[line["productId"]]["cost_price"] for line in lines))
        gross_profit = r4(total - cogs)

        # A gapless sequence — a straight count of every sale ever created
        # (void or not; sales are never deleted).
        next_seq = db.scalar("SELECT COUNT(*) FROM sales") + 1
        invoice_number = f"INV-{next_seq:06d}"

        sale_uuid = new_uuid()
        sale_id = db.insert(
            "sales",
            {
                "uuid": sale_uuid,
                "invoice_number": invoice_number,
                "customer_id": customer_id,
                "user_id": actor["id"],
                "subtotal": subtotal,
                "discount": discount,
                "total": total,
                "amount_paid": amount_paid,
                "payment_method": payment_method,
                "cogs": cogs,
                "gross_profit": gross_profit,
                "created_at": stamp,
            },
        )

        for line in lines:
            product = products[line["productId"]]
            db.insert(
                "sale_items",
                {
                    "uuid": new_uuid(),
                    "sale_id": sale_id,
                    "product_id": line["productId"],
                    "quantity": line["quantity"],
                    "unit_price": line["price"],
                    "total": r4(line["lineTotal"]),
                    "created_at": stamp,
                },
            )
            stock.record_movement(
                db,
                product_id=line["productId"],
                type="SALE",
                quantity=-line["quantity"],
                unit_cost=product["cost_price"],
                reference=sale_uuid,
                user_id=actor["id"],
            )

        if customer is not None and balance_due > 0:
            customers.charge_customer(
                db, customer_id=customer["id"], sale_id=sale_id, amount=balance_due, notes=f"Sale {invoice_number}"
            )

        return db.one("SELECT * FROM sales WHERE id = %s", (sale_id,))


def void_sale(db: Db, actor: dict, uuid: str, reason: str) -> None:
    """Reverses a completed sale: the goods go back into stock and any unpaid
    balance comes off the customer's account. Requires `voidSale` and a
    non-blank reason — a cashier who could void their own sales could take
    cash out of the till and erase the record of it."""
    authz.require(actor, authz.VOID_SALE)
    if not (reason or "").strip():
        raise MissingVoidReason()

    with db.tx():
        sale = db.one("SELECT * FROM sales WHERE uuid = %s FOR UPDATE", (uuid,))
        if sale is None:
            raise NotFound("That sale")
        # Voiding twice would return the stock and credit the balance a
        # second time, so it's refused rather than silently doubling both.
        if sale["status"] == "void":
            raise SaleAlreadyVoid(sale["invoice_number"])

        for item in items_for_sale(db, sale["id"]):
            product = db.one("SELECT cost_price FROM products WHERE id = %s", (item["product_id"],))
            stock.record_movement(
                db,
                product_id=item["product_id"],
                type="RETURN",
                quantity=item["quantity"],
                unit_cost=product["cost_price"],
                reference=sale["uuid"],
            )

        # The mirror of complete_sale's charge: whatever this sale added to the
        # customer's balance comes back off it, as its own REVERSAL row so the
        # statement shows the void rather than silently losing the charge.
        balance_due = r4(sale["total"] - sale["amount_paid"])
        if balance_due > 0 and sale["customer_id"] is not None:
            customers.reverse_sale_charge(
                db,
                customer_id=sale["customer_id"],
                sale_id=sale["id"],
                amount=balance_due,
                notes=f"Void of {sale['invoice_number']}",
            )

        db.update(
            "sales",
            {
                "status": "void",
                "void_reason": reason.strip(),
                "voided_by_user_id": actor["id"],
                "updated_at": now(),
            },
            "id = %s",
            (sale["id"],),
        )
