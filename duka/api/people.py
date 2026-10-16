"""Customers, their credit account and statement."""

from .. import serialize
from ..repos import customers
from . import actor, bp, body, db, ok


@bp.get("/customers")
def list_customers():
    actor()
    return ok(customers=serialize.rows(customers.list_customers(db())))


@bp.post("/customers")
def add_customer():
    customer = customers.add_customer(db(), actor(), body())
    return ok(customer=serialize.row(customer))


@bp.put("/customers/<int:customer_id>")
def update_customer(customer_id):
    customer = customers.update_customer(db(), actor(), customer_id, body())
    return ok(customer=serialize.row(customer))


@bp.get("/customers/<int:customer_id>/ledger")
def customer_ledger(customer_id):
    actor()
    return ok(
        customer=serialize.row(customers.get_customer(db(), customer_id)),
        entries=customers.ledger(db(), customer_id),
    )


@bp.post("/customers/<int:customer_id>/payments")
def receive_payment(customer_id):
    data = body()
    transaction = customers.receive_payment(
        db(), actor(), customer_id, data.get("amount"), data.get("method", ""), data.get("notes")
    )
    return ok(transaction=serialize.row(transaction))
