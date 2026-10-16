"""Receiving stock from suppliers, and paying them off afterwards."""

from .. import authz
from ..db import Db, new_uuid, now, r4
from ..errors import (
    InvalidPaymentStatus,
    InvalidPurchasePayment,
    InvalidPurchaseStatus,
    NotFound,
    ValidationError,
)
from . import stock

_VALID_PAYMENT_STATUSES = ("paid", "partial", "unpaid")


def list_purchases(db: Db) -> list[dict]:
    return db.all("SELECT * FROM purchases ORDER BY created_at DESC, id DESC")


def receive_stock(
    db: Db,
    actor: dict,
    *,
    supplier_id: int,
    items,
    payment_status: str,
    amount_paid: float = 0,
    discount: float = 0,
    tax: float = 0,
    reference_number: str | None = None,
) -> dict:
    """Records goods arriving: the stock goes up, each product's cost price is
    re-averaged, and whatever isn't paid for is added to what the shop owes
    the supplier. One transaction."""
    authz.require(actor, authz.RECEIVE_STOCK)
    if payment_status not in _VALID_PAYMENT_STATUSES:
        raise InvalidPaymentStatus(
            f"Unknown payment status '{payment_status}'; expected one of {set(_VALID_PAYMENT_STATUSES)}."
        )

    lines = []
    for raw in items or []:
        try:
            lines.append(
                {
                    "productId": int(raw["productId"]),
                    "quantity": float(raw["quantity"]),
                    "unitCost": float(raw["unitCost"]),
                }
            )
        except (KeyError, TypeError, ValueError):
            raise ValidationError("A line item is missing its product, quantity or unit cost.") from None
    if not lines:
        raise ValidationError("Add at least one line item with a product and quantity.")
    if any(line["quantity"] <= 0 or line["unitCost"] < 0 for line in lines):
        raise ValidationError("Every line needs a quantity above zero and a cost of zero or more.")
    try:
        amount_paid = float(amount_paid or 0)
        discount = float(discount or 0)
        tax = float(tax or 0)
    except (TypeError, ValueError):
        raise ValidationError("The amounts must be numbers.") from None

    with db.tx():
        supplier = db.one("SELECT * FROM suppliers WHERE id = %s FOR UPDATE", (supplier_id,))
        if supplier is None:
            raise NotFound("That supplier")

        stamp = now()
        # Generated up front so record_movement (called per item, before the
        # purchase row exists) can still reference it.
        purchase_uuid = new_uuid()
        subtotal = r4(sum(line["quantity"] * line["unitCost"] for line in lines))
        total = r4(subtotal - discount + tax)

        for line in lines:
            product = db.one("SELECT * FROM products WHERE id = %s FOR UPDATE", (line["productId"],))
            if product is None:
                raise NotFound("A product in this delivery")

            # The product's cost becomes the weighted average of what's on the
            # shelf and what just arrived.
            on_hand = product["stock"] + line["quantity"]
            new_cost = (
                (product["stock"] * product["cost_price"] + line["quantity"] * line["unitCost"]) / on_hand
                if on_hand
                else line["unitCost"]
            )
            stock.record_movement(
                db,
                product_id=line["productId"],
                type="PURCHASE",
                quantity=line["quantity"],
                unit_cost=line["unitCost"],
                reference=purchase_uuid,
                user_id=actor["id"],
            )
            db.update("products", {"cost_price": r4(new_cost), "updated_at": stamp}, "id = %s", (line["productId"],))

        purchase_id = db.insert(
            "purchases",
            {
                "uuid": purchase_uuid,
                "reference_number": reference_number,
                "supplier_id": supplier_id,
                "user_id": actor["id"],
                "subtotal": subtotal,
                "discount": discount,
                "tax": tax,
                "total": total,
                "amount_paid": amount_paid,
                "status": "received",
                "payment_status": payment_status,
                "created_at": stamp,
            },
        )
        for line in lines:
            db.insert(
                "purchase_items",
                {
                    "uuid": new_uuid(),
                    "purchase_id": purchase_id,
                    "product_id": line["productId"],
                    "quantity": line["quantity"],
                    "unit_cost": line["unitCost"],
                    "total": r4(line["quantity"] * line["unitCost"]),
                    "created_at": stamp,
                },
            )

        outstanding = r4(total - amount_paid)
        if outstanding > 0:
            db.update(
                "suppliers",
                {"balance": r4(supplier["balance"] + outstanding), "updated_at": stamp},
                "id = %s",
                (supplier_id,),
            )
        return db.one("SELECT * FROM purchases WHERE id = %s", (purchase_id,))


def record_payment(db: Db, actor: dict, uuid: str, amount) -> dict:
    """Pays down a received purchase. Rejects overpayment rather than
    flooring it: a purchase is a single invoice with a real total, not an
    open-ended account balance."""
    authz.require(actor, authz.RECEIVE_STOCK)
    try:
        amount = float(amount)
    except (TypeError, ValueError):
        amount = 0.0

    with db.tx():
        purchase = db.one("SELECT * FROM purchases WHERE uuid = %s FOR UPDATE", (uuid,))
        if purchase is None:
            raise NotFound("That purchase")
        if purchase["status"] != "received":
            raise InvalidPurchaseStatus(
                f"Cannot record a payment: this purchase is '{purchase['status']}', not 'received'."
            )

        outstanding = r4(purchase["total"] - purchase["amount_paid"])
        if amount <= 0 or amount > outstanding:
            raise InvalidPurchasePayment(f"Payment of {amount:g} is invalid: {outstanding:.2f} is owed on this purchase.")

        stamp = now()
        new_amount_paid = r4(purchase["amount_paid"] + amount)
        db.update(
            "purchases",
            {
                "amount_paid": new_amount_paid,
                "payment_status": "paid" if new_amount_paid >= purchase["total"] else "partial",
                "updated_at": stamp,
            },
            "id = %s",
            (purchase["id"],),
        )

        supplier = db.one("SELECT * FROM suppliers WHERE id = %s FOR UPDATE", (purchase["supplier_id"],))
        db.update(
            "suppliers",
            {"balance": max(r4(supplier["balance"] - amount), 0), "updated_at": stamp},
            "id = %s",
            (supplier["id"],),
        )
        return db.one("SELECT * FROM purchases WHERE id = %s", (purchase["id"],))
