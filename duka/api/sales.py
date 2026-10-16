"""Sales, receipts and purchases."""

from flask import Response, request

from .. import authz, exports, serialize
from ..repos import customers as customers_repo
from ..repos import purchases, sales, users as users_repo
from . import actor, bp, body, db, ok


@bp.get("/sales")
def list_sales():
    actor()
    return ok(sales=serialize.rows(sales.list_sales(db())))


@bp.post("/sales")
def complete_sale():
    data = body()
    sale = sales.complete_sale(
        db(),
        actor(),
        cart=data.get("cart"),
        customer_id=data.get("customerId"),
        payment_method=data.get("paymentMethod", ""),
        amount_paid=data.get("amountPaid") or 0,
        discount=data.get("discount") or 0,
        override_credit_limit=bool(data.get("overrideCreditLimit")),
    )
    return ok(sale=serialize.row(sale))


@bp.post("/sales/<uuid>/void")
def void_sale(uuid):
    sales.void_sale(db(), actor(), uuid, body().get("reason", ""))
    return ok()


@bp.get("/sales/<uuid>/receipt.pdf")
def receipt(uuid):
    actor()
    conn = db()
    sale = sales.get_sale(conn, uuid)
    items = sales.items_for_sale(conn, sale["id"])
    products = {p["id"]: p for p in conn.all("SELECT id, name FROM products")}
    cashier = users_repo.get_by_id(conn, sale["user_id"])
    customer = customers_repo.get_customer(conn, sale["customer_id"]) if sale["customer_id"] else None
    pdf = exports.receipt_pdf(sale, items, products, cashier, customer)
    return Response(pdf, mimetype="application/pdf", headers={"Content-Disposition": f'inline; filename="{sale["invoice_number"]}.pdf"'})


def _download(data: bytes, filename: str, mimetype: str) -> Response:
    return Response(data, mimetype=mimetype, headers={"Content-Disposition": f'attachment; filename="{filename}"'})


@bp.get("/sales/export.<fmt>")
def export_sales(fmt):
    """Exactly the rows the Sales history screen shows — every sale, void ones
    included, newest first."""
    actor()
    conn = db()
    all_sales = sales.list_sales(conn)
    by_id = {c["id"]: c for c in customers_repo.list_customers(conn)}
    if fmt == "csv":
        return _download(exports.sales_history_csv(all_sales, by_id), f"sales_history_{exports.stamp()}.csv", "text/csv")
    return _download(exports.sales_history_pdf(all_sales, by_id), f"sales_history_{exports.stamp()}.pdf", "application/pdf")


# --- purchases ----------------------------------------------------------------

@bp.get("/purchases")
def list_purchases():
    actor()
    return ok(purchases=serialize.rows(purchases.list_purchases(db())))


@bp.post("/purchases")
def receive_stock():
    data = body()
    purchase = purchases.receive_stock(
        db(),
        actor(),
        supplier_id=int(data.get("supplierId") or 0),
        items=data.get("items"),
        payment_status=data.get("paymentStatus", ""),
        amount_paid=data.get("amountPaid") or 0,
        reference_number=(data.get("referenceNumber") or None),
    )
    return ok(purchase=serialize.row(purchase))


@bp.post("/purchases/<uuid>/payments")
def record_purchase_payment(uuid):
    purchase = purchases.record_payment(db(), actor(), uuid, body().get("amount"))
    return ok(purchase=serialize.row(purchase))
