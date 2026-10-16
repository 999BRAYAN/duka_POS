"""Stock levels and manual corrections."""

from .. import authz, serialize
from ..repos import stock
from . import actor, bp, body, db, ok


@bp.get("/stock/valuation")
def stock_valuation():
    actor()
    return ok(levels=stock.stock_valuation(db()))


@bp.get("/stock/movements")
def recent_movements():
    authz.require(actor(), authz.ADJUST_STOCK)
    return ok(movements=serialize.rows(stock.recent_movements(db(), limit=100)))


@bp.post("/stock/adjustments")
def adjust_stock():
    data = body()
    movement = stock.adjust_stock(
        db(), actor(), int(data.get("productId") or 0), data.get("quantityChange"), data.get("reason", "")
    )
    return ok(movement=serialize.row(movement))
