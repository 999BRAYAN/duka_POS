"""Stock movements — the only writer of `products.stock`.

Every change to a product's stock goes through `record_movement`, which
inserts the audit row *and* updates the stock figure in one transaction, so
the two can never drift apart. Sales, voids and purchases call it from inside
their own transactions and simply join them.
"""

from .. import authz
from ..db import Db, new_uuid, now
from ..errors import MissingAdjustmentReason, NotFound, ValidationError


def record_movement(
    db: Db,
    *,
    product_id: int,
    type: str,
    quantity: float,
    unit_cost: float | None = None,
    reference: str | None = None,
    notes: str | None = None,
    user_id: int | None = None,
) -> dict:
    """`quantity` is the signed delta applied to stock (negative = SALE,
    positive = PURCHASE / RETURN)."""
    with db.tx():
        # Locked, so two tills selling the last unit at once can't both read
        # the same stock figure and both write it back.
        product = db.one("SELECT id, stock FROM products WHERE id = %s FOR UPDATE", (product_id,))
        if product is None:
            raise NotFound("That product")
        stamp = now()
        db.update(
            "products",
            {"stock": product["stock"] + quantity, "updated_at": stamp},
            "id = %s",
            (product_id,),
        )
        movement_id = db.insert(
            "stock_movements",
            {
                "uuid": new_uuid(),
                "product_id": product_id,
                "type": type,
                "quantity": quantity,
                "unit_cost": unit_cost,
                "reference": reference,
                "notes": notes,
                "user_id": user_id,
                "created_at": stamp,
            },
        )
        return db.one("SELECT * FROM stock_movements WHERE id = %s", (movement_id,))


def recent_movements(db: Db, limit: int = 100) -> list[dict]:
    return db.all("SELECT * FROM stock_movements ORDER BY created_at DESC, id DESC LIMIT %s", (limit,))


def adjust_stock(db: Db, actor: dict, product_id: int, quantity_change: float, reason: str) -> dict:
    """A manual stock correction (breakage, theft, a miscount). Requires
    `adjustStock` and a non-blank reason; both are enforced before anything is
    written."""
    authz.require(actor, authz.ADJUST_STOCK)
    if not (reason or "").strip():
        raise MissingAdjustmentReason()
    try:
        change = float(quantity_change)
    except (TypeError, ValueError):
        raise ValidationError("Enter how much to add or remove.") from None
    if change == 0:
        raise ValidationError("Enter how much to add or remove.")
    with db.tx():
        product = db.one("SELECT name, stock FROM products WHERE id = %s FOR UPDATE", (product_id,))
        if product is None:
            raise NotFound("That product")
        if product["stock"] + change < 0:
            raise ValidationError(
                f"That would take {product['name']} below zero. "
                f"It has {_quantity(product['stock'])} on hand."
            )
        return record_movement(
            db,
            product_id=product_id,
            type="ADJUSTMENT",
            quantity=change,
            notes=reason,
            user_id=actor["id"],
        )


def _quantity(value: float) -> str:
    """`#,##0.###`"""
    text = f"{value:,.3f}".rstrip("0").rstrip(".")
    return text or "0"


# Average cost is the weighted average unit cost across a product's PURCHASE
# movements only — not RETURN, whose unit_cost is copied from the product's
# cost price at return time rather than a real amount paid to a supplier, and
# would skew the average if included. A product with no purchase history yet
# falls back to its cost price.
_STOCK_VALUATION_SQL = """
SELECT
  p.id AS product_id,
  p.uuid AS uuid,
  p.name AS name,
  p.stock AS stock,
  p.reorder_level AS reorder_level,
  COALESCE(pc.avg_cost, p.cost_price) AS average_cost
FROM products p
LEFT JOIN (
  SELECT product_id, SUM(quantity * unit_cost) / SUM(quantity) AS avg_cost
  FROM stock_movements
  WHERE type = 'PURCHASE' AND unit_cost IS NOT NULL AND quantity > 0
  GROUP BY product_id
) pc ON pc.product_id = p.id
WHERE p.is_active = 1
ORDER BY p.name
"""


def stock_valuation(db: Db) -> list[dict]:
    result = []
    for row in db.all(_STOCK_VALUATION_SQL):
        stock = float(row["stock"])
        average_cost = float(row["average_cost"])
        result.append(
            {
                "productId": row["product_id"],
                "uuid": row["uuid"],
                "name": row["name"],
                "stock": stock,
                "reorderLevel": float(row["reorder_level"]),
                "averageCost": average_cost,
                "stockValue": stock * average_cost,
                "isLowStock": stock <= float(row["reorder_level"]),
            }
        )
    return result
